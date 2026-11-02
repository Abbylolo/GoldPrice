import Foundation

public enum QuoteChannel: String, Codable, CaseIterable, Identifiable {
    case cmbBuy, cmbSell, london
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .cmbBuy: return "招行 · 客户买入"
        case .cmbSell: return "招行 · 客户卖出"
        case .london: return "伦敦现货金"
        }
    }
    public var shortTitle: String {
        switch self {
        case .cmbBuy: return "招行买"
        case .cmbSell: return "招行卖"
        case .london: return "伦敦金"
        }
    }
    public var unit: String { self == .london ? "美元/盎司" : "元/克" }
    public var isDomestic: Bool { self != .london }
}

/// A chart instrument is separate from a bank's customer quote channel.
public enum TrendMarket: String, CaseIterable, Identifiable {
    case domestic, london
    public var id: String { rawValue }
    public var title: String { self == .domestic ? "上金所 Au99.99" : "伦敦现货金" }
    public var unit: String { self == .domestic ? "元/克" : "美元/盎司" }
    public var providerCode: String { self == .domestic ? "AU9999" : "XAU" }
    public var securityID: String { self == .domestic ? "118.AU9999" : "122.XAU" }
}

public struct MarketQuote: Codable, Equatable {
    public var channel: QuoteChannel
    public var price: Decimal
    public var previousClose: Decimal?
    public var timestamp: Date
    public var receivedAt: Date
    public var isMarketOpen: Bool?

    public init(channel: QuoteChannel, price: Decimal, previousClose: Decimal? = nil,
                timestamp: Date, receivedAt: Date = Date(), isMarketOpen: Bool? = nil) {
        self.channel = channel
        self.price = price
        self.previousClose = previousClose
        self.timestamp = timestamp
        self.receivedAt = receivedAt
        self.isMarketOpen = isMarketOpen
    }

    public var changePercent: Decimal? {
        guard let previousClose, previousClose > 0 else { return nil }
        return (price - previousClose) / previousClose * 100
    }

    public func isFresh(at now: Date) -> Bool {
        let sourceAge = now.timeIntervalSince(timestamp)
        return sourceAge >= -60 && sourceAge <= 120 && now.timeIntervalSince(receivedAt) <= 120
    }
}

public struct PricePoint: Codable, Identifiable, Equatable, Sendable {
    public var date: Date
    public var value: Double
    public var id: Date { date }
    public init(date: Date, value: Double) { self.date = date; self.value = value }
}

public enum TrendRange: String, CaseIterable, Identifiable {
    case day = "当日", month = "1月", quarter = "3月", halfYear = "6月", year = "1年", all = "全部"
    public var id: String { rawValue }
    public func start(at now: Date = Date()) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        switch self {
        case .day: return calendar.startOfDay(for: now)
        case .month: return calendar.date(byAdding: .month, value: -1, to: now)
        case .quarter: return calendar.date(byAdding: .month, value: -3, to: now)
        case .halfYear: return calendar.date(byAdding: .month, value: -6, to: now)
        case .year: return calendar.date(byAdding: .year, value: -1, to: now)
        case .all: return nil
        }
    }
}

public enum AlertDirection: String, Codable, CaseIterable, Identifiable {
    case above = "达到或高于", below = "达到或低于"
    public var id: String { rawValue }
    public var symbol: String { self == .above ? "≥" : "≤" }
}

public struct PriceRule: Codable, Identifiable, Equatable {
    public var id: UUID
    public var channel: QuoteChannel
    public var direction: AlertDirection
    public var target: Decimal
    public var isEnabled: Bool
    public var firedAt: Date?

    public init(id: UUID = UUID(), channel: QuoteChannel, direction: AlertDirection,
                target: Decimal, isEnabled: Bool = true, firedAt: Date? = nil) {
        self.id = id; self.channel = channel; self.direction = direction
        self.target = target; self.isEnabled = isEnabled; self.firedAt = firedAt
    }

    /// One-shot rules: the caller persists isEnabled=false after delivery.
    public func shouldFire(for quote: MarketQuote, at now: Date) -> Bool {
        guard isEnabled, target > 0, quote.channel == channel,
              quote.isFresh(at: now), quote.isMarketOpen != false else { return false }
        return direction == .above ? quote.price >= target : quote.price <= target
    }
}

public enum MarketDataError: LocalizedError {
    case invalidResponse, noData
    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "行情返回格式暂时不可用。"
        case .noData: return "这个时段暂时没有行情数据。"
        }
    }
}

public enum QuoteParser {
    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        formatter.dateFormat = format
        return formatter
    }

    public static func date(_ string: String, formats: [String]) -> Date? {
        for format in formats {
            if let date = formatter(format).date(from: string) { return date }
        }
        return nil
    }

    public static func cmb(_ data: Data, receivedAt: Date = Date()) throws -> [MarketQuote] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["success"] as? Bool == true,
              let body = json["data"] as? [String: Any],
              let values = body["FQAMBPRCZ1"] as? [String: Any],
              let buyString = values["zBuyPrc"] as? String,
              let sellString = values["zSelPrc"] as? String,
              let buy = Decimal(string: buyString), buy > 0,
              let sell = Decimal(string: sellString), sell > 0,
              let time = body["NowTime"] as? String,
              let timestamp = date(time, formats: ["yyyy/MM/dd HH:mm:ss", "yyyy-MM-dd HH:mm:ss"])
        else { throw MarketDataError.invalidResponse }
        let open = (body["MarketDay"] as? Bool).flatMap { marketDay in
            (body["QuotedPrice"] as? Bool).map { marketDay && $0 }
        }
        return [MarketQuote(channel: .cmbBuy, price: buy, timestamp: timestamp, receivedAt: receivedAt, isMarketOpen: open),
                MarketQuote(channel: .cmbSell, price: sell, timestamp: timestamp, receivedAt: receivedAt, isMarketOpen: open)]
    }

    public static func london(_ data: Data, receivedAt: Date = Date()) throws -> MarketQuote {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              let start = text.firstIndex(of: "\""), let end = text.lastIndex(of: "\""), start < end
        else { throw MarketDataError.invalidResponse }
        let fields = text[text.index(after: start)..<end].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard fields.count > 12, let price = Decimal(string: fields[0]), price > 0,
              let timestamp = date("\(fields[12]) \(fields[6])", formats: ["yyyy-MM-dd HH:mm:ss"])
        else { throw MarketDataError.invalidResponse }
        let previous = Decimal(string: fields[7]) ?? Decimal(string: fields[1])
        return MarketQuote(channel: .london, price: price, previousClose: previous,
                           timestamp: timestamp, receivedAt: receivedAt)
    }

    public static func eastmoney(_ data: Data, market: TrendMarket = .london) throws -> [PricePoint] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = json["data"] as? [String: Any], body["code"] as? String == market.providerCode,
              let rows = body["klines"] as? [String] else { throw MarketDataError.noData }
        let dailyFormatter = formatter("yyyy-MM-dd")
        let minuteFormatter = formatter("yyyy-MM-dd HH:mm")
        let points = rows.compactMap { row -> PricePoint? in
            let fields = row.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3,
                  let date = (fields[0].count > 10 ? minuteFormatter : dailyFormatter).date(from: String(fields[0])),
                  let close = Double(fields[2]), close.isFinite, close > 0 else { return nil }
            return PricePoint(date: date, value: close)
        }
        guard !points.isEmpty else { throw MarketDataError.noData }
        return points.sorted { $0.date < $1.date }
    }
}

public extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
