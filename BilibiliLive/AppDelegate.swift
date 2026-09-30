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
        /// `play?aid=&cid=` (or `epid=`), `detail?aid=&cid=`, `stop`, `tab?index=`, `quality?qn=`,
        /// `seek?to=<fraction of the duration>` and `accel?on=0|1`.
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
            case "tab":
                if let index = parameters["index"].flatMap(Int.init),
                   let tabs = AppDelegate.shared.window?.rootViewController as? UITabBarController,
                   index < (tabs.viewControllers?.count ?? 0)
                {
                    tabs.selectedIndex = index
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
