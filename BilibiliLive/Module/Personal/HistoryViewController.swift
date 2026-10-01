//
//  HistoryViewController.swift
//  BilibiliLive
//
//  Created by whw on 2021/4/15.
//

import Alamofire
import SwiftyJSON
import UIKit

class HistoryViewController: UIViewController {
    let collectionVC = FeedCollectionViewController()
    override func viewDidLoad() {
        super.viewDidLoad()
        collectionVC.show(in: self)
        collectionVC.emptyContent = .init(title: "还没有观看记录", symbol: "clock.arrow.circlepath")
        collectionVC.stateView.onRetry = { [weak self] in
            self?.reloadData()
        }
        collectionVC.didSelect = {
            [weak self] in
            guard let history = $0 as? HistoryData else { return }
            self?.goDetail(with: history)
        }
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [collectionVC]
    }

    func goDetail(with history: HistoryData) {
        let detailVC = VideoDetailViewController.create(aid: history.aid, cid: history.cid ?? 0)
        detailVC.present(from: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadData()
    }
}

extension HistoryViewController: BLTabBarContentVCProtocol {
    func reloadData() {
        collectionVC.setState(.loading)
        Task { [weak self] in
            do {
                let datas = try await WebRequest.requestHistory()
                self?.collectionVC.displayDatas = datas
                self?.collectionVC.settleState()
            } catch {
                self?.collectionVC.setState(.failed(error))
            }
        }
    }
}
