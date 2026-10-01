//
//  AppDelegate.swift
//  BilibiliLive
//
//  Created by Etan on 2021/3/27.
//

import AVFoundation
import AVKit
import BiliAccelerator
import CocoaLumberjackSwift
import Kingfisher
import SwiftyJSON
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow? {
        sceneDelegate?.window
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Logger.setup()
        ImageCache.default.diskStorage.config.sizeLimit = 500 * 1024 * 1024
        AVInfoPanelCollectionViewThumbnailCellHook.start()
        AccountManager.shared.bootstrap()
        BiliBiliUpnpDMR.shared.start()
        Accelerator.shared.isEnabled = Settings.acceleratorEnabled
        Accelerator.shared.start(userAgent: Keys.userAgent)
        #if DEBUG
            Accelerator.shared.debugCommandHandler = Self.handleDebugCommand
            Accelerator.shared.startDebugServer(port: 7779)
        #endif
        URLSession.shared.configuration.headers.add(.userAgent("BiLiBiLi AppleTV Client/1.0.0 (github/yichengchen/ATV-Bilibili-live-demo)"))
        WebRequest.requestIndex()
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    #if DEBUG
        /// Commands from the accelerator's debug server, for driving tests from a Mac:
        /// `play?aid=&cid=` (or `epid=`), `detail?aid=&cid=`, `stop`, `home` (the tab bar, even when
        /// signed out), `tab?index=`, `quality?qn=`, `seek?to=<fraction of the duration>`, `accel?on=0|1`,
        /// `open?screen=` (accounts, tabs, login, up&mid=, or a page such as history), `playseq?ids=aid:cid,…` (play a sequence), `search?q=` (the search tab with a query), `route` (the 线路 tab on its own), `routetest` (its test button), `focus?x=&y=` (focus
        /// what is at that point), `select` (press what has focus), `press?x=&y=` (trigger what is at that point), `probe?class=&match=` (log a
        /// class's methods) and `call?sel=&arg=` (send one to the player, such as
        /// `displayInfoViewControllerWithIdentifier:` with `arg=线路` to open the info panel there).
        private static func handleDebugCommand(_ command: String, _ parameters: [String: String]) {
            switch command {
            case "seek":
                guard let fraction = parameters["to"].flatMap(Double.init),
                      let player = activePlayer(),
                      let duration = player.currentItem?.duration.seconds, duration.isFinite
                else { return }
                player.seek(to: CMTime(seconds: duration * min(max(fraction, 0), 1), preferredTimescale: 600))
            case "play":
                var info: [String: Int] = [:]
                for key in ["aid", "cid", "epid"] {
                    info[key] = parameters[key].flatMap(Int.init) ?? 0
                }
                BiliBiliUpnpDMR.shared.playVideo(json: JSON(info))
            case "detail":
                let aid = parameters["aid"].flatMap(Int.init) ?? 0
                let cid = parameters["cid"].flatMap(Int.init) ?? 0
                VideoDetailViewController.create(aid: aid, cid: cid)
                    .present(from: UIViewController.topMostViewController(), direatlyEnterVideo: false)
            case "stop":
                AppDelegate.shared.window?.rootViewController?.dismiss(animated: false)
            case "home":
                AppDelegate.shared.showTabBar()
            case "tab":
                if let index = parameters["index"].flatMap(Int.init),
                   let tabs = AppDelegate.shared.window?.rootViewController as? UITabBarController,
                   index < (tabs.viewControllers?.count ?? 0)
                {
                    tabs.selectedIndex = index
                }
            case "route":
                // The 线路 tab on its own, over whatever is showing, to check it without a remote.
                let panel = UIViewController()
                panel.modalPresentationStyle = .overFullScreen
                let backdrop = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
                backdrop.frame = CGRect(x: 80, y: 56, width: 1760, height: 290)
                backdrop.layer.cornerRadius = 40
                backdrop.clipsToBounds = true
                panel.view.addSubview(backdrop)
                let route = VideoPlayerRouteInfoViewController()
                panel.addChild(route)
                route.view.frame = backdrop.bounds.insetBy(dx: 0, dy: 20)
                backdrop.contentView.addSubview(route.view)
                route.didMove(toParent: panel)
                UIViewController.topMostViewController().present(panel, animated: false)
            case "routetest":
                Accelerator.shared.testOtherHosts()
            case "focus":
                // Moves focus to the focusable view at a screen point, since there is no remote here.
                guard let window = AppDelegate.shared.window,
                      let x = parameters["x"].flatMap(Double.init), let y = parameters["y"].flatMap(Double.init)
                else { return }
                let point = CGPoint(x: x, y: y)
                var target: UIView?
                func visit(_ view: UIView) {
                    guard !view.isHidden, view.alpha > 0.01 else { return }
                    if view.canBecomeFocused, view.convert(view.bounds, to: window).contains(point) {
                        target = view
                    }
                    view.subviews.forEach(visit)
                }
                visit(window)
                guard let target else { return }
                // tvOS ignores focus requests for views the screen doesn't prefer, so the top view
                // controller prefers the target for one focus update.
                let controller = UIViewController.topMostViewController()
                DebugFocus.prefer(target, in: controller)
            case "open":
                // Presents a screen the tab bar can't reach without a remote: `screen=` accounts,
                // tabs, login, up (with `mid=`), or a page name such as history or toView.
                let top = UIViewController.topMostViewController()
                switch parameters["screen"] {
                case "accounts":
                    let controller = AccountSwitcherViewController()
                    controller.modalPresentationStyle = .overFullScreen
                    top.present(controller, animated: false)
                case "tabs":
                    top.present(TabBarCustomizationViewController(), animated: false)
                case "login":
                    AppDelegate.shared.showLogin()
                case "up":
                    let controller = UpSpaceViewController()
                    controller.mid = parameters["mid"].flatMap(Int.init) ?? 0
                    top.present(controller, animated: false)
                case let name?:
                    if let page = TabBarPage(rawValue: name) {
                        top.present(TabBarPageVCFactory.createVC(for: page), animated: false)
                    }
                case nil:
                    break
                }
            case "playseq":
                // Plays `ids=aid:cid,aid:cid,…` in order, as a collection would.
                let seq = (parameters["ids"] ?? "").split(separator: ",").compactMap { pair -> PlayInfo? in
                    let parts = pair.split(separator: ":").compactMap { Int($0) }
                    return parts.count == 2 ? PlayInfo(aid: parts[0], cid: parts[1]) : nil
                }
                guard let first = seq.first else { return }
                let player = VideoPlayerViewController(playInfo: first)
                player.sequenceProvider = VideoSequenceProvider(seq: seq)
                UIViewController.topMostViewController().present(player, animated: false)
            case "search":
                // Opens the search tab with `q` typed, or empty without it.
                guard let tabs = AppDelegate.shared.window?.rootViewController as? UITabBarController,
                      let index = tabs.viewControllers?.firstIndex(where: { $0 is UISearchContainerViewController }),
                      let container = tabs.viewControllers?[index] as? UISearchContainerViewController
                else { return }
                tabs.selectedIndex = index
                let searchController = container.searchController
                searchController.searchBar.text = parameters["q"] ?? ""
                searchController.searchResultsUpdater?.updateSearchResults(for: searchController)
            case "press":
                // Triggers the cell or control at a screen point without moving focus there,
                // for places focus commands can't reach, such as a sidebar under the tab bar.
                guard let window = AppDelegate.shared.window,
                      let x = parameters["x"].flatMap(Double.init), let y = parameters["y"].flatMap(Double.init)
                else { return }
                let point = CGPoint(x: x, y: y)
                var hit: UIView?
                func visit(_ view: UIView) {
                    guard !view.isHidden, view.alpha > 0.01 else { return }
                    if view is UICollectionViewCell || view is UIControl,
                       view.convert(view.bounds, to: window).contains(point)
                    {
                        hit = view
                    }
                    view.subviews.forEach(visit)
                }
                visit(window)
                if let control = hit as? UIControl {
                    control.sendActions(for: .primaryActionTriggered)
                } else if let cell = hit as? UICollectionViewCell {
                    var ancestor = cell.superview
                    while let view = ancestor, !(view is UICollectionView) {
                        ancestor = view.superview
                    }
                    guard let collectionView = ancestor as? UICollectionView,
                          let indexPath = collectionView.indexPath(for: cell) else { return }
                    collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
                    collectionView.delegate?.collectionView?(collectionView, didSelectItemAt: indexPath)
                }
            case "select":
                // Presses the focused item, as the remote's select button would.
                guard let window = AppDelegate.shared.window,
                      let focused = UIFocusSystem.focusSystem(for: window)?.focusedItem as? UIView
                else { return }
                if let control = focused as? UIControl {
                    control.sendActions(for: .primaryActionTriggered)
                } else if let cell = focused as? UICollectionViewCell {
                    var ancestor = cell.superview
                    while let view = ancestor, !(view is UICollectionView) {
                        ancestor = view.superview
                    }
                    guard let collectionView = ancestor as? UICollectionView,
                          let indexPath = collectionView.indexPath(for: cell) else { return }
                    collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
                    collectionView.delegate?.collectionView?(collectionView, didSelectItemAt: indexPath)
                }
            case "probe":
                // Logs the methods of a class whose names contain `match`, for finding test hooks.
                guard let name = parameters["class"], let cls = NSClassFromString(name) else { return }
                let match = parameters["match"]?.lowercased() ?? ""
                var count: UInt32 = 0
                guard let methods = class_copyMethodList(cls, &count) else { return }
                defer { free(methods) }
                let names = (0..<Int(count)).map { NSStringFromSelector(method_getName(methods[$0])) }
                    .filter { match.isEmpty || $0.lowercased().contains(match) }
                NSLog("probe %@ %@: %@", name, match, names.sorted().joined(separator: " "))
            case "call":
                // Sends a selector, with `arg` as its one argument if given, to the playing AVPlayerViewController.
                guard let name = parameters["sel"] else { return }
                var pending = [UIViewController.topMostViewController()]
                while let controller = pending.popLast() {
                    if let playerVC = controller as? AVPlayerViewController {
                        let selector = NSSelectorFromString(name)
                        NSLog("call %@ responds=%d", name, playerVC.responds(to: selector) ? 1 : 0)
                        if playerVC.responds(to: selector) {
                            if let argument = parameters["arg"] {
                                playerVC.perform(selector, with: argument)
                            } else {
                                playerVC.perform(selector)
                            }
                        }
                        return
                    }
                    pending += controller.children
                }
            case "accel":
                let on = parameters["on"] != "0"
                Settings.acceleratorEnabled = on
                Accelerator.shared.isEnabled = on
            case "quality":
                if let qn = parameters["qn"].flatMap(Int.init),
                   let quality = MediaQualityEnum.allCases.first(where: { $0.qn == qn })
                {
                    Settings.mediaQuality = quality
                }
            default:
                Logger.warn("unknown debug command \(command)")
            }
        }

        /// Makes a view controller prefer one view for the next focus update.
        private enum DebugFocus {
            weak static var target: UIView?
            private static var patched = Set<ObjectIdentifier>()

            static func prefer(_ view: UIView, in controller: UIViewController) {
                patch(type(of: controller))
                target = view
                controller.setNeedsFocusUpdate()
                controller.updateFocusIfNeeded()
                target = nil
            }

            private static func patch(_ cls: AnyClass) {
                guard patched.insert(ObjectIdentifier(cls)).inserted else { return }
                let selector = #selector(getter: UIViewController.preferredFocusEnvironments)
                guard let method = class_getInstanceMethod(cls, selector) else { return }
                typealias Getter = @convention(c) (AnyObject, Selector) -> NSArray
                let original = unsafeBitCast(method_getImplementation(method), to: Getter.self)
                let replacement: @convention(block) (AnyObject) -> NSArray = { object in
                    if let target = DebugFocus.target {
                        return [target]
                    }
                    return original(object, selector)
                }
                class_replaceMethod(cls, selector, imp_implementationWithBlock(replacement), method_getTypeEncoding(method))
            }
        }

        private static func activePlayer() -> AVPlayer? {
            var pending = [UIViewController.topMostViewController()]
            while let controller = pending.popLast() {
                if let player = (controller as? AVPlayerViewController)?.player {
                    return player
                }
                pending.append(contentsOf: controller.children)
            }
            return nil
        }
    #endif

    func showLogin() {
        sceneDelegate?.showLogin()
    }

    func showTabBar() {
        sceneDelegate?.showTabBar()
    }

    func resetTabBar() {
        sceneDelegate?.resetTabBar()
    }

    static var shared: AppDelegate {
        return UIApplication.shared.delegate as! AppDelegate
    }

    private var sceneDelegate: SceneDelegate? {
        UIApplication.shared.connectedScenes.compactMap { $0.delegate as? SceneDelegate }.first
    }
}
