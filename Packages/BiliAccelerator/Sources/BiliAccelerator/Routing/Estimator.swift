import Foundation

/// Exponentially weighted average whose weight is time, as in Shaka Player.
struct EWMA {
    private let alpha: Double
    private var estimate: Double = 0
    private var totalWeight: Double = 0

    init(halfLife: Double) {
        alpha = exp(log(0.5) / halfLife)
    }

    mutating func sample(weight: Double, value: Double) {
        let adjusted = pow(alpha, weight)
        estimate = value * (1 - adjusted) + adjusted * estimate
        totalWeight += weight
    }

    var value: Double {
        let zeroFactor = 1 - pow(alpha, totalWeight)
        return zeroFactor > 0 ? estimate / zeroFactor : 0
    }
}

/// Bits per second the player got from one host, from whole requests: bytes over the time from
/// send to the last byte, first-byte wait included, since the player pays for that on every
/// fragment. The lower of a fast and a slow average is used, so the estimate falls quickly and
/// recovers slowly. Ported from `createEstimator` in the userscript's routing.js.
struct Estimator {
    static let minSampleBytes: Int64 = 16000
    static let minTotalBytes: Int64 = 128_000

    private var fast = EWMA(halfLife: 2)
    private var slow = EWMA(halfLife: 5)
    private(set) var bytes: Int64 = 0
    private(set) var seconds: Double = 0

    @discardableResult
    mutating func sample(duration: Double, bytes sampleBytes: Int64) -> Bool {
        guard duration > 0, sampleBytes >= Estimator.minSampleBytes else { return false }
        let bps = Double(sampleBytes) * 8 / duration
        fast.sample(weight: duration, value: bps)
        slow.sample(weight: duration, value: bps)
        bytes += sampleBytes
        seconds += duration
        return true
    }

    var bps: Double? {
        bytes >= Estimator.minTotalBytes ? min(fast.value, slow.value) : nil
    }
}
