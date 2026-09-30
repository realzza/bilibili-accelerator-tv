import Foundation

struct ProxyTuning {
    /// No first byte for this long is a hang whatever the buffer holds. Unlike the web player,
    /// AVPlayer can't fail over by itself here: every URL it has points at the proxy.
    var hardNoFirstByte: TimeInterval = 4
    /// A host that stops sending mid-body for this long is treated as failed.
    var stallTimeout: TimeInterval = 3
    var raceBytes: Int64 = Routing.raceBytes
    var raceTimeout: TimeInterval = Routing.raceTimeout
    /// Hosts one player request may go through before the proxy gives up and lets AVPlayer retry.
    var maxAttempts = 5
    var tickInterval: TimeInterval = 0.25
}

/// Serves `/m/<token>.m4s`: fetches the requested byte range from a CDN host and streams it back.
/// A request that fails or gets stuck is finished by the winner of a race between two other
/// hosts, in the same response, so AVPlayer never sees the failure.
final class MediaProxy {
    let queue: DispatchQueue
    let upstream: Upstream
    let registry: Registry
    let recorder: Recorder
    var tuning = ProxyTuning()
    /// Seconds buffered ahead of the playhead in the player being watched, updated about once a
    /// second. Nil when no player reports it, as for feed previews.
    var bufferAhead: Double?
    /// False while the app is in the background. tvOS defuncts a suspended app's sockets, so
    /// requests fail then for reasons that say nothing about the CDN.
    var appActive = true
    var resumedAt: TimeInterval = 0
    private(set) var sessions: [String: RoutingSession] = [:]
    /// The video the player asked for last, which is the one playing.
    private var current: (session: RoutingSession, rep: MediaRep)?
    private var transfers: [ObjectIdentifier: ProxyTransfer] = [:]
    private var ticker: DispatchSourceTimer?

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
        let session = session(for: rep)
        if rep.kind == .video {
            current = (session, rep)
        }
        let transfer = ProxyTransfer(proxy: self, rep: rep, session: session, range: request.range,
                                     response: response, clientID: recorder.nextClientID())
        let key = ObjectIdentifier(transfer)
        transfers[key] = transfer
        transfer.onDone = { [weak self] in
            self?.transfers[key] = nil
        }
        // A shortfall flagged on the last fragment, or a test: this one is served by a race.
        let raced = session.raceNext && rep.kind == .video && (request.range?.start ?? 0) > 0
        transfer.start(raceTrigger: raced ? session.takeRaceNext() : nil)
        startTicker()
    }

    /// Races the next fragment of the video playing now.
    func requestTest() {
        current?.session.requestTest()
    }

    func status(player: PlayerProbe.Snapshot?) -> RouteStatus? {
        guard let (session, rep) = current else { return nil }
        let host = session.currentHost(for: rep)
        let required = recorder.requiredBps
        return RouteStatus(host: host,
                           isIssuedHost: host == Candidates.key(rep.preferred),
                           switches: session.switches.count,
                           mbps: session.estimate(host).map { $0 / 1_000_000 },
                           recentMbps: session.recentMbps,
                           bufferSeconds: bufferAhead,
                           requiredMbps: required > 0 ? Double(required) / 1_000_000 : nil,
                           isStalled: player?.timeControl == "waiting",
                           test: session.testPending ? .pending : session.lastTest)
    }

    /// Routing state is per video, so a quality switch keeps the host a race moved to and a new
    /// video starts on the host the app chose.
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

    private func startTicker() {
        guard ticker == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + tuning.tickInterval, repeating: tuning.tickInterval)
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        ticker = timer
    }

    /// Whether a failure now can be held against a host: not in the background, and not in the
    /// first two seconds after coming back, when suspended requests are still failing.
    func judging(now: TimeInterval = Recorder.now()) -> Bool {
        appActive && now - resumedAt > 2
    }

    private func tick() {
        let now = Recorder.now()
        guard judging(now: now) else { return }
        for transfer in Array(transfers.values) {
            transfer.tick(now: now, bufferAhead: bufferAhead, requiredBps: recorder.requiredBps)
        }
        if transfers.isEmpty {
            ticker?.cancel()
            ticker = nil
        }
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

/// One player request, served by one host, or by the winner of a race when that host fails.
final class ProxyTransfer {
    /// One upstream fetch of the remaining range.
    private final class Contender {
        let host: String
        let url: URL
        let request = UpstreamRequest()
        let record: RequestRecord
        let startedAt = Recorder.now()
        var http: HTTPURLResponse?
        /// Bytes held back while a race is undecided.
        var buffer = Data()
        var completed = false

        init(url: URL, record: RequestRecord) {
            host = Candidates.key(url)
            self.url = url
            self.record = record
        }
    }

    private unowned let proxy: MediaProxy
    private let rep: MediaRep
    private let session: RoutingSession
    private let requested: ByteRange?
    private weak var response: HTTPResponse?
    private let clientID: Int

    /// Body bytes already sent to the player.
    private var delivered: Int64 = 0
    /// Body length promised to the player.
    private var expected: Int64?
    private var tried: [String] = []
    /// The contender whose bytes go to the player; nil while a race is undecided.
    private var active: Contender?
    private var racers: [Contender] = []
    private var race: (trigger: String, from: String, stuckRate: Double, priorFailures: Int, target: Int64, startedAt: TimeInterval)?
    private var raceTimer: DispatchWorkItem?
    private var racedForStuck = false
    private var pausedForClient = false
    private var lastDataAt = Recorder.now()
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

    private var isHeader: Bool {
        (requested?.start ?? 0) == 0
    }

    /// Starts on the video's host, or with a race between two others when `raceTrigger` is set
    /// and there are others to race.
    func start(raceTrigger: String?) {
        response?.onClientGone = { [weak self] in
            self?.clientGone()
        }
        let current = session.currentHost(for: rep)
        var raceTrigger = raceTrigger
        if let trigger = raceTrigger, session.pickChallengers(for: rep, current: current, excluding: []).isEmpty {
            session.noteRaceSkipped(trigger: trigger)
            raceTrigger = nil
        }
        if let raceTrigger {
            startRace(trigger: raceTrigger, from: current, stuckRate: session.estimate(current) ?? 0, priorFailures: 0)
        } else {
            let contender = makeContender(url: session.url(for: rep))
            active = contender
            proxy.upstream.start(url: contender.url, range: remainingRange(), referer: rep.referer, request: contender.request)
        }
    }

    // MARK: - Contenders

    private func makeContender(url: URL) -> Contender {
        let host = Candidates.key(url)
        tried.append(host)
        let record = proxy.recorder.begin(rep: rep, host: host, range: remainingRange(), clientID: clientID, attempt: tried.count - 1)
        let contender = Contender(url: url, record: record)
        contender.request.onResponse = { [weak self, weak contender] http in
            guard let self, let contender else { return }
            self.didRespond(contender, http)
        }
        contender.request.onData = { [weak self, weak contender] data in
            guard let self, let contender else { return }
            self.didReceive(contender, data)
        }
        let recorder = proxy.recorder
        contender.request.onComplete = { [weak self] error in
            guard let self, !self.done, let current = self.contender(for: record) else {
                // Abandoned for another host or lost a race: its record is final already.
                recorder.finished(record, error: error)
                return
            }
            self.didComplete(current, error)
        }
        return contender
    }

    private func contender(for record: RequestRecord) -> Contender? {
        if active?.record === record {
            return active
        }
        return racers.first { $0.record === record }
    }

    private func isLive(_ contender: Contender) -> Bool {
        !done && (contender === active || racers.contains { $0 === contender })
    }

    private func remainingRange() -> ByteRange? {
        if let requested {
            return ByteRange(start: requested.start + delivered, end: requested.end)
        }
        return delivered > 0 ? ByteRange(start: delivered, end: nil) : nil
    }

    private var remainingLength: Int64? {
        (expected ?? requested?.length).map { $0 - delivered }
    }

    // MARK: - Upstream events

    private func didRespond(_ contender: Contender, _ http: HTTPURLResponse?) {
        guard isLive(contender) else { return }
        proxy.recorder.responded(contender.record, status: http?.statusCode)
        guard let http else {
            contenderFailed(contender, reason: "no response")
            return
        }
        let status = http.statusCode
        guard status == 200 || status == 206 else {
            // 403 from a mirror that refuses the signature, 404, 5xx: another host.
            contenderFailed(contender, reason: "status \(status)")
            return
        }
        if let response, response.headSent {
            // A continuation has to start exactly where the previous host stopped.
            let start = (requested?.start ?? 0) + delivered
            guard status == 206, let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
                  MediaProxy.contentRangeStart(contentRange) == start
            else {
                contenderFailed(contender, reason: "misaligned continuation")
                return
            }
        } else if requested != nil, status == 200 {
            contenderFailed(contender, reason: "range ignored")
            return
        }
        contender.http = http
        if contender === active {
            sendHeadIfNeeded(from: http)
        }
    }

    private func didReceive(_ contender: Contender, _ data: Data) {
        guard isLive(contender) else { return }
        proxy.recorder.received(contender.record, bytes: data.count)
        if contender === active {
            forward(data)
            return
        }
        contender.buffer.append(data)
        if let race, Int64(contender.buffer.count) >= race.target {
            win(contender)
        }
    }

    private func didComplete(_ contender: Contender, _ error: Error?) {
        if let error {
            proxy.recorder.finished(contender.record, error: error)
            contenderFailed(contender, reason: ProxyTransfer.describe(error))
            return
        }
        contender.completed = true
        if contender === active {
            completeActive(contender)
        } else {
            // A racer that fetched the whole remaining range before the race target.
            win(contender)
        }
    }

    private func completeActive(_ contender: Contender) {
        if let expected, delivered < expected {
            proxy.recorder.failed(contender.record, reason: "short body")
            rescue(contender, reason: "short body", countsAsFailure: true)
            return
        }
        proxy.recorder.finished(contender.record, error: nil)
        if !isHeader {
            session.noteCompleted(host: contender.host, rep: rep, seconds: Recorder.now() - contender.startedAt,
                                  bytes: contender.record.bytes)
            if rep.kind == .video,
               session.shortfall(rep: rep, requiredBps: proxy.recorder.requiredBps, bufferAhead: proxy.bufferAhead)
            {
                session.raceNext = true
            }
        }
        finishClient()
    }

    private func contenderFailed(_ contender: Contender, reason: String) {
        if contender === active {
            rescue(contender, reason: reason, countsAsFailure: true)
            return
        }
        guard let index = racers.firstIndex(where: { $0 === contender }) else { return }
        racers.remove(at: index)
        proxy.recorder.failed(contender.record, reason: reason)
        session.noteFailure(contender.host)
        contender.request.cancel()
        if racers.isEmpty, let race {
            raceTimer?.cancel()
            session.conclude(trigger: race.trigger, rep: rep, from: race.from, stuckRateBps: race.stuckRate,
                             priorFailures: race.priorFailures, raceBytes: race.target, contenders: [], winner: nil)
            self.race = nil
            startRace(trigger: race.trigger, from: race.from, stuckRate: race.stuckRate, priorFailures: race.priorFailures)
        }
    }

    // MARK: - Watching the active host

    /// Runs every quarter second. Ported from `stuckVerdict`: a fragment is stuck when it has had
    /// no first byte for a second with under 3 s buffered, or when at its present rate it will
    /// finish after the buffer runs out.
    func tick(now: TimeInterval, bufferAhead: Double?, requiredBps: Int) {
        guard !done, let contender = active, !contender.completed, !pausedForClient else { return }
        let waited = now - contender.startedAt
        guard let firstByte = contender.record.firstByteAt else {
            if waited >= proxy.tuning.hardNoFirstByte {
                rescue(contender, reason: "no first byte \(ProxyTransfer.seconds(waited))", countsAsFailure: true)
            } else if let bufferAhead, bufferAhead < Routing.stuckUrgentBuffer, waited >= Routing.stuckNoFirstByte,
                      !racedForStuck, onVideoHost(contender)
            {
                racedForStuck = true
                rescue(contender, reason: "no first byte", countsAsFailure: true)
            }
            return
        }
        if now - lastDataAt >= proxy.tuning.stallTimeout {
            rescue(contender, reason: "stalled \(ProxyTransfer.seconds(now - lastDataAt))", countsAsFailure: true)
            return
        }
        guard rep.kind == .video, !isHeader, !racedForStuck, requiredBps > 0, let bufferAhead,
              let total = expected, total >= Routing.stuckMinFragmentBytes, onVideoHost(contender)
        else { return }
        let transfer = now - firstByte
        let loaded = contender.record.bytes
        guard transfer >= Routing.stuckMinTransfer || loaded >= Routing.stuckMinFragmentBytes else { return }
        let rate = transfer > 0 ? Double(loaded) * 8 / transfer : 0
        let remaining = rate > 0 ? Double(total - delivered) * 8 / rate : .infinity
        if rate < Routing.stuckRateFactor * Double(requiredBps), remaining > Routing.stuckMinRemaining,
           remaining > bufferAhead - Routing.stuckMargin
        {
            racedForStuck = true
            rescue(contender, reason: "slow fragment", countsAsFailure: false)
        }
    }

    private func onVideoHost(_ contender: Contender) -> Bool {
        contender.host == session.currentHost(for: rep)
    }

    // MARK: - Races

    /// The active host failed or is too slow: its request ends and a race takes the rest.
    private func rescue(_ contender: Contender, reason: String, countsAsFailure: Bool) {
        let now = Recorder.now()
        guard proxy.judging(now: now) else {
            // A suspension, not the CDN: end the response and let AVPlayer ask again.
            proxy.recorder.failed(contender.record, reason: "\(reason) (app in background)")
            active = nil
            contender.request.cancel()
            giveUp()
            return
        }
        let priorFailures = session.recentFailures(contender.host, now: now)
        if countsAsFailure {
            session.noteFailure(contender.host, now: now)
        }
        let since = contender.record.firstByteAt ?? contender.startedAt
        let stuckRate = now > since ? Double(contender.record.bytes) * 8 / (now - since) : 0
        proxy.recorder.failed(contender.record, reason: reason)
        active = nil
        pausedForClient = false
        response?.onDrain = nil
        if !contender.completed {
            contender.request.cancel()
        }
        startRace(trigger: reason, from: contender.host, stuckRate: stuckRate, priorFailures: priorFailures)
    }

    private func startRace(trigger: String, from: String, stuckRate: Double, priorFailures: Int) {
        guard !done else { return }
        let challengers = session.pickChallengers(for: rep, current: from, excluding: Set(tried))
        guard tried.count < proxy.tuning.maxAttempts, !challengers.isEmpty else {
            giveUp()
            return
        }
        let target = min(proxy.tuning.raceBytes, max(1, remainingLength ?? proxy.tuning.raceBytes))
        race = (trigger, from, stuckRate, priorFailures, target, Recorder.now())
        let range = remainingRange()
        racers = challengers.compactMap { host in
            guard let url = Candidates.url(for: rep, host: host) else { return nil }
            return makeContender(url: url)
        }
        guard !racers.isEmpty else {
            race = nil
            giveUp()
            return
        }
        for racer in racers {
            proxy.upstream.start(url: racer.url, range: range, referer: rep.referer, request: racer.request)
        }
        let timer = DispatchWorkItem { [weak self] in
            self?.raceTimedOut()
        }
        raceTimer = timer
        proxy.queue.asyncAfter(deadline: .now() + proxy.tuning.raceTimeout, execute: timer)
    }

    /// No contender reached the target in time: the one with the most bytes wins, or, if none has
    /// any, the next pair gets a try.
    private func raceTimedOut() {
        guard !done, let race else { return }
        if let best = racers.max(by: { $0.buffer.count < $1.buffer.count }), !best.buffer.isEmpty {
            win(best)
            return
        }
        for racer in racers {
            proxy.recorder.failed(racer.record, reason: "no first byte in race")
            session.noteFailure(racer.host)
            racer.request.cancel()
        }
        racers = []
        session.conclude(trigger: race.trigger, rep: rep, from: race.from, stuckRateBps: race.stuckRate,
                         priorFailures: race.priorFailures, raceBytes: race.target, contenders: [], winner: nil)
        self.race = nil
        startRace(trigger: race.trigger, from: race.from, stuckRate: race.stuckRate, priorFailures: race.priorFailures)
    }

    private func win(_ winner: Contender) {
        guard !done, let race, racers.contains(where: { $0 === winner }) else { return }
        raceTimer?.cancel()
        raceTimer = nil
        let now = Recorder.now()
        var results: [RoutingSession.Contender] = []
        for racer in racers {
            if racer === winner {
                results.append(.init(host: racer.host, bytes: Int64(racer.buffer.count), seconds: now - race.startedAt, ok: true))
            } else {
                results.append(.init(host: racer.host, bytes: racer.record.bytes, seconds: nil, ok: false))
                proxy.recorder.lostRace(racer.record)
                racer.request.cancel()
            }
        }
        racers = []
        self.race = nil
        session.conclude(trigger: race.trigger, rep: rep, from: race.from, stuckRateBps: race.stuckRate,
                         priorFailures: race.priorFailures, raceBytes: race.target, contenders: results, winner: winner.host)

        active = winner
        lastDataAt = now
        if let http = winner.http {
            sendHeadIfNeeded(from: http)
        }
        let held = winner.buffer
        winner.buffer = Data()
        forward(held)
        if winner.completed {
            completeActive(winner)
        }
    }

    // MARK: - To the player

    private func sendHeadIfNeeded(from http: HTTPURLResponse) {
        guard let response, !response.headSent else { return }
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
        response.sendHead(status: http.statusCode, headers: headers)
        if response.isHead {
            active?.request.cancel()
            finishClient()
        }
    }

    private func forward(_ data: Data) {
        guard !data.isEmpty, let response else { return }
        lastDataAt = Recorder.now()
        delivered += Int64(data.count)
        response.sendBody(data)
        guard response.isBackedUp, let active else { return }
        // A player that reads slowly is not a slow host: pause the download and the clocks.
        active.request.suspend()
        pausedForClient = true
        response.onDrain = { [weak self, weak active] in
            guard let self, let active, active === self.active else { return }
            active.request.resume()
            self.pausedForClient = false
            self.lastDataAt = Recorder.now()
        }
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
        let abandoned = [active].compactMap { $0 } + racers
        active = nil
        racers = []
        finish()
        for contender in abandoned {
            contender.request.cancel()
        }
    }

    private func finish() {
        guard !done else { return }
        done = true
        raceTimer?.cancel()
        raceTimer = nil
        onDone?()
        onDone = nil
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain ? "error \(nsError.code)" : "\(nsError.domain) \(nsError.code)"
    }

    private static func seconds(_ value: TimeInterval) -> String {
        String(format: "%.1fs", value)
    }
}
