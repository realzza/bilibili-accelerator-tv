import Foundation

/// Numbers from the userscript's src/core/routing.js; docs/vod-routing.md there explains them.
enum Routing {
    /// How much of the remaining range a race fetches from each contender before it is decided.
    static let raceBytes: Int64 = 768 * 1024
    static let raceTimeout: TimeInterval = 4

    static let stuckMinFragmentBytes: Int64 = 128 * 1024
    static let stuckMinTransfer: TimeInterval = 0.5
    static let stuckNoFirstByte: TimeInterval = 1
    static let stuckUrgentBuffer: Double = 3
    static let stuckRateFactor = 1.3
    static let stuckMinRemaining: TimeInterval = 1
    static let stuckMargin: TimeInterval = 2

    static let shortfallRateFactor = 1.2
    static let shortfallMinBytes: Int64 = 4 * 1024 * 1024
    static let shortfallMinSeconds: Double = 8
    static let shortfallBuffer: Double = 30

    static let errorWindow: TimeInterval = 30
    static let errorLimit = 2
    static let switchGain = 1.5
    static let maxSwitches = 4
    static let switchBackoff: TimeInterval = 10
    static let noSwitchCooldown: TimeInterval = 15
    static let maxCooldown: TimeInterval = 120
    static let lostRaceRest: TimeInterval = 60
    static let exploreRate = 0.2
    static let unknownHostBps = 10_000_000.0
}

/// Routing state for one video: the host its requests go to, what each host has delivered, and
/// the races and switches so far. Every request starts on the active host, which is the host the
/// app chose until a race moves it.
final class RoutingSession {
    struct Switch {
        let at: TimeInterval
        let from: String
        let to: String
        let trigger: String
        let beforeMbps: Double?
    }

    struct Contender {
        let host: String
        let bytes: Int64
        let seconds: Double?
        let ok: Bool
    }

    struct Race {
        let at: TimeInterval
        let trigger: String
        let from: String
        let contenders: [Contender]
        let winner: String?
        let moved: Bool
    }

    let key: String
    let startedAt = Recorder.now()
    private(set) var activeHost: String?
    private var estimators: [String: Estimator] = [:]
    /// Video bytes each host delivered successfully in this session.
    private var carried: [String: Int64] = [:]
    /// What the active host has carried since it became active; a new host is judged on its
    /// sustained rate only after 4 MB or 8 s.
    private var activeCarriedBytes: Int64 = 0
    private var activeCarriedSeconds: Double = 0
    private(set) var failures: [String: [TimeInterval]] = [:]
    private var lostAt: [String: TimeInterval] = [:]
    private(set) var switches: [Switch] = []
    private(set) var races: [Race] = []
    private var nextRaceAt: TimeInterval = 0
    private var lastCooldown: TimeInterval = 0
    /// Set by a sustained shortfall or a test from the panel: the next video request is served by
    /// a race, which carries `raceNextTrigger`.
    var raceNext = false
    private(set) var raceNextTrigger = "shortfall"
    /// A test from the panel waits for the next video request.
    private(set) var testPending = false
    private(set) var lastTest: RouteStatus.Test = .none
    /// The download speed once a second while this video plays, in Mbps, oldest first.
    private(set) var recentMbps: [Double] = []
    var random: () -> Double = { Double.random(in: 0..<1) }

    init(key: String) {
        self.key = key
    }

    // MARK: - Where requests go

    func currentHost(for rep: MediaRep) -> String {
        if let activeHost, Candidates.url(for: rep, host: activeHost) != nil {
            return activeHost
        }
        return Candidates.key(rep.preferred)
    }

    func url(for rep: MediaRep) -> URL {
        if let activeHost, let url = Candidates.url(for: rep, host: activeHost) {
            return url
        }
        return rep.preferred
    }

    // MARK: - Measurements

    func estimate(_ host: String) -> Double? {
        estimators[host]?.bps
    }

    /// A video fragment that arrived whole.
    func noteCompleted(host: String, rep: MediaRep, seconds: Double, bytes: Int64) {
        guard rep.kind == .video else { return }
        estimators[host, default: Estimator()].sample(duration: seconds, bytes: bytes)
        carried[host, default: 0] += bytes
        if host == currentHost(for: rep) {
            activeCarriedBytes += bytes
            activeCarriedSeconds += seconds
        }
    }

    /// Failures on `host` within the error window.
    func recentFailures(_ host: String, now: TimeInterval = Recorder.now()) -> Int {
        (failures[host] ?? []).filter { now - $0 < Routing.errorWindow }.count
    }

    func noteFailure(_ host: String, now: TimeInterval = Recorder.now()) {
        failures[host, default: []].append(now)
    }

    func noteRateSample(_ mbps: Double) {
        recentMbps.append(mbps)
        if recentMbps.count > 30 {
            recentMbps.removeFirst(recentMbps.count - 30)
        }
    }

    // MARK: - Races

    /// A test asked for from the panel: the next video request is served by a race. The video
    /// moves only if a challenger is clearly faster, as after any race, and nothing is kept once
    /// the video ends.
    func requestTest() {
        testPending = true
        raceNext = true
        raceNextTrigger = "manual"
    }

    /// The trigger for a request served by a race because `raceNext` was set, which it clears.
    func takeRaceNext() -> String {
        let trigger = raceNextTrigger
        raceNext = false
        raceNextTrigger = "shortfall"
        return trigger
    }

    /// A race that could not run: no other host can serve the video.
    func noteRaceSkipped(trigger: String) {
        if trigger == "manual" {
            testPending = false
            lastTest = .stayed
        }
    }

    /// Whether the engine may start a race of its own (a shortfall race). Rescuing a request that
    /// failed or got stuck is always allowed.
    func mayRace(now: TimeInterval = Recorder.now()) -> Bool {
        now >= nextRaceAt && switches.count < Routing.maxSwitches
    }

    /// Two hosts to race for the rest of a request, ported from `pickChallengers`. The other
    /// issued host comes first until it has carried 128 KB, since it is the player's own
    /// alternative and sometimes the best. The rest go by what they delivered in this session,
    /// with unknown hosts scored as the lower median of the measured ones. Ties go to mainland
    /// mirrors: the overseas mirrors Bilibili did not issue are usually cold.
    func pickChallengers(for rep: MediaRep, current: String, excluding tried: Set<String>,
                         now: TimeInterval = Recorder.now()) -> [String]
    {
        let pool = Candidates.failoverOrder(for: rep, excluding: current).filter { host in
            !tried.contains(host)
                && (failures[host]?.count ?? 0) < Routing.errorLimit
                && !(lostAt[host].map { now - $0 < Routing.lostRaceRest } ?? false)
        }
        guard !pool.isEmpty else { return [] }

        let failedLately = { (host: String) -> Bool in
            (self.failures[host] ?? []).contains { now - $0 < Routing.lostRaceRest }
        }
        let known = pool.filter { !failedLately($0) }.compactMap { estimate($0) }.sorted()
        let typical = known.isEmpty ? Routing.unknownHostBps : known[(known.count - 1) / 2]
        let score = { (host: String) -> Double in self.estimate(host) ?? typical }
        let ordered = pool.enumerated().sorted { a, b in
            let failedA = failedLately(a.element), failedB = failedLately(b.element)
            if failedA != failedB { return !failedA }
            let scoreA = score(a.element), scoreB = score(b.element)
            if scoreA != scoreB { return scoreA > scoreB }
            let overseasA = Candidates.isOverseas(a.element), overseasB = Candidates.isOverseas(b.element)
            if overseasA != overseasB { return !overseasA }
            return a.offset < b.offset
        }.map(\.element)

        var picks: [String] = []
        for host in rep.urls.map(Candidates.key) where picks.isEmpty && pool.contains(host) {
            if (carried[host] ?? 0) < Estimator.minTotalBytes {
                picks.append(host)
            }
        }
        for host in ordered where picks.count < 2 && !picks.contains(host) {
            picks.append(host)
        }
        if picks.count == 2, random() < Routing.exploreRate {
            let rest = pool.filter { !picks.contains($0) }
            if !rest.isEmpty {
                picks[1] = rest[Int(random() * Double(rest.count)) % rest.count]
            }
        }
        return picks
    }

    /// Settles a race, ported from `stuckRaceVerdict`. The request always goes to the winner.
    /// The video moves to the winner only if it fetched the race bytes in two-thirds of the time
    /// the host it left needs for them. A host that failed within the error window gets no credit
    /// for its earlier rate: one hang on a host that keeps up is a bad connection, a second one
    /// is a bad host.
    /// - Parameters:
    ///   - from: the host the request was on.
    ///   - stuckRateBps: what the request was getting from `from` when the race started.
    ///   - priorFailures: failures on `from` in the window before this race.
    /// - Returns: whether the video moved to the winner.
    @discardableResult
    func conclude(trigger: String, rep: MediaRep, from: String, stuckRateBps: Double, priorFailures: Int,
                  raceBytes: Int64, contenders: [Contender], winner: String?, now: TimeInterval = Recorder.now()) -> Bool
    {
        for contender in contenders where contender.host != winner {
            lostAt[contender.host] = now
        }
        var moved = false
        if let winner, let seconds = contenders.first(where: { $0.host == winner })?.seconds, seconds > 0 {
            let sustained = estimate(from) ?? 0
            let hostRate = priorFailures > 0 ? stuckRateBps : max(stuckRateBps, sustained)
            let hostSeconds = hostRate > 0 ? Double(raceBytes) * 8 / hostRate : .infinity
            let better = seconds * Routing.switchGain <= hostSeconds
            if better, from == currentHost(for: rep), switches.count < Routing.maxSwitches {
                moved = true
                activeHost = winner
                activeCarriedBytes = 0
                activeCarriedSeconds = 0
                let before = sustained > 0 ? sustained / 1_000_000 : nil
                switches.append(Switch(at: now, from: from, to: winner, trigger: trigger, beforeMbps: before))
                let video = key
                Log.proxy.info("session \(video, privacy: .public) moved \(from, privacy: .public) -> \(winner, privacy: .public) (\(trigger, privacy: .public))")
            }
        }
        if moved {
            lastCooldown = 0
            nextRaceAt = now + Routing.switchBackoff * pow(2, Double(max(0, switches.count - 1)))
        } else {
            lastCooldown = min(Routing.maxCooldown, lastCooldown > 0 ? lastCooldown * 2 : Routing.noSwitchCooldown)
            nextRaceAt = now + lastCooldown
        }
        if trigger == "manual" {
            testPending = false
            lastTest = moved ? .moved(to: winner ?? from) : .stayed
        }
        races.append(Race(at: now, trigger: trigger, from: from, contenders: contenders, winner: winner, moved: moved))
        if races.count > 20 {
            races.removeFirst(races.count - 20)
        }
        return moved
    }

    /// Sustained shortfall, from `evaluate`: the active host's estimate is under 1.2 times the
    /// required rate after 4 MB or 8 s on it, and less than 30 s is buffered.
    func shortfall(rep: MediaRep, requiredBps: Int, bufferAhead: Double?, now: TimeInterval = Recorder.now()) -> Bool {
        guard requiredBps > 0, let bufferAhead, bufferAhead < Routing.shortfallBuffer, mayRace(now: now),
              activeCarriedBytes >= Routing.shortfallMinBytes || activeCarriedSeconds >= Routing.shortfallMinSeconds,
              let bps = estimate(currentHost(for: rep))
        else { return false }
        return bps < Routing.shortfallRateFactor * Double(requiredBps)
    }

    var measuredMbps: [String: Double] {
        estimators.compactMapValues { $0.bps.map { $0 / 1_000_000 } }
    }
}
