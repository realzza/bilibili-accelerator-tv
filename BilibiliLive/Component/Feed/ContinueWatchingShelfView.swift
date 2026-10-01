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

    var progress: Double {
        duration > 0 ? Double(position) / Double(duration) : 0
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

/// 继续观看: a titled row of cards with how far each video got, scrolling sideways.
final class ContinueWatchingShelfView: UIView {
    static let height: CGFloat = 360

    var onSelect: ((ContinueWatchingItem) -> Void)?

    private let titleLabel = UILabel()
    private let collectionView: UICollectionView
    private var items = [ContinueWatchingItem]()

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 60
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
        titleLabel.text = "继续观看"
        titleLabel.font = .systemFont(ofSize: 30, weight: .semibold)
        titleLabel.textColor = Theme.textPrimary
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.leading.equalToSuperview().offset(inset)
        }

        collectionView.backgroundColor = .clear
        collectionView.clipsToBounds = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.contentInset = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
        collectionView.register(FeedCollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        collectionView.dataSource = self
        collectionView.delegate = self
        addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(24)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The same width as a card in the grid below, so the two line up.
        guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        let style = Settings.displayStyle
        let width = bounds.width * style.fractionalWidth - style.itemInset * 2
        let size = CGSize(width: width.rounded(), height: collectionView.bounds.height)
        if layout.itemSize != size, size.width > 0, size.height > 0 {
            layout.itemSize = size
        }
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
        cell.progress = item.progress
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(items[indexPath.item])
    }
}
