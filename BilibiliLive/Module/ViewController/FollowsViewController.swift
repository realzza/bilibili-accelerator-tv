//
//  FollowsViewController.swift
//  BilibiliLive
//
//  Created by Etan Chen on 2021/4/4.
//

import Alamofire
import Kingfisher
import SnapKit
import SwiftyJSON
import UIKit

final class FollowsViewController: UIViewController, BLTabBarContentVCProtocol {
    private enum LayoutMode {
        case feedFlow
        case grid
    }

    private var currentMode: LayoutMode?
    private var currentContentViewController: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleLayoutModeDidChange),
                                               name: .followsLayoutModeDidChange,
                                               object: nil)
        syncLayoutIfNeeded(force: true)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        syncLayoutIfNeeded(force: false)
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        currentContentViewController?.preferredFocusEnvironments ?? [view]
    }

    func reloadData() {
        if let content = currentContentViewController as? BLTabBarContentVCProtocol {
            content.reloadData()
        } else {
            syncLayoutIfNeeded(force: true)
        }
    }

    @objc private func handleLayoutModeDidChange() {
        guard isViewLoaded else { return }
        syncLayoutIfNeeded(force: true)
    }

    private func syncLayoutIfNeeded(force: Bool) {
        let targetMode: LayoutMode = Settings.followsFeedFlowEnabled ? .feedFlow : .grid
        guard force || currentMode != targetMode else { return }

        let targetViewController: UIViewController
        switch targetMode {
        case .feedFlow:
            targetViewController = FollowsFeedFlowViewController()
        case .grid:
            targetViewController = FollowsSubscriptionsViewController()
        }

        transition(to: targetViewController)
        currentMode = targetMode
    }

    private func transition(to targetViewController: UIViewController) {
        let previousViewController = currentContentViewController
        addChild(targetViewController)
        view.addSubview(targetViewController.view)
        targetViewController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        targetViewController.didMove(toParent: self)
        currentContentViewController = targetViewController

        guard let previousViewController else { return }
        previousViewController.willMove(toParent: nil)
        previousViewController.view.removeFromSuperview()
        previousViewController.removeFromParent()
    }
}

/// 关注 as subscriptions: the uploaders you follow down the side, recently updated first, and on
/// the right either everyone's new videos (全部动态) or the selected uploader's.
final class FollowsSubscriptionsViewController: UIViewController, BLTabBarContentVCProtocol {
    private enum Row: Hashable {
        case all
        case up(WebRequest.FollowedUp)
    }

    private var rows: [Row] = [.all]
    private let sidebar = UICollectionView(frame: .zero, collectionViewLayout: BLSettingLineCollectionViewCell.makeLayout())
    private let contentView = UIView()
    private lazy var allFeed: FollowsGridViewController = {
        let feed = FollowsGridViewController()
        feed.collectionVC.styleOverride = .sideBar
        return feed
    }()

    private weak var current: UIViewController?
    private var selectedRow: Row = .all

    override func viewDidLoad() {
        super.viewDidLoad()
        sidebar.register(FollowUpSidebarCell.self, forCellWithReuseIdentifier: "cell")
        sidebar.dataSource = self
        sidebar.delegate = self
        sidebar.remembersLastFocusedIndexPath = true
        view.addSubview(sidebar)
        sidebar.snp.makeConstraints { make in
            make.leading.bottom.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.width.equalTo(500)
        }
        view.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.bottom.trailing.equalToSuperview()
            make.leading.equalTo(sidebar.snp.trailing)
        }
        show(allFeed)
        sidebar.selectItem(at: IndexPath(item: 0, section: 0), animated: false, scrollPosition: [])
        loadUps()
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [current, sidebar].compactMap { $0 }
    }

    func reloadData() {
        (current as? BLTabBarContentVCProtocol)?.reloadData()
        loadUps()
    }

    private func loadUps() {
        Task { [weak self] in
            guard let ups = try? await WebRequest.requestFollowedUps(), let self else { return }
            rows = [.all] + ups.map { .up($0) }
            sidebar.reloadData()
            if let index = rows.firstIndex(of: selectedRow) {
                sidebar.selectItem(at: IndexPath(item: index, section: 0), animated: false, scrollPosition: [])
            }
        }
    }

    private func select(_ row: Row) {
        guard row != selectedRow || current == nil else { return }
        selectedRow = row
        switch row {
        case .all:
            show(allFeed)
        case let .up(up):
            let space = UpSpaceViewController()
            space.mid = up.mid
            space.collectionVC.styleOverride = .sideBar
            show(space)
        }
    }

    private func show(_ controller: UIViewController) {
        guard controller !== current else { return }
        if let current {
            current.willMove(toParent: nil)
            current.view.removeFromSuperview()
            current.removeFromParent()
        }
        addChild(controller)
        contentView.addSubview(controller.view)
        controller.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        controller.didMove(toParent: self)
        current = controller
    }
}

extension FollowsSubscriptionsViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        rows.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! FollowUpSidebarCell
        switch rows[indexPath.item] {
        case .all:
            cell.configure(title: "全部动态", avatar: nil, symbol: "square.grid.2x2", hasUpdate: false)
        case let .up(up):
            cell.configure(title: up.name, avatar: up.face, symbol: nil, hasUpdate: up.hasUpdate)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        select(rows[indexPath.item])
    }

    func collectionView(_ collectionView: UICollectionView, didUpdateFocusIn context: UICollectionViewFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        guard Settings.sideMenuAutoSelectChange, let indexPath = context.nextFocusedIndexPath else { return }
        collectionView.selectItem(at: indexPath, animated: true, scrollPosition: [])
        select(rows[indexPath.item])
    }
}

/// A sidebar row for an uploader: avatar, name, and a pink dot when they have posted since you
/// last looked.
final class FollowUpSidebarCell: BLSettingLineCollectionViewCell {
    private let avatarView = UIImageView()
    private let updateDot = UIView()

    override func setup() {
        super.setup()
        contentView.addSubview(avatarView)
        avatarView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(18)
            make.centerY.equalToSuperview()
            make.size.equalTo(44)
        }
        avatarView.layer.cornerRadius = 22
        avatarView.clipsToBounds = true
        avatarView.contentMode = .scaleAspectFill
        avatarView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        contentView.addSubview(updateDot)
        updateDot.backgroundColor = Theme.accent
        updateDot.layer.cornerRadius = 6
        updateDot.snp.makeConstraints { make in
            make.size.equalTo(12)
            make.trailing.equalToSuperview().offset(-22)
            make.centerY.equalToSuperview()
        }
        titleLabel.snp.remakeConstraints { make in
            make.leading.equalTo(avatarView.snp.trailing).offset(16)
            make.trailing.equalTo(updateDot.snp.leading).offset(-12)
            make.centerY.equalToSuperview()
        }
    }

    func configure(title: String, avatar: URL?, symbol: String?, hasUpdate: Bool) {
        titleLabel.text = title
        updateDot.isHidden = !hasUpdate
        avatarView.kf.cancelDownloadTask()
        if let symbol {
            avatarView.image = UIImage(systemName: symbol)
            avatarView.contentMode = .center
            avatarView.backgroundColor = .clear
        } else {
            avatarView.image = nil
            avatarView.contentMode = .scaleAspectFill
            avatarView.backgroundColor = Theme.groupedFill
            avatarView.kf.setImage(with: avatar, options: [.processor(DownsamplingImageProcessor(size: CGSize(width: 88, height: 88)))])
        }
        updateView()
    }

    override func updateView() {
        super.updateView()
        titleLabel.font = .systemFont(ofSize: 28, weight: isFocused || isSelected ? .semibold : .medium)
        avatarView.tintColor = isFocused ? Theme.focusedText : Theme.textSecondary
    }
}

final class FollowsGridViewController: StandardVideoCollectionViewController<DynamicFeedData> {
    var lastOffset = ""
    private var nextSourcePage = 1

    override func setupCollectionView() {
        super.setupCollectionView()
        collectionVC.emptyContent = .init(title: "关注的 UP 主最近没有新视频", symbol: "person.2")
        collectionVC.pageSize = 1
    }

    override func request(page: Int) async throws -> [DynamicFeedData] {
        if page == 1 {
            lastOffset = ""
            nextSourcePage = 1
        }

        for _ in 0..<6 {
            try Task.checkCancellation()
            let requestedOffset = lastOffset
            let info = try await WebRequest.requestFollowsFeed(offset: requestedOffset, page: nextSourcePage)
            try Task.checkCancellation()
            nextSourcePage += 1
            lastOffset = info.offset
            Logger.debug("request page\(nextSourcePage - 1) get count:\(info.videoFeeds.count) next offset:\(info.offset)")
            if !info.videoFeeds.isEmpty || !info.has_more || info.offset == requestedOffset {
                return info.videoFeeds
            }
        }
        return []
    }

    override func goDetail(with feed: DynamicFeedData) {
        let epid = feed.modules.module_dynamic.major?.pgc?.epid
        let detailVC = VideoDetailViewController.create(aid: feed.aid, cid: feed.cid, epid: epid)
        detailVC.present(from: self)
    }
}

final class FollowsFeedFlowViewController: FeedFlowBrowserViewController {
    init() {
        super.init(dataSource: FollowsFeedFlowDataSource())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class FollowsFeedFlowDataSource: FeedFlowDataSource {
    let title = "关注"
    let defaultPreviewHintText = "停留后自动预览，按确认键进入视频流"
    let loadingHintText = "正在加载关注视频..."
    let emptyStateText = "当前关注区暂无可播放视频"
    let emptyHintText = "可以在设置中关闭关注刷视频模式"
    let loadFailureText = "关注加载失败，请稍后重试"
    let autoReloadInterval: TimeInterval? = 60 * 60

    var reloadToken: String {
        "\(ApiRequest.getToken()?.mid ?? 0)"
    }

    private var lastOffset = ""
    private var nextPage = 1
    private var hasMore = true
    private var seenItemKeys = Set<String>()

    private struct LoadResult {
        let items: [FeedFlowItem]
        let lastOffset: String
        let nextPage: Int
        let hasMore: Bool
        let seenItemKeys: Set<String>
    }

    func reset() {
        lastOffset = ""
        nextPage = 1
        hasMore = true
        seenItemKeys = []
    }

    func refreshFromStart(targetCount: Int, maxSourcePages: Int) async throws -> [FeedFlowItem] {
        let result = try await loadMoreUntilTarget(targetCount: targetCount,
                                                   maxSourcePages: maxSourcePages,
                                                   startingOffset: "",
                                                   startingPage: 1,
                                                   startingHasMore: true,
                                                   seenItemKeys: [])
        commit(result)
        return result.items
    }

    func loadMoreItems(targetCount: Int, maxSourcePages: Int) async throws -> [FeedFlowItem] {
        let result = try await loadMoreUntilTarget(targetCount: targetCount,
                                                   maxSourcePages: maxSourcePages,
                                                   startingOffset: lastOffset,
                                                   startingPage: nextPage,
                                                   startingHasMore: hasMore,
                                                   seenItemKeys: seenItemKeys)
        commit(result)
        return result.items
    }

    private func loadMoreUntilTarget(targetCount: Int,
                                     maxSourcePages: Int,
                                     startingOffset: String,
                                     startingPage: Int,
                                     startingHasMore: Bool,
                                     seenItemKeys: Set<String>) async throws -> LoadResult
    {
        guard startingHasMore else {
            return LoadResult(items: [],
                              lastOffset: startingOffset,
                              nextPage: startingPage,
                              hasMore: false,
                              seenItemKeys: seenItemKeys)
        }

        var pagesScanned = 0
        var accepted = [FeedFlowItem]()
        var resolvedOffset = startingOffset
        var resolvedPage = startingPage
        var resolvedHasMore = startingHasMore
        var resolvedSeenItemKeys = seenItemKeys

        while accepted.count < targetCount, pagesScanned < maxSourcePages, resolvedHasMore {
            try Task.checkCancellation()
            let requestedOffset = resolvedOffset
            let info = try await WebRequest.requestFollowsFeed(offset: resolvedOffset, page: resolvedPage)
            try Task.checkCancellation()
            pagesScanned += 1
            resolvedPage += 1
            resolvedOffset = info.offset
            resolvedHasMore = info.has_more && info.offset != requestedOffset

            let newItems = info.videoFeeds
                .compactMap(\.feedFlowItem)
                .filter { resolvedSeenItemKeys.insert($0.identityKey).inserted }
            accepted.append(contentsOf: newItems)
        }

        try Task.checkCancellation()
        return LoadResult(items: accepted,
                          lastOffset: resolvedOffset,
                          nextPage: resolvedPage,
                          hasMore: resolvedHasMore,
                          seenItemKeys: resolvedSeenItemKeys)
    }

    private func commit(_ result: LoadResult) {
        lastOffset = result.lastOffset
        nextPage = result.nextPage
        hasMore = result.hasMore
        seenItemKeys = result.seenItemKeys
    }
}

extension WebRequest {
    struct DynamicFeedInfo: Codable {
        let items: [DynamicFeedData]
        let offset: String
        let update_num: Int
        let update_baseline: String
        let has_more: Bool

        var videoFeeds: [DynamicFeedData] {
            items.filter { $0.aid != 0 || $0.modules.module_dynamic.major?.pgc?.epid != nil }
        }

        enum CodingKeys: String, CodingKey {
            case items, offset, update_num, update_baseline, has_more
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            items = try container.decode([DynamicFeedData].self, forKey: .items)
            offset = try container.decode(String.self, forKey: .offset)
            if let intVal = try? container.decode(Int.self, forKey: .update_num) {
                update_num = intVal
            } else if let strVal = try? container.decode(String.self, forKey: .update_num) {
                update_num = Int(strVal) ?? 0
            } else {
                update_num = 0
            }
            update_baseline = try container.decode(String.self, forKey: .update_baseline)
            has_more = try container.decode(Bool.self, forKey: .has_more)
        }
    }

    static func requestFollowsFeed(offset: String, page: Int) async throws -> DynamicFeedInfo {
        var parameters: [String: Any] = ["type": "all", "timezone_offset": "-480", "page": page]
        if let offset = Int(offset) {
            parameters["offset"] = offset
        }
        return try await request(
            url: "https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/all",
            parameters: parameters
        )
    }
}

struct DynamicFeedData: Codable, PlayableData, DisplayData {
    var aid: Int {
        if let str = modules.module_dynamic.major?.archive?.aid {
            return Int(str) ?? 0
        }
        return 0
    }

    var cid: Int { 0 }

    var title: String {
        modules.module_dynamic.major?.archive?.title ?? modules.module_dynamic.major?.pgc?.title ?? ""
    }

    var ownerName: String {
        modules.module_author.name
    }

    var pic: URL? {
        URL(string: modules.module_dynamic.major?.archive?.cover ?? "") ?? modules.module_dynamic.major?.pgc?.cover
    }

    var avatar: URL? {
        URL(string: modules.module_author.face)
    }

    var date: String? {
        modules.module_author.pub_time
    }

    var overlay: DisplayOverlay? {
        var leftItems = [DisplayOverlay.DisplayOverlayItem]()
        var rightItems = [DisplayOverlay.DisplayOverlayItem]()
        if let stat = modules.module_dynamic.major?.archive?.stat {
            if let play = stat.play {
                leftItems.append(DisplayOverlay.DisplayOverlayItem(icon: "play.rectangle", text: play == "0" ? "-" : "\(play)"))
            }
            if let danmaku = stat.danmaku {
                leftItems.append(DisplayOverlay.DisplayOverlayItem(icon: "list.bullet.rectangle", text: danmaku == "0" ? "-" : "\(danmaku)"))
            }
        }
        if let durationText = modules.module_dynamic.major?.archive?.duration_text {
            rightItems.append(DisplayOverlay.DisplayOverlayItem(icon: nil, text: durationText))
        }
        return DisplayOverlay(leftItems: leftItems, rightItems: rightItems)
    }

    var feedFlowItem: FeedFlowItem? {
        if aid > 0 {
            return FeedFlowItem(aid: aid,
                                title: title,
                                ownerName: ownerName,
                                coverURL: pic,
                                avatarURL: avatar,
                                durationText: modules.module_dynamic.major?.archive?.duration_text ?? "",
                                viewCountText: modules.module_dynamic.major?.archive?.stat?.play ?? "",
                                danmakuCountText: modules.module_dynamic.major?.archive?.stat?.danmaku ?? "",
                                reasonText: date)
        }

        if let epid = modules.module_dynamic.major?.pgc?.epid, epid > 0 {
            return FeedFlowItem(aid: 0,
                                epid: epid,
                                title: title,
                                ownerName: ownerName,
                                coverURL: pic,
                                avatarURL: avatar,
                                durationText: "",
                                reasonText: date)
        }

        return nil
    }

    let type: String
    let basic: Basic
    let modules: Modules
    let id_str: String

    struct Basic: Codable, Hashable {
        let comment_id_str: String
        let comment_type: Int
    }

    struct Modules: Codable, Hashable {
        let module_author: ModuleAuthor
        let module_dynamic: ModuleDynamic

        struct ModuleAuthor: Codable, Hashable {
            let face: String
            let mid: Int
            let name: String
            let pub_time: String
        }

        struct ModuleDynamic: Codable, Hashable {
            let major: Major?

            struct Major: Codable, Hashable {
                let archive: Archive?
                let pgc: Pgc?

                struct Archive: Codable, Hashable {
                    let aid: String?
                    let cover: String?
                    let desc: String?
                    let title: String?
                    let duration_text: String?
                    let stat: Stat?

                    struct Stat: Codable, Hashable {
                        let danmaku: String?
                        let play: String?
                    }
                }

                struct Pgc: Codable, Hashable {
                    let epid: Int?
                    let title: String?
                    let cover: URL?
                    let jump_url: URL?

                    enum CodingKeys: String, CodingKey {
                        case epid, title, cover, jump_url
                    }

                    init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        if let intVal = try? container.decodeIfPresent(Int.self, forKey: .epid) {
                            epid = intVal
                        } else if let strVal = try? container.decodeIfPresent(String.self, forKey: .epid) {
                            epid = Int(strVal)
                        } else {
                            epid = nil
                        }
                        title = try container.decodeIfPresent(String.self, forKey: .title)
                        cover = try container.decodeIfPresent(URL.self, forKey: .cover)
                        jump_url = try container.decodeIfPresent(URL.self, forKey: .jump_url)
                    }
                }
            }
        }
    }
}

extension WebRequest {
    struct FollowedUp: Hashable {
        let mid: Int
        let name: String
        let face: URL?
        let hasUpdate: Bool
    }

    /// The uploaders you follow, those with new posts first, as the dynamics page lists them;
    /// the plain following list if that fails.
    static func requestFollowedUps() async throws -> [FollowedUp] {
        struct Item: Decodable {
            let mid: Int
            let uname: String
            let face: URL?
            let has_update: Bool?
        }
        struct Portal: Decodable {
            let up_list: [Item]?
        }
        if let portal: Portal = try? await request(url: "https://api.bilibili.com/x/polymer/web-dynamic/v1/portal"),
           let list = portal.up_list, !list.isEmpty
        {
            return list.map { FollowedUp(mid: $0.mid, name: $0.uname, face: $0.face, hasUpdate: $0.has_update ?? false) }
        }
        return try await requestFollowing(page: 1).map {
            FollowedUp(mid: $0.mid, name: $0.uname, face: $0.face, hasUpdate: false)
        }
    }
}
