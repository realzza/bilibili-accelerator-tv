//
//  UpSpaceTitleSupplementaryView.swift
//  BilibiliLive
//
//  Created by bitxeno on 2025/11/27.
//

import SnapKit
import UIKit

/// The top of an uploader's space: avatar, name and signature, and labeled buttons to change the
/// order of the videos, follow and block.
class UpSpaceTitleSupplementaryView: UICollectionReusableView {
    let imageView = UIImageView()
    let nameLabel = UILabel()
    let despLabel = UILabel()
    /// On: sorted by plays; off: newest first.
    let sortButton = CapsuleToggleButton(off: ("最新发布", "clock"), on: ("最多播放", "flame"))
    let followButton = CapsuleToggleButton(off: ("关注", "plus"), on: ("已关注", "checkmark"))
    let blockButton = CapsuleToggleButton(off: ("拉黑", "hand.raised"), on: ("已拉黑", "hand.raised.fill"))
    private let focusGuide = UIFocusGuide()

    var onFollowTapped: ((Bool) -> Void)?
    var onBlockTapped: ((Bool) -> Void)?
    var onSortTapped: ((Bool) -> Void)?
    var mid: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    private func setupUI() {
        let buttons = UIStackView(arrangedSubviews: [sortButton, followButton, blockButton])
        buttons.spacing = 20
        buttons.alignment = .center
        addSubview(imageView)
        addSubview(nameLabel)
        addSubview(despLabel)
        addSubview(buttons)
        addLayoutGuide(focusGuide)

        imageView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Settings.displayStyle.itemInset)
            make.top.equalToSuperview()
            make.bottom.equalToSuperview().offset(-36)
            make.width.equalTo(imageView.snp.height)
            make.width.equalTo(120)
        }
        imageView.layer.cornerRadius = 60
        imageView.clipsToBounds = true
        imageView.backgroundColor = Theme.groupedFill

        nameLabel.snp.makeConstraints { make in
            make.bottom.equalTo(imageView.snp.centerY).offset(-4)
            make.leading.equalTo(imageView.snp.trailing).offset(28)
            make.trailing.lessThanOrEqualTo(buttons.snp.leading).offset(-40)
        }

        despLabel.snp.makeConstraints { make in
            make.leading.equalTo(nameLabel.snp.leading)
            make.top.equalTo(imageView.snp.centerY).offset(6)
            make.trailing.lessThanOrEqualTo(buttons.snp.leading).offset(-40)
        }

        buttons.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-Settings.displayStyle.itemInset)
            make.centerY.equalTo(imageView)
        }

        nameLabel.font = .systemFont(ofSize: 40, weight: .bold)
        nameLabel.textColor = Theme.textPrimary
        despLabel.font = .systemFont(ofSize: 24)
        despLabel.textColor = Theme.textTertiary
        despLabel.numberOfLines = 2

        followButton.onPrimaryAction = { [weak self] in
            self?.followButtonTapped()
        }
        blockButton.onPrimaryAction = { [weak self] in
            self?.blockButtonTapped()
        }
        sortButton.onPrimaryAction = { [weak self] in
            self?.sortButtonTapped()
        }

        focusGuide.preferredFocusEnvironments = [sortButton, followButton, blockButton]
        focusGuide.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.top.bottom.equalTo(buttons)
            make.trailing.equalTo(buttons.snp.leading)
        }
    }

    private func sortButtonTapped() {
        sortButton.isOn.toggle()
        onSortTapped?(sortButton.isOn)
    }

    private func followButtonTapped() {
        followButton.isOn.toggle()
        onFollowTapped?(followButton.isOn)

        if let mid = mid {
            WebRequest.follow(mid: mid, follow: followButton.isOn)
        }
    }

    private func blockButtonTapped() {
        blockButton.isOn.toggle()

        if let mid = mid {
            WebRequest.block(mid: mid, block: blockButton.isOn) { [weak self] _ in
                guard let self else { return }
                self.onBlockTapped?(self.blockButton.isOn)
            }
        }
    }
}

/// A capsule button with a title and symbol for each of two states, such as 关注 and 已关注.
final class CapsuleToggleButton: UIButton {
    var isOn = false {
        didSet { setNeedsUpdateConfiguration() }
    }

    var onPrimaryAction: (() -> Void)?

    init(off: (title: String, symbol: String), on: (title: String, symbol: String)) {
        super.init(frame: .zero)
        var config = UIButton.Configuration.capsule()
        config.imagePadding = 10
        config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 28, bottom: 16, trailing: 28)
        config.setTitleFont(.systemFont(ofSize: 24, weight: .semibold))
        configuration = config
        configurationUpdateHandler = { [weak self] button in
            let state = (self?.isOn ?? false) ? on : off
            button.configuration?.title = state.title
            button.configuration?.image = UIImage(systemName: state.symbol,
                                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold))
        }
        addAction(UIAction { [weak self] _ in self?.onPrimaryAction?() }, for: .primaryActionTriggered)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
