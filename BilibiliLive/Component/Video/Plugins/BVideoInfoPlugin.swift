//
//  BVideoInfoPlugin.swift
//  BilibiliLive
//
//  Created by yicheng on 2024/5/25.
//

import AVKit
import Kingfisher

class BVideoInfoPlugin: NSObject, CommonPlayerPlugin {
    let title: String?
    let subTitle: String?
    let desp: String?
    let pic: URL?
    let viewPoints: [PlayerInfo.ViewPoint]?

    /// The cover, fetched as soon as the plugin exists so it is ready when the player is.
    private var artworkTask: Task<AVPlayerMetaUtils.Artwork?, Never>?
    private var artwork: AVPlayerMetaUtils.Artwork?

    init(title: String?, subTitle: String?, desp: String?, pic: URL?, viewPoints: [PlayerInfo.ViewPoint]?) {
        self.title = title
        self.subTitle = subTitle
        self.desp = desp
        self.pic = pic
        self.viewPoints = viewPoints
        super.init()
        artworkTask = Task { await AVPlayerMetaUtils.loadArtwork(pic) }
    }

    func playerDidLoad(playerVC: AVPlayerViewController) {
        if let player = playerVC.player {
            applyInfo(to: player)
        }
    }

    /// The info goes on the item as soon as there is one, while it still loads. The info panel
    /// builds its tabs when it first shows; info that arrived later added 简介 in front of the
    /// tabs already on screen.
    func playerDidChange(player: AVPlayer) {
        applyInfo(to: player)
    }

    func playerWillStart(player: AVPlayer) {
        if player.currentItem?.externalMetadata.isEmpty == true {
            applyInfo(to: player)
        }
        if let viewPoints {
            Task {
                await updatePlayerCharpter(viewPoints: viewPoints, player: player)
            }
        }
    }

    private func applyInfo(to player: AVPlayer) {
        MainActor.callSafely { [self] in
            guard let item = player.currentItem else { return }
            AVPlayerMetaUtils.apply(title: title, subTitle: subTitle, desp: desp, artwork: artwork, to: item)
            guard artwork == nil, let artworkTask else { return }
            Task { @MainActor [weak self, weak item] in
                guard let loaded = await artworkTask.value, let self, let item else { return }
                artwork = loaded
                AVPlayerMetaUtils.apply(title: title, subTitle: subTitle, desp: desp, artwork: loaded, to: item)
            }
        }
    }

    private func updatePlayerCharpter(viewPoints: [PlayerInfo.ViewPoint], player: AVPlayer) async {
        _ = await withTaskGroup(of: Void.self) { group in
            for viewPoint in viewPoints {
                group.addTask {
                    if let pic = viewPoint.imgUrl?.addSchemeIfNeed(),
                       let result = try? await KingfisherManager.shared.retrieveImage(
                           with: Kingfisher.ImageResource(downloadURL: pic),
                           options: [
                               .onlyLoadFirstFrame,
                               .processor(DownsamplingImageProcessor(size: CGSize(width: 320, height: 180))),
                           ]
                       ),
                       let data = result.image.pngData()
                    {
                        viewPoint.imageData = data
                    }
                }
            }
            return group
        }

        let metas = viewPoints.compactMap { convertTimedMetadataGroup(viewPoint: $0) }

        MainActor.callSafely {
            player.currentItem?.navigationMarkerGroups = [AVNavigationMarkersGroup(title: nil, timedNavigationMarkers: metas)]
        }
    }

    private func convertTimedMetadataGroup(viewPoint: PlayerInfo.ViewPoint) -> AVTimedMetadataGroup {
        let mapping: [AVMetadataIdentifier: Any?] = [
            .commonIdentifierTitle: viewPoint.content,
        ]
        var metadatas = mapping.compactMap { AVPlayerMetaUtils.createMetadataItem(for: $0, value: $1) }
        let timescale: Int32 = 600
        let cmStartTime = CMTimeMakeWithSeconds(viewPoint.from, preferredTimescale: timescale)
        let cmEndTime = CMTimeMakeWithSeconds(viewPoint.to, preferredTimescale: timescale)
        let timeRange = CMTimeRangeFromTimeToTime(start: cmStartTime, end: cmEndTime)
        if let imageData = viewPoint.imageData,
           let item = AVPlayerMetaUtils.createMetadataItem(for: .commonIdentifierArtwork, value: imageData)
        {
            metadatas.append(item)
        }

        return AVTimedMetadataGroup(items: metadatas, timeRange: timeRange)
    }
}

extension KingfisherManager {
    func retrieveImage(with resource: Resource,
                       options: KingfisherOptionsInfo? = nil) async throws -> RetrieveImageResult
    {
        try await withCheckedThrowingContinuation { conf in
            retrieveImage(with: resource, options: options) { result in
                switch result {
                case let .success(result):
                    conf.resume(returning: result)
                case let .failure(err):
                    conf.resume(throwing: err)
                }
            }
        }
    }
}
