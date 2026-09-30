@testable import BiliAccelerator
import XCTest

final class RoutingSessionTests: XCTestCase {
    private let cosovHost = "upos-sz-mirrorcosov.bilivideo.com"
    private let akamHost = "upos-hz-mirrorakam.akamaized.net"
    private let aliHost = "upos-sz-mirrorali.bilivideo.com"
    private let hwHost = "upos-sz-mirrorhw.bilivideo.com"

    private lazy var rep: MediaRep = {
        let path = "/upgcxcode/99/18/42301918299/42301918299-1-100026.m4s?e=abc&os=cosovbv"
        let cosov = URL(string: "https://\(cosovHost)\(path)")!
        let akam = URL(string: "https://\(akamHost)\(path)&hdnts=x")!
        return MediaRep(kind: .video, id: 116, bandwidth: 2_000_000, codecs: "hvc1", urls: [cosov, akam],
                        preferred: cosov, referer: "r")
    }()

    private func session() -> RoutingSession {
        let session = RoutingSession(key: "42301918299")
        session.random = { 0.99 }
        return session
    }

    func testTheOtherIssuedHostIsTriedFirstUntilMeasured() {
        let session = session()
        XCTAssertEqual(session.pickChallengers(for: rep, current: cosovHost, excluding: [cosovHost]).first, akamHost)
        session.noteCompleted(host: akamHost, rep: rep, seconds: 1, bytes: 200_000)
        XCTAssertNotEqual(session.pickChallengers(for: rep, current: cosovHost, excluding: [cosovHost]).first, akamHost)
    }

    func testUnmeasuredTiesGoToMainlandMirrors() {
        let session = session()
        session.noteCompleted(host: akamHost, rep: rep, seconds: 1, bytes: 200_000)
        let picks = session.pickChallengers(for: rep, current: cosovHost, excluding: [cosovHost, akamHost])
        XCTAssertEqual(picks.count, 2)
        XCTAssertFalse(picks.contains { Candidates.isOverseas($0) })
    }

    func testMeasuredFastHostsComeFirst() {
        let session = session()
        session.noteCompleted(host: akamHost, rep: rep, seconds: 1, bytes: 200_000)
        session.noteCompleted(host: hwHost, rep: rep, seconds: 0.1, bytes: 2_000_000)
        let picks = session.pickChallengers(for: rep, current: cosovHost, excluding: [cosovHost])
        XCTAssertEqual(picks.first, hwHost)
    }

    func testFailedAndLosingHostsAreLeftOut() {
        let session = session()
        session.noteFailure(aliHost)
        session.noteFailure(aliHost)
        session.conclude(trigger: "t", rep: rep, from: cosovHost, stuckRateBps: 0, priorFailures: 0, raceBytes: 768 * 1024,
                         contenders: [.init(host: hwHost, bytes: 10, seconds: nil, ok: false),
                                      .init(host: akamHost, bytes: 768 * 1024, seconds: 0.2, ok: true)],
                         winner: akamHost)
        let picks = session.pickChallengers(for: rep, current: akamHost, excluding: [akamHost])
        XCTAssertFalse(picks.contains(aliHost))
        XCTAssertFalse(picks.contains(hwHost))
    }

    func testTheVideoMovesOnlyForAClearlyFasterWinner() {
        let session = session()
        // 768 KB in 1 s from the winner is 6.3 Mbps.
        let winner = [RoutingSession.Contender(host: aliHost, bytes: 768 * 1024, seconds: 1, ok: true)]
        session.noteCompleted(host: cosovHost, rep: rep, seconds: 1, bytes: 1_000_000) // 8 Mbps
        XCTAssertFalse(session.conclude(trigger: "stuck", rep: rep, from: cosovHost, stuckRateBps: 1_000_000,
                                        priorFailures: 0, raceBytes: 768 * 1024, contenders: winner, winner: aliHost))
        XCTAssertNil(session.activeHost)
        // A host that already failed in the window gets no credit for its 8 Mbps.
        XCTAssertTrue(session.conclude(trigger: "stuck", rep: rep, from: cosovHost, stuckRateBps: 1_000_000,
                                       priorFailures: 1, raceBytes: 768 * 1024, contenders: winner, winner: aliHost))
        XCTAssertEqual(session.activeHost, aliHost)
        XCTAssertEqual(session.switches.last?.from, cosovHost)
    }

    func testAtMostFourSwitchesAndCooldownsAfterRaces() {
        let session = session()
        let hosts = [aliHost, hwHost, "upos-tf-all-hw.bilivideo.com", "upos-tf-all-tx.bilivideo.com", "upos-sz-mirrorcos.bilivideo.com"]
        var from = cosovHost
        var moves = 0
        for host in hosts {
            let moved = session.conclude(trigger: "stuck", rep: rep, from: from, stuckRateBps: 0, priorFailures: 1,
                                         raceBytes: 768 * 1024, contenders: [.init(host: host, bytes: 1, seconds: 0.1, ok: true)],
                                         winner: host)
            if moved {
                moves += 1
                from = host
            }
        }
        XCTAssertEqual(moves, Routing.maxSwitches)
        XCTAssertFalse(session.mayRace())
    }

    func testShortfallNeedsEvidenceALowBufferAndAShortHost() {
        let session = session()
        XCTAssertFalse(session.shortfall(rep: rep, requiredBps: 2_000_000, bufferAhead: 5))
        for _ in 0..<5 {
            session.noteCompleted(host: cosovHost, rep: rep, seconds: 2, bytes: 500_000) // 2 Mbps
        }
        XCTAssertTrue(session.shortfall(rep: rep, requiredBps: 2_000_000, bufferAhead: 5))
        XCTAssertFalse(session.shortfall(rep: rep, requiredBps: 2_000_000, bufferAhead: 40))
        XCTAssertFalse(session.shortfall(rep: rep, requiredBps: 1_000_000, bufferAhead: 5))
    }

    func testATestRacesTheNextFragmentAndKeepsItsOutcome() {
        let session = session()
        session.requestTest()
        XCTAssertTrue(session.raceNext)
        XCTAssertTrue(session.testPending)
        XCTAssertEqual(session.takeRaceNext(), "manual")
        XCTAssertFalse(session.raceNext)

        // 20 Mbps on the current host: 768 KB takes it 0.31 s, so a winner must do it in 0.21 s.
        session.noteCompleted(host: cosovHost, rep: rep, seconds: 1, bytes: 2_500_000)
        session.conclude(trigger: "manual", rep: rep, from: cosovHost, stuckRateBps: 20_000_000, priorFailures: 0,
                         raceBytes: 768 * 1024, contenders: [.init(host: aliHost, bytes: 768 * 1024, seconds: 0.3, ok: true)],
                         winner: aliHost)
        XCTAssertFalse(session.testPending)
        XCTAssertEqual(session.lastTest, .stayed)
        XCTAssertNil(session.activeHost)

        session.requestTest()
        XCTAssertEqual(session.takeRaceNext(), "manual")
        session.conclude(trigger: "manual", rep: rep, from: cosovHost, stuckRateBps: 20_000_000, priorFailures: 0,
                         raceBytes: 768 * 1024, contenders: [.init(host: hwHost, bytes: 768 * 1024, seconds: 0.1, ok: true)],
                         winner: hwHost)
        XCTAssertEqual(session.lastTest, .moved(to: hwHost))
        XCTAssertEqual(session.activeHost, hwHost)
    }

    func testAShortfallRaceIsNotATest() {
        let session = session()
        session.raceNext = true
        XCTAssertEqual(session.takeRaceNext(), "shortfall")
        session.conclude(trigger: "shortfall", rep: rep, from: cosovHost, stuckRateBps: 0, priorFailures: 0,
                         raceBytes: 768 * 1024, contenders: [.init(host: hwHost, bytes: 768 * 1024, seconds: 0.1, ok: true)],
                         winner: hwHost)
        XCTAssertEqual(session.lastTest, .none)
    }

    func testRateHistoryKeepsTheLastThirtySamples() {
        let session = session()
        for mbps in 1...40 {
            session.noteRateSample(Double(mbps))
        }
        XCTAssertEqual(session.recentMbps.count, 30)
        XCTAssertEqual(session.recentMbps.first, 11)
        XCTAssertEqual(session.recentMbps.last, 40)
    }

    func testCurrentSpeedIsTheLatestMegabyteOfVideo() {
        let audio = MediaRep(kind: .audio, id: 30280, bandwidth: 128_000, codecs: "mp4a", urls: rep.urls,
                             preferred: rep.preferred, referer: "r")
        var records: [RequestRecord] = []
        func fetch(_ rep: MediaRep, bytes: Int64, from start: TimeInterval, to end: TimeInterval?) -> RequestRecord {
            let record = RequestRecord(id: records.count, clientID: records.count, attempt: 0, host: cosovHost, rep: rep,
                                       range: ByteRange(start: 1000, end: nil), startedAt: start)
            record.firstByteAt = start
            record.bytes = bytes
            record.endedAt = end
            records.append(record)
            return record
        }
        func mbps(at now: TimeInterval) -> Double {
            Recorder.currentVideoMbps(in: records, now: now) ?? 0
        }
        XCTAssertNil(Recorder.currentVideoMbps(in: records, now: 1))

        // A big fetch is measured alone: 2.5 MB in a second.
        _ = fetch(rep, bytes: 2_500_000, from: 10, to: 11)
        XCTAssertEqual(mbps(at: 20), 20, accuracy: 0.001)

        // Small ones are added up until they reach a megabyte: 3 x 400 KB in 3 x 0.1 s.
        for index in 0..<3 {
            _ = fetch(rep, bytes: 400_000, from: 12 + Double(index), to: 12.1 + Double(index))
        }
        XCTAssertEqual(mbps(at: 20), 32, accuracy: 0.001)

        // Audio, lost races and a fetch still waiting for most of its bytes don't count.
        _ = fetch(audio, bytes: 500_000, from: 16, to: 16.01)
        let lost = fetch(rep, bytes: 900_000, from: 16, to: nil)
        lost.lostRace = true
        _ = fetch(rep, bytes: 10000, from: 19.9, to: nil)
        XCTAssertEqual(mbps(at: 20), 32, accuracy: 0.001)

        // One running with enough bytes counts up to now: 5 MB in its first second.
        _ = fetch(rep, bytes: 5_000_000, from: 30, to: nil)
        XCTAssertEqual(mbps(at: 31), 40, accuracy: 0.001)
    }

    func testEstimatorFallsFastAndIgnoresTinySamples() {
        var estimator = Estimator()
        XCTAssertFalse(estimator.sample(duration: 0.1, bytes: 1000))
        estimator.sample(duration: 1, bytes: 1_000_000)
        XCTAssertEqual(estimator.bps ?? 0, 8_000_000, accuracy: 1)
        estimator.sample(duration: 4, bytes: 500_000)
        XCTAssertLessThan(estimator.bps ?? .infinity, 3_000_000)
    }
}
