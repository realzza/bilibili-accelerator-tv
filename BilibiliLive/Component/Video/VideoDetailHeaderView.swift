//
//  VideoDetailHeaderView.swift
//  BilibiliLive
//

import Kingfisher
import SnapKit
import UIKit

/// The top of the video page: title, uploader, one line of stats, the description and the
/// actions. The page draws the cover behind it.
final class VideoDetailHeaderView: UIView {
    /// Tall enough that the first section below starts about two thirds down the screen.
    static let minimumHeight: CGFloat = 720

    let titleLabel = UILabel()
    let upButton = UIButton(configuration: .capsule())
    let followButton = UIButton(configuration: .capsule())
    let followersLabel = UILabel()
    let statsLabel = UILabel()
    let noteView = NoteDetailView()
    let playButton = UIButton(configuration: .capsule())
    let likeButton = DetailActionButton(symbol: "hand.thumbsup", onSymbol: "hand.thumbsup.fill", title: "点赞")
    let coinButton = DetailActionButton(symbol: "bitcoinsign.circle", onSymbol: "bitcoinsign.circle.fill", title: "投币")
    let favButton = DetailActionButton(symbol: "star", onSymbol: "star.fill", title: "收藏")
    let watchLaterButton = DetailActionButton(symbol: "clock", onSymbol: "clock.fill", title: "稍后看")
    let dislikeButton = DetailActionButton(symbol: "hand.thumbsdown", onSymbol: "hand.thumbsdown.fill", title: "不喜欢")

    var isFollowing = false {
        didSet { followButton.setNeedsUpdateConfiguration() }
    }

    var playTitle = "播放" {
        didSet { playButton.configuration?.title = playTitle }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setUploader(name: String, avatar: URL?) {
        upButton.configuration?.title = name
        guard let avatar else { return }
        let side = Self.avatarSide
        let processor = DownsamplingImageProcessor(size: CGSize(width: side, height: side))
            |> RoundCornerImageProcessor(radius: .widthFraction(0.5))
        KingfisherManager.shared.retrieveImage(with: avatar, options: [.processor(processor),
                                                                       .scaleFactor(UIScreen.main.scale),
                                                                       .cacheSerializer(FormatIndicatedCacheSerializer.png)])
        { [weak self] result in
            guard case let .success(value) = result else { return }
            self?.upButton.configuration?.image = value.image.withRenderingMode(.alwaysOriginal)
        }
    }

    private static let avatarSide: CGFloat = 44

    private func setup() {
        titleLabel.font = .systemFont(ofSize: 62, weight: .bold)
        titleLabel.textColor = Theme.textPrimary
        titleLabel.numberOfLines = 2

        var upConfig = upButton.configuration
        upConfig?.image = UIImage(systemName: "person.crop.circle.fill",
                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: Self.avatarSide))
        upConfig?.imagePadding = 14
        upConfig?.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 26)
        upConfig?.setTitleFont(.systemFont(ofSize: 26, weight: .semibold))
        upButton.configuration = upConfig

        var followConfig = followButton.configuration
        followConfig?.imagePadding = 8
        followConfig?.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24)
        followConfig?.setTitleFont(.systemFont(ofSize: 24, weight: .semibold))
        followButton.configuration = followConfig
        followButton.configurationUpdateHandler = { [weak self] button in
            let following = self?.isFollowing ?? false
            var config = button.configuration
            config?.title = following ? "已关注" : "关注"
            config?.image = UIImage(systemName: following ? "checkmark" : "plus",
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold))
            button.configuration = config
        }

        followersLabel.font = .systemFont(ofSize: 22)
        followersLabel.textColor = Theme.textTertiary
        statsLabel.font = .systemFont(ofSize: 23)
        statsLabel.textColor = Theme.textSecondary

        var playConfig = playButton.configuration
        playConfig?.title = playTitle
        playConfig?.image = UIImage(systemName: "play.fill")
        playConfig?.imagePadding = 14
        playConfig?.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 48, bottom: 0, trailing: 48)
        playConfig?.setTitleFont(.systemFont(ofSize: 28, weight: .semibold))
        playButton.configuration = playConfig
        playButton.snp.makeConstraints { make in
            make.height.equalTo(DetailActionButton.side)
        }

        let uploaderRow = UIStackView(arrangedSubviews: [upButton, followersLabel, followButton])
        uploaderRow.axis = .horizontal
        uploaderRow.alignment = .center
        uploaderRow.spacing = 20

        let actionRow = UIStackView(arrangedSubviews: [playButton, likeButton, coinButton, favButton, watchLaterButton, dislikeButton])
        actionRow.axis = .horizontal
        actionRow.alignment = .top
        actionRow.spacing = 28

        let stack = UIStackView(arrangedSubviews: [titleLabel, uploaderRow, statsLabel, noteView, actionRow])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 22
        stack.setCustomSpacing(40, after: noteView)
        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.leading.equalTo(layoutMarginsGuide)
            make.width.equalTo(960)
            make.top.greaterThanOrEqualToSuperview().offset(100)
            make.bottom.equalToSuperview().offset(-30)
        }
        noteView.snp.makeConstraints { make in
            make.width.equalTo(stack)
        }
        snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(Self.minimumHeight)
            // As short as the content allows: without this the height is ambiguous.
            make.height.equalTo(Self.minimumHeight).priority(.low)
        }
    }
}

/// A round button with a count or name under it, for 点赞, 投币, 收藏, 稍后看 and 不喜欢.
final class DetailActionButton: UIStackView {
    static let side: CGFloat = 80

    let button = UIButton(configuration: .capsule())
    private let caption = UILabel()

    /// The count under the button, or its name until the count is known.
    var title: String? {
        get { caption.text }
        set { caption.text = newValue }
    }

    var isOn = false {
        didSet { button.setNeedsUpdateConfiguration() }
    }

    init(symbol: String, onSymbol: String, title: String) {
        super.init(frame: .zero)
        axis = .vertical
        alignment = .center
        spacing = 12
        addArrangedSubview(button)
        addArrangedSubview(caption)
        button.snp.makeConstraints { make in
            make.size.equalTo(Self.side)
        }
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 30, weight: .medium)
        button.configurationUpdateHandler = { [weak self] button in
            let on = self?.isOn ?? false
            var config = button.configuration
            config?.image = UIImage(systemName: on ? onSymbol : symbol, withConfiguration: symbolConfig)
            // The accent marks an action already taken; focused, tvOS picks the colors.
            config?.baseForegroundColor = on && !button.isFocused ? Theme.accent : nil
            button.configuration = config
        }
        caption.text = title
        caption.font = .systemFont(ofSize: 20)
        caption.textColor = Theme.textSecondary
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
