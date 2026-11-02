import Foundation

/// Prepared only when history or the selected range changes, never per chart mark.
public struct TrendSnapshot: Equatable, Sendable {
    public let points: [PricePoint]
    public let bounds: ClosedRange<Double>

    public init(history: [PricePoint], range: TrendRange, now: Date = Date(), pointLimit: Int = 600) {
        precondition(pointLimit >= 2)
        let start = range.start(at: now)
        let filtered = history.filter { (start == nil || $0.date >= start!) && $0.date <= now }
        if filtered.count > pointLimit {
            let step = Double(filtered.count - 1) / Double(pointLimit - 1)
            points = (0..<pointLimit).map { filtered[Int((Double($0) * step).rounded())] }
        } else { points = filtered }
        let low = points.map(\.value).min() ?? 0
        let high = points.map(\.value).max() ?? 1
        let padding = max((high - low) * 0.15, max(low * 0.0005, 0.01))
        bounds = max(0, low - padding)...(high + padding)
    }

    public func nearest(to date: Date) -> PricePoint? {
        guard !points.isEmpty else { return nil }
        var low = 0, high = points.count
        while low < high {
            let middle = (low + high) / 2
            if points[middle].date < date { low = middle + 1 }
            else { high = middle }
        }
        if low == 0 { return points.first }
        if low == points.count { return points.last }
        let before = points[low - 1], after = points[low]
        return date.timeIntervalSince(before.date) <= after.date.timeIntervalSince(date) ? before : after
    }
}
