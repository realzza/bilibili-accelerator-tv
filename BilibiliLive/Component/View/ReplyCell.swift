//
// Created by Yam on 2024/6/9.
//

import Kingfisher
import UIKit

class ReplyCell: BLMotionCollectionViewCell {
    class var identifier: String {
        return String(describing: Self.self)
    }

    @IBOutlet var avatarImageView: UIImageView!
    @IBOutlet var userNameLabel: UILabel!
    @IBOutlet var contenLabel: UILabel!
    /// Likes and how long ago, at the top right beside the name.
    private let metaLabel = UILabel()

    private var card: BLCardView? {
        contentView.subviews.first as? BLCardView
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        scaleFactor = 1.04
        userNameLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        contenLabel.font = .systemFont(ofSize: 24)
        contenLabel.textAlignment = .natural
        contenLabel.numberOfLines = 5
        contenLabel.lineBreakMode = .byTruncatingTail
        if let container = userNameLabel.superview {
            container.addSubview(metaLabel)
            metaLabel.font = .systemFont(ofSize: 20)
            metaLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            metaLabel.snp.makeConstraints { make in
                make.centerY.equalTo(userNameLabel)
                make.trailing.equalToSuperview().offset(-20)
                make.leading.greaterThanOrEqualTo(userNameLabel.snp.trailing).offset(12)
            }
        }
        updateColors()
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations {
            self.updateColors()
        }
    }

    /// A white card with dark text when focused, as rows and buttons are elsewhere.
    private func updateColors() {
        card?.fill = isFocused ? Theme.focusedFill : BLCardView.restingFill
        userNameLabel.textColor = isFocused ? Theme.focusedText : Theme.textPrimary
        contenLabel.textColor = isFocused ? Theme.focusedText : Theme.textSecondary
        metaLabel.textColor = isFocused ? Theme.focusedText.withAlphaComponent(0.6) : Theme.textTertiary
    }

    func config(replay: Replys.Reply) {
        avatarImageView.kf.setImage(
            with: URL(string: replay.member.avatar),
            options: [
                .processor(DownsamplingImageProcessor(size: CGSize(width: 80, height: 80))),
                .processor(RoundCornerImageProcessor(radius: .widthFraction(0.5))),
                .cacheSerializer(FormatIndicatedCacheSerializer.png),
            ]
        )
        userNameLabel.text = replay.member.uname
        let parts = [replay.like.flatMap { $0 > 0 ? "♥ " + $0.numberString().replacingOccurrences(of: " ", with: "") : nil },
                     DateFormatter.relativeTimeStringFor(timestamp: replay.ctime)]
        metaLabel.text = parts.compactMap { $0 }.joined(separator: " · ")
        if let attr = replay.createAttributedString(displayView: contenLabel) {
            contenLabel.attributedText = attr
        } else {
            contenLabel.text = replay.content.message
        }
        updateColors()
    }
}
