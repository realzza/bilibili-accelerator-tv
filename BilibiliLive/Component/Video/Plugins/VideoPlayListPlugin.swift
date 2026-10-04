//
//  VideoPlayListPlugin.swift
//  BilibiliLive
//
//  Created by yicheng on 2024/5/26.
//

import AVKit

class VideoPlayListPlugin: NSObject, CommonPlayerPlugin {
    private let nextActionIdentifierPrefix = "play.next"
    private weak var playerVC: AVPlayerViewController?
    var onPlayEnd: (() -> Void)?
    var onPlayNextWithInfo: ((PlayInfo) -> Void)?
    var onShowCurrentDetail: ((PlayInfo) -> Void)?

    let sequenceProvider: VideoSequenceProvider?
    /// What plays next when the video isn't part of a sequence: the top related video. Not
    /// offered while 循环播放 is on, which repeats the video instead.
    var fallbackNext: PlayInfo?

    private var offeredFallback: PlayInfo? {
        Settings.loopPlay ? nil : fallbackNext
    }

    /// The Up Next card on the current item, and whether the viewer turned it down.
    private var upNextProposal: AVContentProposal?
    private var declinedNext = false
    /// The card is on screen, waiting for 立即播放, 取消 or the end of the video.
    private var isShowingUpNext = false

    init(sequenceProvider: VideoSequenceProvider?) {
        self.sequenceProvider = sequenceProvider
    }

    func playerDidLoad(playerVC: AVPlayerViewController) {
        self.playerVC = playerVC
    }

    func playerWillStart(player: AVPlayer) {
        guard let playerVC else { return }
        guard let sequenceProvider else {
            scheduleUpNext(on: player, next: offeredFallback)
            return
        }
        let menuState = MainActor.assumeIsolated { () -> (PlayInfo?, PlayInfo?) in
            guard sequenceProvider.count > 0 else { return (nil, nil) }
            return (sequenceProvider.peekPrevious(), sequenceProvider.peekNext())
        }
        let next = menuState.1
        var actions = playerVC.infoViewActions.filter {
            !$0.identifier.rawValue.hasPrefix(nextActionIdentifierPrefix)
        }

        if let next {
            let nextAction = UIAction(title: "下一条",
                                      image: UIImage(systemName: "forward.end.fill"),
                                      identifier: .init(rawValue: "\(nextActionIdentifierPrefix).\(next.sequenceKey)"))
            { [weak self] _ in
                Task { [weak self] in
                    _ = await self?.playNext()
                }
            }
            actions.append(nextAction)
        }

        playerVC.infoViewActions = actions
        scheduleUpNext(on: player, next: next ?? offeredFallback)
    }

    /// Offers the next video in the last seconds of this one, as the system's Up Next card.
    private func scheduleUpNext(on player: AVPlayer, next: PlayInfo?) {
        declinedNext = false
        isShowingUpNext = false
        guard let item = player.currentItem else { return }
        let duration = item.duration.seconds
        guard Settings.continouslyPlay, let next, let playerVC, duration.isFinite, duration > 60 else {
            item.nextContentProposal = nil
            upNextProposal = nil
            return
        }
        let lead = min(UpNextViewController.leadTime, duration * 0.1)
        let proposal = AVContentProposal(contentTimeForTransition: CMTime(seconds: duration - lead, preferredTimescale: 600),
                                         title: next.title ?? "下一个视频", previewImage: nil)
        upNextProposal = proposal
        item.nextContentProposal = proposal
        playerVC.contentProposalViewController = UpNextViewController(next: next)
    }

    /// AVKit hands back its own copy of the proposal, so it is matched by title.
    private func isUpNext(_ proposal: AVContentProposal) -> Bool {
        upNextProposal?.title == proposal.title
    }

    func playerShouldPresent(contentProposal: AVContentProposal) -> Bool {
        let show = isUpNext(contentProposal)
        isShowingUpNext = isShowingUpNext || show
        return show
    }

    func playerDidAccept(contentProposal: AVContentProposal) {
        guard isUpNext(contentProposal) else { return }
        isShowingUpNext = false
        upNextProposal = nil
        Task { [weak self] in
            _ = await self?.playNext()
        }
    }

    /// 取消 pauses on dismissal, as AVKit leaves it; the video picks up again so it can end
    /// here, without moving on.
    func playerDidReject(contentProposal: AVContentProposal) {
        guard isUpNext(contentProposal) else { return }
        isShowingUpNext = false
        declinedNext = true
        playerVC?.player?.play()
    }

    func addMenuItems(current: inout [UIMenuElement]) -> [UIMenuElement] {
        let loopImage = UIImage(systemName: "infinity")
        let loopAction = UIAction(title: "循环播放", image: loopImage, state: Settings.loopPlay ? .on : .off) {
            action in
            action.state = (action.state == .off) ? .on : .off
            Settings.loopPlay = action.state == .on
        }
        var actions = [UIMenuElement](arrayLiteral: loopAction)
        let currentInfo = sequenceProvider.map { provider in
            MainActor.assumeIsolated { provider.current() }
        } ?? nil
        if let currentInfo, let onShowCurrentDetail {
            let detailAction = UIAction(title: "查看详情", image: UIImage(systemName: "info.circle")) { _ in
                onShowCurrentDetail(currentInfo)
            }
            actions.append(detailAction)
        }

        if let setting = current.compactMap({ $0 as? UIMenu })
            .first(where: { $0.identifier == UIMenu.Identifier(rawValue: "setting") })
        {
            var child = setting.children
            child.append(contentsOf: actions)
            if let index = current.firstIndex(of: setting) {
                current[index] = setting.replacingChildren(child)
            }
            return []
        }
        return actions
    }

    func playerDidEnd(player: AVPlayer) {
        // The card waits for the end; take it down before moving on.
        if isShowingUpNext {
            isShowingUpNext = false
            playerVC?.contentProposalViewController?.dismissContentProposal(for: .defer, animated: true, completion: nil)
        }
        Task { [weak self] in
            guard let self else { return }
            // 连续播放 off, or the Up Next card turned down: this video is the last.
            let advance = Settings.continouslyPlay && !declinedNext
            if !(advance ? await playNext() : false) {
                if Settings.loopPlay {
                    await MainActor.run {
                        self.sequenceProvider?.reset()
                    }
                    if !(await playNext(allowFallback: false)) {
                        player.currentItem?.seek(to: .zero, completionHandler: nil)
                        player.play()
                    }
                    return
                }
                await MainActor.run { [weak self] in
                    self?.onPlayEnd?()
                }
            }
        }
    }

    /// The next video of the sequence, or the related one when there is no sequence next.
    @discardableResult
    private func playNext(allowFallback: Bool = true) async -> Bool {
        if let next = await sequenceProvider?.moveNext() {
            await MainActor.run { [weak self] in
                self?.onPlayNextWithInfo?(next)
            }
            return true
        }
        let hasSequenceNext = await MainActor.run { sequenceProvider?.hasNext ?? false }
        if allowFallback, !hasSequenceNext, let fallbackNext = offeredFallback {
            self.fallbackNext = nil
            await MainActor.run { [weak self] in
                self?.onPlayNextWithInfo?(fallbackNext)
            }
            return true
        }
        return false
    }
}
