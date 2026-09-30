//
//  BLSettingLineCollectionViewCell.swift
//  BilibiliLive
//
//  Created by yicheng on 2022/10/29.
//

import UIKit

/// A row in a sidebar list (直播 categories, 我的). Plain text at rest, a soft fill when it is the
/// selected page, and the white tvOS highlight when focused.
class BLSettingLineCollectionViewCell: BLMotionCollectionViewCell {
    let fillView = UIView()
    let titleLabel = UILabel()
    override var isSelected: Bool {
        didSet {
            updateView()
        }
    }

    override func setup() {
        super.setup()
        scaleFactor = 1.04
        contentView.addSubview(fillView)
        fillView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        fillView.layer.cornerRadius = Theme.rowRadius
        fillView.layer.cornerCurve = .continuous
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(28)
            make.trailing.equalToSuperview().offset(-20)
            make.centerY.equalToSuperview()
        }
        titleLabel.textAlignment = .left
        updateView()
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations {
            self.updateView()
        }
    }

    func updateView() {
        if isFocused {
            fillView.backgroundColor = Theme.focusedFill
            titleLabel.textColor = Theme.focusedText
            titleLabel.font = .systemFont(ofSize: 30, weight: .semibold)
        } else if isSelected {
            fillView.backgroundColor = Theme.selectedFill
            titleLabel.textColor = Theme.textPrimary
            titleLabel.font = .systemFont(ofSize: 30, weight: .semibold)
        } else {
            fillView.backgroundColor = .clear
            titleLabel.textColor = Theme.textSecondary
            titleLabel.font = .systemFont(ofSize: 30, weight: .medium)
        }
    }

    static func makeLayout() -> UICollectionViewLayout {
        // Rows start at the safe margin, where the avatar of 我的 and the cards of other tabs start.
        let itemSize = NSCollectionLayoutSize(widthDimension: .absolute(380),
                                              heightDimension: .fractionalHeight(1.0))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                               heightDimension: .absolute(68))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize,
                                                       subitems: [item])
        group.edgeSpacing = .init(leading: nil, top: .fixed(6), trailing: nil, bottom: nil)
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 20, leading: 0, bottom: 40, trailing: 0)
        let layout = UICollectionViewCompositionalLayout(section: section)
        return layout
    }
}
