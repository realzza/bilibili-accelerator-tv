import AVFoundation
import Foundation

/// Reads the player's buffer, stall and error state. Main thread only.
final class PlayerProbe {
    struct Snapshot {
        var currentTime: Double = 0
        var bufferedAhead: Double = 0
        var likelyToKeepUp = false
        var bufferEmpty = false
        var stalls = 0
        var observedMbps: Double?
        var indicatedMbps: Double?
        var itemStatus = "unknown"
        var itemError: String?
        var lastErrorLog: String?
        var timeControl: String?
        var waitingReason: String?
    }

    private weak var item: AVPlayerItem?
    private weak var player: AVPlayer?
    private var stallObserver: NSObjectProtocol?
    private(set) var stallCount = 0

    var isAttached: Bool {
        item != nil
    }

    func attach(_ item: AVPlayerItem, player: AVPlayer?) {
        detach()
        self.item = item
        self.player = player
        stallObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemPlaybackStalled,
                                                               object: item, queue: .main)
        { [weak self] _ in
            self?.stallCount += 1
        }
    }

    func detach() {
        if let stallObserver {
            NotificationCenter.default.removeObserver(stallObserver)
        }
        stallObserver = nil
        stallCount = 0
        item = nil
        player = nil
    }

    func snapshot() -> Snapshot? {
        guard let item else { return nil }
        var snapshot = Snapshot()
        let now = item.currentTime().seconds
        snapshot.currentTime = now.isFinite ? now : 0
        for value in item.loadedTimeRanges {
            let range = value.timeRangeValue
            let start = range.start.seconds
            let end = (range.start + range.duration).seconds
            guard start.isFinite, end.isFinite else { continue }
            if start <= snapshot.currentTime + 0.5, end >= snapshot.currentTime {
                snapshot.bufferedAhead = max(snapshot.bufferedAhead, end - snapshot.currentTime)
            }
        }
        snapshot.likelyToKeepUp = item.isPlaybackLikelyToKeepUp
        snapshot.bufferEmpty = item.isPlaybackBufferEmpty
        snapshot.stalls = stallCount
        if let event = item.accessLog()?.events.last {
            snapshot.observedMbps = event.observedBitrate > 0 ? event.observedBitrate / 1_000_000 : nil
            snapshot.indicatedMbps = event.indicatedBitrate > 0 ? event.indicatedBitrate / 1_000_000 : nil
        }
        switch item.status {
        case .readyToPlay: snapshot.itemStatus = "ready"
        case .failed: snapshot.itemStatus = "failed"
        default: snapshot.itemStatus = "unknown"
        }
        if let error = item.error as NSError? {
            snapshot.itemError = "\(error.domain) \(error.code)"
        }
        if let events = item.errorLog()?.events, !events.isEmpty {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withTime, .withColonSeparatorInTime, .withFractionalSeconds]
            snapshot.lastErrorLog = events.suffix(4).map { event in
                let at = event.date.map { formatter.string(from: $0) } ?? "?"
                // Proxy URLs carry only a token; CDN URLs lose their query here.
                let uri = event.uri.flatMap { URLComponents(string: $0) }.map { "\($0.host ?? ""):\($0.port ?? 0)\($0.path)" } ?? "-"
                return "\(at) \(event.errorDomain) \(event.errorStatusCode) \(uri) \(event.errorComment ?? "")"
            }.joined(separator: " | ")
        }
        if let player {
            switch player.timeControlStatus {
            case .playing: snapshot.timeControl = "playing"
            case .paused: snapshot.timeControl = "paused"
            case .waitingToPlayAtSpecifiedRate: snapshot.timeControl = "waiting"
            @unknown default: snapshot.timeControl = "unknown"
            }
            snapshot.waitingReason = player.reasonForWaitingToPlay?.rawValue
        }
        return snapshot
    }
}
