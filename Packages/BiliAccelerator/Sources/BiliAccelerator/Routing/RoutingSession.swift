import Foundation

/// Routing state for one video. Every request starts on the active host, which is the host the
/// app chose until a failover moves it.
final class RoutingSession {
    /// Two failures on one host within this window move the whole video, as in the userscript.
    static let errorWindow: TimeInterval = 30
    static let errorLimit = 2
    /// A host that failed is tried again only after this long.
    static let failureRest: TimeInterval = 60

    struct Switch {
        let at: TimeInterval
        let from: String
        let to: String
        let reason: String
    }

    let key: String
    let startedAt = Recorder.now()
    private(set) var activeHost: String?
    private(set) var failures: [String: [TimeInterval]] = [:]
    private(set) var switches: [Switch] = []
    private(set) var rescues = 0

    init(key: String) {
        self.key = key
    }

    /// Where a new request for `rep` goes.
    func url(for rep: MediaRep) -> URL {
        if let activeHost, let url = Candidates.url(for: rep, host: activeHost) {
            return url
        }
        return rep.preferred
    }

    /// Records a failure on `host` and picks where the rest of the bytes come from. Moves the
    /// video to the new host once `host` has failed twice within the window.
    func failover(rep: MediaRep, from host: String, reason: String, tried: [String]) -> (host: String, url: URL)? {
        let now = Recorder.now()
        var times = failures[host, default: []].filter { now - $0 < RoutingSession.failureRest }
        times.append(now)
        failures[host] = times

        let resting = Set(failures.filter { $0.value.contains { now - $0 < RoutingSession.failureRest } }.keys)
        let order = Candidates.failoverOrder(for: rep, excluding: host).filter { !tried.contains($0) }
        guard let next = order.first(where: { !resting.contains($0) }) ?? order.first,
              let url = Candidates.url(for: rep, host: next)
        else { return nil }

        rescues += 1
        let recent = times.filter { now - $0 < RoutingSession.errorWindow }.count
        let current = activeHost ?? Candidates.key(rep.preferred)
        if host == current, recent >= RoutingSession.errorLimit {
            activeHost = next
            switches.append(Switch(at: now, from: host, to: next, reason: reason))
            // A local copy: the project's SwiftFormat pass strips `self.` inside the log
            // interpolation, which Swift 5 rejects in an escaping autoclosure.
            let video = key
            Log.proxy.info("session \(video, privacy: .public) moved \(host, privacy: .public) -> \(next, privacy: .public) (\(reason, privacy: .public))")
        }
        return (next, url)
    }
}
