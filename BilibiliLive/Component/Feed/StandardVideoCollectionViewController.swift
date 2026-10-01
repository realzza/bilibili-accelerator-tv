//
//  StandardVideoCollectionViewController.swift
//  BilibiliLive
//
//  Created by yicheng on 2022/11/5.
//

import UIKit

protocol PlayableData: DisplayData {
    var aid: Int { get }
    var cid: Int { get }
}

class StandardVideoCollectionViewController<T: PlayableData>: UIViewController, BLTabBarContentVCProtocol {
    let collectionVC = FeedCollectionViewController()
    var lastReloadDate = Date()
    var reloadInterval: TimeInterval = 60 * 60
    var reloading = false
    private var page = 0
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        return [collectionVC]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
        collectionVC.show(in: self)
        reloadData()
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        autoReloadIfNeed()
    }

    func setupCollectionView() {
        collectionVC.pageSize = 20
        collectionVC.didSelect = {
            [weak self] in
            self?.goDetail(with: $0 as! T)
        }
        collectionVC.loadMore = {
            [weak self] in
            self?.loadMore()
        }
        collectionVC.stateView.onRetry = { [weak self] in
            self?.reloadData()
        }
    }

    func supportPullToLoad() -> Bool {
        return true
    }

    func request(page: Int) async throws -> [T] {
        return [T]()
    }

    func goDetail(with record: T) {
        let detailVC = VideoDetailViewController.create(aid: record.aid, cid: record.cid)
        detailVC.present(from: self)
    }

    func reloadData() {
        Task {
            await reallyReloadData()
        }
    }

    func reallyReloadData() async {
        if reloading { return }
        reloading = true
        defer {
            reloading = false
        }
        lastReloadDate = Date()
        page = 1
        collectionVC.setState(.loading)
        do {
            let res = try await request(page: 1)
            collectionVC.displayDatas = []
            collectionVC.appendData(displayData: res)
            collectionVC.settleState()
        } catch is CancellationError {
            collectionVC.settleState()
        } catch let err {
            Logger.warn("load failed: \(err)")
            collectionVC.setState(.failed(err))
        }
    }

    // MARK: - Private

    private func loadMore() {
        guard supportPullToLoad() else { return }
        Task {
            do {
                if let res = (try? await request(page: page + 1)) {
                    collectionVC.appendData(displayData: res)
                    page = page + 1
                }
            }
        }
    }

    func autoReloadIfNeed() {
        guard isViewLoaded, view.window != nil else { return }
        guard Date().timeIntervalSince(lastReloadDate) > reloadInterval else { return }
        Task {
            await reallyReloadData()
        }
    }

    @objc private func didBecomeActive() {
        autoReloadIfNeed()
    }
}
