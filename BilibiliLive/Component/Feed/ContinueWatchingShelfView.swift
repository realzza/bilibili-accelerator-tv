//
//  ContinueWatchingShelfView.swift
//  BilibiliLive
//

import SnapKit
import UIKit

/// A video from watch history that was left part way, for 继续观看.
struct ContinueWatchingItem: DisplayData {
    let aid: Int
    let cid: Int
    let title: String
    let ownerName: String
    let pic: URL?
    /// Seconds watched and the video's length.
    let position: Int
    let duration: Int

    var watchProgress: Double? {
        duration > 0 ? Double(position) / Double(duration) : nil
    }

    /// `还剩 5 分钟`, in the metadata line where a card puts its date.
    var date: String? {
        let minutes = max(1, (duration - position + 59) / 60)
        return "还剩 \(minutes) 分钟"
    }

    /// Videos left between 10 s in and 15 s before the end, most recent first. A finished video
    /// reports -1.
    static func from(_ history: [HistoryData], limit: Int = 12) -> [ContinueWatchingItem] {
        history.lazy
            .filter { $0.progress > 10 && $0.progress < $0.duration - 15 }
            .compactMap { entry -> ContinueWatchingItem? in
                guard let cid = entry.cid, cid > 0 else { return nil }
                return ContinueWatchingItem(aid: entry.aid, cid: cid, title: entry.title, ownerName: entry.ownerName,
                                            pic: entry.pic, position: entry.progress, duration: entry.duration)
            }
            .prefix(limit)
            .map { $0 }
    }
}

/// 继续观看: a slim strip of thumbnails with how far each video got, after a title that scrolls away
/// with them. They carry no text, which keeps the strip small enough to leave the recommendations
/// on the first screen; the line under the strip names the focused video.
final class ContinueWatchingShelfView: UIView {
    private static let cardSize = CGSize(width: 176, height: 99)
    private static let captionHeight: CGFloat = 38
    /// The strip and the line under it.
    static let height: CGFloat = cardSize.height + captionHeight

    var onSelect: ((ContinueWatchingItem) -> Void)?

    private let captionLabel = UILabel()
    private let collectionView: UICollectionView
    private var items = [ContinueWatchingItem]()

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 24
        layout.itemSize = Self.cardSize
        layout.headerReferenceSize = CGSize(width: ShelfTitleView.width, height: Self.cardSize.height)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [collectionView]
    }

    func update(items: [ContinueWatchingItem]) {
        self.items = items
        collectionView.reloadData()
    }

    private func setup() {
        let inset = Settings.displayStyle.itemInset
        collectionView.backgroundColor = .clear
        collectionView.clipsToBounds = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.contentInset = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
        collectionView.register(FeedCollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        collectionView.register(ShelfTitleView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: "title")
        collectionView.dataSource = self
        collectionView.delegate = self
        addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(Self.cardSize.height)
        }

        captionLabel.alpha = 0
        captionLabel.lineBreakMode = .byTruncatingTail
        addSubview(captionLabel)
        captionLabel.snp.makeConstraints { make in
            make.top.equalTo(collectionView.snp.bottom).offset(10)
            // Under the thumbnails it describes, apart from the section title below.
            make.leading.equalToSuperview().offset(inset + ShelfTitleView.width)
            make.trailing.lessThanOrEqualToSuperview().offset(-inset)
        }
    }

    /// `Tom Dwan 在 KPC 上到底怎么了 · chang_poker · 还剩 2 分钟`, the title brightest.
    private func caption(for item: ContinueWatchingItem) -> NSAttributedString {
        let font = UIFont.systemFont(ofSize: 24, weight: .medium)
        let text = NSMutableAttributedString(string: item.title, attributes: [.font: font, .foregroundColor: Theme.textPrimary])
        let details = [item.ownerName, item.date].compactMap { $0 }.filter { !$0.isEmpty }
        for detail in details {
            text.append(NSAttributedString(string: " · \(detail)", attributes: [.font: font, .foregroundColor: Theme.textTertiary]))
        }
        return text
    }
}

extension ContinueWatchingShelfView: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! FeedCollectionViewCell
        let item = items[indexPath.item]
        cell.setup(data: item)
        cell.showThumbnailOnly()
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "title", for: indexPath)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(items[indexPath.item])
    }

    func collectionView(_ collectionView: UICollectionView, didUpdateFocusIn context: UICollectionViewFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        let item = context.nextFocusedIndexPath.flatMap { items.indices.contains($0.item) ? items[$0.item] : nil }
        if let item {
            captionLabel.attributedText = caption(for: item)
        }
        coordinator.addCoordinatedAnimations {
            self.captionLabel.alpha = item == nil ? 0 : 1
        }
    }
}

/// 继续观看 at the start of the strip.
private final class ShelfTitleView: UICollectionReusableView {
    static let width: CGFloat = 132

    override init(frame: CGRect) {
        super.init(frame: frame)
        let label = UILabel()
        label.text = "继续观看"
        label.font = .systemFont(ofSize: 26, weight: .semibold)
        label.textColor = Theme.textPrimary
        addSubview(label)
        label.snp.makeConstraints { make in
            make.leading.centerY.equalToSuperview()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
