//
//  AVPlayerMetaUtils.swift
//  BilibiliLive
//
//  Created by yicheng on 2024/6/6.
//

import AVKit
import Kingfisher
import MediaPlayer

enum AVPlayerMetaUtils {
    /// The cover for the info panel and Now Playing, as PNG data and an image.
    struct Artwork {
        let data: Data
        let image: UIImage
    }

    static func loadArtwork(_ pic: URL?) async -> Artwork? {
        guard let pic,
              let resource = try? await KingfisherManager.shared.retrieveImage(
                  with: Kingfisher.KF.ImageResource(downloadURL: pic),
                  options: [
                      .onlyLoadFirstFrame,
                      .processor(DownsamplingImageProcessor(size: CGSize(width: 640, height: 360))),
                  ]
              ),
              let data = resource.image.pngData()
        else { return nil }
        return Artwork(data: data, image: resource.image)
    }

    /// Puts the title, subtitle, description and cover on `item` for the info panel's 简介 tab,
    /// and on Now Playing. A description of just "-", which Bilibili shows for none, is left out.
    @MainActor
    static func apply(title: String?, subTitle: String?, desp: String?, artwork: Artwork?, to item: AVPlayerItem) {
        var desp = desp?.components(separatedBy: "\n").joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if desp == "-" || desp?.isEmpty == true {
            desp = nil
        }
        let mapping: [AVMetadataIdentifier: Any?] = [
            .commonIdentifierTitle: title,
            .iTunesMetadataTrackSubTitle: subTitle,
            .commonIdentifierDescription: desp,
            .commonIdentifierArtwork: artwork?.data,
        ]
        item.externalMetadata = mapping.compactMap { createMetadataItem(for: $0, value: $1) }

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: title ?? "",
            MPMediaItemPropertyArtist: subTitle ?? "",
        ]
        if let artwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.image.size) { _ in artwork.image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    static func createMetadataItem(for identifier: AVMetadataIdentifier, value: Any?) -> AVMetadataItem? {
        if value == nil { return nil }
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as? NSCopying & NSObjectProtocol
        // Specify "und" to indicate an undefined language.
        item.extendedLanguageTag = "und"
        return item.copy() as? AVMetadataItem
    }
}
