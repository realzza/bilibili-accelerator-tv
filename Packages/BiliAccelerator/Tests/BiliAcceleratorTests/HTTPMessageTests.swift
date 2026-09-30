@testable import BiliAccelerator
import XCTest

final class HTTPMessageTests: XCTestCase {
    func testByteRangeParsing() {
        XCTAssertEqual(ByteRange(header: "bytes=0-1023"), ByteRange(start: 0, end: 1023))
        XCTAssertEqual(ByteRange(header: "bytes=500-"), ByteRange(start: 500, end: nil))
        XCTAssertEqual(ByteRange(header: " Bytes=7-9 "), ByteRange(start: 7, end: 9))
        XCTAssertNil(ByteRange(header: "bytes=-500"))
        XCTAssertNil(ByteRange(header: "bytes=0-1,5-9"))
        XCTAssertNil(ByteRange(header: "bytes=9-3"))
        XCTAssertNil(ByteRange(header: "items=0-1"))
        XCTAssertNil(ByteRange(header: nil))
        XCTAssertEqual(ByteRange(start: 10, end: 19).length, 10)
        XCTAssertEqual(ByteRange(start: 10, end: nil).headerValue, "bytes=10-")
    }

    func testParsesRequestHead() throws {
        let text = "GET /m/abc123.m4s?x=1 HTTP/1.1\r\nHost: 127.0.0.1\r\nRange: bytes=100-199\r\nX-Playback-Session-Id: 1\r\n\r\nGET /next"
        guard case let .request(request, consumed) = HTTPParser.parse(Data(text.utf8)) else {
            return XCTFail("expected a request")
        }
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.path, "/m/abc123.m4s")
        XCTAssertEqual(request.query["x"], "1")
        XCTAssertEqual(request.headers["range"], "bytes=100-199")
        XCTAssertEqual(request.range, ByteRange(start: 100, end: 199))
        XCTAssertTrue(request.keepAlive)
        XCTAssertEqual(consumed, text.utf8.count - "GET /next".utf8.count)
    }

    func testIncompleteAndInvalidHeads() {
        guard case .incomplete = HTTPParser.parse(Data("GET / HTTP/1.1\r\nHost: x\r\n".utf8)) else {
            return XCTFail("expected incomplete")
        }
        guard case .invalid = HTTPParser.parse(Data("NONSENSE\r\n\r\n".utf8)) else {
            return XCTFail("expected invalid")
        }
        guard case .invalid = HTTPParser.parse(Data(repeating: 65, count: HTTPParser.maxHeaderBytes + 1)) else {
            return XCTFail("expected invalid for an oversized head")
        }
    }

    func testKeepAliveRules() throws {
        func request(_ text: String) -> HTTPRequest? {
            if case let .request(request, _) = HTTPParser.parse(Data(text.utf8)) {
                return request
            }
            return nil
        }
        XCTAssertFalse(try XCTUnwrap(request("GET / HTTP/1.1\r\nConnection: close\r\n\r\n")).keepAlive)
        XCTAssertFalse(try XCTUnwrap(request("GET / HTTP/1.0\r\n\r\n")).keepAlive)
        XCTAssertTrue(try XCTUnwrap(request("GET / HTTP/1.0\r\nConnection: keep-alive\r\n\r\n")).keepAlive)
    }

    func testTokenFromPath() {
        XCTAssertEqual(MediaProxy.token(from: "/m/abc123.m4s"), "abc123")
        XCTAssertEqual(MediaProxy.token(from: "/m/abc123"), "abc123")
        XCTAssertNil(MediaProxy.token(from: "/m/"))
        XCTAssertNil(MediaProxy.token(from: "/debug"))
    }

    func testMediaKindFromID() {
        XCTAssertEqual(MediaRep.kind(forID: 30280), .audio)
        XCTAssertEqual(MediaRep.kind(forID: 30251), .audio)
        XCTAssertEqual(MediaRep.kind(forID: 120), .video)
    }
}
