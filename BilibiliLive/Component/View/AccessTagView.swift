//
//  AccessTagView.swift
//  BilibiliLive
//

import SnapKit
import UIKit

/// A tag for who may watch a video, such as 充电专属: Bilibili's pink lightning bolt and the text
/// on a pill. Its baselines are the text's, so a stack can line it up with text beside it.
final class AccessTagView: UIView {
    /// Nil hides the tag.
    var text: String? {
        didSet {
            label.text = text
            isHidden = text == nil
        }
    }

    private let icon = UIImageView()
    private let label = UILabel()

    init(font: UIFont, fill: UIColor, cornerRadius: CGFloat) {
        super.init(frame: .zero)
        backgroundColor = fill
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        isHidden = true

        label.font = font
        label.textColor = Theme.textPrimary
        icon.image = UIImage(systemName: "bolt.fill", withConfiguration: UIImage.SymbolConfiguration(font: font, scale: .small))
        icon.tintColor = Theme.accent
        addSubview(icon)
        addSubview(label)
        icon.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(10)
            // On the middle of the capitals, where the text's own symbols sit.
            make.centerY.equalTo(label.snp.firstBaseline).offset(-font.capHeight / 2)
        }
        label.snp.makeConstraints { make in
            make.leading.equalTo(icon.snp.trailing).offset(5)
            make.trailing.equalToSuperview().inset(10)
            make.top.bottom.equalToSuperview().inset(4)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var forFirstBaselineLayout: UIView { label }
    override var forLastBaselineLayout: UIView { label }
}
