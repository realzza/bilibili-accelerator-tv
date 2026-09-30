//
//  VideoDetailViewController.swift
//  BilibiliLive
//
//  Created by yicheng on 2021/4/17.
//

import AVKit
import Combine
import Foundation
import UIKit

import Alamofire
import Kingfisher
import MarqueeLabel
import SnapKit
import TVUIKit

private struct PageRange {
    let startIndex: Int
    let endIndex: Int

    var title: String {
        "\(startIndex + 1) - \(endIndex + 1)"
    }
}

class VideoDetailViewController: UIViewController {
    @IBOutlet var effectContainerView: UIVisualEffectView!
    @IBOutlet var contentStackView: UIStackView!
    @IBOutlet var pageCollectionView: UICollectionView!
    @IBOutlet var recommandCollectionView: UICollectionView!
    @IBOutlet var replysCollectionView: UICollectionView!
    @IBOutlet var repliesCollectionViewHeightConstraints: NSLayoutConstraint!
    @IBOutlet var ugcCollectionView: UICollectionView!
    @IBOutlet var pageView: UIView!
    @IBOutlet var ugcLabel: UILabel!
    @IBOutlet var ugcView: UIView!

    private var loadingView = UIActivityIndicatorView()
    private let header = VideoDetailHeaderView()
    /// The cover, top right, behind the header. It fades out as the page scrolls down.
    private let backdrop = BackdropView()

    private var pageCollectionViewTopToTitleConstraint: Constraint?
    private var pageCollectionViewTopToRangeConstraint: Constraint?
    private let pageRangeSize = 20
    private var pageRanges = [PageRange]()
    private lazy var pageRangeCollectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: makePageRangeCollectionViewLayout())
        collectionView.register(BLTextOnlyCollectionViewCell.self, forCellWithReuseIdentifier: String(describing: BLTextOnlyCollectionViewCell.self))
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.backgroundColor = .clear
        collectionView.clipsToBounds = false
        collectionView.isHidden = true
        return collectionView
    }()

    private var epid = 0
    private var seasonId = 0
    private var aid = 0
    private var cid = 0
    private var lastPlayCid: Int?
    private var lastPlayTitle: String?
    private var playTimeInSecond: Int?
    private var subType: Int?
    private var data: VideoDetail?
    @IBOutlet var scrollView: UIScrollView!
    private var didSentCoins = 0 {
        didSet {
            if didSentCoins > 0 {
                header.coinButton.isOn = true
            }
        }
    }

    private var isBangumi = false
    private var startTime = 0
    private var pages = [VideoPage]()
    private var replys: Replys?
    private var subTitles: [SubtitleData]?

    private var allUgcEpisodes = [VideoDetail.Info.UgcSeason.UgcVideoInfo]()

    private var subscriptions = [AnyCancellable]()

    static func create(aid: Int, cid: Int?, epid: Int? = nil) -> VideoDetailViewController {
        let vc = UIStoryboard(name: "Main", bundle: .main).instantiateViewController(identifier: String(describing: self)) as! VideoDetailViewController
        vc.aid = aid
        vc.cid = cid ?? 0
        vc.epid = epid ?? 0
        return vc
    }

    static func create(epid: Int) -> VideoDetailViewController {
        let vc = UIStoryboard(name: "Main", bundle: .main).instantiateViewController(identifier: String(describing: self)) as! VideoDetailViewController
        vc.epid = epid
        return vc
    }

    static func create(seasonId: Int) -> VideoDetailViewController {
        let vc = UIStoryboard(name: "Main", bundle: .main).instantiateViewController(identifier: String(describing: self)) as! VideoDetailViewController
        vc.seasonId = seasonId
        return vc
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupHeader()

        pageCollectionView.register(BLTextOnlyCollectionViewCell.self, forCellWithReuseIdentifier: String(describing: BLTextOnlyCollectionViewCell.self))
        pageCollectionView.collectionViewLayout = makePageCollectionViewLayout()
        pageCollectionView.clipsToBounds = false
        setupPageRangeCollectionView()
        recommandCollectionView.register(RelatedVideoCell.self, forCellWithReuseIdentifier: String(describing: RelatedVideoCell.self))
        ugcCollectionView.register(RelatedVideoCell.self, forCellWithReuseIdentifier: String(describing: RelatedVideoCell.self))
        recommandCollectionView.collectionViewLayout = makeRelatedVideoCollectionViewLayout()
        ugcCollectionView.collectionViewLayout = makeRelatedVideoCollectionViewLayout()

        replysCollectionView.publisher(for: \.contentSize).sink { [weak self] newSize in
            self?.repliesCollectionViewHeightConstraints.constant = newSize.height
            self?.view.setNeedsLayout()
        }.store(in: &subscriptions)

        Task { await fetchData() }
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [header.playButton]
    }

    private func setupHeader() {
        view.backgroundColor = Theme.background
        effectContainerView.effect = nil
        view.insertSubview(backdrop, at: 0)
        backdrop.snp.makeConstraints { make in
            make.top.trailing.equalToSuperview()
            make.width.equalToSuperview().multipliedBy(2.0 / 3)
            make.height.equalTo(backdrop.snp.width).multipliedBy(9.0 / 16)
        }
        // tvOS scrolls about 90 pt to bring 播放 toward the middle, so dimming starts past that.
        scrollView.publisher(for: \.contentOffset).sink { [weak self] offset in
            self?.backdrop.alpha = 1 - min(max((offset.y - 120) / 400, 0), 1)
        }.store(in: &subscriptions)

        contentStackView.insertArrangedSubview(header, at: 0)
        header.playButton.addAction(UIAction { [weak self] _ in self?.actionPlay() }, for: .primaryActionTriggered)
        header.upButton.addAction(UIAction { [weak self] _ in self?.actionShowUpSpace() }, for: .primaryActionTriggered)
        header.followButton.addAction(UIAction { [weak self] _ in self?.actionFollow() }, for: .primaryActionTriggered)
        header.likeButton.button.addAction(UIAction { [weak self] _ in self?.actionLike() }, for: .primaryActionTriggered)
        header.coinButton.button.addAction(UIAction { [weak self] _ in self?.actionCoin() }, for: .primaryActionTriggered)
        header.favButton.button.addAction(UIAction { [weak self] _ in self?.actionFavorite() }, for: .primaryActionTriggered)
        header.watchLaterButton.button.addAction(UIAction { [weak self] _ in self?.actionWatchLater() }, for: .primaryActionTriggered)
        header.dislikeButton.button.addAction(UIAction { [weak self] _ in self?.actionDislike() }, for: .primaryActionTriggered)
        header.noteView.onPrimaryAction = { [weak self] note in
            let detail = ContentDetailViewController.createDesp(content: note.label.text ?? "")
            self?.present(detail, animated: true)
        }
    }

    private func updatePlayProgressIfNeeded(progress: BangumiInfo.UserStatus.Progress?, episode: BangumiInfo.Episode) {
        guard let lastEpId = progress?.last_ep_id,
              let lastTime = progress?.last_time,
              lastEpId == episode.id
        else {
            return
        }
        playTimeInSecond = lastTime
        lastPlayCid = episode.cid
        lastPlayTitle = episode.title + " " + episode.long_title
    }

    private func setupPageRangeCollectionView() {
        let titleLabel = pageView.subviews.compactMap { $0 as? UILabel }.first { $0.text == "视频选集" }!

        pageView.addSubview(pageRangeCollectionView)

        let storyboardTopConstraints = pageView.constraints.filter { constraint in
            (constraint.firstItem as? UICollectionView) === pageCollectionView && constraint.firstAttribute == .top
        }
        storyboardTopConstraints.forEach { $0.isActive = false }

        let storyboardHeightConstraints = (pageView.constraints + pageCollectionView.constraints).filter { constraint in
            (constraint.firstItem as? UICollectionView) === pageCollectionView && constraint.firstAttribute == .height
        }
        storyboardHeightConstraints.forEach { $0.isActive = false }

        pageRangeCollectionView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(30)
            make.height.equalTo(90)
        }
        pageCollectionView.snp.makeConstraints { make in
            pageCollectionViewTopToTitleConstraint = make.top.equalTo(titleLabel.snp.bottom).offset(30).constraint
            pageCollectionViewTopToRangeConstraint = make.top.equalTo(pageRangeCollectionView.snp.bottom).offset(30).constraint
            make.height.equalTo(150)
        }
        pageCollectionViewTopToRangeConstraint?.deactivate()
    }

    private func updatePageRanges() {
        guard pages.count >= pageRangeSize else {
            pageRanges = []
            setPageRangeCollectionViewHidden(true)
            return
        }

        pageRanges = stride(from: 0, to: pages.count, by: pageRangeSize).map { startIndex in
            PageRange(startIndex: startIndex, endIndex: min(startIndex + pageRangeSize, pages.count) - 1)
        }
        setPageRangeCollectionViewHidden(false)
    }

    private func setPageRangeCollectionViewHidden(_ isHidden: Bool) {
        pageRangeCollectionView.isHidden = isHidden
        if isHidden {
            pageCollectionViewTopToRangeConstraint?.deactivate()
            pageCollectionViewTopToTitleConstraint?.activate()
        } else {
            pageCollectionViewTopToTitleConstraint?.deactivate()
            pageCollectionViewTopToRangeConstraint?.activate()
        }
    }

    private func setupLoading() {
        effectContainerView.isHidden = true
        view.addSubview(loadingView)
        loadingView.color = .white
        loadingView.style = .large
        loadingView.startAnimating()
        loadingView.makeConstraintsBindToCenterOfSuperview()
    }

    func present(from vc: UIViewController, direatlyEnterVideo: Bool = Settings.direatlyEnterVideo) {
        if !direatlyEnterVideo {
            vc.present(self, animated: true)
        } else {
            vc.present(self, animated: false) { [weak self] in
                guard let self else { return }
                let player = VideoPlayerViewController(playInfo: PlayInfo(aid: self.aid, cid: self.cid, epid: self.epid, seasonId: isBangumi ? self.seasonId : nil, lastPlayCid: self.lastPlayCid, playTimeInSecond: self.playTimeInSecond))
                self.present(player, animated: true)
            }
        }
    }

    private func exit(with error: Error) {
        Logger.warn(error)
        let alertVC = UIAlertController(title: "获取失败", message: error.localizedDescription, preferredStyle: .alert)
        alertVC.addAction(UIAlertAction(title: "Ok", style: .cancel, handler: { [weak self] action in
            self?.dismiss(animated: true)
        }))
        present(alertVC, animated: true, completion: nil)
    }

    private func fetchData() async {
        scrollView.setContentOffset(.zero, animated: false)
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
        backdrop.imageView.alpha = 0
        setupLoading()
        pageView.isHidden = true
        setPageRangeCollectionViewHidden(true)
        ugcView.isHidden = true
        do {
            if seasonId > 0 {
                isBangumi = true
                let info = try await WebRequest.requestBangumiInfo(seasonID: seasonId)
                subType = info.type
                if let epi = info.episodes.first(where: { $0.id == info.user_status?.progress?.last_ep_id }) ?? info.episodes.first ?? info.section?.first?.episodes.first {
                    aid = epi.aid
                    cid = epi.cid
                    epid = epi.id
                    updatePlayProgressIfNeeded(progress: info.user_status?.progress, episode: epi)
                }
                pages = info.episodes.map({ VideoPage(cid: $0.cid, page: $0.aid, epid: $0.id, from: "", part: $0.title + " " + $0.long_title) })
            } else if epid > 0 {
                isBangumi = true
                let info = try await WebRequest.requestBangumiInfo(epid: epid)
                seasonId = info.season_id
                subType = info.type
                if let epi = info.findEpisodeById(epid) ?? info.episodes.first {
                    aid = epi.aid
                    cid = epi.cid
                    updatePlayProgressIfNeeded(progress: info.user_status?.progress, episode: epi)
                } else {
                    throw NSError(domain: "get epi fail", code: -1)
                }
                pages = info.episodes.map({ VideoPage(cid: $0.cid, page: $0.aid, epid: $0.id, from: "", part: $0.title + " " + $0.long_title) })
            }
            let data = try await WebRequest.requestDetailVideo(aid: aid)
            self.data = data

            if let redirect = data.View.redirect_url?.lastPathComponent, redirect.starts(with: "ep"), let id = Int(redirect.dropFirst(2)), !isBangumi {
                isBangumi = true
                epid = id
                let info = try await WebRequest.requestBangumiInfo(epid: epid)
                seasonId = info.season_id
                subType = info.type
                pages = info.episodes.map({ VideoPage(cid: $0.cid, page: $0.aid, epid: $0.id, from: "", part: $0.title + " " + $0.long_title) })
                if let epi = info.episodes.first(where: { $0.id == epid }) {
                    updatePlayProgressIfNeeded(progress: info.user_status?.progress, episode: epi)
                }
            }
            if !isBangumi {
                let playInfo = try await WebRequest.requestPlayerInfo(aid: aid, cid: cid == 0 ? data.View.cid : cid)
                if cid == 0 {
                    cid = playInfo.last_play_cid > 0 ? playInfo.last_play_cid : data.View.cid
                }
                if playInfo.last_play_cid == cid, let page = data.View.pages?.first(where: { $0.cid == cid }) {
                    playTimeInSecond = playInfo.playTimeInSecond
                    lastPlayCid = playInfo.last_play_cid
                    lastPlayTitle = page.part
                }
            }
            update(with: data)
        } catch let err {
            if case let .statusFail(code, _) = err as? RequestError, code == -404 {
                // 解锁港澳台番剧处理
                if let ok = await fetchAreaLimitBangumiData(), !ok {
                    self.exit(with: err)
                }
            } else {
                self.exit(with: err)
            }
        }

        WebRequest.requestReplys(aid: aid) { [weak self] replys in
            self?.replys = replys
            self?.replysCollectionView.reloadData()
        }

        WebRequest.requestLikeStatus(aid: aid) { [weak self] isLiked in
            self?.header.likeButton.isOn = isLiked
        }

        WebRequest.requestCoinStatus(aid: aid) { [weak self] coins in
            self?.didSentCoins = coins
        }

        if isBangumi {
            header.favButton.isHidden = true
            recommandCollectionView.superview?.isHidden = true
            return
        }

        WebRequest.requestFavoriteStatus(aid: aid) { [weak self] isFavorited in
            self?.header.favButton.isOn = isFavorited
        }
    }

    private func fetchAreaLimitBangumiData() async -> Bool? {
        guard Settings.areaLimitUnlock else { return false }

        do {
            var info: ApiRequest.BangumiInfo?

            if seasonId > 0 {
                info = try await ApiRequest.requestBangumiInfo(seasonID: seasonId)
            } else if epid > 0 {
                info = try await ApiRequest.requestBangumiInfo(epid: epid)
            }
            guard let info = info else { return false }

            let season = try await WebRequest.requestBangumiSeasonView(seasonID: info.season_id)
            isBangumi = true
            if let epi = season.episodes.first(where: { $0.ep_id == epid }) ?? season.episodes.first {
                aid = epi.aid
                cid = epi.cid
                pages = season.episodes.filter { $0.section_type == 0 }.map({ VideoPage(cid: $0.cid, page: $0.aid, epid: $0.ep_id, from: "", part: $0.index + " " + ($0.index_title ?? "")) })

                let userEpisodeInfo = try await WebRequest.requestUserEpisodeInfo(epid: epi.ep_id)

                let data = VideoDetail(View: VideoDetail.Info(aid: aid, cid: cid, title: info.title, videos: nil, pic: epi.cover, desc: info.evaluate, owner: VideoOwner(mid: season.up_info.mid, name: season.up_info.uname, face: season.up_info.avatar), pages: nil, dynamic: nil, bvid: epi.bvid, duration: epi.durationSeconds, pubdate: epi.pubdate, ugc_season: nil, redirect_url: nil, stat: VideoDetail.Info.Stat(favorite: info.stat.favorites, coin: info.stat.coins, like: info.stat.likes, share: info.stat.share, danmaku: info.stat.danmakus, view: info.stat.views)), Related: [], Card: VideoDetail.Owner(following: userEpisodeInfo.related_up.first?.is_follow == 1, follower: season.up_info.follower))

                self.data = data
                update(with: data)
                return true
            }

        } catch let err {
            print(err)
        }

        return false
    }

    private func update(with data: VideoDetail) {
        header.titleLabel.text = data.title
        header.setUploader(name: data.ownerName, avatar: data.avatar(size: 240))
        header.followersLabel.text = Self.count(data.Card.follower ?? 0) + " 粉丝"
        header.isFollowing = data.Card.following
        let stats = [Self.count(data.View.stat.view) + " 播放",
                     Self.count(data.View.stat.danmaku) + " 弹幕",
                     data.View.date,
                     TimeInterval(data.View.duration).timeString(),
                     data.View.bvid]
        header.statsLabel.text = stats.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        header.coinButton.title = Self.count(data.View.stat.coin)
        header.favButton.title = Self.count(data.View.stat.favorite)
        header.likeButton.title = Self.count(data.View.stat.like)

        // 更新播放按钮标题
        if Settings.continuePlay {
            if let lastPlayCid, lastPlayCid == cid {
                header.playTitle = "继续播放"
            } else {
                header.playTitle = "播放"
            }
        }

        backdrop.imageView.kf.setImage(with: data.pic, options: [.processor(DownsamplingImageProcessor(size: CGSize(width: 1280, height: 720)))])
        recommandCollectionView.superview?.isHidden = data.Related.count == 0

        var notes = [String]()
        let status = data.View.dynamic ?? ""
        if status.count > 1, status != data.View.desc {
            notes.append(status)
        }
        notes.append(data.View.desc ?? "")
        let note = notes.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        header.noteView.label.text = note
        header.noteView.isHidden = note.isEmpty || note == "-"
        if !isBangumi {
            pages = data.View.pages ?? []
        }
        updatePageRanges()
        pageRangeCollectionView.reloadData()
        if pages.count > 1 {
            pageCollectionView.reloadData()
            pageView.isHidden = false
            let index = pages.firstIndex { $0.cid == cid } ?? 0
            pageCollectionView.scrollToItem(at: IndexPath(row: index, section: 0), at: .left, animated: false)
            if cid == 0 {
                cid = pages.first?.cid ?? 0
            }
        }
        loadingView.stopAnimating()
        loadingView.removeFromSuperview()
        effectContainerView.isHidden = false
        UIView.animate(withDuration: 0.25) {
            self.backdrop.imageView.alpha = 1
        }

        if let season = data.View.ugc_season {
            if season.sections.count > 1 {
                if let section = season.sections.first(where: { section in section.episodes.contains(where: { episode in episode.aid == data.View.aid }) }) {
                    allUgcEpisodes = section.episodes
                }
            } else {
                allUgcEpisodes = season.sections.first?.episodes ?? []
            }
            allUgcEpisodes.sort { $0.arc.ctime < $1.arc.ctime }
        }

        ugcCollectionView.reloadData()
        if let season = data.View.ugc_season {
            var parts = ["合集", season.title]
            if season.sections.count > 1,
               let section = season.sections.first(where: { $0.episodes.contains { $0.aid == data.View.aid } })
            {
                parts.append(section.title)
            }
            ugcLabel.text = parts.filter { !$0.isEmpty }.joined(separator: " · ")
        }
        ugcView.isHidden = allUgcEpisodes.count == 0
        if allUgcEpisodes.count > 0 {
            ugcCollectionView.scrollToItem(at: IndexPath(item: allUgcEpisodes.map { $0.aid }.firstIndex(of: aid) ?? 0, section: 0), at: .left, animated: false)
        }

        recommandCollectionView.reloadData()
    }

    /// `12.3万`: `numberString()` without its space, for the tight lines of the header.
    private static func count(_ value: Int) -> String {
        value.numberString().replacingOccurrences(of: " ", with: "")
    }

    private func actionShowUpSpace() {
        let upSpaceVC = UpSpaceViewController()
        upSpaceVC.mid = data?.View.owner.mid
        present(upSpaceVC, animated: true)
    }

    private func actionFollow() {
        header.isFollowing.toggle()
        if let mid = data?.View.owner.mid {
            WebRequest.follow(mid: mid, follow: header.isFollowing)
        }
    }

    private func actionPlay() {
        let player = VideoPlayerViewController(playInfo: PlayInfo(aid: aid, cid: cid, epid: epid, seasonId: seasonId, subType: subType, lastPlayCid: lastPlayCid, playTimeInSecond: playTimeInSecond, title: data?.title))
        player.data = data
        if pages.count > 0, let index = pages.firstIndex(where: { $0.cid == cid }) {
            let seq = pages.map({ PlayInfo(aid: aid, cid: $0.cid, epid: $0.epid, seasonId: seasonId, subType: subType, title: $0.part) })
            if seq.count > 0 {
                player.sequenceProvider = VideoSequenceProvider(seq: seq, currentIndex: index)
            }
        }
        if allUgcEpisodes.count > 0, let index = allUgcEpisodes.firstIndex(where: { $0.cid == cid }) {
            let seq = allUgcEpisodes.map({ PlayInfo(aid: $0.aid, cid: $0.cid, title: $0.title) })
            if seq.count > 0 {
                player.sequenceProvider = VideoSequenceProvider(seq: seq, currentIndex: index)
            }
        }
        present(player, animated: true, completion: nil)
    }

    private func actionLike() {
        let likeButton = header.likeButton
        Task {
            if likeButton.isOn {
                likeButton.title? -= 1
            } else {
                likeButton.title? += 1
            }
            likeButton.isOn.toggle()
            let success = await WebRequest.requestLike(aid: aid, like: likeButton.isOn)
            if !success {
                likeButton.isOn.toggle()
            }
        }
    }

    private func actionCoin() {
        guard didSentCoins < 2 else { return }
        let coinButton = header.coinButton
        let likeButton = header.likeButton
        let alert = UIAlertController(title: "投币个数", message: nil, preferredStyle: .actionSheet)
        WebRequest.requestTodayCoins { todayCoins in
            alert.message = "今日已投(\(todayCoins / 10)/5)个币"
        }
        let aid = aid
        alert.addAction(UIAlertAction(title: "1", style: .default) { [weak self] _ in
            guard let self else { return }
            coinButton.title? += 1
            if !likeButton.isOn {
                likeButton.title? += 1
                likeButton.isOn = true
            }
            self.didSentCoins += 1
            WebRequest.requestCoin(aid: aid, num: 1)
        })
        if didSentCoins == 0 {
            alert.addAction(UIAlertAction(title: "2", style: .default) { [weak self] _ in
                guard let self else { return }
                coinButton.title? += 2
                if !likeButton.isOn {
                    likeButton.title? += 1
                    likeButton.isOn = true
                }
                self.didSentCoins += 2
                WebRequest.requestCoin(aid: aid, num: 2)
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func actionFavorite() {
        let favButton = header.favButton
        Task {
            guard let favList = try? await WebRequest.requestFavVideosList() else {
                return
            }
            if favButton.isOn {
                favButton.title? -= 1
                favButton.isOn = false
                WebRequest.removeFavorite(aid: aid, mid: favList.map { $0.id })
                return
            }
            let alert = UIAlertController(title: "收藏", message: nil, preferredStyle: .actionSheet)
            let aid = aid
            for fav in favList {
                alert.addAction(UIAlertAction(title: fav.title, style: .default) { _ in
                    favButton.title? += 1
                    favButton.isOn = true
                    WebRequest.requestFavorite(aid: aid, mid: fav.id)
                })
            }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            present(alert, animated: true)
        }
    }

    private func actionWatchLater() {
        let button = header.watchLaterButton
        let add = !button.isOn
        button.isOn = add
        button.title = add ? "已添加" : "稍后看"
        let aid = aid
        Task {
            guard await !WebRequest.requestToView(aid: aid, add: add) else { return }
            button.isOn = !add
            button.title = add ? "稍后看" : "已添加"
        }
    }

    private func actionDislike() {
        header.dislikeButton.isOn.toggle()
        ApiRequest.requestDislike(aid: aid, dislike: header.dislikeButton.isOn)
    }
}

extension VideoDetailViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch collectionView {
        case pageRangeCollectionView:
            let range = pageRanges[indexPath.item]
            pageCollectionView.scrollToItem(at: IndexPath(item: range.startIndex, section: 0), at: .left, animated: true)
        case pageCollectionView:
            let page = pages[indexPath.item]
            let player = VideoPlayerViewController(playInfo: PlayInfo(aid: isBangumi ? page.page : aid, cid: page.cid, epid: page.epid, seasonId: seasonId, subType: subType, lastPlayCid: lastPlayCid, playTimeInSecond: playTimeInSecond, title: page.part))
            player.data = isBangumi ? nil : data

            let seq = pages.map({ PlayInfo(aid: isBangumi ? $0.page : aid, cid: $0.cid, epid: $0.epid, seasonId: seasonId, subType: subType, title: $0.part) })
            if seq.count > 0 {
                player.sequenceProvider = VideoSequenceProvider(seq: seq, currentIndex: indexPath.item)
            }
            present(player, animated: true, completion: nil)
        case replysCollectionView:
            guard let reply = replys?.replies?[indexPath.item] else { return }
            let detail = ReplyDetailViewController(reply: reply)
            present(detail, animated: true)
        case ugcCollectionView:
            let video = allUgcEpisodes[indexPath.item]
            if Settings.showRelatedVideoInCurrentVC {
                aid = video.aid
                cid = video.cid
                Task { await fetchData() }
            } else {
                let detailVC = VideoDetailViewController.create(aid: video.aid, cid: video.cid)
                detailVC.present(from: self)
            }
        case recommandCollectionView:
            if let video = data?.Related[indexPath.item] {
                if Settings.showRelatedVideoInCurrentVC {
                    aid = video.aid
                    cid = video.cid
                    Task { await fetchData() }
                } else {
                    let detailVC = VideoDetailViewController.create(aid: video.aid, cid: video.cid)
                    detailVC.present(from: self)
                }
            }
        default:
            break
        }
    }
}

extension VideoDetailViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch collectionView {
        case pageRangeCollectionView:
            return pageRanges.count
        case pageCollectionView:
            return pages.count
        case replysCollectionView:
            return replys?.replies?.count ?? 0
        case ugcCollectionView:
            return allUgcEpisodes.count
        case recommandCollectionView:
            return data?.Related.count ?? 0
        default:
            return 0
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch collectionView {
        case pageRangeCollectionView:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "BLTextOnlyCollectionViewCell", for: indexPath) as! BLTextOnlyCollectionViewCell
            cell.titleLabel.text = pageRanges[indexPath.item].title
            return cell
        case pageCollectionView:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "BLTextOnlyCollectionViewCell", for: indexPath) as! BLTextOnlyCollectionViewCell
            let page = pages[indexPath.item]
            cell.titleLabel.text = page.part
            return cell
        case replysCollectionView:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: String(describing: ReplyCell.self), for: indexPath) as! ReplyCell
            if let reply = replys?.replies?[indexPath.item] {
                cell.config(replay: reply)
            }
            return cell
        case ugcCollectionView:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: String(describing: RelatedVideoCell.self), for: indexPath) as! RelatedVideoCell
            let record = allUgcEpisodes[indexPath.row]
            cell.update(data: record, isCurrent: record.aid == aid)
            return cell
        case recommandCollectionView:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: String(describing: RelatedVideoCell.self), for: indexPath) as! RelatedVideoCell
            if let related = data?.Related[indexPath.row] {
                cell.update(data: related)
            }
            return cell
        default:
            return UICollectionViewCell()
        }
    }
}

class BLCardView: TVCardView {
    /// White at 0.08 over the ground, made opaque: the card draws translucent colors as white.
    static let restingFill = UIColor(red: 33 / 255, green: 35 / 255, blue: 38 / 255, alpha: 1)

    var fill = BLCardView.restingFill {
        didSet { cardBackgroundColor = fill }
    }

    /// The cell around the card takes focus and draws it. The card's own focus effect grows its
    /// content past the clipped background, which only shifts the content.
    override var canBecomeFocused: Bool {
        false
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        focusSizeIncrease = .zero
        subviews.first?.subviews.first?.subviews.last?.subviews.first?.subviews.first?.layer.cornerRadius = Theme.rowRadius
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        cardBackgroundColor = fill
    }
}

extension VideoDetailViewController {
    func makePageCollectionViewLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout {
            _, _ in
            let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                                  heightDimension: .fractionalHeight(1.0))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let groupSize = NSCollectionLayoutSize(widthDimension: .absolute(300), heightDimension: .absolute(150))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = .init(top: 0, leading: 8, bottom: 0, trailing: 8)
            section.orthogonalScrollingBehavior = .continuous
            section.interGroupSpacing = 40
            return section
        }
    }

    func makePageRangeCollectionViewLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout {
            _, _ in
            let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                                  heightDimension: .fractionalHeight(1.0))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let groupSize = NSCollectionLayoutSize(widthDimension: .absolute(200), heightDimension: .fractionalHeight(1))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = .init(top: 0, leading: 8, bottom: 0, trailing: 8)
            section.orthogonalScrollingBehavior = .continuous
            section.interGroupSpacing = 40
            return section
        }
    }

    func makeRelatedVideoCollectionViewLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout {
            _, _ in
            let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                                  heightDimension: .estimated(256))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let groupSize = NSCollectionLayoutSize(widthDimension: .absolute(380), heightDimension: .estimated(256))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = .init(top: 40, leading: 8, bottom: 0, trailing: 8)
            section.orthogonalScrollingBehavior = .continuous
            section.interGroupSpacing = 40
            return section
        }
    }
}

/// A small video card in a row: 16:9 artwork and a one-line title, with 正在看 on the
/// episode that is open.
class RelatedVideoCell: BLMotionCollectionViewCell {
    let titleLabel = MarqueeLabel()
    let imageView = UIImageView()
    private let artwork = UIView()
    private let badgeLabel = PillLabel()

    override var shadowLayer: CALayer {
        artwork.layer
    }

    override func setup() {
        super.setup()
        scaleFactor = 1.08
        contentView.addSubview(artwork)
        contentView.addSubview(titleLabel)
        artwork.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.height.equalTo(artwork.snp.width).multipliedBy(9.0 / 16)
        }
        artwork.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        imageView.layer.cornerRadius = Theme.cardRadius
        imageView.layer.cornerCurve = .continuous
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = UIColor(white: 1, alpha: 0.06)
        artwork.addSubview(badgeLabel)
        badgeLabel.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().inset(12)
        }
        badgeLabel.text = "正在看"
        badgeLabel.font = .systemFont(ofSize: 18, weight: .bold)
        badgeLabel.textColor = Theme.onAccent
        badgeLabel.backgroundColor = Theme.accent
        badgeLabel.layer.cornerRadius = 10
        badgeLabel.clipsToBounds = true
        badgeLabel.isHidden = true
        titleLabel.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(artwork.snp.bottom).offset(12)
        }
        titleLabel.setContentHuggingPriority(.required, for: .vertical)
        titleLabel.font = .systemFont(ofSize: 25, weight: .medium)
        titleLabel.textColor = Theme.textPrimary
        titleLabel.fadeLength = 40
        stopScroll()
    }

    func update(data: any DisplayData, isCurrent: Bool = false) {
        titleLabel.text = data.title
        badgeLabel.isHidden = !isCurrent
        imageView.kf.setImage(with: data.pic, options: [.processor(DownsamplingImageProcessor(size: CGSize(width: 380, height: 214))), .cacheOriginalImage])
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        if isFocused {
            startScroll()
        } else {
            stopScroll()
        }
    }

    private func startScroll() {
        titleLabel.restartLabel()
        titleLabel.holdScrolling = false
    }

    private func stopScroll() {
        titleLabel.shutdownLabel()
        titleLabel.holdScrolling = true
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        stopScroll()
    }
}

class DetailLabel: UILabel {
    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations {
            if self.isFocused {
                self.backgroundColor = .white
            } else {
                self.backgroundColor = .clear
            }
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        isUserInteractionEnabled = true
    }

    override var canBecomeFocused: Bool {
        return true
    }

    override func drawText(in rect: CGRect) {
        let insets = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 5)
        super.drawText(in: rect.inset(by: insets))
    }
}

class NoteDetailView: UIControl {
    let label = UILabel()
    var onPrimaryAction: ((NoteDetailView) -> Void)?
    private let backgroundView = UIView()
    init() {
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func setup() {
        addSubview(backgroundView)
        backgroundView.backgroundColor = Theme.focusedFill
        backgroundView.layer.cornerRadius = Theme.rowRadius
        backgroundView.layer.cornerCurve = .continuous
        backgroundView.alpha = 0
        backgroundView.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.left.equalToSuperview().offset(-20)
            make.right.equalToSuperview().offset(20)
        }

        addSubview(label)
        label.numberOfLines = 2
        label.font = .systemFont(ofSize: 24)
        label.textColor = Theme.textSecondary
        label.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalToSuperview().offset(12)
            make.bottom.equalToSuperview().offset(-12)
        }
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations {
            self.backgroundView.alpha = self.isFocused ? 1 : 0
            self.label.textColor = self.isFocused ? Theme.focusedText : Theme.textSecondary
            self.transform = self.isFocused ? CGAffineTransform(scaleX: 1.02, y: 1.02) : .identity
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        super.pressesEnded(presses, with: event)
        if presses.first?.type == .select {
            sendActions(for: .primaryActionTriggered)
            onPrimaryAction?(self)
        }
    }
}

class ContentDetailViewController: UIViewController {
    private let titleLabel = UILabel()
    private let contentTextView = UITextView()

    static func createDesp(content: String) -> ContentDetailViewController {
        let vc = ContentDetailViewController()
        vc.titleLabel.text = "简介"
        vc.contentTextView.text = content
        return vc
    }

    static func createReply(content: String) -> ContentDetailViewController {
        let vc = ContentDetailViewController()
        vc.titleLabel.text = "评论"
        vc.contentTextView.text = content
        return vc
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [contentTextView]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(titleLabel)
        view.addSubview(contentTextView)
        titleLabel.font = UIFont.systemFont(ofSize: 60, weight: .semibold)
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(80)
            make.centerX.equalToSuperview()
        }
        contentTextView.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        contentTextView.isScrollEnabled = true
        contentTextView.isUserInteractionEnabled = true
        contentTextView.isSelectable = true
        contentTextView.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom)
            make.centerX.equalToSuperview()
            make.leading.equalToSuperview().offset(60)
            make.trailing.equalToSuperview().inset(60)
            make.bottom.equalToSuperview().inset(80)
        }
    }
}
