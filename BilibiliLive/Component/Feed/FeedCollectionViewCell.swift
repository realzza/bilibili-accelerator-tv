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

/// A video card: a 16:9 thumbnail with the view count bottom left and the duration bottom right,
/// a one-line title that scrolls when focused, and one line of metadata below.
class FeedCollectionViewCell: BLMotionCollectionViewCell {
    var onLongPress: (() -> Void)?
    var styleOverride: FeedDisplayStyle? { didSet { if oldValue != styleOverride { updateStyle() } }}

    private let titleLabel = MarqueeLabel()
    private let metaLabel = UILabel()
    private let artwork = UIView()
    private let imageView = UIImageView()
    private let durationLabel = PillLabel()
    private let viewsLabel = PillLabel()
    private let badgeLabel = PillLabel()
    private let progressTrack = UIView()
    private let progressFill = UIView()

    /// How much of the video was watched, 0 to 1, drawn along the bottom of the thumbnail in
    /// place of the view count and duration. Nil hides it.
    var progress: Double? {
        didSet { updateProgress() }
    }

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

        for pill in [durationLabel, viewsLabel] {
            artwork.addSubview(pill)
            pill.font = Self.pillFont
            pill.textColor = Theme.textPrimary
            pill.backgroundColor = Theme.badgeFill
            pill.layer.cornerRadius = 10
            pill.clipsToBounds = true
        }
        durationLabel.snp.makeConstraints { make in
            make.trailing.bottom.equalToSuperview().inset(12)
        }
        viewsLabel.snp.makeConstraints { make in
            make.leading.bottom.equalToSuperview().inset(12)
            make.trailing.lessThanOrEqualTo(durationLabel.snp.leading).offset(-8)
        }

        artwork.addSubview(progressTrack)
        progressTrack.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview().inset(14)
            make.height.equalTo(6)
        }
        progressTrack.backgroundColor = UIColor(white: 1, alpha: 0.32)
        progressTrack.layer.cornerRadius = 3
        progressTrack.clipsToBounds = true
        progressTrack.addSubview(progressFill)
        progressFill.backgroundColor = Theme.accent
        progressTrack.isHidden = true

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
        let facts = CardFacts(overlay: data.overlay)
        durationLabel.text = facts.duration
        durationLabel.isHidden = (facts.duration ?? "").isEmpty
        viewsLabel.attributedText = facts.views.map(Self.viewsText)
        viewsLabel.isHidden = facts.views == nil
        progress = data.watchProgress
        if let badge = data.overlay?.badge, !badge.text.isEmpty {
            setBadge(badge.text, color: badge.color ?? Theme.accent)
        } else {
            setBadge(nil)
        }
        if var pic = data.pic {
            if pic.scheme == nil {
                pic = URL(string: "http:\(pic.absoluteString)")!
            }
            imageView.kf.setImage(with: pic, options: [.processor(DownsamplingImageProcessor(size: CGSize(width: 480, height: 270))), .cacheOriginalImage])
        }
        updateStyle()
    }

    private static let pillFont = UIFont.systemFont(ofSize: 20, weight: .semibold)

    /// A label at the top left of the thumbnail, such as 直播中 or 正在看; nil hides it.
    func setBadge(_ text: String?, color: UIColor = Theme.accent) {
        badgeLabel.text = text
        badgeLabel.font = .systemFont(ofSize: 18, weight: .bold)
        badgeLabel.insets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        badgeLabel.backgroundColor = color
        badgeLabel.textColor = Theme.onAccent
        badgeLabel.isHidden = text == nil
    }

    /// A ranking's place at the top left of the thumbnail: pink for the top three.
    func setRank(_ rank: Int) {
        badgeLabel.text = "\(rank)"
        badgeLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .heavy)
        badgeLabel.insets = UIEdgeInsets(top: 2, left: 14, bottom: 2, right: 14)
        badgeLabel.backgroundColor = rank <= 3 ? Theme.accent : Theme.badgeFill
        badgeLabel.textColor = rank <= 3 ? Theme.onAccent : Theme.textPrimary
        badgeLabel.isHidden = false
    }

    /// `▶ 18.6万` for `18.6万播放` or `18.6万观看`, and `👤 945` for `945人在看` on a live room, to
    /// sit on the thumbnail like the duration.
    static func viewsText(_ views: String) -> NSAttributedString {
        var count = views
        let isLive = views.hasSuffix("在看")
        for suffix in ["播放", "观看", "人在看", "在看"] where count.hasSuffix(suffix) {
            count = String(count.dropLast(suffix.count))
        }
        let text = NSMutableAttributedString()
        let symbol = UIImage(systemName: isLive ? "person.fill" : "play.fill",
                             withConfiguration: UIImage.SymbolConfiguration(font: pillFont, scale: .small))
        if let symbol = symbol?.withTintColor(Theme.textPrimary, renderingMode: .alwaysOriginal) {
            text.append(NSAttributedString(attachment: NSTextAttachment(image: symbol)))
            text.append(NSAttributedString(string: " "))
        }
        text.append(NSAttributedString(string: count.replacingOccurrences(of: " ", with: "")))
        text.addAttributes([.font: pillFont, .foregroundColor: Theme.textPrimary], range: NSRange(location: 0, length: text.length))
        return text
    }

    /// Up name, category or area, and date on one line. Views sit on the thumbnail; danmaku counts
    /// stay off the card.
    static func metaText(for data: any DisplayData) -> String {
        let facts = CardFacts(overlay: data.overlay)
        var parts = [String]()
        if !data.ownerName.isEmpty {
            parts.append(data.ownerName)
        }
        parts += facts.others
        if let date = data.date, !date.isEmpty {
            parts.append(shortDate(date))
        }
        return parts.joined(separator: " · ")
    }

    private static let yearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// `9月30日` for a `2026-09-30` in the current year, so the line has room for the rest.
    static func shortDate(_ text: String) -> String {
        guard let date = yearFormatter.date(from: text),
              Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        else { return text }
        let components = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)月\(components.day ?? 0)日"
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

    private func updateProgress() {
        guard let progress else {
            progressTrack.isHidden = true
            return
        }
        progressTrack.isHidden = false
        durationLabel.isHidden = true
        viewsLabel.isHidden = true
        progressFill.snp.remakeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.width.equalToSuperview().multipliedBy(min(max(progress, 0.02), 1))
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        progress = nil
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
            } else if views == nil, text.hasSuffix("观看") || text.hasSuffix("播放") || text.hasSuffix("在看") {
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
