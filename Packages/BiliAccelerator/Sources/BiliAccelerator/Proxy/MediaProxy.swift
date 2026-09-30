import Foundation

struct ProxyTuning {
    /// No first byte from a host within this long: fetch the bytes elsewhere. The web player
    /// gives up after about 2 s; a cold overseas edge can take 1.4 to 11.5 s.
    var firstByteTimeout: TimeInterval = 2.5
    /// A host that stops sending mid-body for this long is treated as failed.
    var stallTimeout: TimeInterval = 3
    /// Hosts one player request may go through before the proxy gives up and lets AVPlayer retry.
    var maxAttempts = 4
}

/// Serves `/m/<token>.m4s`: fetches the requested byte range from a CDN host and streams it back.
/// When a host fails partway, the rest of the range comes from the next host in the same
/// response, so AVPlayer never sees the failure.
final class MediaProxy {
    let queue: DispatchQueue
    let upstream: Upstream
    let registry: Registry
    let recorder: Recorder
    var tuning = ProxyTuning()
    private(set) var sessions: [String: RoutingSession] = [:]
    private var transfers: [ObjectIdentifier: ProxyTransfer] = [:]

    init(queue: DispatchQueue, upstream: Upstream, registry: Registry, recorder: Recorder) {
        self.queue = queue
        self.upstream = upstream
        self.registry = registry
        self.recorder = recorder
    }

    func handle(_ request: HTTPRequest, _ response: HTTPResponse) {
        guard request.method == "GET" || request.method == "HEAD" else {
            response.respond(status: 405)
            return
        }
        guard let token = MediaProxy.token(from: request.path), let rep = registry.rep(for: token) else {
            response.respond(status: 404)
            return
        }
        let transfer = ProxyTransfer(proxy: self, rep: rep, session: session(for: rep), range: request.range,
                                     response: response, clientID: recorder.nextClientID())
        let key = ObjectIdentifier(transfer)
        transfers[key] = transfer
        transfer.onDone = { [weak self] in
            self?.transfers[key] = nil
        }
        transfer.start()
    }

    /// Routing state is per video, so a quality switch keeps the host a failover moved to and a
    /// new video starts on the host the app chose.
    func session(for rep: MediaRep) -> RoutingSession {
        let key = Candidates.sessionKey(for: rep.preferred)
        if let session = sessions[key] {
            return session
        }
        let session = RoutingSession(key: key)
        sessions[key] = session
        if sessions.count > 8, let oldest = sessions.values.min(by: { $0.startedAt < $1.startedAt }) {
            sessions[oldest.key] = nil
        }
        return session
    }

    static func token(from path: String) -> String? {
        guard path.hasPrefix("/m/") else { return nil }
        var name = Substring(path.dropFirst(3))
        if let dot = name.firstIndex(of: ".") {
            name = name[..<dot]
        }
        return name.isEmpty ? nil : String(name)
    }

    /// The first byte offset in `Content-Range: bytes a-b/total`.
    static func contentRangeStart(_ value: String) -> Int64? {
        let spec = value.lowercased().replacingOccurrences(of: "bytes", with: "").trimmingCharacters(in: .whitespaces)
        return spec.split(separator: "-").first.flatMap { Int64($0) }
    }
}

/// One player request, served from one or more hosts in turn.
final class ProxyTransfer {
    private unowned let proxy: MediaProxy
    private let rep: MediaRep
    private let session: RoutingSession
    private let requested: ByteRange?
    private weak var response: HTTPResponse?
    private let clientID: Int

    /// Body bytes already sent to the player.
    private var delivered: Int64 = 0
    /// Body length promised to the player by the first host's headers.
    private var expected: Int64?
    private var tried: [String] = []
    private var current: UpstreamRequest?
    private var record: RequestRecord?
    private var watchdog: DispatchWorkItem?
    private var done = false
    var onDone: (() -> Void)?

    init(proxy: MediaProxy, rep: MediaRep, session: RoutingSession, range: ByteRange?, response: HTTPResponse, clientID: Int) {
        self.proxy = proxy
        self.rep = rep
        self.session = session
        requested = range
        self.response = response
        self.clientID = clientID
    }

    func start() {
        response?.onClientGone = { [weak self] in
            self?.clientGone()
        }
        attempt(url: session.url(for: rep))
    }

    private func attempt(url: URL) {
        let host = Candidates.key(url)
        tried.append(host)
        let range = remainingRange()
        let recorder = proxy.recorder
        let record = recorder.begin(rep: rep, host: host, range: range, clientID: clientID, attempt: tried.count - 1)
        self.record = record
        let request = UpstreamRequest()
        current = request

        request.onResponse = { [weak self, weak request] http in
            guard let self, let request, request === self.current else { return }
            self.didReceive(http, record: record)
        }
        request.onData = { [weak self, weak request] data in
            guard let self, let request, request === self.current else { return }
            self.didReceive(data, record: record)
        }
        request.onComplete = { [weak self, weak request] error in
            guard let self, let request, request === self.current else {
                // A request abandoned for another host ends as cancelled; its record is final.
                recorder.finished(record, error: error)
                return
            }
            self.didComplete(error, record: record)
        }
        proxy.upstream.start(url: url, range: range, referer: rep.referer, request: request)
        armWatchdog(after: proxy.tuning.firstByteTimeout, reason: "no first byte")
    }

    private func remainingRange() -> ByteRange? {
        if let requested {
            return ByteRange(start: requested.start + delivered, end: requested.end)
        }
        return delivered > 0 ? ByteRange(start: delivered, end: nil) : nil
    }

    private func didReceive(_ http: HTTPURLResponse?, record: RequestRecord) {
        proxy.recorder.responded(record, status: http?.statusCode)
        guard let http else {
            failover(reason: "no response")
            return
        }
        let status = http.statusCode
        guard status == 200 || status == 206 else {
            // 403 from a mirror that refuses the signature, 404, 5xx: try the next host.
            failover(reason: "status \(status)")
            return
        }
        guard let response else { return }

        if !response.headSent {
            if requested != nil, status == 200 {
                failover(reason: "range ignored")
                return
            }
            var headers: [(String, String)] = [
                ("Content-Type", http.value(forHTTPHeaderField: "Content-Type") ?? "video/mp4"),
                ("Accept-Ranges", "bytes"),
            ]
            if let length = http.value(forHTTPHeaderField: "Content-Length") {
                headers.append(("Content-Length", length))
                expected = Int64(length)
            }
            if let contentRange = http.value(forHTTPHeaderField: "Content-Range") {
                headers.append(("Content-Range", contentRange))
            }
            response.sendHead(status: status, headers: headers)
            if response.isHead {
                current?.cancel()
                finishClient()
            }
            return
        }

        // A continuation has to start exactly where the previous host stopped.
        let start = (requested?.start ?? 0) + delivered
        guard status == 206,
              let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
              MediaProxy.contentRangeStart(contentRange) == start
        else {
            failover(reason: "misaligned continuation")
            return
        }
    }

    private func didReceive(_ data: Data, record: RequestRecord) {
        proxy.recorder.received(record, bytes: data.count)
        guard let response else { return }
        delivered += Int64(data.count)
        response.sendBody(data)
        if response.isBackedUp, let current {
            // A player that reads slowly is not a slow host: pause the download, and the clock.
            current.suspend()
            disarmWatchdog()
            response.onDrain = { [weak self, weak current] in
                guard let self, let current, current === self.current else { return }
                current.resume()
                self.armWatchdog(after: self.proxy.tuning.stallTimeout, reason: "stalled")
            }
        } else {
            armWatchdog(after: proxy.tuning.stallTimeout, reason: "stalled")
        }
    }

    private func didComplete(_ error: Error?, record: RequestRecord) {
        disarmWatchdog()
        if let error {
            proxy.recorder.finished(record, error: error)
            failover(reason: ProxyTransfer.describe(error))
            return
        }
        if let expected, delivered < expected {
            proxy.recorder.failed(record, reason: "short body")
            failover(reason: "short body")
            return
        }
        proxy.recorder.finished(record, error: nil)
        finishClient()
    }

    private func failover(reason: String) {
        disarmWatchdog()
        guard !done, let record else { return }
        proxy.recorder.failed(record, reason: reason)
        let abandoned = current
        current = nil
        abandoned?.cancel()
        response?.onDrain = nil

        guard response != nil, tried.count < proxy.tuning.maxAttempts,
              let next = session.failover(rep: rep, from: record.host, reason: reason, tried: tried)
        else {
            giveUp()
            return
        }
        attempt(url: next.url)
    }

    private func giveUp() {
        if let response {
            if response.headSent {
                response.abort()
            } else {
                response.respond(status: 502)
            }
        }
        finish()
    }

    private func finishClient() {
        response?.finish()
        finish()
    }

    private func clientGone() {
        let abandoned = current
        current = nil
        abandoned?.cancel()
        finish()
    }

    private func finish() {
        guard !done else { return }
        done = true
        disarmWatchdog()
        onDone?()
        onDone = nil
    }

    private func armWatchdog(after timeout: TimeInterval, reason: String) {
        watchdog?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.failover(reason: "\(reason) \(timeout)s")
        }
        watchdog = item
        proxy.queue.asyncAfter(deadline: .now() + timeout, execute: item)
    }

    private func disarmWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain ? "error \(nsError.code)" : "\(nsError.domain) \(nsError.code)"
    }
}
