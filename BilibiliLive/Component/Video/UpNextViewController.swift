//
//  UpNextViewController.swift
//  BilibiliLive
//

import AVKit
import Kingfisher
import SnapKit
import UIKit

/// The Up Next card in the last seconds of a video: the picture shrinks to the left and keeps
/// playing, and the next video's cover and title sit beside it with 立即播放 and 取消. The
/// countdown is the time left in this video; the next one starts when it ends.
final class UpNextViewController: AVContentProposalViewController {
    /// How long before the end the card appears, at most.
    static let leadTime: TimeInterval = 15

    private let upcoming: PlayInfo
    private let kickerLabel = UILabel()
    private let coverView = UIImageView()
    private let titleLabel = UILabel()
    private let ownerLabel = UILabel()
    private let countdownLabel = UILabel()
    private let playButton = UpNextViewController.makeButton(title: "立即播放", symbol: "play.fill")
    private let cancelButton = UpNextViewController.makeButton(title: "取消", symbol: "xmark")
    private var timer: Timer?

    init(next: PlayInfo) {
        upcoming = next
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredPlayerViewFrame: CGRect {
        CGRect(x: 80, y: 150, width: 1088, height: 612)
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [playButton]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Clear, so the shrunken picture shows; the player draws black around it.
        view.backgroundColor = .clear

        kickerLabel.text = "接下来播放"
        kickerLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        kickerLabel.textColor = Theme.accent
        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = Theme.cardRadius
        coverView.layer.cornerCurve = .continuous
        coverView.backgroundColor = Theme.groupedFill
        titleLabel.font = .systemFont(ofSize: 34, weight: .bold)
        titleLabel.textColor = Theme.textPrimary
        titleLabel.numberOfLines = 2
        ownerLabel.font = .systemFont(ofSize: 24)
        ownerLabel.textColor = Theme.textSecondary
        countdownLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .regular)
        countdownLabel.textColor = Theme.textTertiary

        playButton.addAction(UIAction { [weak self] _ in
            self?.dismissContentProposal(for: .accept, animated: true, completion: nil)
        }, for: .primaryActionTriggered)
        cancelButton.addAction(UIAction { [weak self] _ in
            self?.dismissContentProposal(for: .reject, animated: true, completion: nil)
        }, for: .primaryActionTriggered)
        let buttons = UIStackView(arrangedSubviews: [playButton, cancelButton])
        buttons.spacing = 20

        let column = UIStackView(arrangedSubviews: [kickerLabel, coverView, titleLabel, ownerLabel, buttons, countdownLabel])
        column.axis = .vertical
        column.alignment = .leading
        column.spacing = 16
        column.setCustomSpacing(24, after: coverView)
        column.setCustomSpacing(36, after: ownerLabel)
        column.setCustomSpacing(20, after: buttons)
        view.addSubview(column)
        let frame = preferredPlayerViewFrame
        column.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(frame.maxX + 64)
            make.trailing.lessThanOrEqualToSuperview().offset(-80)
            make.top.equalToSuperview().offset(frame.minY)
        }
        coverView.snp.makeConstraints { make in
            make.width.equalTo(608)
            make.height.equalTo(coverView.snp.width).multipliedBy(9.0 / 16)
        }
        titleLabel.snp.makeConstraints { make in
            make.width.lessThanOrEqualTo(608)
        }
        show(title: upcoming.title, owner: upcoming.ownerName, cover: upcoming.coverURL)
        if upcoming.title == nil || upcoming.coverURL == nil {
            loadDetails()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Danmaku and other overlays stay full screen while the picture shrinks; hide them.
        playerViewController?.contentOverlayView?.alpha = 0
        // No automatic acceptance: the video plays to its end, and the end moves on.
        dateOfAutomaticAcceptance = nil
        updateCountdown()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateCountdown()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        playerViewController?.contentOverlayView?.alpha = 1
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        timer?.invalidate()
        timer = nil
    }

    /// The time left in the video playing, which pauses when it does.
    private func updateCountdown() {
        guard let player = playerViewController?.player, let item = player.currentItem,
              item.duration.seconds.isFinite
        else {
            countdownLabel.text = nil
            return
        }
        let left = max(0, item.duration.seconds - player.currentTime().seconds)
        countdownLabel.text = "\(Int(left.rounded(.up))) 秒后自动播放"
    }

    private func show(title: String?, owner: String?, cover: URL?) {
        titleLabel.text = title ?? contentProposal?.title
        ownerLabel.text = owner
        ownerLabel.isHidden = (owner ?? "").isEmpty
        if var cover {
            if cover.scheme == nil {
                cover = URL(string: "https:\(cover.absoluteString)") ?? cover
            }
            coverView.kf.setImage(with: cover, options: [.processor(DownsamplingImageProcessor(size: CGSize(width: 608, height: 342)))])
        }
    }

    /// Sequences from collections and part lists may carry only ids; the rest comes from the
    /// video's page data.
    private func loadDetails() {
        let aid = upcoming.aid
        Task { [weak self] in
            guard let detail = try? await WebRequest.requestDetailVideo(aid: aid), let self else { return }
            show(title: upcoming.title ?? detail.title, owner: upcoming.ownerName ?? detail.ownerName, cover: upcoming.coverURL ?? detail.pic)
        }
    }

    private static func makeButton(title: String, symbol: String) -> UIButton {
        var config = UIButton.Configuration.capsule()
        config.title = title
        config.image = UIImage(systemName: symbol)
        config.imagePadding = 12
        config.contentInsets = NSDirectionalEdgeInsets(top: 18, leading: 36, bottom: 18, trailing: 36)
        config.setTitleFont(.systemFont(ofSize: 26, weight: .semibold))
        return UIButton(configuration: config)
    }
}
