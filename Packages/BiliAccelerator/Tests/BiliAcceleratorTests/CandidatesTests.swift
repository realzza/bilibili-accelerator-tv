@testable import BiliAccelerator
import XCTest

final class CandidatesTests: XCTestCase {
    private let cosov = URL(string: "https://upos-sz-mirrorcosov.bilivideo.com/upgcxcode/99/18/42301918299/42301918299-1-100026.m4s?e=abc&os=cosovbv&deadline=1")!
    private let akam = URL(string: "https://upos-hz-mirrorakam.akamaized.net/upgcxcode/99/18/42301918299/42301918299-1-100026.m4s?e=abc&os=akam&hdnts=x")!

    private func rep(_ urls: [URL]) -> MediaRep {
        MediaRep(kind: .video, id: 116, bandwidth: 2_530_000, codecs: "hvc1", urls: urls, preferred: urls[0], referer: "r")
    }

    func testIssuedHostsUseTheirOwnURL() {
        let rep = rep([akam, cosov])
        XCTAssertEqual(Candidates.url(for: rep, host: "upos-hz-mirrorakam.akamaized.net"), akam)
        XCTAssertEqual(Candidates.url(for: rep, host: "upos-sz-mirrorcosov.bilivideo.com"), cosov)
    }

    func testMirrorsGetAHostSwapOfTheUposURL() throws {
        let swapped = try XCTUnwrap(Candidates.url(for: rep([akam, cosov]), host: "upos-sz-mirrorali.bilivideo.com"))
        XCTAssertEqual(swapped.host, "upos-sz-mirrorali.bilivideo.com")
        XCTAssertEqual(swapped.path, cosov.path)
        XCTAssertEqual(swapped.query, cosov.query)
    }

    func testAkamaiIsReachableOnlyThroughItsIssuedURL() {
        XCTAssertNil(Candidates.url(for: rep([cosov]), host: "upos-hz-mirrorakam.akamaized.net"))
        XCTAssertNil(Candidates.url(for: rep([akam]), host: "upos-sz-mirrorali.bilivideo.com"))
    }

    func testFailoverOrderTriesIssuedThenMainlandThenOverseas() {
        let order = Candidates.failoverOrder(for: rep([akam, cosov]), excluding: "upos-hz-mirrorakam.akamaized.net")
        XCTAssertEqual(order.first, "upos-sz-mirrorcosov.bilivideo.com")
        XCTAssertFalse(order.contains("upos-hz-mirrorakam.akamaized.net"))
        let mainland = order.firstIndex(of: "upos-sz-mirrorali.bilivideo.com")!
        let overseas = order.firstIndex(of: "upos-sz-mirroraliov.bilivideo.com")!
        XCTAssertLessThan(mainland, overseas)
        XCTAssertEqual(Set(order).count, order.count)
    }

    func testOverseasHosts() {
        XCTAssertTrue(Candidates.isOverseas("upos-sz-mirrorcosov.bilivideo.com"))
        XCTAssertTrue(Candidates.isOverseas("upos-sz-mirrorhwov.bilivideo.com"))
        XCTAssertTrue(Candidates.isOverseas("upos-hz-mirrorakam.akamaized.net"))
        XCTAssertFalse(Candidates.isOverseas("upos-sz-mirrorcos.bilivideo.com"))
        XCTAssertFalse(Candidates.isOverseas("upos-tf-all-tx.bilivideo.com"))
    }

    func testSessionKeyIsTheCid() {
        XCTAssertEqual(Candidates.sessionKey(for: cosov), "42301918299")
        XCTAssertEqual(Candidates.sessionKey(for: URL(string: "https://x/y/file.m4s")!), "default")
    }

    func testContentRangeStart() {
        XCTAssertEqual(MediaProxy.contentRangeStart("bytes 4005279-4342297/12345678"), 4_005_279)
        XCTAssertNil(MediaProxy.contentRangeStart("bytes */1234"))
    }
}
