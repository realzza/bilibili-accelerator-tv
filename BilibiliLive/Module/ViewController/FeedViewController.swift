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

    /// The featured video's page data: its description and danmaku count, which the feed item
    /// doesn't carry.
    private var heroDetail: VideoDetail?
    private var heroInWatchLater = false

    private func refreshHero() {
        heroDetail = nil
        heroInWatchLater = false
        if let heroView {
            configure(heroView)
        }
        setNeedsFocusUpdate()
        guard let hero else { return }
        Task { [weak self] in
            guard let detail = try? await WebRequest.requestDetailVideo(aid: hero.aid),
                  let self, self.hero?.aid == hero.aid else { return }
            heroDetail = detail
            if let heroView {
                configure(heroView)
            }
        }
    }

    private func configure(_ view: HeroHeaderView) {
        guard let hero else {
            view.isHidden = true
            return
        }
        view.isHidden = false
        let facts = CardFacts(overlay: hero.overlay)
        var meta = [hero.ownerName, facts.views, facts.duration]
        if let info = heroDetail?.View {
            meta = [hero.ownerName,
                    Self.count(info.stat.view) + "播放",
                    Self.count(info.stat.danmaku) + "弹幕",
                    facts.duration ?? TimeInterval(info.duration).timeString()]
        }
        view.configure(title: hero.title,
                       kicker: hero.top_rcmd_reason ?? hero.bottom_rcmd_reason,
                       meta: meta.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                       description: heroDetail?.View.desc,
                       cover: hero.pic, hasUpSpace: hero.args.up_id != nil)
        view.isInWatchLater = heroInWatchLater
        view.onPlay = { [weak self] in
            guard let self else { return }
            VideoDetailViewController.create(aid: hero.aid, cid: hero.cid).present(from: self, direatlyEnterVideo: true)
        }
        view.onDetail = { [weak self] in
            self?.goDetail(with: hero)
        }
        view.onWatchLater = { [weak self, weak view] in
            guard let self else { return }
            let add = !self.heroInWatchLater
            self.heroInWatchLater = add
            view?.isInWatchLater = add
            Task {
                guard await !WebRequest.requestToView(aid: hero.aid, add: add), self.hero?.aid == hero.aid else { return }
                self.heroInWatchLater = !add
                view?.isInWatchLater = !add
            }
        }
        view.onUpSpace = { [weak self] in
            guard let mid = hero.args.up_id else { return }
            let upSpaceVC = UpSpaceViewController()
            upSpaceVC.mid = mid
            self?.present(upSpaceVC, animated: true)
        }
    }

    private static func count(_ value: Int) -> String {
        value.numberString().replacingOccurrences(of: " ", with: "")
    }
}

extension ApiRequest.FeedResp.Items: PlayableData {
    var aid: Int { Int(param) ?? 0 }
    var cid: Int { player_args?.cid ?? 0 }
}
