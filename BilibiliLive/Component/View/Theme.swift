//
//  Theme.swift
//  BilibiliLive
//

import UIKit

/// Colors and shapes of the tvOS-native redesign. The app runs in the dark appearance; Bilibili
/// pink is kept for small accents (badges, the live marker, the line above a featured title).
enum Theme {
    /// The ground behind every screen, #0E1014.
    static let background = UIColor(red: 14 / 255, green: 16 / 255, blue: 20 / 255, alpha: 1)
    static let textPrimary = UIColor(red: 245 / 255, green: 245 / 255, blue: 247 / 255, alpha: 1)
    /// Metadata under titles. 0.72 of #EBEBF5 keeps 4.5:1 on the ground at small sizes.
    static let textSecondary = UIColor(red: 235 / 255, green: 235 / 255, blue: 245 / 255, alpha: 0.72)
    static let textTertiary = UIColor(red: 235 / 255, green: 235 / 255, blue: 245 / 255, alpha: 0.62)
    static let accent = UIColor(red: 251 / 255, green: 114 / 255, blue: 153 / 255, alpha: 1)
    /// Text on the accent.
    static let onAccent = UIColor(red: 26 / 255, green: 11 / 255, blue: 17 / 255, alpha: 1)
    /// A focused row or button: near-white fill with dark text, as tvOS draws it.
    static let focusedFill = textPrimary
    static let focusedText = UIColor(red: 17 / 255, green: 19 / 255, blue: 24 / 255, alpha: 1)
    /// A selected but unfocused row.
    static let selectedFill = UIColor(white: 1, alpha: 0.14)
    /// The card behind a group of settings rows.
    static let groupedFill = UIColor(white: 1, alpha: 0.06)
    /// Scrim behind text on a thumbnail.
    static let badgeFill = UIColor(red: 14 / 255, green: 16 / 255, blue: 20 / 255, alpha: 0.72)

    static let cardRadius: CGFloat = 18
    static let rowRadius: CGFloat = 20
    static let groupRadius: CGFloat = 28
}

extension UIButton.Configuration {
    /// The capsule buttons of the redesign: Liquid Glass on tvOS 26 and later, the system
    /// platter before that. tvOS draws the focused state itself. Every button uses the same
    /// style: a prominent one is as light at rest as a focused one, so focus would be unclear.
    static func capsule() -> UIButton.Configuration {
        var config: UIButton.Configuration
        if #available(tvOS 26.0, *) {
            config = .glass()
        } else {
            config = .bordered()
        }
        config.cornerStyle = .capsule
        return config
    }

    /// Sets the title font, which a configuration otherwise takes from the button style.
    mutating func setTitleFont(_ font: UIFont) {
        titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = font
            return attributes
        }
    }
}

/// A label with padding, for the small pills on thumbnails.
final class PillLabel: UILabel {
    var insets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}
