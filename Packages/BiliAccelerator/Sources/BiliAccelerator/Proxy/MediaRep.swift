import Foundation

/// One DASH representation as the playurl API issued it: the same file on each CDN host.
public struct MediaRep {
    public enum Kind: String {
        case video
        case audio
    }

    public let kind: Kind
    /// Quality id (qn) for video, 302xx or 3025x for audio.
    public let id: Int
    /// Declared average bitrate, bits per second.
    public let bandwidth: Int
    public let codecs: String
    /// Every issued URL: base first, then backups.
    public let urls: [URL]
    /// The URL the app would have played without the proxy.
    public let preferred: URL
    public let referer: String

    public init(kind: Kind, id: Int, bandwidth: Int, codecs: String, urls: [URL], preferred: URL, referer: String) {
        self.kind = kind
        self.id = id
        self.bandwidth = bandwidth
        self.codecs = codecs
        self.urls = urls
        self.preferred = preferred
        self.referer = referer
    }

    /// Audio ids are 302xx (AAC) and 3025x (Dolby, FLAC); video qn values stay below 200.
    public static func kind(forID id: Int) -> Kind {
        id >= 30000 ? .audio : .video
    }
}

/// Maps the tokens in proxy URLs to representations.
final class Registry {
    private var reps: [String: MediaRep] = [:]
    private var order: [String] = []
    private let limit = 64

    func add(_ rep: MediaRep) -> String {
        // A playlist reload for the same file reuses its token.
        if let existing = order.first(where: { reps[$0]?.preferred == rep.preferred }) {
            reps[existing] = rep
            return existing
        }
        let token = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).lowercased()
        reps[token] = rep
        order.append(token)
        while order.count > limit {
            reps[order.removeFirst()] = nil
        }
        return token
    }

    func rep(for token: String) -> MediaRep? {
        reps[token]
    }

    var all: [MediaRep] {
        order.compactMap { reps[$0] }
    }
}
