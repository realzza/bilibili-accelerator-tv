import Foundation

/// One fetch from one CDN host. A player request that fails over mid-segment has several,
/// sharing a `clientID`.
final class RequestRecord {
    let id: Int
    let clientID: Int
    /// 0 for the first host tried, 1 for the first failover, and so on.
    let attempt: Int
    let host: String
    let kind: MediaRep.Kind
    let repID: Int
    let bandwidth: Int
    let range: ByteRange?
    /// Init segments sit at the start of the file; they are a few KB and say nothing about speed.
    let isHeader: Bool
    let startedAt: TimeInterval
    var firstByteAt: TimeInterval?
    var endedAt: TimeInterval?
    var bytes: Int64 = 0
    var status: Int?
    var error: String?
    var cancelled = false
    /// Cancelled because another host won the race for these bytes.
    var lostRace = false

    init(id: Int, clientID: Int, attempt: Int, host: String, rep: MediaRep, range: ByteRange?, startedAt: TimeInterval) {
        self.id = id
        self.clientID = clientID
        self.attempt = attempt
        self.host = host
        kind = rep.kind
        repID = rep.id
        bandwidth = rep.bandwidth
        self.range = range
        isHeader = (range?.start ?? 0) == 0
        self.startedAt = startedAt
    }

    var firstByteMs: Double? {
        firstByteAt.map { ($0 - startedAt) * 1000 }
    }

    var durationMs: Double? {
        endedAt.map { ($0 - startedAt) * 1000 }
    }

    var failed: Bool {
        (error != nil && !cancelled) || (status ?? 200) >= 400
    }

    /// Timed from request to last byte, which is what the player pays. Small, failed or
    /// unfinished requests don't count.
    var goodputMbps: Double? {
        guard let endedAt, !failed, !cancelled, !isHeader, bytes >= Recorder.minGoodputBytes,
              endedAt > startedAt
        else { return nil }
        return Double(bytes) * 8 / (endedAt - startedAt) / 1_000_000
    }
}

/// Keeps the recent request history and running totals per host.
final class Recorder {
    static let minGoodputBytes: Int64 = 128 * 1024
    private static let keep = 400

    struct HostTotals {
        var requests = 0
        var bytes: Int64 = 0
        var errors = 0
        var cancelled = 0
    }

    private(set) var records: [RequestRecord] = []
    private(set) var totals: [String: HostTotals] = [:]
    /// Highest video bitrate the player has requested in this session, bits per second.
    private(set) var requiredBps = 0
    private(set) var sessionStartedAt = Recorder.now()
    private var nextID = 1

    static func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    /// A new video: totals and the required rate start over. Records are kept for the report.
    func beginSession() {
        totals.removeAll()
        requiredBps = 0
        sessionStartedAt = Recorder.now()
    }

    func nextClientID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    func begin(rep: MediaRep, host: String, range: ByteRange?, clientID: Int, attempt: Int) -> RequestRecord {
        let record = RequestRecord(id: nextID, clientID: clientID, attempt: attempt, host: host, rep: rep,
                                   range: range, startedAt: Recorder.now())
        nextID += 1
        records.append(record)
        if records.count > Recorder.keep {
            records.removeFirst(records.count - Recorder.keep)
        }
        totals[host, default: HostTotals()].requests += 1
        if rep.kind == .video, !record.isHeader, attempt == 0 {
            requiredBps = max(requiredBps, rep.bandwidth)
        }
        return record
    }

    func received(_ record: RequestRecord, bytes: Int) {
        if record.firstByteAt == nil {
            record.firstByteAt = Recorder.now()
        }
        record.bytes += Int64(bytes)
        totals[record.host, default: HostTotals()].bytes += Int64(bytes)
    }

    func responded(_ record: RequestRecord, status: Int?) {
        record.status = status
    }

    /// Another host won the race; not held against this one as a failure.
    func lostRace(_ record: RequestRecord) {
        guard record.endedAt == nil else { return }
        record.endedAt = Recorder.now()
        record.cancelled = true
        record.lostRace = true
        totals[record.host, default: HostTotals()].cancelled += 1
    }

    /// The proxy gave up on this host for this request (a status, a hang, a short body).
    func failed(_ record: RequestRecord, reason: String) {
        guard record.endedAt == nil else { return }
        record.endedAt = Recorder.now()
        record.error = reason
        totals[record.host, default: HostTotals()].errors += 1
    }

    func finished(_ record: RequestRecord, error: Error?) {
        guard record.endedAt == nil else { return }
        record.endedAt = Recorder.now()
        if let error {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                record.cancelled = true
                totals[record.host, default: HostTotals()].cancelled += 1
                return
            }
            record.error = "\(nsError.domain) \(nsError.code)"
        }
        if record.failed {
            totals[record.host, default: HostTotals()].errors += 1
        }
    }
}
