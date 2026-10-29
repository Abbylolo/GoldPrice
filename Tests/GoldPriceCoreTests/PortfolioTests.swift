import XCTest
@testable import GoldPriceCore

final class PortfolioTests: XCTestCase {
    func testWeightedAverageIncludesExplicitPurchaseFee() throws {
        let p = try Portfolio.calculate([
            Trade(kind: .buy, grams: 10, pricePerGram: 800, fee: 10),
            Trade(kind: .buy, grams: 10, pricePerGram: 900)
        ])
        XCTAssertEqual(p.grams, 20)
        XCTAssertEqual(p.averageCost, Decimal(string: "850.5"))
        XCTAssertEqual(p.unrealizedProfit(sellPrice: 870), 390)
    }

    func testPartialSalePreservesRemainingAverageAndSeparatesRealizedProfit() throws {
        let p = try Portfolio.calculate([
            Trade(kind: .buy, grams: 10, pricePerGram: 800),
            Trade(kind: .buy, grams: 10, pricePerGram: 900),
            Trade(kind: .sell, grams: 5, pricePerGram: 880, fee: 5)
        ])
        XCTAssertEqual(p.grams, 15)
        XCTAssertEqual(p.averageCost, 850)
        XCTAssertEqual(p.realizedProfit, 145)
        XCTAssertEqual(p.unrealizedProfit(sellPrice: 870), 300)
    }

    func testFullSaleResetsCostForNextPosition() throws {
        let p = try Portfolio.calculate([
            Trade(kind: .buy, grams: 10, pricePerGram: 800),
            Trade(kind: .sell, grams: 10, pricePerGram: 850),
            Trade(kind: .buy, grams: 2, pricePerGram: 900)
        ])
        XCTAssertEqual(p.averageCost, 900)
        XCTAssertEqual(p.realizedProfit, 500)
    }

    func testBackdatedTransactionsAreReplayedBeforeSellValidation() throws {
        let earlier = Date(timeIntervalSince1970: 1)
        let later = Date(timeIntervalSince1970: 2)
        XCTAssertThrowsError(try Portfolio.calculate([
            Trade(date: later, kind: .buy, grams: 10, pricePerGram: 800),
            Trade(date: earlier, kind: .sell, grams: 1, pricePerGram: 850)
        ])) { XCTAssertEqual($0 as? PortfolioError, .insufficientGrams) }
    }

    func testOverSellingAndNonPositiveInputsAreRejected() throws {
        XCTAssertThrowsError(try Portfolio.calculate([Trade(kind: .sell, grams: 1, pricePerGram: 850)]))
        XCTAssertThrowsError(try Portfolio.calculate([Trade(kind: .buy, grams: 0, pricePerGram: 850)]))
        XCTAssertThrowsError(try Portfolio.calculate([Trade(kind: .buy, grams: 1, pricePerGram: 850, fee: -1)]))
    }
}
