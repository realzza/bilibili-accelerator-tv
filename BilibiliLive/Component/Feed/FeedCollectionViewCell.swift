//
//  FeedCollectionViewCell.swift
//  BilibiliLive
//
//  Created by yicheng on 2022/10/20.
//

import CoreText
import Kingfisher
import MarqueeLabel
import SnapKit
import TVUIKit
import UIKit

/// A video card: a 16:9 thumbnail with the view count bottom left, the duration bottom right and
/// who may watch (such as 充电专属) top right, a title of up to `maxTitleLines` lines whose last line
/// scrolls when focused, and one line of metadata below.
class FeedCollectionViewCell: BLMotionCollectionViewCell {
    var onLongPress: (() -> Void)?
    var styleOverride: FeedDisplayStyle? { didSet { if oldValue != styleOverride { updateStyle() } }}
    /// How many lines the title may take. Lists whose cards size themselves to their content can
    /// use two; a card of fixed height keeps one.
    var maxTitleLines = 1
    /// Smaller text and spacing, for rows of fixed height, such as on the video page.
    var isCompact = false {
        didSet { if oldValue != isCompact { updateStyle() } }
    }

    /// The title's first line when it has two. Its last line is `titleLabel`, so all of a long
    /// title can still be read by focusing the card.
    private let firstLineLabel = UILabel()
    private let titleLabel = MarqueeLabel()
    private let metaLabel = UILabel()
    private let artwork = UIView()
    private let imageView = UIImageView()
    private let scrim = CardScrimView()
    private let focusRing = UIView()
    private let durationLabel = PillLabel()
    private let viewsLabel = PillLabel()
    private let badgeLabel = PillLabel()
    private let accessTag = AccessTagView(font: FeedCollectionViewCell.pillFont, fill: Theme.badgeFill, cornerRadius: 10)
    private let progressTrack = UIView()
    private let progressFill = UIView()
    private let textStack = UIStackView()
    private var textTopConstraint: Constraint?

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

        artwork.addSubview(scrim)
        scrim.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

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
        badgeLabel.font = .systemFont(ofSize: 20, weight: .bold)
        badgeLabel.textColor = Theme.onAccent
        badgeLabel.layer.cornerRadius = 10
        badgeLabel.clipsToBounds = true

        artwork.addSubview(accessTag)
        accessTag.snp.makeConstraints { make in
            make.trailing.top.equalToSuperview().inset(12)
            make.leading.greaterThanOrEqualTo(badgeLabel.snp.trailing).offset(8)
        }

        // Just outside the thumbnail, on top of everything on it. The usual dark shadow doesn't
        // show on the dark ground, so this is what marks the focused card from across the room.
        artwork.addSubview(focusRing)
        focusRing.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(-3)
        }
        focusRing.isUserInteractionEnabled = false
        focusRing.alpha = 0
        focusRing.layer.borderColor = Theme.textPrimary.cgColor
        focusRing.layer.borderWidth = 3
        focusRing.layer.cornerRadius = Theme.cardRadius + 3
        focusRing.layer.cornerCurve = .continuous

        [firstLineLabel, titleLabel, metaLabel].forEach(textStack.addArrangedSubview)
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.setCustomSpacing(4, after: firstLineLabel)
        contentView.addSubview(textStack)
        // Held to the top, so a one-line title in a taller card sits right under the thumbnail.
        textStack.snp.makeConstraints { make in
            textTopConstraint = make.top.equalTo(artwork.snp.bottom).offset(20).constraint
            make.leading.trailing.equalToSuperview()
            make.bottom.lessThanOrEqualToSuperview().priority(.high)
        }
        firstLineLabel.textColor = Theme.textPrimary
        firstLineLabel.lineBreakMode = .byClipping
        firstLineLabel.isHidden = true
        firstLineLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        titleLabel.textColor = Theme.textPrimary
        titleLabel.holdScrolling = true
        titleLabel.fadeLength = 40
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        metaLabel.textColor = Theme.textTertiary
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    }

    func setup(data: any DisplayData) {
        title = data.title
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
        accessTag.text = data.accessTag
        scrim.isHidden = durationLabel.isHidden && viewsLabel.isHidden && progressTrack.isHidden
        if var pic = data.pic {
            if pic.scheme == nil {
                pic = URL(string: "http:\(pic.absoluteString)")!
            }
            imageView.kf.setImage(with: pic, options: [.processor(DownsamplingImageProcessor(size: CGSize(width: 480, height: 270))),
                                                       .cacheOriginalImage,
                                                       .transition(.fade(0.2))])
        }
        updateStyle()
    }

    private var title = "" {
        didSet { splitTitle(width: contentView.bounds.width, force: true) }
    }

    private var splitWidth: CGFloat = 0
    private static let shortestSecondLine = 4

    /// Fills the title's lines for a card this wide, so the cell can size itself to them.
    private func splitTitle(width: CGFloat, force: Bool = false) {
        guard force || width != splitWidth else { return }
        splitWidth = width
        var firstLine = ""
        var rest = title
        if maxTitleLines > 1, width > 0, let font = titleLabel.font {
            let typesetter = CTTypesetterCreateWithAttributedString(NSAttributedString(string: title, attributes: [.font: font]))
            let text = title as NSString
            var length = CTTypesetterSuggestLineBreak(typesetter, 0, Double(width))
            // Don't leave a character or two alone on the second line.
            if length < text.length, text.length - length < Self.shortestSecondLine, length > Self.shortestSecondLine {
                length = text.rangeOfComposedCharacterSequence(at: text.length - Self.shortestSecondLine).location
            }
            firstLine = text.substring(to: length)
            rest = text.substring(from: length).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        firstLineLabel.text = firstLine
        firstLineLabel.isHidden = firstLine.isEmpty
        titleLabel.text = rest
        titleLabel.isHidden = rest.isEmpty
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        splitTitle(width: layoutAttributes.size.width)
        return super.preferredLayoutAttributesFitting(layoutAttributes)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        splitTitle(width: contentView.bounds.width)
    }

    /// Only the thumbnail, with corners and a progress bar to match its smaller size, for a strip
    /// of small cards.
    func showThumbnailOnly() {
        textStack.isHidden = true
        scaleFactor = 1.1
        imageView.layer.cornerRadius = 12
        scrim.layer.cornerRadius = 12
        focusRing.layer.cornerRadius = 15
        progressTrack.snp.remakeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview().inset(10)
            make.height.equalTo(5)
        }
        progressTrack.layer.cornerRadius = 2.5
    }

    private static let pillFont = UIFont.systemFont(ofSize: 20, weight: .semibold)

    /// A label at the top left of the thumbnail, such as 直播中 or 正在看; nil hides it.
    func setBadge(_ text: String?, color: UIColor = Theme.accent) {
        badgeLabel.text = text
        badgeLabel.font = .systemFont(ofSize: 20, weight: .bold)
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

    override func updateTransform() {
        super.updateTransform()
        focusRing.alpha = isFocused ? 1 : 0
        metaLabel.textColor = isFocused ? Theme.textSecondary : Theme.textTertiary
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
        let titleFont = isCompact ? .systemFont(ofSize: 24, weight: .semibold) : style.titleFont
        firstLineLabel.font = titleFont
        titleLabel.font = titleFont
        metaLabel.font = isCompact ? .systemFont(ofSize: 21) : style.upFont
        // Enough air between the thumbnail and its text that they don't read as crowded.
        textTopConstraint?.update(offset: isCompact ? 16 : 20)
        textStack.spacing = isCompact ? 6 : 8
        splitTitle(width: contentView.bounds.width, force: true)
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
        scrim.isHidden = false
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
        case .normal, .sideBar:
            return .systemFont(ofSize: 28, weight: .semibold)
        }
    }

    var upFont: UIFont {
        switch self {
        case .large:
            return .systemFont(ofSize: 25)
        case .normal, .sideBar:
            return .systemFont(ofSize: 23)
        }
    }
}

/// Darkens the bottom of a thumbnail, so what sits on it stays readable over any cover: Bilibili
/// covers usually carry big text of their own right where the pills go.
private final class CardScrimView: UIView {
    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        layer.cornerRadius = Theme.cardRadius
        layer.cornerCurve = .continuous
        guard let gradient = layer as? CAGradientLayer else { return }
        gradient.colors = [Theme.background.withAlphaComponent(0).cgColor, Theme.background.withAlphaComponent(0.72).cgColor]
        gradient.locations = [0.55, 1]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
