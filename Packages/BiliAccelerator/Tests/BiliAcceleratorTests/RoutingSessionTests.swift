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

    func testEstimatorFallsFastAndIgnoresTinySamples() {
        var estimator = Estimator()
        XCTAssertFalse(estimator.sample(duration: 0.1, bytes: 1000))
        estimator.sample(duration: 1, bytes: 1_000_000)
        XCTAssertEqual(estimator.bps ?? 0, 8_000_000, accuracy: 1)
        estimator.sample(duration: 4, bytes: 500_000)
        XCTAssertLessThan(estimator.bps ?? .infinity, 3_000_000)
    }
}
