import XCTest
@testable import GoldPriceCore

final class TrendSnapshotTests: XCTestCase {
    func testRangeUsesBeijingDayAndExcludesFuturePoints() throws {
        let now = try XCTUnwrap(QuoteParser.date("2026-11-02 10:00", formats: ["yyyy-MM-dd HH:mm"]))
        let yesterday = PricePoint(date: now.addingTimeInterval(-11 * 3600), value: 800)
        let midnight = PricePoint(date: now.addingTimeInterval(-10 * 3600), value: 810)
        let current = PricePoint(date: now, value: 820)
        let future = PricePoint(date: now.addingTimeInterval(60), value: 830)
        XCTAssertEqual(TrendSnapshot(history: [yesterday, midnight, current, future], range: .day, now: now).points, [midnight, current])
    }

    func testLongHistoryHasBoundedPlotAndRetainsCoverageEndpoints() {
        let points = (0..<10_000).map { PricePoint(date: Date(timeIntervalSince1970: Double($0)), value: Double($0 + 1)) }
        let snapshot = TrendSnapshot(history: points, range: .all, now: Date(timeIntervalSince1970: 10_001))
        XCTAssertEqual(snapshot.points.count, 600)
        XCTAssertEqual(snapshot.points.first, points.first)
        XCTAssertEqual(snapshot.points.last, points.last)
        XCTAssertTrue(zip(snapshot.points, snapshot.points.dropFirst()).allSatisfy { pair in pair.0.date < pair.1.date })
    }

    func testInspectionFindsClosestPointAndClampsAtCoverageBoundaries() {
        let points = [0.0, 10, 20].map { PricePoint(date: Date(timeIntervalSince1970: $0), value: 800 + $0) }
        let snapshot = TrendSnapshot(history: points, range: .all, now: Date(timeIntervalSince1970: 30))
        XCTAssertEqual(snapshot.nearest(to: Date(timeIntervalSince1970: -1)), points[0])
        XCTAssertEqual(snapshot.nearest(to: Date(timeIntervalSince1970: 6)), points[1])
        XCTAssertEqual(snapshot.nearest(to: Date(timeIntervalSince1970: 15)), points[1])
        XCTAssertEqual(snapshot.nearest(to: Date(timeIntervalSince1970: 99)), points[2])
    }

    func testFlatAndEmptyHistoriesKeepValidAxes() {
        let now = Date()
        let empty = TrendSnapshot(history: [], range: .all, now: now)
        XCTAssertNil(empty.nearest(to: now))
        XCTAssertGreaterThan(empty.bounds.upperBound, empty.bounds.lowerBound)
        let flat = TrendSnapshot(history: [PricePoint(date: now, value: 850)], range: .all, now: now)
        XCTAssertLessThan(flat.bounds.lowerBound, 850)
        XCTAssertGreaterThan(flat.bounds.upperBound, 850)
    }
}
