import Foundation
import GoldPriceCore

struct GoldPriceService {
    private func request(_ request: URLRequest) async throws -> Data {
        var request = request
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MarketDataError.invalidResponse
        }
        return data
    }

    func cmbQuotes() async throws -> [MarketQuote] {
        var req = URLRequest(url: URL(string: "https://mbmodule-openapi.paas.cmbchina.com/product/v1/func/market-center")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue("https://mbmodule-openapi.paas.cmbchina.com/", forHTTPHeaderField: "Referer")
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "params", value: #"[{"prdType":"H","prdCode":""}]"#)]
        req.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        return try QuoteParser.cmb(await request(req))
    }

    func londonQuote() async throws -> MarketQuote {
        var req = URLRequest(url: URL(string: "https://hq.sinajs.cn/list=hf_XAU")!)
        req.setValue("https://finance.sina.com.cn/", forHTTPHeaderField: "Referer")
        return try QuoteParser.london(await request(req))
    }

    func history(market: TrendMarket, intraday: Bool) async throws -> [PricePoint] {
        let interval = intraday ? 1 : 101
        let limit = intraday ? 1500 : 10000
        let queries = ["lmt=\(limit)", "beg=0&lmt=\(intraday ? 1500 : 400)"]
        // Keep the native minute client; switch clients once on a transient failure.
        for attempt in 0..<2 {
            do {
                let url = URL(string: "https://push2his.eastmoney.com/api/qt/stock/kline/get?secid=\(market.securityID)&klt=\(interval)&fqt=0&\(queries[attempt])&end=20500101&fields1=f1,f2,f3,f4,f5,f6&fields2=f51,f52,f53,f54,f55,f56")!
                let data: Data
                if intraday == (attempt == 0) {
                    var req = URLRequest(url: url)
                    req.setValue("https://quote.eastmoney.com/", forHTTPHeaderField: "Referer")
                    req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
                    data = try await request(req)
                } else { data = try await downloadHistory(url) }
                return try QuoteParser.eastmoney(data, market: market)
            } catch {
                guard attempt == 0, !Task.isCancelled else { throw error }
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        throw MarketDataError.noData
    }

    private func downloadHistory(_ url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let process = Process()
                    let output = Pipe()
                    let errors = Pipe()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                    process.arguments = [
                        "--fail", "--silent", "--show-error",
                        "--connect-timeout", "5", "--max-time", "20",
                        url.absoluteString
                    ]
                    process.standardOutput = output
                    process.standardError = errors
                    try process.run()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0 else {
                        let detail = String(data: errorData, encoding: .utf8) ?? "历史行情暂时不可用。"
                        throw NSError(domain: "GoldPrice.History", code: Int(process.terminationStatus),
                                      userInfo: [NSLocalizedDescriptionKey: detail])
                    }
                    continuation.resume(returning: data)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
