import Foundation

/// Which hosts can serve a representation, and at what URL. Ported from `urlFor` and
/// `candidatesFor` in the userscript's src/core/routing.js.
enum Candidates {
    /// Mirrors a host swap can reach, as in the userscript's CANDIDATE_POOL.
    static let pool = [
        "upos-sz-mirrorcosov.bilivideo.com",
        "upos-sz-mirroraliov.bilivideo.com",
        "upos-sz-mirrorhwov.bilivideo.com",
        "upos-sz-mirrorali.bilivideo.com",
        "upos-tf-all-hw.bilivideo.com",
        "upos-sz-mirrorhw.bilivideo.com",
        "upos-sz-mirrorcos.bilivideo.com",
        "upos-tf-all-tx.bilivideo.com",
    ]

    /// Overseas edges, Akamai included, as `describeHost` has it. The UPOS ones Bilibili did not
    /// issue see little of this region's traffic and are usually cold, so failover tries them
    /// last, and they lose ties to mainland mirrors.
    static func isOverseas(_ host: String) -> Bool {
        isAkamai(host)
            || host.range(of: #"^upos-[a-z0-9-]*ov\.bilivideo\.com$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isAkamai(_ host: String) -> Bool {
        host.lowercased().hasSuffix(".akamaized.net")
    }

    /// A UPOS mirror accepts any other UPOS host's signed path; Akamai accepts only the URL
    /// issued for it.
    static func isUposHost(_ host: String) -> Bool {
        host.range(of: #"^upos-[a-z0-9-]+\.bilivideo\.com$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Host plus port, so two servers on one machine stay apart. CDN URLs carry no port.
    static func key(_ url: URL) -> String {
        let host = (url.host ?? "?").lowercased()
        return url.port.map { "\(host):\($0)" } ?? host
    }

    /// The URL of `rep`'s bytes on `host`: its issued URL if it has one, else a host swap of an
    /// issued UPOS URL. Nil when neither exists.
    static func url(for rep: MediaRep, host: String) -> URL? {
        if let issued = rep.urls.first(where: { key($0) == host }) {
            return issued
        }
        guard isUposHost(host),
              let source = rep.urls.first(where: { isUposHost(key($0)) }),
              var components = URLComponents(url: source, resolvingAgainstBaseURL: false)
        else { return nil }
        components.host = host
        return components.url
    }

    /// Hosts to fail over to, best guess first: the other issued hosts, then mainland mirrors,
    /// then the overseas mirrors Bilibili did not issue.
    static func failoverOrder(for rep: MediaRep, excluding current: String) -> [String] {
        var out: [String] = []
        func add(_ host: String) {
            if host != current, !out.contains(host), url(for: rep, host: host) != nil {
                out.append(host)
            }
        }
        rep.urls.map(key).forEach(add)
        pool.filter { !isOverseas($0) }.forEach(add)
        pool.filter(isOverseas).forEach(add)
        return out
    }

    /// The video a file belongs to: its name starts with the cid, as in `42301918299-1-30280.m4s`.
    static func sessionKey(for url: URL) -> String {
        let name = url.lastPathComponent
        let digits = name.prefix { $0.isNumber }
        return digits.isEmpty ? "default" : String(digits)
    }
}
