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
    func testDomesticHistoryUsesAu9999ClosingPricesInDateOrder() throws {
        let data = Data(#"{"data":{"code":"AU9999","klines":["2026-11-02,851,837.5,855,836,50","2004-01-02,111,111.18,111.2,111,50"]}}"#.utf8)
        let points = try QuoteParser.eastmoney(data, market: .domestic)
        XCTAssertEqual(points.map(\.value), [111.18, 837.5])
        XCTAssertEqual(points.first?.date, QuoteParser.date("2004-01-02", formats: ["yyyy-MM-dd"]))
        XCTAssertThrowsError(try QuoteParser.eastmoney(data, market: .london))
    }

    func testDomesticHistoryRejectsBankSubstitutesAndEmptyResponses() throws {
        for code in ["XAU", "GC", "AU0"] {
            let data = Data("{\"data\":{\"code\":\"\(code)\",\"klines\":[\"2026-11-02,851,837.5\"]}}".utf8)
            XCTAssertThrowsError(try QuoteParser.eastmoney(data, market: .domestic))
        }
        XCTAssertThrowsError(try QuoteParser.eastmoney(Data(#"{"data":null}"#.utf8), market: .domestic))
        XCTAssertThrowsError(try QuoteParser.eastmoney(Data(#"{"data":{"code":"AU9999","klines":[]}}"#.utf8), market: .domestic))
    }

    func testDomesticMinuteHistorySkipsInvalidPrices() throws {
        let data = Data(#"{"data":{"code":"AU9999","klines":["2026-11-02 09:31,840,837.5,841,836,1","bad row","2026-11-02 09:32,840,nan","2026-11-02 09:33,840,-1"]}}"#.utf8)
        let points = try QuoteParser.eastmoney(data, market: .domestic)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.value, 837.5)
        XCTAssertEqual(points.first?.date, QuoteParser.date("2026-11-02 09:31", formats: ["yyyy-MM-dd HH:mm"]))
    }

}
