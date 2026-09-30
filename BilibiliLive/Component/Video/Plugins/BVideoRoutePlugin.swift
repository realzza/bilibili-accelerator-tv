//
//  BVideoRoutePlugin.swift
//  BilibiliLive
//

import AVKit
import UIKit

/// Adds the 线路 tab, first after the system's own, to the player's info panel.
final class BVideoRoutePlugin: NSObject, CommonPlayerPlugin {
    private let routeViewController = VideoPlayerRouteInfoViewController()
    private weak var playerVC: AVPlayerViewController?

    func playerDidLoad(playerVC: AVPlayerViewController) {
        self.playerVC = playerVC
        var controllers = playerVC.customInfoViewControllers.filter { $0 !== routeViewController }
        controllers.insert(routeViewController, at: 0)
        playerVC.customInfoViewControllers = controllers
    }

    func playerDidDismiss(playerVC: AVPlayerViewController) {
        removeTab()
    }

    func playerWillCleanUp(playerVC: AVPlayerViewController) {
        removeTab()
    }

    private func removeTab() {
        playerVC?.customInfoViewControllers.removeAll { $0 === routeViewController }
    }
}
