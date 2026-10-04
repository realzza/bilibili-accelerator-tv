//
//  VideoPlayerDiscoveryInfoViewController.swift
//  BilibiliLive
//
//  Created by OpenAI on 2026/4/5.
//

import AVKit
import UIKit

/// 博主视频 or 相关视频 in the player's info panel: a row of video cards, as in the rest of the
/// app, on the dark card the 线路 tab uses.
final class VideoPlayerDiscoveryInfoViewController: UIViewController {
    private enum Layout {
        static let cardWidth: CGFloat = 360
        static let cardHeight: CGFloat = 282
        static let sectionInsets = NSDirectionalEdgeInsets(top: 30, leading: 40, bottom: 26, trailing: 40)
        static let interGroupSpacing: CGFloat = 40
        static let preferredHeight: CGFloat = 340
    }

    struct Entry: Hashable {
        let playInfo: PlayInfo
        let displayData: AnyDispplayData
    }

    var onSelect: ((PlayInfo) -> Void)?

    private let emptyText: String
    private var entries = [Entry]()
    private var isLoading = false

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { _, _ in
            let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                                  heightDimension: .fractionalHeight(1.0))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let groupSize = NSCollectionLayoutSize(widthDimension: .absolute(Layout.cardWidth),
                                                   heightDimension: .absolute(Layout.cardHeight))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = Layout.sectionInsets
            section.interGroupSpacing = Layout.interGroupSpacing
            section.orthogonalScrollingBehavior = .continuousGroupLeadingBoundary
            return section
        }

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        // Clipped to the card; the section's insets leave room for a focused card to grow.
        collectionView.clipsToBounds = true
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.remembersLastFocusedIndexPath = true
        collectionView.alwaysBounceVertical = false
        collectionView.register(FeedCollectionViewCell.self, forCellWithReuseIdentifier: String(describing: FeedCollectionViewCell.self))
        return collectionView
    }()

    /// The info panel draws nothing behind a custom tab; text needs a ground over a bright picture.
    private let card = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let stateLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 28, weight: .medium)
        label.textColor = Theme.textSecondary
        label.numberOfLines = 2
        label.textAlignment = .center
        label.isHidden = true
        return label
    }()

    private let spinner = UIActivityIndicatorView(style: .medium)

    init(title: String, emptyText: String) {
        self.emptyText = emptyText
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 0, height: Layout.preferredHeight)
        view.backgroundColor = .clear

        card.layer.cornerRadius = 36
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        view.addSubview(card)
        view.addSubview(collectionView)
        view.addSubview(stateLabel)
        view.addSubview(spinner)
        spinner.color = Theme.textSecondary
        card.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        stateLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(32)
        }
        spinner.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        updateState()
    }

    /// Shows `entries`; while `isLoading`, a spinner stands in for an empty row.
    func update(entries: [Entry], isLoading: Bool = false) {
        self.entries = entries
        self.isLoading = isLoading
        guard isViewLoaded else { return }
        collectionView.reloadData()
        updateState()
    }

    private func updateState() {
        let isEmpty = entries.isEmpty
        collectionView.isHidden = isEmpty
        stateLabel.text = emptyText
        stateLabel.isHidden = !isEmpty || isLoading
        if isEmpty, isLoading {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
    }
}

extension VideoPlayerDiscoveryInfoViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        entries.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let entry = entries[indexPath.item]
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: String(describing: FeedCollectionViewCell.self),
                                                      for: indexPath) as! FeedCollectionViewCell
        cell.styleOverride = .sideBar
        cell.setup(data: entry.displayData.data)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(entries[indexPath.item].playInfo)
    }
}
