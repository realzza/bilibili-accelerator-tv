//
//  TitleSupplementaryView.swift
//  BilibiliLive
//
//  Created by yicheng on 2022/10/21.
//

import SnapKit
import UIKit

/// A section title above a grid of cards, with an optional count or note after it in gray.
class TitleSupplementaryView: UICollectionReusableView {
    let label = UILabel()
    static let reuseIdentifier = "title-supplementary-reuse-identifier"

    /// Where the title starts, to line it up with the first card.
    var leadingInset: CGFloat = 20 {
        didSet {
            label.snp.updateConstraints { make in
                make.leading.equalToSuperview().offset(leadingInset)
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }
}

extension TitleSupplementaryView {
    func configure() {
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.leading.equalToSuperview().offset(leadingInset)
            make.trailing.equalToSuperview()
            make.bottom.equalToSuperview().offset(-8)
        }
        label.font = .systemFont(ofSize: 30, weight: .semibold)
        label.textColor = Theme.textPrimary
    }

    func set(title: String, detail: String?) {
        let text = NSMutableAttributedString(string: title)
        if let detail, !detail.isEmpty {
            text.append(NSAttributedString(string: "  " + detail, attributes: [.foregroundColor: Theme.textTertiary,
                                                                               .font: UIFont.systemFont(ofSize: 30, weight: .medium)]))
        }
        label.attributedText = text
    }
}
