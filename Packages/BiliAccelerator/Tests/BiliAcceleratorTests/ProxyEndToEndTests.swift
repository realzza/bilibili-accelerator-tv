@testable import BiliAccelerator
import XCTest

/// Runs the proxy against fake CDN hosts built on the same HTTP server, all on loopback.
/// Query parameters on a host's URL pick its behavior:
/// `dropAfter=N` closes the connection after N body bytes, `hang` sends headers and no body,
/// `deny` answers 403, `nolength` streams without Content-Length, `slow` trickles.
final class ProxyEndToEndTests: XCTestCase {
    private static let referer = "https://www.bilibili.com/video/av1"
    private let blob = Data((0..<5_000_000).map { UInt8(truncatingIfNeeded: $0 % 251) })

    private var queue: DispatchQueue!
    private var registry: Registry!
    private var recorder: Recorder!
    private var proxy: MediaProxy!
    private var cdns: [HTTPServer] = []
    private var cdnPorts: [UInt16] = []
    private var proxyServer: HTTPServer!
    private var proxyPort: UInt16 = 0

    override func setUpWithError() throws {
        queue = DispatchQueue(label: "test.accelerator")
        registry = Registry()
        recorder = Recorder()
        for _ in 0..<3 {
            let cdn = HTTPServer(queue: queue, handler: fakeCDN(blob: blob, queue: queue))
            cdns.append(cdn)
            try cdnPorts.append(start(cdn))
        }
        proxy = MediaProxy(queue: queue, upstream: Upstream(queue: queue, userAgent: "test"), registry: registry, recorder: recorder)
        proxy.tuning.hardNoFirstByte = 0.3
        proxy.tuning.stallTimeout = 0.3
        proxy.tuning.raceTimeout = 5
        let proxy = proxy!
        proxyServer = HTTPServer(queue: queue) { request, response in
            proxy.handle(request, response)
        }
        proxyPort = try start(proxyServer)
    }

    override func tearDown() {
        queue.sync {
            cdns.forEach { $0.stop() }
            proxyServer.stop()
        }
    }

    func testStreamsARangeWithContentLength() throws {
        let (body, http) = try fetch([cdn(0, "a")], range: "bytes=1000-1999999")
        XCTAssertEqual(http.statusCode, 206)
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Range"), "bytes 1000-1999999/5000000")
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Length"), "1999000")
        XCTAssertEqual(body, blob.subdata(in: 1000..<2_000_000))

        let record = try XCTUnwrap(queue.sync { recorder.records.last })
        XCTAssertEqual(record.bytes, 1_999_000)
        XCTAssertEqual(record.status, 206)
        XCTAssertEqual(record.attempt, 0)
        XCTAssertNotNil(record.goodputMbps)
    }

    func testChunkedWhenTheCDNSendsNoLength() throws {
        let (body, http) = try fetch([cdn(0, "b", "nolength=1")], range: "bytes=0-300000")
        XCTAssertEqual(http.statusCode, 206)
        XCTAssertEqual(body, blob.subdata(in: 0..<300_001))
    }

    func testKeepsTheConnectionForTheNextRequest() throws {
        let first = try fetch([cdn(0, "c")], range: "bytes=0-99999").0
        let second = try fetch([cdn(0, "c")], range: "bytes=100000-199999").0
        XCTAssertEqual(first + second, blob.subdata(in: 0..<200_000))
    }

    func testUnknownTokenIs404() throws {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(proxyPort)/m/nope.m4s"))
        XCTAssertEqual(try get(URLRequest(url: url)).1.statusCode, 404)
    }

    func testContinuesOnTheNextHostWhenOneDropsMidBody() throws {
        let (body, http) = try fetch([cdn(0, "d", "dropAfter=700000"), cdn(1, "d")], range: "bytes=10-1999999")
        XCTAssertEqual(http.statusCode, 206)
        XCTAssertEqual(body, blob.subdata(in: 10..<2_000_000))

        let records = queue.sync { recorder.records }
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records[0].failed)
        XCTAssertEqual(records[1].attempt, 1)
        XCTAssertEqual(records[1].clientID, records[0].clientID)
        XCTAssertEqual(records[1].range?.start, 10 + records[0].bytes)
        XCTAssertEqual(records[1].host, "127.0.0.1:\(cdnPorts[1])")
    }

    func testFailsOverWhenAHostSendsHeadersAndNothingElse() throws {
        let (body, _) = try fetch([cdn(0, "e", "hang=1"), cdn(1, "e")], range: "bytes=0-499999")
        XCTAssertEqual(body, blob.subdata(in: 0..<500_000))
        let records = queue.sync { recorder.records }
        XCTAssertTrue(records.first?.error?.hasPrefix("no first byte") == true)
        XCTAssertEqual(records.last?.bytes, 500_000)
    }

    func testFailsOverWhenAHostRefuses() throws {
        let (body, http) = try fetch([cdn(0, "f", "deny=1"), cdn(1, "f")], range: "bytes=0-99")
        XCTAssertEqual(http.statusCode, 206)
        XCTAssertEqual(body, blob.subdata(in: 0..<100))
        XCTAssertEqual(queue.sync { recorder.records.first?.error }, "status 403")
    }

    func testGivesUpWhenEveryHostFails() throws {
        let (_, http) = try fetch([cdn(0, "g", "deny=1"), cdn(1, "g", "deny=1")], range: "bytes=0-99")
        XCTAssertEqual(http.statusCode, 502)
    }

    func testAHostThatDeliveredNothingLosesTheVideoAtOnce() throws {
        let urls = [cdn(0, "42301918299-1-100026.m4s", "dropAfter=0"), cdn(1, "42301918299-1-100026.m4s")]
        let (body, _) = try fetch(urls, range: "bytes=100-99999")
        XCTAssertEqual(body, blob.subdata(in: 100..<100_000))
        XCTAssertEqual(queue.sync { proxy.sessions["42301918299"]?.activeHost }, "127.0.0.1:\(cdnPorts[1])")

        let before = queue.sync { recorder.records.count }
        _ = try fetch(urls, range: "bytes=100000-199999")
        XCTAssertEqual(queue.sync { recorder.records[before...].map(\.host) }, ["127.0.0.1:\(cdnPorts[1])"])
    }

    func testOneHangOnAHostThatKeepsUpRescuesTheFragmentOnly() throws {
        let good = cdn(0, "40105674804-1-100026.m4s")
        let slow = cdn(1, "40105674804-1-100026.m4s", "slow=1")
        // A few fragments at loopback speed give the first host a record.
        for index in 0..<3 {
            let start = 100 + index * 300_000
            _ = try fetch([good, slow], range: "bytes=\(start)-\(start + 299_999)")
        }
        let hanging = cdn(0, "40105674804-1-100026.m4s", "hang=1")
        let (body, _) = try fetch([hanging, slow], range: "bytes=1000000-1099999")
        XCTAssertEqual(body, blob.subdata(in: 1_000_000..<1_100_000))

        let session = try XCTUnwrap(queue.sync { proxy.sessions["40105674804"] })
        XCTAssertNil(queue.sync { session.activeHost })
        let race = try XCTUnwrap(queue.sync { session.races.last })
        XCTAssertEqual(race.winner, "127.0.0.1:\(cdnPorts[1])")
        XCTAssertFalse(race.moved)
    }

    func testASecondFailureWithinTheWindowMovesTheVideo() throws {
        let good = cdn(0, "39161958084-1-100026.m4s")
        let slow = cdn(1, "39161958084-1-100026.m4s", "slow=1")
        for index in 0..<3 {
            let start = 100 + index * 300_000
            _ = try fetch([good, slow], range: "bytes=\(start)-\(start + 299_999)")
        }
        let hanging = cdn(0, "39161958084-1-100026.m4s", "hang=1")
        _ = try fetch([hanging, slow], range: "bytes=1000000-1049999")
        XCTAssertNil(queue.sync { proxy.sessions["39161958084"]?.activeHost })
        _ = try fetch([hanging, slow], range: "bytes=1050000-1099999")
        XCTAssertEqual(queue.sync { proxy.sessions["39161958084"]?.activeHost }, "127.0.0.1:\(cdnPorts[1])")
    }

    func testARaceGoesToTheFasterChallenger() throws {
        let urls = [cdn(0, "36277192945-1-100026.m4s", "dropAfter=0"),
                    cdn(1, "36277192945-1-100026.m4s", "slow=1"),
                    cdn(2, "36277192945-1-100026.m4s")]
        let (body, _) = try fetch(urls, range: "bytes=0-1999999")
        XCTAssertEqual(body, blob.subdata(in: 0..<2_000_000))
        let race = try XCTUnwrap(queue.sync { proxy.sessions["36277192945"]?.races.last })
        XCTAssertEqual(race.winner, "127.0.0.1:\(cdnPorts[2])")
        XCTAssertEqual(Set(race.contenders.map(\.host)), ["127.0.0.1:\(cdnPorts[1])", "127.0.0.1:\(cdnPorts[2])"])
        let loser = try XCTUnwrap(queue.sync { recorder.records.first { $0.host == "127.0.0.1:\(cdnPorts[1])" } })
        XCTAssertTrue(loser.lostRace)
        XCTAssertFalse(loser.failed)
    }

    func testATestFromThePanelRacesTheNextFragment() throws {
        let urls = (0..<3).map { cdn($0, "36277192946-1-100026.m4s") }
        _ = try fetch(urls, range: "bytes=1000-99999")
        var status = try XCTUnwrap(queue.sync { proxy.status(player: nil) })
        XCTAssertEqual(status.host, "127.0.0.1:\(cdnPorts[0])")
        XCTAssertTrue(status.isIssuedHost)
        XCTAssertEqual(status.requiredMbps, 5)
        XCTAssertEqual(status.test, .none)

        queue.sync { proxy.requestTest() }
        XCTAssertEqual(queue.sync { proxy.status(player: nil)?.test }, .pending)
        let (body, _) = try fetch(urls, range: "bytes=100000-1099999")
        XCTAssertEqual(body, blob.subdata(in: 100_000..<1_100_000))
        let race = try XCTUnwrap(queue.sync { proxy.sessions["36277192946"]?.races.last })
        XCTAssertEqual(race.trigger, "manual")
        XCTAssertFalse(race.contenders.contains { $0.host == "127.0.0.1:\(cdnPorts[0])" })
        status = try XCTUnwrap(queue.sync { proxy.status(player: nil) })
        XCTAssertNotEqual(status.test, .pending)
        XCTAssertEqual(status.switches, race.moved ? 1 : 0)
    }

    func testATestWithNoOtherHostServesTheFragmentNormally() throws {
        let urls = [cdn(0, "36277192947-1-100026.m4s")]
        _ = try fetch(urls, range: "bytes=1000-99999")
        queue.sync { proxy.requestTest() }
        let (body, _) = try fetch(urls, range: "bytes=100000-199999")
        XCTAssertEqual(body, blob.subdata(in: 100_000..<200_000))
        XCTAssertEqual(queue.sync { proxy.status(player: nil)?.test }, .stayed)
        XCTAssertEqual(queue.sync { proxy.sessions["36277192947"]?.races.count }, 0)
    }

    func testComesBackOnTheSamePortAfterTheSystemTearsTheListenerDown() throws {
        let port = proxyPort
        queue.sync { proxyServer.simulateSystemCancel() }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !queue.sync(execute: { proxyServer.isListening && proxyServer.restarts > 0 }) {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(queue.sync { proxyServer.isListening })
        XCTAssertEqual(queue.sync { proxyServer.port }, port)
        let (body, _) = try fetch([cdn(0, "r")], range: "bytes=0-9999")
        XCTAssertEqual(body, blob.subdata(in: 0..<10000))
    }

    func testCancelsTheCDNRequestWhenThePlayerHangsUp() throws {
        var request = try URLRequest(url: register([cdn(0, "h", "slow=1")]))
        request.setValue("bytes=0-4999999", forHTTPHeaderField: "Range")
        proxy.tuning.stallTimeout = 5
        let started = expectation(description: "first bytes")
        let delegate = FirstBytesDelegate(onBytes: { started.fulfill() })
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: request)
        task.resume()
        wait(for: [started], timeout: 5)
        task.cancel()

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !queue.sync(execute: { recorder.records.last?.cancelled == true }) {
            Thread.sleep(forTimeInterval: 0.05)
        }
        let record = try XCTUnwrap(queue.sync { recorder.records.last })
        XCTAssertTrue(record.cancelled)
        XCTAssertLessThan(record.bytes, Int64(blob.count))
        session.invalidateAndCancel()
    }

    // MARK: - Fake CDN

    private func fakeCDN(blob: Data, queue: DispatchQueue) -> HTTPServer.Handler {
        { request, response in
            guard request.headers["referer"] == ProxyEndToEndTests.referer, request.query["deny"] == nil else {
                response.respond(status: 403)
                return
            }
            let last = Int64(blob.count - 1)
            let range = request.range ?? ByteRange(start: 0, end: last)
            let end = min(range.end ?? last, last)
            let slice = blob.subdata(in: Int(range.start)..<Int(end + 1))
            var headers = [("Content-Type", "video/mp4"), ("Content-Range", "bytes \(range.start)-\(end)/\(blob.count)")]
            if request.query["nolength"] == nil {
                headers.append(("Content-Length", String(slice.count)))
            }
            response.sendHead(status: 206, headers: headers)
            if request.query["hang"] != nil {
                return
            }
            let dropAfter = request.query["dropAfter"].flatMap(Int.init)
            let slow = request.query["slow"] != nil
            let step = slow ? 16 * 1024 : 64 * 1024
            func send(from offset: Int) {
                guard !response.finished else { return }
                if let dropAfter, offset >= dropAfter {
                    response.abort()
                    return
                }
                guard offset < slice.count else {
                    response.finish()
                    return
                }
                var count = min(step, slice.count - offset)
                if let dropAfter {
                    count = min(count, dropAfter - offset)
                }
                response.sendBody(slice.subdata(in: offset..<offset + count))
                if slow {
                    queue.asyncAfter(deadline: .now() + 0.05) { send(from: offset + count) }
                } else {
                    send(from: offset + count)
                }
            }
            send(from: 0)
        }
    }

    // MARK: - Helpers

    private func cdn(_ index: Int, _ file: String, _ query: String? = nil) -> URL {
        let name = file.hasSuffix(".m4s") ? file : "\(file).m4s"
        return URL(string: "http://127.0.0.1:\(cdnPorts[index])/upgcxcode/\(name)" + (query.map { "?\($0)" } ?? ""))!
    }

    private func start(_ server: HTTPServer) throws -> UInt16 {
        let ready = expectation(description: "listening")
        var port: UInt16?
        queue.async {
            server.start(localOnly: true) { bound in
                port = bound
                ready.fulfill()
            }
        }
        wait(for: [ready], timeout: 5)
        return try XCTUnwrap(port)
    }

    private func register(_ urls: [URL]) throws -> URL {
        let rep = MediaRep(kind: .video, id: 120, bandwidth: 5_000_000, codecs: "hev1.1.6.L150.90",
                           urls: urls, preferred: urls[0], referer: ProxyEndToEndTests.referer)
        let token = queue.sync { () -> String in
            proxy.session(for: rep).random = { 0.99 }
            return registry.add(rep)
        }
        return try XCTUnwrap(URL(string: "http://127.0.0.1:\(proxyPort)/m/\(token).m4s"))
    }

    private func fetch(_ urls: [URL], range: String) throws -> (Data, HTTPURLResponse) {
        var request = try URLRequest(url: register(urls))
        request.setValue(range, forHTTPHeaderField: "Range")
        return try get(request)
    }

    private func get(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let done = expectation(description: "response")
        var result: (Data, HTTPURLResponse)?
        var failure: Error?
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let data, let http = response as? HTTPURLResponse {
                result = (data, http)
            }
            failure = error
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 20)
        if let failure {
            throw failure
        }
        return try XCTUnwrap(result)
    }
}

private final class FirstBytesDelegate: NSObject, URLSessionDataDelegate {
    private var onBytes: (() -> Void)?

    init(onBytes: @escaping () -> Void) {
        self.onBytes = onBytes
    }

    func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive _: Data) {
        onBytes?()
        onBytes = nil
    }
}
