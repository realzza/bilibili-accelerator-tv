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
        if let attr = replay.createAttributedString(displayView: contenLabel) {
            contenLabel.attributedText = attr
        } else {
            contenLabel.text = replay.content.message
        }
        updateColors()
    }
}
