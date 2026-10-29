import XCTest
@testable import GoldPriceCore

final class MarketTests: XCTestCase {
    func testCMBSeparatesCustomerBuyAndSellAndKeepsSourceTimestamp() throws {
        let data = Data(#"{"success":true,"data":{"NowTime":"2026/10/29 09:53:56","MarketDay":true,"QuotedPrice":true,"FQAMBPRCZ1":{"zBuyPrc":"874.29","zSelPrc":"869.29"}}}"#.utf8)
        let quotes = try QuoteParser.cmb(data)
        XCTAssertEqual(quotes.map(\.channel), [.cmbBuy, .cmbSell])
        XCTAssertEqual(quotes[0].price, Decimal(string: "874.29"))
        XCTAssertEqual(quotes[1].price, Decimal(string: "869.29"))
        XCTAssertEqual(quotes[0].timestamp, QuoteParser.date("2026-10-29 09:53:56", formats: ["yyyy-MM-dd HH:mm:ss"]))
        XCTAssertThrowsError(try QuoteParser.cmb(Data(#"{"success":false}"#.utf8)))
    }

    func testThresholdIncludesEqualityAndRejectsStaleWrongChannelAndClosedMarket() {
        let now = Date()
        let rule = PriceRule(channel: .cmbSell, direction: .above, target: 870)
        var quote = MarketQuote(channel: .cmbSell, price: 870, timestamp: now, receivedAt: now)
        XCTAssertTrue(rule.shouldFire(for: quote, at: now))
        quote.channel = .cmbBuy
        XCTAssertFalse(rule.shouldFire(for: quote, at: now))
        quote.channel = .cmbSell
        quote.timestamp = now.addingTimeInterval(-121)
        XCTAssertFalse(rule.shouldFire(for: quote, at: now))
        quote.timestamp = now
        quote.isMarketOpen = false
        XCTAssertFalse(rule.shouldFire(for: quote, at: now))
    }

    func testDisabledRuleDoesNotRepeat() {
        let now = Date()
        var rule = PriceRule(channel: .london, direction: .below, target: 4100)
        let quote = MarketQuote(channel: .london, price: 4050, timestamp: now, receivedAt: now)
        XCTAssertTrue(rule.shouldFire(for: quote, at: now))
        rule.isEnabled = false
        XCTAssertFalse(rule.shouldFire(for: quote, at: now))
    }

    func testSpotHistoryUsesClosingPriceAndDoesNotAcceptAnotherInstrument() throws {
        let data = Data(#"{"data":{"code":"XAU","klines":["2026-10-29,4067.15,4065.74,4068.72,4036.49,0"]}}"#.utf8)
        XCTAssertEqual(try QuoteParser.eastmoney(data).first?.value, 4065.74)
        XCTAssertThrowsError(try QuoteParser.eastmoney(Data(#"{"data":{"code":"GC","klines":[]}}"#.utf8)))
    }
}
