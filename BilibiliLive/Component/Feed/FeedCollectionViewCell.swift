//
//  FeedCollectionViewCell.swift
//  BilibiliLive
//
//  Created by yicheng on 2022/10/20.
//

import Kingfisher
import MarqueeLabel
import TVUIKit
import UIKit

/// A video card: a clean 16:9 thumbnail with only the duration on it, a one-line title that
/// scrolls when focused, and one line of metadata below.
class FeedCollectionViewCell: BLMotionCollectionViewCell {
    var onLongPress: (() -> Void)?
    var styleOverride: FeedDisplayStyle? { didSet { if oldValue != styleOverride { updateStyle() } }}

    private let titleLabel = MarqueeLabel()
    private let metaLabel = UILabel()
    private let artwork = UIView()
    private let imageView = UIImageView()
    private let durationLabel = PillLabel()
    private let badgeLabel = PillLabel()

    override var shadowLayer: CALayer {
        artwork.layer
    }

    override func setup() {
        super.setup()
        scaleFactor = 1.08
        let longpress = UILongPressGestureRecognizer(target: self, action: #selector(actionLongPress(sender:)))
        addGestureRecognizer(longpress)

        contentView.addSubview(artwork)
        artwork.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview()
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

        artwork.addSubview(durationLabel)
        durationLabel.snp.makeConstraints { make in
            make.trailing.bottom.equalToSuperview().inset(12)
        }
        durationLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        durationLabel.textColor = Theme.textPrimary
        durationLabel.backgroundColor = Theme.badgeFill
        durationLabel.layer.cornerRadius = 10
        durationLabel.clipsToBounds = true

        artwork.addSubview(badgeLabel)
        badgeLabel.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().inset(12)
        }
        badgeLabel.font = .systemFont(ofSize: 18, weight: .bold)
        badgeLabel.textColor = Theme.onAccent
        badgeLabel.layer.cornerRadius = 10
        badgeLabel.clipsToBounds = true

        let stackView = UIStackView(arrangedSubviews: [titleLabel, metaLabel])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 6
        contentView.addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.top.equalTo(artwork.snp.bottom).offset(14)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalToSuperview().priority(.high)
        }
        titleLabel.textColor = Theme.textPrimary
        titleLabel.holdScrolling = true
        titleLabel.fadeLength = 40
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        metaLabel.textColor = Theme.textTertiary
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    }

    func setup(data: any DisplayData) {
        titleLabel.text = data.title
        metaLabel.text = Self.metaText(for: data)
        let duration = CardFacts(overlay: data.overlay).duration
        durationLabel.text = duration
        durationLabel.isHidden = (duration ?? "").isEmpty
        if let badge = data.overlay?.badge, !badge.text.isEmpty {
            badgeLabel.text = badge.text
            badgeLabel.backgroundColor = badge.color ?? Theme.accent
            badgeLabel.isHidden = false
        } else {
            badgeLabel.isHidden = true
        }
        if var pic = data.pic {
            if pic.scheme == nil {
                pic = URL(string: "http:\(pic.absoluteString)")!
            }
            imageView.kf.setImage(with: pic, options: [.processor(DownsamplingImageProcessor(size: CGSize(width: 480, height: 270))), .cacheOriginalImage])
        }
        updateStyle()
    }

    /// Up name, views and category or area on one line. Danmaku counts stay off the card.
    static func metaText(for data: any DisplayData) -> String {
        let facts = CardFacts(overlay: data.overlay)
        var parts = [String]()
        if !data.ownerName.isEmpty {
            parts.append(data.ownerName)
        }
        if let views = facts.views {
            parts.append(views)
        }
        parts += facts.others
        if let date = data.date, !date.isEmpty {
            parts.append(date)
        }
        return parts.joined(separator: " · ")
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

    private func updateStyle() {
        let style = styleOverride ?? Settings.displayStyle
        titleLabel.font = style.titleFont
        metaLabel.font = style.upFont
    }

    @objc private func actionLongPress(sender: UILongPressGestureRecognizer) {
        guard sender.state == .began else { return }
        onLongPress?()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onLongPress = nil
        imageView.kf.cancelDownloadTask()
        imageView.image = nil
        stopScroll()
    }
}

extension FeedDisplayStyle {
    var fractionalWidth: CGFloat {
        switch self {
        case .large, .sideBar:
            return 0.33
        case .normal:
            return 0.25
        }
    }

    var fractionalHeight: CGFloat {
        switch self {
        case .large:
            return fractionalWidth / 1.5
        case .normal:
            return fractionalWidth / 1.5
        case .sideBar:
            return fractionalWidth / 1.15
        }
    }

    var heightEstimated: CGFloat {
        switch self {
        case .large:
            return 460
        case .normal, .sideBar:
            return 340
        }
    }

    var titleFont: UIFont {
        switch self {
        case .large:
            return .systemFont(ofSize: 32, weight: .semibold)
        case .normal:
            return .systemFont(ofSize: 28, weight: .semibold)
        case .sideBar:
            return .systemFont(ofSize: 24, weight: .semibold)
        }
    }

    var upFont: UIFont {
        switch self {
        case .large:
            return .systemFont(ofSize: 24)
        case .normal:
            return .systemFont(ofSize: 22)
        case .sideBar:
            return .systemFont(ofSize: 20)
        }
    }
}

/// What an overlay says, read from the text itself. Feeds disagree on which slot and icon carry
/// which value: the app's recommend feed puts the duration first under a play icon and the views
/// under the danmaku icon, while the web feeds put the duration on the right.
struct CardFacts {
    var duration: String?
    var views: String?
    var others: [String] = []

    init(overlay: DisplayOverlay?) {
        guard let overlay else { return }
        for item in overlay.rightItems + overlay.leftItems {
            let text = item.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, text != "-" else { continue }
            if duration == nil, CardFacts.isDuration(text) {
                duration = text
            } else if text.hasSuffix("弹幕") || (item.icon == "list.bullet.rectangle" && CardFacts.isCount(text)) {
                continue
            } else if views == nil, text.hasSuffix("观看") || text.hasSuffix("播放") {
                views = text
            } else if views == nil, item.icon == "play.rectangle", CardFacts.isCount(text) {
                views = text.replacingOccurrences(of: " ", with: "") + "播放"
            } else if item.icon == nil {
                others.append(text)
            }
        }
    }

    /// `3:34`, `1:07:07`, or watch progress such as `12:05/48:19`.
    static func isDuration(_ text: String) -> Bool {
        text.range(of: #"^\d{1,3}:\d{2}(:\d{2})?(/\d{1,3}:\d{2}(:\d{2})?)?$"#, options: .regularExpression) != nil
    }

    /// `139`, `5.6万`, or `12.3 万` as `numberString()` writes it.
    static func isCount(_ text: String) -> Bool {
        text.range(of: #"^[0-9.]+ ?[万亿]?$"#, options: .regularExpression) != nil
    }
}
