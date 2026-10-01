//
//  BLTabBarViewController.swift
//  BilibiliLive
//
//  Created by Etan Chen on 2021/4/5.
//

import UIKit

protocol BLTabBarContentVCProtocol {
    func reloadData()
}

class BLTabBarViewController: UITabBarController, UITabBarControllerDelegate {
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Tab titles a little larger than the system's, which read small from the couch.
    static let titleFont = UIFont.systemFont(ofSize: 32, weight: .semibold)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        enlargeTabTitles()
        delegate = self
        Settings.bootstrapTabBarPlacementModelIfNeeded()
        NotificationCenter.default.addObserver(self, selector: #selector(handleTabBarPagesDidChange), name: .tabBarPagesDidChange, object: nil)
        reloadTabs(animated: false)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        super.pressesEnded(presses, with: event)
        guard let buttonPress = presses.first?.type else { return }
        if buttonPress == .playPause {
            if let reloadVC = topMostViewController() as? BLTabBarContentVCProtocol {
                print("send reload to \(reloadVC)")
                reloadVC.reloadData()
            }
        }
    }

    @objc private func handleTabBarPagesDidChange() {
        reloadTabs(animated: false)
    }

    private func reloadTabs(animated: Bool) {
        // On launch, the tab the viewer last used, or 推荐 the first time.
        let previousPage = selectedViewController?.tabBarItem.accessibilityIdentifier
            ?? Settings.lastTabPage ?? TabBarPage.feed.rawValue
        let pages = Settings.tabBarPages
        let controllers = pages.map { controller(for: $0) }

        setViewControllers(controllers, animated: animated)

        if let index = controllers.firstIndex(where: { $0.tabBarItem.accessibilityIdentifier == previousPage }) {
            selectedIndex = index
        }
    }

    /// Starts from the system's appearance, so the bar keeps its glass, and changes only the font.
    private func enlargeTabTitles() {
        let appearance = tabBar.standardAppearance.copy()
        for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            for state in [layout.normal, layout.selected, layout.focused, layout.disabled] {
                state.titleTextAttributes[.font] = Self.titleFont
            }
        }
        tabBar.standardAppearance = appearance
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        Settings.lastTabPage = viewController.tabBarItem.accessibilityIdentifier
    }

    private func controller(for page: TabBarPage) -> UIViewController {
        return TabBarPageVCFactory.createVC(for: page)
    }
}
