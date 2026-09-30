import Foundation

/// What the player's route panel shows about the video playing now.
public struct RouteStatus: Equatable {
    public enum Test: Equatable {
        /// None asked for on this video.
        case none
        /// Asked for: the next video fragment is served by a race between two other hosts.
        case pending
        /// The last test moved the video to this host.
        case moved(to: String)
        /// The last test found no host clearly faster than the current one.
        case stayed
    }

    /// The host serving the video now.
    public let host: String
    /// Whether that is the host Bilibili issued first, where the video started.
    public let isIssuedHost: Bool
    /// Times the engine moved this video to another host.
    public let switches: Int
    /// Sustained rate on the current host, in Mbps.
    public let mbps: Double?
    /// Rates of the last video fragments on any host, oldest first, in Mbps.
    public let recentMbps: [Double]
    /// Seconds buffered ahead of the playhead.
    public let bufferSeconds: Double?
    /// Bitrate of the video being played, in Mbps.
    public let requiredMbps: Double?
    /// The player is waiting for data.
    public let isStalled: Bool
    public let test: Test

    /// Overseas edges, Akamai included, as opposed to mainland mirrors and caches.
    public static func isOverseas(_ host: String) -> Bool {
        Candidates.isOverseas(host)
    }
}
