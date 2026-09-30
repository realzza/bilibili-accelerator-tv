import AVFoundation
import Foundation

/// Reads the player's buffer and stall state. Main thread only.
final class PlayerProbe {
    struct Snapshot {
        var currentTime: Double = 0
        var bufferedAhead: Double = 0
        var likelyToKeepUp = false
        var bufferEmpty = false
        var stalls = 0
        var observedMbps: Double?
        var indicatedMbps: Double?
    }

    private weak var item: AVPlayerItem?
    private var stallObserver: NSObjectProtocol?
    private(set) var stallCount = 0

    var isAttached: Bool {
        item != nil
    }

    func attach(_ item: AVPlayerItem) {
        detach()
        self.item = item
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
        return snapshot
    }
}
