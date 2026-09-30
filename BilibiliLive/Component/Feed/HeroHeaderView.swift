//
//  HeroHeaderView.swift
//  BilibiliLive
//

import Kingfisher
import UIKit

/// The featured video at the top of 推荐: its cover as a backdrop that fades into the ground,
/// the reason it was recommended, the title, one line of metadata and three actions.
final class HeroHeaderView: UICollectionReusableView {
    static let height: CGFloat = 660

    var onPlay: (() -> Void)?
    var onDetail: (() -> Void)?
    var onUpSpace: (() -> Void)?

    let playButton = HeroHeaderView.makeButton(title: "播放", symbol: "play.fill", primary: true)
    private let detailButton = HeroHeaderView.makeButton(title: "详情", symbol: "info.circle", primary: false)
    private let upButton = HeroHeaderView.makeButton(title: "UP 主页", symbol: "person.crop.circle", primary: false)
    private let backdrop = UIImageView()
    private let sideScrim = CAGradientLayer()
    private let bottomScrim = CAGradientLayer()
    private let kickerLabel = UILabel()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()

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
        backdrop.contentMode = .scaleAspectFill
        backdrop.clipsToBounds = true
        sideScrim.colors = [Theme.background.cgColor,
                            Theme.background.withAlphaComponent(0.72).cgColor,
                            Theme.background.withAlphaComponent(0).cgColor]
        sideScrim.locations = [0, 0.3, 0.72]
        sideScrim.startPoint = CGPoint(x: 0, y: 0.5)
        sideScrim.endPoint = CGPoint(x: 1, y: 0.5)
        backdrop.layer.addSublayer(sideScrim)
        bottomScrim.colors = [Theme.background.withAlphaComponent(0).cgColor, Theme.background.cgColor]
        bottomScrim.locations = [0.55, 1]
        backdrop.layer.addSublayer(bottomScrim)

        kickerLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        kickerLabel.textColor = Theme.accent
        titleLabel.font = .systemFont(ofSize: 60, weight: .bold)
        titleLabel.textColor = Theme.textPrimary
        titleLabel.numberOfLines = 2
        metaLabel.font = .systemFont(ofSize: 26)
        metaLabel.textColor = Theme.textSecondary

        playButton.addAction(UIAction { [weak self] _ in self?.onPlay?() }, for: .primaryActionTriggered)
        detailButton.addAction(UIAction { [weak self] _ in self?.onDetail?() }, for: .primaryActionTriggered)
        upButton.addAction(UIAction { [weak self] _ in self?.onUpSpace?() }, for: .primaryActionTriggered)
        let buttons = UIStackView(arrangedSubviews: [playButton, detailButton, upButton])
        buttons.axis = .horizontal
        buttons.spacing = 24

        let stack = UIStackView(arrangedSubviews: [kickerLabel, titleLabel, metaLabel, buttons])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.setCustomSpacing(36, after: metaLabel)
        addSubview(stack)
        stack.snp.makeConstraints { make in
            // Line the text up with the first card of the grid below.
            make.leading.equalToSuperview().offset(Settings.displayStyle.itemInset)
            make.width.lessThanOrEqualTo(920)
            make.bottom.equalToSuperview().offset(-72)
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
        let left = bounds.width * 0.28
        backdrop.frame = CGRect(x: left, y: -top, width: bounds.width - left + right, height: bounds.height - 24 + top)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sideScrim.frame = backdrop.bounds
        bottomScrim.frame = backdrop.bounds
        CATransaction.commit()
    }

    func configure(title: String, kicker: String?, meta: String, cover: URL?, hasUpSpace: Bool) {
        titleLabel.text = title
        kickerLabel.text = kicker ?? "为你推荐"
        metaLabel.text = meta
        upButton.isHidden = !hasUpSpace
        if var cover {
            if cover.scheme == nil {
                cover = URL(string: "https:\(cover.absoluteString)") ?? cover
            }
            backdrop.kf.setImage(with: cover, options: [.processor(DownsamplingImageProcessor(size: CGSize(width: 1600, height: 900))),
                                                        .transition(.fade(0.3))])
        }
    }

    private static func makeButton(title: String, symbol: String, primary: Bool) -> UIButton {
        var config: UIButton.Configuration
        if #available(tvOS 26.0, *) {
            config = primary ? .prominentGlass() : .glass()
        } else {
            config = primary ? .filled() : .bordered()
        }
        config.title = title
        config.image = UIImage(systemName: symbol)
        config.imagePadding = 12
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 18, leading: 36, bottom: 18, trailing: 36)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 28, weight: .semibold)
            return attributes
        }
        return UIButton(configuration: config)
    }
}
