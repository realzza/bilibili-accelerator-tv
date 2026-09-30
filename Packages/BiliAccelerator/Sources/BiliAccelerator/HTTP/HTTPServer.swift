import Foundation
import Network

/// A small HTTP/1.1 server on Network.framework: GET and HEAD, keep-alive, streamed bodies.
/// Everything runs on the queue passed in, including the handler.
final class HTTPServer {
    typealias Handler = (HTTPRequest, HTTPResponse) -> Void

    private let queue: DispatchQueue
    private let handler: Handler
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: HTTPConnection] = [:]
    private var localOnly = true
    private var stopped = false
    private var restartScheduled = false
    /// The port currently listened on; nil while down.
    private(set) var port: UInt16?
    /// The first port bound. Playlists already handed to AVPlayer carry it, so a restart after the
    /// system tore the listener down has to come back on the same one.
    private(set) var stickyPort: UInt16 = 0
    private(set) var accepted = 0
    private(set) var restarts = 0
    private(set) var events: [(at: TimeInterval, text: String)] = []

    init(queue: DispatchQueue, handler: @escaping Handler) {
        self.queue = queue
        self.handler = handler
    }

    var isListening: Bool {
        listener != nil && port != nil
    }

    /// Starts listening. `completion` runs once on the server queue with the bound port, or nil.
    /// Port 0 asks the system for a free one.
    func start(port: UInt16 = 0, localOnly: Bool, completion: @escaping (UInt16?) -> Void) {
        self.localOnly = localOnly
        stopped = false
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.acceptLocalOnly = localOnly
        let requested = NWEndpoint.Port(rawValue: port) ?? .any
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: requested)
        } catch {
            note("init failed: \(error.localizedDescription)")
            queue.async { completion(nil) }
            scheduleRestart()
            return
        }

        var reported = false
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener, listener === self.listener else { return }
            switch state {
            case .ready:
                let bound = listener.port?.rawValue
                self.port = bound
                if self.stickyPort == 0, let bound {
                    self.stickyPort = bound
                }
                self.note("ready \(bound ?? 0)")
                if !reported {
                    reported = true
                    completion(bound)
                }
            case let .failed(error):
                self.note("failed: \(error.localizedDescription)")
                self.teardown(listener)
                if !reported {
                    reported = true
                    completion(nil)
                }
            case .cancelled:
                // Cancelled by the system rather than by `stop()` or a teardown of ours.
                self.note("cancelled")
                self.teardown(listener)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    /// Starts again on the sticky port if the listener is down, which happens when a tvOS app is
    /// suspended and its sockets are defuncted.
    func restartIfNeeded(completion: @escaping (UInt16?) -> Void) {
        guard !isListening, !stopped else {
            completion(port)
            return
        }
        restarts += 1
        note("restart on \(stickyPort)")
        listener?.cancel()
        listener = nil
        start(port: stickyPort, localOnly: localOnly, completion: completion)
    }

    /// Rebinds the sticky port unconditionally. After a tvOS app returns from the background its
    /// loopback listener can still report `ready` while refusing every connection: the socket was
    /// defuncted during the suspension and Network.framework doesn't say so.
    func forceRestart(completion: @escaping (UInt16?) -> Void) {
        guard !stopped else {
            completion(port)
            return
        }
        restarts += 1
        note("forced restart on \(stickyPort)")
        let old = listener
        listener = nil
        port = nil
        old?.cancel()
        for connection in connections.values {
            connection.close()
        }
        connections.removeAll()
        start(port: stickyPort, localOnly: localOnly, completion: completion)
    }

    func stop() {
        stopped = true
        let old = listener
        listener = nil
        port = nil
        old?.cancel()
        for connection in connections.values {
            connection.close()
        }
        connections.removeAll()
    }

    /// What the system does to a suspended app's listener, for tests.
    func simulateSystemCancel() {
        listener?.cancel()
    }

    private func teardown(_ failed: NWListener) {
        listener = nil
        port = nil
        failed.cancel()
        scheduleRestart()
    }

    /// Retries every half second until the listener is back. While the app is suspended the queue
    /// doesn't run, so the retry happens on resume.
    private func scheduleRestart() {
        guard !stopped, !restartScheduled else { return }
        restartScheduled = true
        queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.restartScheduled = false
            self.restartIfNeeded { _ in }
        }
    }

    private func note(_ text: String) {
        Log.proxy.info("server: \(text, privacy: .public)")
        events.append((Recorder.now(), text))
        if events.count > 20 {
            events.removeFirst(events.count - 20)
        }
    }

    private func accept(_ nwConnection: NWConnection) {
        accepted += 1
        let connection = HTTPConnection(connection: nwConnection, queue: queue, handler: handler)
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        connection.onClose = { [weak self] in
            self?.connections[key] = nil
        }
        connection.start()
    }
}

final class HTTPConnection {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let handler: HTTPServer.Handler
    private var buffer = Data()
    private var current: HTTPResponse?
    private var closed = false
    private var closeWhenDrained = false
    private(set) var pendingBytes = 0
    var onClose: (() -> Void)?

    init(connection: NWConnection, queue: DispatchQueue, handler: @escaping HTTPServer.Handler) {
        self.connection = connection
        self.queue = queue
        self.handler = handler
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.close()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    /// Keeps a read pending the whole time, so a client that hangs up mid-response is noticed
    /// at once and its upstream request can be cancelled.
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, !self.closed else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.processBuffer()
            }
            if isComplete || error != nil {
                self.close()
            } else {
                self.receive()
            }
        }
    }

    private func processBuffer() {
        guard current == nil, !closed, !closeWhenDrained else { return }
        switch HTTPParser.parse(buffer) {
        case .incomplete:
            return
        case .invalid:
            close()
        case let .request(request, consumed):
            buffer.removeFirst(consumed)
            let response = HTTPResponse(connection: self, keepAlive: request.keepAlive, isHead: request.method == "HEAD")
            current = response
            handler(request, response)
        }
    }

    func write(_ data: Data, completion: @escaping (Bool) -> Void) {
        guard !closed else {
            completion(false)
            return
        }
        pendingBytes += data.count
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            self.pendingBytes -= data.count
            completion(error == nil)
            if error != nil {
                self.close()
            } else if self.closeWhenDrained, self.pendingBytes == 0 {
                self.close()
            }
        })
    }

    func responseFinished(_ response: HTTPResponse) {
        guard current === response else { return }
        current = nil
        if response.keepAlive {
            processBuffer()
        } else if pendingBytes == 0 {
            close()
        } else {
            closeWhenDrained = true
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        let response = current
        current = nil
        response?.connectionClosed()
        connection.cancel()
        onClose?()
        onClose = nil
    }
}

final class HTTPResponse {
    /// Output buffered for a slow client beyond which the upstream download is paused.
    static let highWater = 4 * 1024 * 1024
    static let lowWater = 1024 * 1024

    private weak var connection: HTTPConnection?
    let keepAlive: Bool
    let isHead: Bool
    private(set) var headSent = false
    private(set) var finished = false
    private var chunked = false
    private var backedUp = false

    /// Runs if the client disconnects before `finish()`.
    var onClientGone: (() -> Void)?
    /// Runs when buffered output drains below the low-water mark after exceeding the high-water mark.
    var onDrain: (() -> Void)?

    init(connection: HTTPConnection, keepAlive: Bool, isHead: Bool) {
        self.connection = connection
        self.keepAlive = keepAlive
        self.isHead = isHead
    }

    var isBackedUp: Bool {
        (connection?.pendingBytes ?? 0) > HTTPResponse.highWater
    }

    func sendHead(status: Int, headers: [(String, String)]) {
        guard !headSent, !finished else { return }
        headSent = true
        let hasLength = headers.contains { $0.0.lowercased() == "content-length" }
        chunked = !hasLength && !isHead && status != 204 && status != 304
        var lines = ["HTTP/1.1 \(status) \(HTTPResponse.reason(for: status))"]
        lines += headers.map { "\($0.0): \($0.1)" }
        if chunked {
            lines.append("Transfer-Encoding: chunked")
        }
        lines.append(keepAlive ? "Connection: keep-alive" : "Connection: close")
        write(Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8))
    }

    func sendBody(_ data: Data) {
        guard headSent, !finished, !isHead, !data.isEmpty else { return }
        guard chunked else {
            write(data)
            return
        }
        var framed = Data(String(data.count, radix: 16).utf8)
        framed.append(contentsOf: [13, 10])
        framed.append(data)
        framed.append(contentsOf: [13, 10])
        write(framed)
    }

    func finish() {
        guard !finished else { return }
        if !headSent {
            sendHead(status: 500, headers: [("Content-Length", "0")])
        }
        if chunked {
            write(Data("0\r\n\r\n".utf8))
        }
        finished = true
        connection?.responseFinished(self)
    }

    /// A status with an empty body, if nothing has been sent yet.
    func respond(status: Int) {
        sendHead(status: status, headers: [("Content-Length", "0")])
        finish()
    }

    func respond(status: Int, contentType: String, body: Data) {
        sendHead(status: status, headers: [("Content-Type", contentType), ("Content-Length", String(body.count))])
        sendBody(body)
        finish()
    }

    /// Drops the connection mid-body. AVPlayer treats a short body as a failed request and retries.
    func abort() {
        guard !finished else { return }
        finished = true
        connection?.close()
    }

    func connectionClosed() {
        guard !finished else { return }
        finished = true
        let gone = onClientGone
        onClientGone = nil
        onDrain = nil
        gone?()
    }

    private func write(_ data: Data) {
        guard let connection else { return }
        connection.write(data) { [weak self] ok in
            guard let self, ok, self.backedUp else { return }
            if (self.connection?.pendingBytes ?? 0) < HTTPResponse.lowWater {
                self.backedUp = false
                self.onDrain?()
            }
        }
        if connection.pendingBytes > HTTPResponse.highWater {
            backedUp = true
        }
    }

    static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 206: return "Partial Content"
        case 304: return "Not Modified"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 416: return "Range Not Satisfiable"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        default: return "Status \(status)"
        }
    }
}
