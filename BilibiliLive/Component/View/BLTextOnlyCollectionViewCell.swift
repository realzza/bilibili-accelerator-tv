//
//  BLTextOnlyCollectionViewCell.swift
//  BilibiliLive
//
//  Created by yicheng on 2022/10/24.
//

import Foundation
import UIKit

/// A text-only tile, for pages and page ranges on the video page.
class BLTextOnlyCollectionViewCell: BLMotionCollectionViewCell {
    private let fillView = UIView()
    let titleLabel = UILabel()

    override func setup() {
        super.setup()
        scaleFactor = 1.08
        contentView.addSubview(fillView)
        fillView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        fillView.layer.cornerRadius = Theme.rowRadius
        fillView.layer.cornerCurve = .continuous
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.centerX.centerY.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(20)
            make.top.bottom.lessThanOrEqualToSuperview().inset(8)
        }
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.font = .systemFont(ofSize: 26, weight: .medium)
        updateView()
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations {
            self.updateView()
        }
    }

    private func updateView() {
        fillView.backgroundColor = isFocused ? Theme.focusedFill : Theme.selectedFill
        titleLabel.textColor = isFocused ? Theme.focusedText : Theme.textPrimary
    }
}
