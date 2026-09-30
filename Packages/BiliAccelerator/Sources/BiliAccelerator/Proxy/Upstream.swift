import Foundation

/// Callbacks for one upstream fetch. All of them run on the accelerator queue.
final class UpstreamRequest {
    fileprivate(set) var task: URLSessionDataTask?
    var onResponse: ((HTTPURLResponse?) -> Void)?
    var onData: ((Data) -> Void)?
    var onComplete: ((Error?) -> Void)?

    func cancel() {
        task?.cancel()
    }

    func suspend() {
        task?.suspend()
    }

    func resume() {
        task?.resume()
    }
}

/// One URLSession for every CDN request, so races and playback share connections to a host.
final class Upstream: NSObject, URLSessionDataDelegate {
    private var session: URLSession!
    private var requests: [Int: UpstreamRequest] = [:]

    init(queue: DispatchQueue, userAgent: String) {
        super.init()
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 300
        configuration.httpAdditionalHeaders = [
            "User-Agent": userAgent,
            "Accept-Encoding": "identity",
        ]
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.underlyingQueue = queue
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
    }

    /// Every UPOS host answers 403 without a Referer.
    func start(url: URL, range: ByteRange?, referer: String, request handler: UpstreamRequest) {
        var request = URLRequest(url: url)
        request.setValue(referer, forHTTPHeaderField: "Referer")
        if let range {
            request.setValue(range.headerValue, forHTTPHeaderField: "Range")
        }
        let task = session.dataTask(with: request)
        handler.task = task
        requests[task.taskIdentifier] = handler
        task.resume()
    }

    func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void)
    {
        requests[dataTask.taskIdentifier]?.onResponse?(response as? HTTPURLResponse)
        completionHandler(.allow)
    }

    func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        requests[dataTask.taskIdentifier]?.onData?(data)
    }

    func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        requests.removeValue(forKey: task.taskIdentifier)?.onComplete?(error)
    }
}
