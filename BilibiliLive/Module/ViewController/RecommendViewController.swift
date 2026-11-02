import UIKit

/// Keeps the existing recommendation tab stable while switching its presentation.
final class RecommendViewController: UIViewController, BLTabBarContentVCProtocol {
    private var activeMode: Bool?
    private var contentViewController: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        updateContentIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateContentIfNeeded()
    }

    override var preferredFocusEnvironments: [any UIFocusEnvironment] {
        contentViewController.map { [$0] } ?? super.preferredFocusEnvironments
    }

    func reloadData() {
        (contentViewController as? BLTabBarContentVCProtocol)?.reloadData()
    }

    private func updateContentIfNeeded() {
        let usesFeedFlow = Settings.recommendFeedFlowEnabled
        guard activeMode != usesFeedFlow else { return }

        let next = usesFeedFlow ? FeaturedBrowserViewController() : FeedViewController()
        contentViewController?.willMove(toParent: nil)
        contentViewController?.view.removeFromSuperview()
        contentViewController?.removeFromParent()

        addChild(next)
        next.view.frame = view.bounds
        next.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(next.view)
        next.didMove(toParent: self)
        // The tab bar only follows the scroll view of the tab's own controller. Without this it
        // stays up as the feed scrolls, with the featured video's title sliding under it.
        setContentScrollView(next.contentScrollView(for: .top))

        contentViewController = next
        activeMode = usesFeedFlow
    }
}
