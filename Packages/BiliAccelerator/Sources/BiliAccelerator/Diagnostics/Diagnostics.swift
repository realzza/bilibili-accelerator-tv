import Foundation

/// The report behind the debug endpoint and the diagnostics file. Hosts only: no signed URLs,
/// query strings or account data.
enum Diagnostics {
    static func report(recorder: Recorder, registry: Registry, sessions: [RoutingSession],
                       player: PlayerProbe.Snapshot?, port: UInt16?, enabled: Bool) -> [String: Any]
    {
        let now = Recorder.now()
        var report: [String: Any] = [
            "version": Accelerator.version,
            "enabled": enabled,
            "proxyPort": port.map { Int($0) } ?? NSNull(),
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "sessionAgeS": round1(now - recorder.sessionStartedAt),
            "requiredMbps": round2(Double(recorder.requiredBps) / 1_000_000),
        ]
        if let player {
            var state: [String: Any] = [
                "currentTime": round1(player.currentTime),
                "bufferedAheadS": round1(player.bufferedAhead),
                "likelyToKeepUp": player.likelyToKeepUp,
                "bufferEmpty": player.bufferEmpty,
                "stalls": player.stalls,
            ]
            if let observed = player.observedMbps {
                state["observedMbps"] = round2(observed)
            }
            if let indicated = player.indicatedMbps {
                state["indicatedMbps"] = round2(indicated)
            }
            state["itemStatus"] = player.itemStatus
            state["itemError"] = player.itemError ?? NSNull()
            state["lastErrorLog"] = player.lastErrorLog ?? NSNull()
            state["timeControl"] = player.timeControl ?? NSNull()
            state["waitingReason"] = player.waitingReason ?? NSNull()
            report["player"] = state
        }
        report["hosts"] = hostSummaries(recorder: recorder)
        report["reps"] = registry.all.suffix(12).map { rep -> [String: Any] in
            [
                "kind": rep.kind.rawValue,
                "id": rep.id,
                "mbps": round2(Double(rep.bandwidth) / 1_000_000),
                "codecs": rep.codecs,
                "issuedHosts": rep.urls.compactMap(\.host),
                "preferredHost": rep.preferred.host ?? "?",
            ]
        }
        report["sessions"] = sessions.sorted { $0.startedAt > $1.startedAt }.prefix(3).map { session -> [String: Any] in
            [
                "video": session.key,
                "activeHost": session.activeHost ?? "native",
                "estimateMbps": session.measuredMbps.mapValues { round1($0) },
                "failures": session.failures.mapValues(\.count),
                "switches": session.switches.map { change -> [String: Any] in
                    var entry: [String: Any] = ["from": change.from, "to": change.to, "trigger": change.trigger,
                                                "ageS": round1(now - change.at)]
                    if let before = change.beforeMbps {
                        entry["beforeMbps"] = round1(before)
                    }
                    return entry
                },
                "races": session.races.suffix(8).reversed().map { race -> [String: Any] in
                    [
                        "trigger": race.trigger,
                        "from": race.from,
                        "winner": race.winner ?? NSNull(),
                        "moved": race.moved,
                        "ageS": round1(now - race.at),
                        "contenders": race.contenders.map { contender -> [String: Any] in
                            var entry: [String: Any] = ["host": contender.host, "bytes": contender.bytes]
                            if let seconds = contender.seconds {
                                entry["ms"] = Int(seconds * 1000)
                            }
                            return entry
                        },
                    ]
                },
            ]
        }
        report["recent"] = recorder.records.suffix(40).reversed().map { describe($0, now: now) }
        return report
    }

    /// JSONSerialization raises an Objective-C exception, which `try?` doesn't catch, for a value
    /// it can't encode (an ArraySlice, say), so the report is checked first.
    static func json(_ object: [String: Any]) -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            Log.proxy.error("diagnostics report is not valid JSON")
            return Data(#"{"error":"report not encodable"}"#.utf8)
        }
        return (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
    }

    private static func hostSummaries(recorder: Recorder) -> [String: Any] {
        var byHost: [String: [RequestRecord]] = [:]
        for record in recorder.records where record.startedAt >= recorder.sessionStartedAt {
            byHost[record.host, default: []].append(record)
        }
        var out: [String: Any] = [:]
        for (host, totals) in recorder.totals {
            let records = byHost[host] ?? []
            let firstBytes = records.compactMap(\.firstByteMs)
            let goodputs = records.compactMap(\.goodputMbps)
            var summary: [String: Any] = [
                "requests": totals.requests,
                "megabytes": round2(Double(totals.bytes) / 1_000_000),
                "errors": totals.errors,
                "cancelled": totals.cancelled,
            ]
            if let median = median(firstBytes) {
                summary["medianFirstByteMs"] = Int(median)
            }
            if let median = median(goodputs) {
                summary["medianGoodputMbps"] = round1(median)
            }
            if let last = goodputs.last {
                summary["lastGoodputMbps"] = round1(last)
            }
            out[host] = summary
        }
        return out
    }

    private static func describe(_ record: RequestRecord, now: TimeInterval) -> [String: Any] {
        var entry: [String: Any] = [
            "id": record.id,
            "host": record.host,
            "kind": record.isHeader ? "\(record.kind.rawValue)-init" : record.kind.rawValue,
            "rep": record.repID,
            "bytes": record.bytes,
            "ageS": round1(now - record.startedAt),
        ]
        if let range = record.range {
            entry["range"] = "\(range.start)-\(range.end.map(String.init) ?? "")"
        }
        if let firstByte = record.firstByteMs {
            entry["firstByteMs"] = Int(firstByte)
        }
        if let duration = record.durationMs {
            entry["durationMs"] = Int(duration)
        } else {
            entry["inFlight"] = true
        }
        if let goodput = record.goodputMbps {
            entry["mbps"] = round1(goodput)
        }
        if let status = record.status {
            entry["status"] = status
        }
        if let error = record.error {
            entry["error"] = error
        }
        if record.lostRace {
            entry["lostRace"] = true
        } else if record.cancelled {
            entry["cancelled"] = true
        }
        if record.attempt > 0 {
            entry["attempt"] = record.attempt
            entry["client"] = record.clientID
        }
        return entry
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    // Decimal numbers, so the JSON reads 5.3 rather than 5.2999999999999998.
    private static func round1(_ value: Double) -> NSDecimalNumber {
        NSDecimalNumber(string: String(format: "%.1f", value))
    }

    private static func round2(_ value: Double) -> NSDecimalNumber {
        NSDecimalNumber(string: String(format: "%.2f", value))
    }
}
