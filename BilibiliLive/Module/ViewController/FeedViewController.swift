//
//  FeedViewController.swift
//  BilibiliLive
//
//  Created by yicheng on 2021/5/19.
//

import UIKit

class FeedViewController: StandardVideoCollectionViewController<ApiRequest.FeedResp.Items> {
    /// The first playable video of the first page, shown large above the grid instead of in it.
    private var hero: ApiRequest.FeedResp.Items? {
        didSet {
            refreshHero()
        }
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if hero != nil, let heroView {
            return [heroView.playButton]
        }
        return super.preferredFocusEnvironments
    }

    private var heroView: HeroHeaderView? {
        collectionVC.collectionView?
            .visibleSupplementaryViews(ofKind: String(describing: HeroHeaderView.self))
            .first as? HeroHeaderView
    }

    override func setupCollectionView() {
        super.setupCollectionView()
        collectionVC.pageSize = 1
        collectionVC.showHeader = true
        collectionVC.customHeaderConfig = FeedHeaderConfig(viewType: HeroHeaderView.self,
                                                           estimatedHeight: HeroHeaderView.height)
        { [weak self] view, _ in
            self?.configure(view)
        }
    }

    override func request(page: Int) async throws -> [ApiRequest.FeedResp.Items] {
        if page == 1 {
            var items = try await ApiRequest.getFeeds()
            if let index = items.firstIndex(where: { $0.goto == "av" && $0.cid > 0 }) {
                let featured = items.remove(at: index)
                await MainActor.run { hero = featured }
            }
            return items
        } else if let last = (collectionVC.displayDatas.last as? ApiRequest.FeedResp.Items)?.idx {
            return try await ApiRequest.getFeeds(lastIdx: last)
        } else {
            throw NSError(domain: "", code: -1)
        }
    }

    private func refreshHero() {
        if let heroView {
            configure(heroView)
        }
        setNeedsFocusUpdate()
    }

    private func configure(_ view: HeroHeaderView) {
        guard let hero else {
            view.isHidden = true
            return
        }
        view.isHidden = false
        let facts = CardFacts(overlay: hero.overlay)
        let meta = [hero.ownerName, facts.views, facts.duration].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        view.configure(title: hero.title, kicker: hero.top_rcmd_reason ?? hero.bottom_rcmd_reason,
                       meta: meta, cover: hero.pic, hasUpSpace: hero.args.up_id != nil)
        view.onPlay = { [weak self] in
            guard let self else { return }
            VideoDetailViewController.create(aid: hero.aid, cid: hero.cid).present(from: self, direatlyEnterVideo: true)
        }
        view.onDetail = { [weak self] in
            self?.goDetail(with: hero)
        }
        view.onUpSpace = { [weak self] in
            guard let mid = hero.args.up_id else { return }
            let upSpaceVC = UpSpaceViewController()
            upSpaceVC.mid = mid
            self?.present(upSpaceVC, animated: true)
        }
    }
}

extension ApiRequest.FeedResp.Items: PlayableData {
    var aid: Int { Int(param) ?? 0 }
    var cid: Int { player_args?.cid ?? 0 }
}
