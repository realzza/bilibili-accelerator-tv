//
//  HeroHeaderView.swift
//  BilibiliLive
//

import Kingfisher
import UIKit

/// The featured video at the top of 推荐: its cover as a backdrop that fades into the ground,
/// the reason it was recommended, the title, one line of metadata, the description and the
/// actions, with the grid's own title under them.
final class HeroHeaderView: UICollectionReusableView {
    /// Short enough that the first row of cards, with its titles, fits on the first screen.
    static let height: CGFloat = 600

    var onPlay: (() -> Void)?
    var onDetail: (() -> Void)?
    var onWatchLater: (() -> Void)?
    var onUpSpace: (() -> Void)?

    let playButton = HeroHeaderView.makeButton(title: "播放", symbol: "play.fill")
    private let watchLaterButton = HeroHeaderView.makeButton(title: "稍后再看", symbol: "clock")
    private let detailButton = HeroHeaderView.makeButton(title: "详情", symbol: "info.circle")
    private let upButton = HeroHeaderView.makeButton(title: "UP 主页", symbol: "person.crop.circle")
    private let backdrop = BackdropView()
    private let kickerLabel = UILabel()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let sectionLabel = UILabel()

    var isInWatchLater = false {
        didSet { watchLaterButton.setNeedsUpdateConfiguration() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        snp.makeConstraints { make in
            make.height.equalTo(HeroHeaderView.height).priority(.high)
        }

        addSubview(backdrop)

        kickerLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        kickerLabel.textColor = Theme.accent

        titleLabel.font = .systemFont(ofSize: 60, weight: .bold)
        titleLabel.textColor = Theme.textPrimary
        titleLabel.numberOfLines = 2
        metaLabel.font = .systemFont(ofSize: 24)
        metaLabel.textColor = Theme.textSecondary
        descriptionLabel.font = .systemFont(ofSize: 24)
        descriptionLabel.textColor = Theme.textSecondary
        descriptionLabel.numberOfLines = 2

        playButton.addAction(UIAction { [weak self] _ in self?.onPlay?() }, for: .primaryActionTriggered)
        watchLaterButton.addAction(UIAction { [weak self] _ in self?.onWatchLater?() }, for: .primaryActionTriggered)
        detailButton.addAction(UIAction { [weak self] _ in self?.onDetail?() }, for: .primaryActionTriggered)
        upButton.addAction(UIAction { [weak self] _ in self?.onUpSpace?() }, for: .primaryActionTriggered)
        watchLaterButton.configurationUpdateHandler = { [weak self] button in
            let added = self?.isInWatchLater ?? false
            button.configuration?.title = added ? "已加入稍后再看" : "稍后再看"
            button.configuration?.image = UIImage(systemName: added ? "checkmark" : "clock")
        }
        let buttons = UIStackView(arrangedSubviews: [playButton, watchLaterButton, detailButton, upButton])
        buttons.axis = .horizontal
        buttons.spacing = 20

        let stack = UIStackView(arrangedSubviews: [kickerLabel, titleLabel, metaLabel, descriptionLabel, buttons])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.setCustomSpacing(12, after: kickerLabel)
        stack.setCustomSpacing(36, after: descriptionLabel)
        addSubview(stack)

        sectionLabel.text = "为你推荐"
        sectionLabel.font = .systemFont(ofSize: 30, weight: .semibold)
        sectionLabel.textColor = Theme.textPrimary
        addSubview(sectionLabel)

        // Line the text up with the first card of the grid below.
        let inset = Settings.displayStyle.itemInset
        sectionLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(inset)
            make.bottom.equalToSuperview().offset(-8)
        }
        stack.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(inset)
            make.width.lessThanOrEqualTo(960)
            make.bottom.equalTo(sectionLabel.snp.top).offset(-96)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The grid is inset from the screen edges; let the art run past those insets, up under
        // the tab bar and out to the right edge, so it has no hard edge there.
        var top: CGFloat = 0
        var right: CGFloat = 0
        if let collectionView = superview as? UICollectionView {
            top = collectionView.adjustedContentInset.top + frame.minY
            right = max(0, collectionView.bounds.maxX - frame.maxX)
        }
        let left = bounds.width * 0.26
        backdrop.frame = CGRect(x: left, y: -top, width: bounds.width - left + right, height: bounds.height + top)
    }

    /// `kicker` is why the video was picked; `meta` and `description` may arrive later, once the
    /// video's details load.
    func configure(title: String, kicker: String?, meta: String, description: String?, cover: URL?, hasUpSpace: Bool) {
        titleLabel.text = title
        kickerLabel.text = kicker ?? "今日推荐"
        metaLabel.text = meta
        let description = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        descriptionLabel.text = description
        descriptionLabel.isHidden = description.isEmpty || description == "-"
        upButton.isHidden = !hasUpSpace
        if var cover {
            if cover.scheme == nil {
                cover = URL(string: "https:\(cover.absoluteString)") ?? cover
            }
            backdrop.imageView.kf.setImage(with: cover, options: [.processor(DownsamplingImageProcessor(size: CGSize(width: 1600, height: 900))),
                                                                  .transition(.fade(0.3))])
        }
    }

    private static func makeButton(title: String, symbol: String) -> UIButton {
        var config = UIButton.Configuration.capsule()
        config.title = title
        config.image = UIImage(systemName: symbol)
        config.imagePadding = 12
        config.contentInsets = NSDirectionalEdgeInsets(top: 18, leading: 32, bottom: 18, trailing: 32)
        config.setTitleFont(.systemFont(ofSize: 26, weight: .semibold))
        return UIButton(configuration: config)
    }
}
