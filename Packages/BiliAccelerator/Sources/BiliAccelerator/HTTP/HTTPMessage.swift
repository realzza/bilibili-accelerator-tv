import Foundation

/// One byte range from a `Range: bytes=a-b` header. `end` is inclusive, nil for an open range.
public struct ByteRange: Equatable, Hashable {
    public let start: Int64
    public let end: Int64?

    public init(start: Int64, end: Int64?) {
        self.start = start
        self.end = end
    }

    /// Parses `bytes=a-b` and `bytes=a-`. Suffix ranges and multiple ranges give nil;
    /// AVPlayer sends neither for byte-range segments.
    public init?(header: String?) {
        guard let header = header?.trimmingCharacters(in: .whitespaces),
              header.lowercased().hasPrefix("bytes=")
        else { return nil }
        let spec = header.dropFirst("bytes=".count)
        guard !spec.contains(",") else { return nil }
        let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let start = Int64(parts[0].trimmingCharacters(in: .whitespaces))
        else { return nil }
        let endText = parts[1].trimmingCharacters(in: .whitespaces)
        if endText.isEmpty {
            self.init(start: start, end: nil)
            return
        }
        guard let end = Int64(endText), end >= start else { return nil }
        self.init(start: start, end: end)
    }

    public var headerValue: String {
        "bytes=\(start)-\(end.map(String.init) ?? "")"
    }

    public var length: Int64? {
        end.map { $0 - start + 1 }
    }
}

struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    /// Header names are lowercased.
    let headers: [String: String]
    let version: String

    var range: ByteRange? {
        ByteRange(header: headers["range"])
    }

    var keepAlive: Bool {
        let connection = headers["connection"]?.lowercased()
        if version == "HTTP/1.0" {
            return connection == "keep-alive"
        }
        return connection != "close"
    }
}

enum HTTPParser {
    static let maxHeaderBytes = 64 * 1024
    private static let terminator = Data("\r\n\r\n".utf8)

    enum Result {
        case incomplete
        case invalid
        case request(HTTPRequest, consumed: Int)
    }

    /// Parses one request head from the front of `buffer`. Request bodies are not supported;
    /// the proxy only serves GET and HEAD.
    static func parse(_ buffer: Data) -> Result {
        guard let end = buffer.range(of: terminator) else {
            return buffer.count > maxHeaderBytes ? .invalid : .incomplete
        }
        let head = buffer[buffer.startIndex..<end.lowerBound]
        guard let text = String(data: head, encoding: .utf8) ?? String(data: head, encoding: .isoLatin1) else {
            return .invalid
        }
        var lines = text.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count == 3 else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let target = String(requestLine[1])
        let components = URLComponents(string: target)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }
        let request = HTTPRequest(method: String(requestLine[0]).uppercased(),
                                  path: components?.path ?? target,
                                  query: query,
                                  headers: headers,
                                  version: String(requestLine[2]).uppercased())
        return .request(request, consumed: buffer.distance(from: buffer.startIndex, to: end.upperBound))
    }
}
