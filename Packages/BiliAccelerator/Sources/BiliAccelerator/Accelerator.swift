import AVFoundation
import Foundation
#if canImport(UIKit)
    import UIKit
#endif

/// Entry point for the app. AVPlayer loads media segments from a loopback proxy, which fetches
/// them from a CDN host and measures every request. This first version always uses the URL the
/// app chose; host switching builds on the measurements.
public final class Accelerator {
    public static let shared = Accelerator()
    public static let version = "0.1.0"

    let queue = DispatchQueue(label: "io.github.realzza.bilibili-tv.accelerator")
    private let registry = Registry()
    private let recorder = Recorder()
    private var server: HTTPServer?
    private var debugServer: HTTPServer?
    private var proxy: MediaProxy?
    private var port: UInt16?
    private var lastPlayer: PlayerProbe.Snapshot?
    private var snapshotCount = 0

    // Main thread.
    private let probe = PlayerProbe()
    private var snapshotTimer: Timer?

    private let enabledLock = NSLock()
    private var _enabled = true

    private init() {}

    /// Development builds: runs on the main thread for `/debug/<command>?...` requests to the
    /// debug server, so a video can be started from the Mac while testing.
    public var debugCommandHandler: ((String, [String: String]) -> Void)?

    /// When false, `proxyURL(for:)` returns nil and AVPlayer goes straight to the CDN.
    public var isEnabled: Bool {
        get {
            enabledLock.lock()
            defer { enabledLock.unlock() }
            return _enabled
        }
        set {
            enabledLock.lock()
            _enabled = newValue
            enabledLock.unlock()
        }
    }

    /// Starts the loopback proxy. Call once at launch; playback that starts before it is ready
    /// plays directly.
    public func start(userAgent: String) {
        queue.async { [self] in
            guard server == nil else { return }
            let upstream = Upstream(queue: queue, userAgent: userAgent)
            let proxy = MediaProxy(queue: queue, upstream: upstream, registry: registry, recorder: recorder)
            let server = HTTPServer(queue: queue) { request, response in
                proxy.handle(request, response)
            }
            self.proxy = proxy
            self.server = server
            server.start(localOnly: true) { [self] bound in
                port = bound
                Log.proxy.info("media proxy listening on 127.0.0.1:\(bound ?? 0, privacy: .public)")
            }
        }
        #if canImport(UIKit)
            NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                   object: nil, queue: nil)
            { [weak self] _ in
                self?.restartIfNeeded()
            }
        #endif
    }

    /// Serves the diagnostics report at `http://<device>:<port>/debug` on the local network.
    /// For development builds only.
    public func startDebugServer(port: UInt16) {
        queue.async { [self] in
            guard debugServer == nil else { return }
            let server = HTTPServer(queue: queue) { [weak self] request, response in
                self?.handleDebug(request, response)
            }
            debugServer = server
            server.start(port: port, localOnly: false) { bound in
                Log.proxy.info("debug server listening on port \(bound ?? 0, privacy: .public)")
            }
        }
    }

    /// The loopback URL AVPlayer should load `rep`'s bytes from, or nil to play directly.
    /// Must not be called on the accelerator queue.
    public func proxyURL(for rep: MediaRep) -> URL? {
        guard isEnabled else { return nil }
        return queue.sync {
            guard let port, server?.isListening == true else { return nil }
            let token = registry.add(rep)
            return URL(string: "http://127.0.0.1:\(port)/m/\(token).m4s")
        }
    }

    /// Call on the main thread when a new player item starts. The engine reads the buffer from
    /// it to judge whether a slow fragment will arrive in time.
    public func attach(playerItem: AVPlayerItem) {
        probe.attach(playerItem)
        queue.async { self.recorder.beginSession() }
        snapshotTimer?.invalidate()
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.takeSnapshot()
        }
    }

    /// Call on the main thread when playback ends.
    public func detach() {
        takeSnapshot()
        probe.detach()
        snapshotTimer?.invalidate()
        snapshotTimer = nil
        queue.async { self.proxy?.bufferAhead = nil }
    }

    /// The current report as JSON.
    public func diagnosticsJSON() -> Data {
        queue.sync { Diagnostics.json(report()) }
    }

    private func takeSnapshot() {
        let snapshot = probe.snapshot()
        queue.async { [self] in
            if let snapshot {
                lastPlayer = snapshot
                proxy?.bufferAhead = snapshot.bufferedAhead
            }
            snapshotCount += 1
            if snapshotCount % 2 == 0 {
                writeDiagnosticsFile()
            }
        }
    }

    private func restartIfNeeded() {
        queue.async { [self] in
            server?.restartIfNeeded { [self] bound in
                if bound != port {
                    Log.proxy.info("media proxy restarted on port \(bound ?? 0, privacy: .public)")
                }
                port = bound
            }
        }
    }

    private func report() -> [String: Any] {
        Diagnostics.report(recorder: recorder, registry: registry, sessions: proxy.map { Array($0.sessions.values) } ?? [],
                           player: lastPlayer, port: port, enabled: isEnabled)
    }

    private func writeDiagnosticsFile() {
        guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("BiliAccelerator", isDirectory: true)
        else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Diagnostics.json(report()).write(to: directory.appendingPathComponent("diagnostics.json"), options: .atomic)
    }

    private func handleDebug(_ request: HTTPRequest, _ response: HTTPResponse) {
        switch request.path {
        case "/debug", "/debug/":
            response.respond(status: 200, contentType: "application/json", body: Diagnostics.json(report()))
        case let path where path.hasPrefix("/debug/"):
            let command = String(path.dropFirst("/debug/".count))
            guard let handler = debugCommandHandler else {
                response.respond(status: 404)
                return
            }
            let parameters = request.query
            DispatchQueue.main.async {
                handler(command, parameters)
            }
            response.respond(status: 202, contentType: "text/plain", body: Data("queued \(command)\n".utf8))
        default:
            response.respond(status: 404)
        }
    }
}
