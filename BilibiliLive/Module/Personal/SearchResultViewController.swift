//
//  SearchResultViewController.swift
//  BilibiliLive
//
//  Created by whw on 2022/11/2.
//

import Combine
import Kingfisher
import UIKit

class SearchResultViewController: UIViewController {
    var collectionView: UICollectionView!
    var dataSource: UICollectionViewDiffableDataSource<SearchList, Item>!
    var currentSnapshot: NSDiffableDataSourceSnapshot<SearchList, Item>!
    static let titleElementKind = "titleElementKind"

    enum Item: Hashable {
        case video(SearchResult.Video)
        case bangumi(SearchResult.Bangumi)
        case user(SearchResult.User)
        case liveRoom(SearchLiveResult.Result.LiveRoom)
        case term(SearchTerm)
    }

    /// A trending query, ranked. Past searches stay in the suggestion row under the keyboard.
    struct SearchTerm: Hashable {
        let rank: Int
        let text: String
    }

    @Published var searchText: String = ""
    var cancellable: Cancellable?
    private let suggestDelayWork = DelayWork(delay: 1.0, noDelayForFirstTask: true)
    private var showHistorySuggest = false
    private var trendingCache: [SearchHotMobileResult.Item] = []
    private weak var searchController: UISearchController?
    private var searchTask: Task<Void, Never>?
    /// The query of the search last started, so a debounced repeat of it is skipped.
    private var lastSearchKey: String?
    private let stateView = ContentStateView()

    override func viewDidLoad() {
        super.viewDidLoad()

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: createLayout())
        collectionView.delegate = self
        tabBarObservedScrollView = collectionView
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        configureDataSource()
        view.addSubview(stateView)
        stateView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        stateView.onRetry = { [weak self] in
            guard let self, !searchText.isEmpty else { return }
            runSearch(searchText)
        }
        showDiscovery()

        cancellable = $searchText
            .filter({ $0.count > 0 })
            .debounce(for: 1.0, scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] key in
                guard key != self?.lastSearchKey else { return }
                self?.runSearch(key)
            }
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        stateView.hasActions ? [stateView] : [collectionView]
    }

    /// Searches for `key` now, replacing any search still running.
    private func runSearch(_ key: String) {
        lastSearchKey = key
        searchTask?.cancel()
        searchTask = Task { @MainActor [weak self] in
            await self?.performSearch(key: key)
        }
    }

    @MainActor
    private func performSearch(key: String) async {
        currentSnapshot.deleteAllItems()
        await dataSource.apply(currentSnapshot, animatingDifferences: false)
        stateView.state = .loading
        // 使用 async let 并行请求
        async let searchResultTask = WebRequest.requestSearchResult(key: key)
        async let liveResultTask = WebRequest.requestSearchLiveResult(key: key)

        var failure: Error?
        var searchResult: SearchResult?
        do { searchResult = try await searchResultTask } catch { failure = error }
        let liveResult = try? await liveResultTask
        guard !Task.isCancelled, key == searchText else { return }

        updateSnapshot(searchResult: searchResult, liveResult: liveResult)
        if currentSnapshot.numberOfItems > 0 {
            stateView.state = nil
        } else if let failure {
            stateView.state = .failed(failure)
        } else {
            stateView.state = .empty(.init(title: "没有找到「\(key)」", message: "换个关键词试试。", symbol: "magnifyingglass"))
        }
    }

    /// With nothing typed, what is trending.
    @MainActor
    private func showDiscovery() {
        searchTask?.cancel()
        lastSearchKey = nil
        stateView.state = nil
        var snapshot = NSDiffableDataSourceSnapshot<SearchList, Item>()
        if !trendingCache.isEmpty {
            let list = SearchList(title: "热搜", height: .absolute(SearchTermCell.rowHeight), scrollingBehavior: .none, kind: .ranking)
            snapshot.appendSections([list])
            snapshot.appendItems(trendingCache.enumerated().map {
                .term(SearchTerm(rank: $0.offset + 1, text: $0.element.show_name))
            }, toSection: list)
        }
        currentSnapshot = snapshot
        dataSource.apply(snapshot, animatingDifferences: false)

        guard trendingCache.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let items = try? await WebRequest.requestSearchHotMobile(limit: 20).list, !items.isEmpty,
                  let self else { return }
            trendingCache = items
            if searchText.isEmpty {
                showDiscovery()
            }
        }
    }

    private func select(_ term: SearchTerm) {
        searchController?.searchBar.text = term.text
        Settings.addHistory(term.text)
        searchText = term.text
        runSearch(term.text)
    }

    @MainActor
    private func updateSnapshot(searchResult: SearchResult?, liveResult: SearchLiveResult?) {
        currentSnapshot.deleteAllItems()
        dataSource.apply(currentSnapshot)

        let defaultHeight = NSCollectionLayoutDimension.fractionalWidth(Settings.displayStyle == .large ? 0.26 : 0.2)

        // 添加综合搜索结果
        if let searchResult {
            for section in searchResult.result {
                switch section {
                case let .video(data):
                    let list = SearchList(title: "视频", height: defaultHeight, scrollingBehavior: .continuous)
                    currentSnapshot.appendSections([list])
                    currentSnapshot.appendItems(data.map { .video($0) }, toSection: list)
                case let .bangumi(data):
                    let list = SearchList(title: "番剧", height: defaultHeight, scrollingBehavior: .continuous)
                    currentSnapshot.appendSections([list])
                    currentSnapshot.appendItems(data.map { .bangumi($0) }, toSection: list)
                case let .movie(data):
                    let list = SearchList(title: "影视", height: defaultHeight, scrollingBehavior: .none)
                    currentSnapshot.appendSections([list])
                    currentSnapshot.appendItems(data.map { .bangumi($0) }, toSection: list)
                case let .user(data):
                    let list = SearchList(title: "用户", height: .estimated(140), scrollingBehavior: .continuous)
                    currentSnapshot.appendSections([list])
                    currentSnapshot.appendItems(data.map { .user($0) }, toSection: list)
                case .none:
                    break
                }
            }
        }

        // 添加直播搜索结果
        if let liveResult, let liveRooms = liveResult.result.live_room, !liveRooms.isEmpty {
            let list = SearchList(title: "直播", height: defaultHeight, scrollingBehavior: .continuous)
            currentSnapshot.appendSections([list])
            currentSnapshot.appendItems(liveRooms.map { .liveRoom($0) }, toSection: list)
        }

        dataSource.apply(currentSnapshot)
    }
}

extension SearchResultViewController {
    private func createLayout() -> UICollectionViewLayout {
        let sectionProvider = { [self]
            (sectionIndex: Int, layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? in
                let sectionIdentifier = dataSource.snapshot().sectionIdentifiers[sectionIndex]

                let section: NSCollectionLayoutSection
                if sectionIdentifier.kind == .ranking {
                    let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.5), heightDimension: .fractionalHeight(1)))
                    item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 30)
                    let group = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: sectionIdentifier.height), subitems: [item])
                    section = NSCollectionLayoutSection(group: group)
                    section.interGroupSpacing = 8
                    section.contentInsets = NSDirectionalEdgeInsets(top: 24, leading: Self.cardInset, bottom: 40, trailing: 0)
                } else if sectionIdentifier.scrollingBehavior == .none {
                    let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                                           heightDimension: sectionIdentifier.height)
                    let itemSize = NSCollectionLayoutSize(widthDimension: sectionIdentifier.width,
                                                          heightDimension: .fractionalHeight(1))
                    let item = NSCollectionLayoutItem(layoutSize: itemSize)
                    let hSpacing: CGFloat = Settings.displayStyle == .large ? 35 : 30
                    item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: hSpacing, bottom: 0, trailing: hSpacing)
                    let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
                    group.edgeSpacing = .init(leading: .fixed(0), top: .fixed(40), trailing: .fixed(0), bottom: .fixed(-60))
                    section = NSCollectionLayoutSection(group: group)
                } else {
                    let groupSize = NSCollectionLayoutSize(widthDimension: sectionIdentifier.width,
                                                           heightDimension: sectionIdentifier.height)
                    let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                                          heightDimension: .fractionalHeight(1))
                    let item = NSCollectionLayoutItem(layoutSize: itemSize)
                    let hSpacing: CGFloat = Settings.displayStyle == .large ? 35 : 30
                    item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: hSpacing, bottom: 0, trailing: hSpacing)
                    let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
                    group.edgeSpacing = .init(leading: .fixed(0), top: .fixed(40), trailing: .fixed(0), bottom: .fixed(0))
                    section = NSCollectionLayoutSection(group: group)
                    section.orthogonalScrollingBehavior = sectionIdentifier.scrollingBehavior
                }

                let titleSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                                       heightDimension: .estimated(44))
                let titleSupplementary = NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: titleSize,
                    elementKind: FavoriteViewController.titleElementKind,
                    alignment: .top
                )
                section.boundarySupplementaryItems = [titleSupplementary]
                return section
        }

        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.interSectionSpacing = 20

        let layout = UICollectionViewCompositionalLayout(
            sectionProvider: sectionProvider, configuration: config
        )
        return layout
    }

    /// The inset of a card inside its column, which section titles line up with.
    static var cardInset: CGFloat { Settings.displayStyle.itemInset }

    private func configureDataSource() {
        let displayCell = UICollectionView.CellRegistration<FeedCollectionViewCell, any DisplayData> {
            $0.setup(data: $2)
        }
        let termCell = UICollectionView.CellRegistration<SearchTermCell, SearchTerm> {
            $0.configure(with: $2)
        }
        let userCell = UICollectionView.CellRegistration<UpCell, SearchResult.User> {
            $0.nameLabel.text = $2.uname
            $0.despLabel.text = $2.usign
            $0.imageView.kf.setImage(with: $2.upic.addSchemeIfNeed(), options: [.processor(DownsamplingImageProcessor(size: CGSize(width: 80, height: 80))), .processor(RoundCornerImageProcessor(radius: .widthFraction(0.5))), .cacheSerializer(FormatIndicatedCacheSerializer.png)])
        }
        dataSource = UICollectionViewDiffableDataSource<SearchList, Item>(collectionView: collectionView) {
            collectionView, indexPath, item in
            switch item {
            case let .video(item):
                return collectionView.dequeueConfiguredReusableCell(using: displayCell, for: indexPath, item: item)
            case let .bangumi(item):
                return collectionView.dequeueConfiguredReusableCell(using: displayCell, for: indexPath, item: item)
            case let .user(item):
                return collectionView.dequeueConfiguredReusableCell(using: userCell, for: indexPath, item: item)
            case let .liveRoom(item):
                return collectionView.dequeueConfiguredReusableCell(using: displayCell, for: indexPath, item: item)
            case let .term(term):
                return collectionView.dequeueConfiguredReusableCell(using: termCell, for: indexPath, item: term)
            }
        }

        let supplementaryRegistration = UICollectionView.SupplementaryRegistration<TitleSupplementaryView>(elementKind: FavoriteViewController.titleElementKind) {
            supplementaryView, string, indexPath in
            if let snapshot = self.currentSnapshot, snapshot.sectionIdentifiers.indices.contains(indexPath.section) {
                let videoCategory = snapshot.sectionIdentifiers[indexPath.section]
                supplementaryView.leadingInset = Self.cardInset
                supplementaryView.set(title: videoCategory.title, detail: nil)
            }
        }

        dataSource.supplementaryViewProvider = { view, kind, index in
            return self.collectionView.dequeueConfiguredReusableSupplementary(
                using: supplementaryRegistration, for: index
            )
        }

        currentSnapshot = NSDiffableDataSourceSnapshot<SearchList, Item>()
    }
}

extension SearchResultViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let data = dataSource.itemIdentifier(for: indexPath) else { return }
        switch data {
        case let .term(term):
            select(term)
        case let .video(data):
            let detailVC = VideoDetailViewController.create(aid: data.aid, cid: 0)
            detailVC.present(from: self)
        case let .bangumi(data):
            let detailVC = VideoDetailViewController.create(seasonId: data.season_id)
            detailVC.present(from: self)
        case let .user(data):
            let upSpaceVC = UpSpaceViewController()
            upSpaceVC.mid = data.mid
            present(upSpaceVC, animated: true)
        case let .liveRoom(data):
            let playerVC = LivePlayerViewController()
            let room = LiveRoom(
                title: data.title,
                room_id: data.roomid,
                uname: data.uname,
                area_v2_name: data.cate_name,
                keyframe: data.cover?.absoluteString,
                face: data.uface,
                cover_from_user: data.user_cover
            )
            playerVC.room = room
            present(playerVC, animated: true)
        }
    }

    func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
        if let section = currentSnapshot.sectionIdentifiers.first, currentSnapshot.numberOfItems(inSection: section) > 0 {
            return IndexPath(item: 0, section: 0)
        }
        return nil
    }

    func collectionView(_ collectionView: UICollectionView, didUpdateFocusIn context: UICollectionViewFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        // 从搜索框进入结果查看时，认为本搜索词是用户想要的，保存搜索历史
        if context.previouslyFocusedIndexPath == nil && context.nextFocusedIndexPath != nil {
            Settings.addHistory(searchText)
        }
    }
}

extension SearchResultViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        self.searchController = searchController
        guard searchController.searchBar.text != "清空历史" else { return }
        if let text = searchController.searchBar.text, text != searchText {
            searchText = text
            if text.isEmpty {
                showDiscovery()
            }
        }

        if let text = searchController.searchBar.text, !text.isEmpty {
            showHistorySuggest = false
            suggestDelayWork.submit {
                let result = try await WebRequest.requestSuggest(key: text)
                searchController.searchSuggestions = result.result.tag.map {
                    SuggestEntry(title: $0.term, iconImage: UIImage(systemName: "magnifyingglass"))
                }
            }
        } else {
            suggestDelayWork.cancel()
            // 添加showHistorySuggest判断避免可能重复执行
            if !showHistorySuggest {
                showHistorySuggest = true
                // Trending queries fill the page below; the row under the keyboard keeps history.
                searchController.searchSuggestions = buildHistorySuggestions()
            }
        }
    }

    func updateSearchResults(for searchController: UISearchController, selecting searchSuggestion: any UISearchSuggestion) {
        // 选中建议词后添加搜索历史
        if searchSuggestion.localizedDescription == "清空历史" {
            Settings.clearHistory()
            searchController.searchSuggestions = []
            searchController.searchBar.text = nil
            showHistorySuggest = false
            updateSearchResults(for: searchController)
        } else if let text = searchController.searchBar.text {
            Settings.addHistory(text)
        }
    }
}

private extension SearchResultViewController {
    func buildHistorySuggestions() -> [SuggestEntry] {
        var suggests = Settings.searchHistories.map {
            SuggestEntry(title: $0, iconImage: UIImage(systemName: "clock"))
        }
        if !suggests.isEmpty {
            suggests.append(SuggestEntry(title: "清空历史", iconImage: UIImage(systemName: "trash")))
        }
        return suggests
    }
}

extension WebRequest {
    static func requestSearchResult(key: String) async throws -> SearchResult {
        try await request(url: "https://api.bilibili.com/x/web-interface/search/all/v2", parameters: ["keyword": key])
    }

    static func requestSearchLiveResult(key: String) async throws -> SearchLiveResult {
        try await request(url: "https://api.bilibili.com/x/web-interface/wbi/search/type", parameters: ["keyword": key, "search_type": "live"])
    }

    static func requestSuggest(key: String) async throws -> SuggestResult {
        try await request(url: "https://api.bilibili.com/x/web-interface/suggest", parameters: ["term": key])
    }

    static func requestSearchHotMobile(limit: Int) async throws -> SearchHotMobileResult {
        try await request(url: "https://app.bilibili.com/x/v2/search/trending/ranking", parameters: ["limit": limit])
    }
}

struct SearchResult: Decodable, Hashable {
    struct Video: Codable, Hashable, DisplayData {
        let type: String
        let author: String
        let upic: String
        let aid: Int
        let pubdate: Int
        let danmaku: Int
        let play: Int?
        let duration: String?

        // DisplayData
        var title: String
        var ownerName: String { author }
        let pic: URL?
        var avatar: URL? { URL(string: upic) }
        var date: String? { DateFormatter.stringFor(timestamp: pubdate) }
        var overlay: DisplayOverlay? {
            var leftItems = [DisplayOverlay.DisplayOverlayItem]()
            var rightItems = [DisplayOverlay.DisplayOverlayItem]()
            leftItems.append(DisplayOverlay.DisplayOverlayItem(icon: "play.rectangle", text: play == 0 ? "-" : play?.numberString() ?? "-"))
            leftItems.append(DisplayOverlay.DisplayOverlayItem(icon: "list.bullet.rectangle", text: danmaku == 0 ? "-" : danmaku.numberString()))
            if let duration {
                rightItems.append(DisplayOverlay.DisplayOverlayItem(icon: nil, text: duration))
            }
            return DisplayOverlay(leftItems: leftItems, rightItems: rightItems)
        }
    }

    struct Bangumi: Codable, Hashable, DisplayData {
        let season_id: Int
        let styles: String
        let cover: URL
        let pubtime: Int

        // DisplayData
        var title: String
        var ownerName: String { styles }
        var pic: URL? { cover }
        var date: String? { DateFormatter.stringFor(timestamp: pubtime) }
    }

    struct User: Codable, Hashable {
        let uname: String
        let upic: URL
        let usign: String
        let mid: Int
    }

    enum DataType: String, Codable {
        case video
        case media_bangumi
        case media_ft
        case bili_user
    }

    enum Section: Decodable, Hashable {
        case video(_ video: [Video])
        case bangumi(_ bangumi: [Bangumi])
        case movie(_ movie: [Bangumi])
        case user(_ user: [User])
        case none

        enum CodingKeys: CodingKey {
            case result_type
            case data
        }

        init(from decoder: Decoder) throws {
            let container: KeyedDecodingContainer<SearchResult.Section.CodingKeys> = try decoder.container(keyedBy: SearchResult.Section.CodingKeys.self)
            let result_type = try? container.decode(DataType.self, forKey: .result_type)
            switch result_type {
            case .video:
                var video = try container.decode([Video].self, forKey: .data)
                video.indices.forEach({ video[$0].title = video[$0].title.removingHTMLTags() })
                // 过滤只保留视频类型，去掉直播和课堂等类型
                video = video.filter { $0.type == "video" }
                video = Array(Set(video))
                self = .video(video)
            case .media_bangumi:
                var bangumi = try container.decode([Bangumi].self, forKey: .data)
                if bangumi.count == 0 {
                    self = .none
                    break
                }
                bangumi.indices.forEach({ bangumi[$0].title = bangumi[$0].title.removingHTMLTags() })
                bangumi = Array(Set(bangumi))
                self = .bangumi(bangumi)
            case .media_ft:
                var bangumi = try container.decode([Bangumi].self, forKey: .data)
                if bangumi.count == 0 {
                    self = .none
                    break
                }
                bangumi.indices.forEach({ bangumi[$0].title = bangumi[$0].title.removingHTMLTags() })
                bangumi = Array(Set(bangumi))
                self = .movie(bangumi)
            case .bili_user:
                var user = try container.decode([User].self, forKey: .data)
                if user.count == 0 {
                    self = .none
                    break
                }
                user = Array(Set(user))
                self = .user(user)
            case .none:
                self = .none
            }
        }
    }

    let result: [Section]
}

struct SearchList: Hashable {
    enum Kind {
        /// Video, live or user cards.
        case cards
        /// Numbered trending queries in two columns.
        case ranking
    }

    let title: String
    let width = NSCollectionLayoutDimension.fractionalWidth(Settings.displayStyle.fractionalWidth)
    let height: NSCollectionLayoutDimension
    let scrollingBehavior: UICollectionLayoutSectionOrthogonalScrollingBehavior
    var kind = Kind.cards
}

struct SearchLiveResult: Decodable, Hashable {
    struct Result: Codable, Hashable {
        let live_room: [LiveRoom]?

        struct LiveRoom: Codable, Hashable, DisplayData {
            let uname: String
            let uface: URL?
            let user_cover: URL?
            let cover: URL?
            let roomid: Int
            let cate_name: String
            let titleWithHtml: String

            // DisplayData
            var title: String { titleWithHtml.removingHTMLTags() }
            var ownerName: String { uname.removingHTMLTags() }
            var pic: URL? { cover?.addSchemeIfNeed() }
            var avatar: URL? { uface?.addSchemeIfNeed() }
            var overlay: DisplayOverlay? {
                var leftItems = [DisplayOverlay.DisplayOverlayItem]()
                leftItems.append(DisplayOverlay.DisplayOverlayItem(icon: nil, text: cate_name))
                return DisplayOverlay(leftItems: leftItems)
            }

            enum CodingKeys: String, CodingKey {
                case uname, uface, user_cover, cover, roomid, cate_name
                case titleWithHtml = "title"
            }
        }
    }

    let result: Result
}

struct SuggestResult: Decodable, Hashable {
    struct Result: Codable, Hashable {
        let tag: [Tag]

        struct Tag: Codable, Hashable {
            let term: String
        }
    }

    let result: Result
}

struct SearchHotMobileResult: Decodable, Hashable {
    let trackid: String
    let list: [Item]

    struct Item: Codable, Hashable {
        let position: Int
        let keyword: String
        let show_name: String
        let word_type: Int
        let icon: URL?
        let hot_id: Int
    }
}

class SuggestEntry: NSObject, UISearchSuggestion {
    var localizedSuggestion: String? {
        return title
    }

    var localizedDescription: String? {
        return title
    }

    var representedObject: Any?

    var title: String
    var iconImage: UIImage? = nil

    init(title: String, iconImage: UIImage? = nil) {
        self.title = title
        self.iconImage = iconImage
    }
}

/// A trending query: its rank, pink for the top three, and the query.
final class SearchTermCell: BLMotionCollectionViewCell {
    static let rowHeight: CGFloat = 76

    private let fillView = UIView()
    private let rankLabel = UILabel()
    private let titleLabel = UILabel()
    private var rank = 0

    override func setup() {
        super.setup()
        scaleFactor = 1.05
        contentView.addSubview(fillView)
        fillView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        fillView.layer.cornerRadius = Theme.rowRadius
        fillView.layer.cornerCurve = .continuous
        let stack = UIStackView(arrangedSubviews: [rankLabel, titleLabel])
        stack.spacing = 14
        stack.alignment = .center
        contentView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(18)
            make.trailing.lessThanOrEqualToSuperview().offset(-26)
            make.centerY.equalToSuperview()
        }
        rankLabel.font = .monospacedDigitSystemFont(ofSize: 30, weight: .bold)
        rankLabel.textAlignment = .center
        rankLabel.snp.makeConstraints { make in
            make.width.equalTo(44)
        }
        titleLabel.font = .systemFont(ofSize: 28, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
    }

    func configure(with term: SearchResultViewController.SearchTerm) {
        rank = term.rank
        rankLabel.text = "\(term.rank)"
        titleLabel.text = term.text
        updateColors()
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations {
            self.updateColors()
        }
    }

    private func updateColors() {
        let top = rank <= 3
        fillView.backgroundColor = isFocused ? Theme.focusedFill : .clear
        titleLabel.textColor = isFocused ? Theme.focusedText : Theme.textPrimary
        rankLabel.textColor = top ? Theme.accent : (isFocused ? Theme.focusedText.withAlphaComponent(0.6) : Theme.textTertiary)
    }
}
