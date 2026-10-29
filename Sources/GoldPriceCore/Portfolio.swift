import Foundation

public enum TradeKind: String, Codable, CaseIterable {
    case buy, sell
}

public struct Trade: Codable, Identifiable, Equatable {
    public var id: UUID
    public var date: Date
    public var kind: TradeKind
    public var grams: Decimal
    public var pricePerGram: Decimal
    /// The explicit total fee, excluding a spread already included in the price.
    public var fee: Decimal

    public init(id: UUID = UUID(), date: Date = Date(), kind: TradeKind,
                grams: Decimal, pricePerGram: Decimal, fee: Decimal = 0) {
        self.id = id
        self.date = date
        self.kind = kind
        self.grams = grams
        self.pricePerGram = pricePerGram
        self.fee = fee
    }
}

public enum PortfolioError: LocalizedError, Equatable {
    case invalidTrade
    case insufficientGrams

    public var errorDescription: String? {
        switch self {
        case .invalidTrade: return "克数和成交单价须大于 0，手续费不能小于 0。"
        case .insufficientGrams: return "这笔卖出的克数超过了当时的持仓，请检查交易日期和数量。"
        }
    }
}

public struct Portfolio: Equatable {
    public private(set) var grams: Decimal = 0
    public private(set) var remainingCost: Decimal = 0
    public private(set) var realizedProfit: Decimal = 0

    public var averageCost: Decimal { grams > 0 ? remainingCost / grams : 0 }

    public func unrealizedProfit(sellPrice: Decimal) -> Decimal {
        grams * sellPrice - remainingCost
    }

    public func unrealizedReturn(sellPrice: Decimal) -> Decimal? {
        remainingCost > 0 ? unrealizedProfit(sellPrice: sellPrice) / remainingCost * 100 : nil
    }

    /// Moving weighted-average cost. Selling removes proportional cost and never
    /// changes the cost per gram of the remaining position.
    public static func calculate(_ trades: [Trade]) throws -> Portfolio {
        var result = Portfolio()
        let ordered = trades.enumerated().sorted {
            $0.element.date == $1.element.date
                ? $0.offset < $1.offset
                : $0.element.date < $1.element.date
        }
        for (_, trade) in ordered {
            guard !trade.grams.isNaN, !trade.pricePerGram.isNaN, !trade.fee.isNaN,
                  trade.grams > 0, trade.pricePerGram > 0, trade.fee >= 0 else {
                throw PortfolioError.invalidTrade
            }
            switch trade.kind {
            case .buy:
                result.grams += trade.grams
                result.remainingCost += trade.grams * trade.pricePerGram + trade.fee
            case .sell:
                guard trade.grams <= result.grams else { throw PortfolioError.insufficientGrams }
                let disposedCost = result.averageCost * trade.grams
                result.realizedProfit += trade.grams * trade.pricePerGram - trade.fee - disposedCost
                result.grams -= trade.grams
                result.remainingCost = result.grams == 0 ? 0 : result.remainingCost - disposedCost
            }
        }
        return result
    }
}
