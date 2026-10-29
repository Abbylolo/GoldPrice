import AppKit
import Combine
import Foundation
import GoldPriceCore
import ServiceManagement
import UserNotifications
import UniformTypeIdentifiers

struct AppPreferences: Codable {
    var displayChannel: QuoteChannel = .cmbSell
    var refreshSeconds: Int = 15
}

private struct SavedState: Codable {
    var schemaVersion: Int = 1
    var preferences = AppPreferences()
    var quotes: [String: MarketQuote] = [:]
    var localHistory: [String: [PricePoint]] = [:]
    var londonDaily: [PricePoint] = []
    var londonMinutes: [PricePoint] = []
    var dailyFetchedAt: Date?
    var trades: [Trade] = []
    var alerts: [PriceRule] = []
}

@MainActor
final class AppStore: ObservableObject {
    @Published var preferences = AppPreferences()
    @Published private(set) var quotes: [String: MarketQuote] = [:]
    @Published private(set) var trades: [Trade] = []
    @Published private(set) var alerts: [PriceRule] = []
    @Published private(set) var localHistory: [String: [PricePoint]] = [:]
    @Published private(set) var londonDaily: [PricePoint] = []
    @Published private(set) var londonMinutes: [PricePoint] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingHistory = false
    @Published private(set) var channelErrors: [String: String] = [:]
    @Published var message: String?
    @Published var activeTab: AppTab = .market
    @Published var chartChannel: QuoteChannel = .cmbSell
    @Published var chartRange: TrendRange = .day
    @Published private(set) var notificationAllowed = false
    @Published private(set) var loginEnabled = false

    private let service = GoldPriceService()
    private let stateURL: URL
    private var timer: Timer?
    private var historyFetchedAt: Date?
    private var dailyFetchedAt: Date?
    private var notificationsInFlight = Set<UUID>()
    private var persistenceBlocked = false

    init() {
        let defaultDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GoldPricePersonal", isDirectory: true)
        let args = CommandLine.arguments
        let customIndex = args.firstIndex(of: "--data-directory")
        let directory: URL
        if let customIndex, args.indices.contains(customIndex + 1) {
            directory = URL(fileURLWithPath: args[customIndex + 1], isDirectory: true)
        } else { directory = defaultDirectory }
        stateURL = directory.appendingPathComponent("state.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: stateURL.path) {
                let state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: stateURL))
                guard state.schemaVersion == 1 else { throw MarketDataError.invalidResponse }
                _ = try Portfolio.calculate(state.trades)
                preferences = state.preferences
                preferences.refreshSeconds = [5, 15, 30, 60].contains(preferences.refreshSeconds) ? preferences.refreshSeconds : 15
                quotes = state.quotes
                trades = state.trades
                alerts = state.alerts
                localHistory = state.localHistory
                londonDaily = state.londonDaily
                londonMinutes = state.londonMinutes
                dailyFetchedAt = state.dailyFetchedAt
            }
        } catch {
            // A broken file must never be silently overwritten with an empty portfolio.
            persistenceBlocked = true
            message = "本地数据读取失败，已停止写入以保护原文件。请先导出数据备份。"
        }
        chartChannel = preferences.displayChannel
        loginEnabled = Bundle.main.bundleIdentifier != nil && SMAppService.mainApp.status == .enabled
    }

    var portfolio: Portfolio { (try? Portfolio.calculate(trades)) ?? PortfolioFallback.empty }

    func start() {
        updateTimer()
        Task {
            await updateNotificationPermission()
            await refresh()
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.refresh() }
        }
    }

    func quote(_ channel: QuoteChannel) -> MarketQuote? { quotes[channel.rawValue] }

    func setDisplayChannel(_ channel: QuoteChannel) {
        preferences.displayChannel = channel
        save()
    }

    func setRefreshSeconds(_ seconds: Int) {
        preferences.refreshSeconds = seconds
        save()
        updateTimer()
    }

    private func updateTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: TimeInterval(preferences.refreshSeconds), repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh(forceHistory: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        async let cmbResult = capture { try await self.service.cmbQuotes() }
        async let londonResult = capture { try await self.service.londonQuote() }
        let (cmb, london) = await (cmbResult, londonResult)
        switch cmb {
        case .success(let values):
            values.forEach { accept($0) }
            channelErrors.removeValue(forKey: "cmb")
        case .failure:
            channelErrors["cmb"] = "招行暂时连接不上，显示最近一次报价。"
        }
        switch london {
        case .success(let value):
            accept(value)
            channelErrors.removeValue(forKey: "london")
        case .failure:
            channelErrors["london"] = "伦敦金暂时连接不上，显示最近一次报价。"
        }
        save()
        await checkAlerts()
        if forceHistory || (historyFetchedAt.map({ Date().timeIntervalSince($0) >= 300 }) ?? true) {
            await loadHistory(forceDaily: forceHistory)
        }
    }

    private func accept(_ quote: MarketQuote) {
        quotes[quote.channel.rawValue] = quote
        guard quote.isFresh(at: Date()) else { return }
        let minute = floor(quote.timestamp.timeIntervalSince1970 / 60) * 60
        var points = localHistory[quote.channel.rawValue] ?? []
        let point = PricePoint(date: Date(timeIntervalSince1970: minute), value: quote.price.doubleValue)
        if let last = points.last, last.date == point.date {
            points[points.count - 1] = point
        } else if points.last.map({ $0.date < point.date }) ?? true {
            points.append(point)
        }
        // Keep recent minute points and older daily closes, without inventing gaps.
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        var daily: [String: PricePoint] = [:]
        var recent: [PricePoint] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        for p in points {
            if p.date >= cutoff { recent.append(p) }
            else { daily[formatter.string(from: p.date)] = p }
        }
        localHistory[quote.channel.rawValue] = daily.values.sorted { $0.date < $1.date } + recent
    }

    func loadHistory(forceDaily: Bool = false) async {
        guard !isLoadingHistory else { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        let needsDaily = forceDaily || londonDaily.isEmpty || !(dailyFetchedAt.map { Calendar.current.isDateInToday($0) } ?? false)
        let daily: Result<[PricePoint], Error> = needsDaily
            ? await capture { try await self.service.londonHistory(intraday: false) }
            : .success(londonDaily)
        let minutes = await capture { try await self.service.londonHistory(intraday: true) }
        if case .success(let points) = daily {
            londonDaily = points
            if needsDaily { dailyFetchedAt = Date() }
        }
        if case .success(let points) = minutes { londonMinutes = points }
        if case .failure(let error) = daily {
            NSLog("[GoldPrice] 伦敦日线加载失败：%@", error.localizedDescription)
            channelErrors["history"] = "伦敦日线暂时连接不上，可点击右上角刷新重试。"
        } else if case .failure(let error) = minutes {
            NSLog("[GoldPrice] 伦敦分钟线加载失败：%@", error.localizedDescription)
            channelErrors["history"] = "伦敦分钟线暂时连接不上，可点击右上角刷新重试。"
        } else { channelErrors.removeValue(forKey: "history") }
        historyFetchedAt = Date()
        save()
    }

    func chartPoints(channel: QuoteChannel, range: TrendRange) -> [PricePoint] {
        let points: [PricePoint]
        if channel == .london {
            points = range == .day ? londonMinutes : londonDaily
        } else {
            points = localHistory[channel.rawValue] ?? []
        }
        let start = range.start()
        let filtered = points.filter { (start == nil || $0.date >= start!) && $0.date <= Date() }
        // Bound drawing work for the 30+ year chart while retaining first and last.
        guard filtered.count > 600 else { return filtered }
        let step = Double(filtered.count - 1) / 599
        return (0..<600).map { filtered[Int((Double($0) * step).rounded())] }
    }

    func addTrade(_ trade: Trade) throws {
        let candidate = trades + [trade]
        _ = try Portfolio.calculate(candidate)
        try ensureWritable()
        let original = trades
        trades = candidate
        do { try persist() } catch { trades = original; throw error }
    }

    func removeTrade(_ id: UUID) throws {
        let candidate = trades.filter { $0.id != id }
        _ = try Portfolio.calculate(candidate)
        try ensureWritable()
        let original = trades
        trades = candidate
        do { try persist() } catch { trades = original; throw error }
    }

    func addAlert(_ rule: PriceRule) async throws {
        try ensureWritable()
        guard Bundle.main.bundleIdentifier != nil else { throw AppError.bundleRequired }
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        notificationAllowed = granted
        guard granted else { throw AppError.notificationsDenied }
        let original = alerts
        alerts.append(rule)
        do { try persist() } catch { alerts = original; throw error }
    }

    func toggleAlert(_ id: UUID, enabled: Bool) {
        guard let i = alerts.firstIndex(where: { $0.id == id }) else { return }
        alerts[i].isEnabled = enabled
        if enabled { alerts[i].firedAt = nil }
        save()
    }

    func removeAlert(_ id: UUID) {
        alerts.removeAll { $0.id == id }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        save()
    }

    func updateNotificationPermission() async {
        guard Bundle.main.bundleIdentifier != nil else { notificationAllowed = false; return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAllowed = settings.authorizationStatus == .authorized
    }

    private func checkAlerts() async {
        guard Bundle.main.bundleIdentifier != nil else { return }
        await updateNotificationPermission()
        guard notificationAllowed else { return }
        for rule in alerts {
            guard !notificationsInFlight.contains(rule.id),
                  let quote = quote(rule.channel), rule.shouldFire(for: quote, at: Date()) else { continue }
            notificationsInFlight.insert(rule.id)
            defer { notificationsInFlight.remove(rule.id) }
            let content = UNMutableNotificationContent()
            content.title = "金价到啦 · \(rule.channel.shortTitle)"
            content.body = "当前 \(String(format: "%.2f", quote.price.doubleValue)) \(rule.channel.unit)，已达到 \(rule.direction.symbol) \(String(format: "%.2f", rule.target.doubleValue))。"
            content.sound = .default
            do {
                try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: rule.id.uuidString, content: content, trigger: nil))
                if let index = alerts.firstIndex(where: { $0.id == rule.id }) {
                    alerts[index].isEnabled = false
                    alerts[index].firedAt = Date()
                    save()
                }
            } catch {
                message = "到价提醒未发出，请检查系统通知权限。"
            }
        }
    }

    func setLoginEnabled(_ enabled: Bool) {
        guard Bundle.main.bundleIdentifier != nil else { message = AppError.bundleRequired.localizedDescription; return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if enabled && !loginEnabled { message = "请在系统设置 → 通用 → 登录项中允许 GoldPrice。" }
        } catch { message = "自启设置未保存。请将应用放入“应用程序”后重试：\(error.localizedDescription)" }
    }

    func exportData() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "GoldPrice-备份.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if persistenceBlocked {
                try Data(contentsOf: stateURL).write(to: url, options: .atomic)
            } else {
                try JSONEncoder().encode(state()).write(to: url, options: .atomic)
            }
        } catch { message = "导出失败：\(error.localizedDescription)" }
    }

    private func state() -> SavedState {
        SavedState(preferences: preferences, quotes: quotes, localHistory: localHistory,
                   londonDaily: londonDaily, londonMinutes: londonMinutes, dailyFetchedAt: dailyFetchedAt,
                   trades: trades, alerts: alerts)
    }
    private func ensureWritable() throws {
        if persistenceBlocked { throw AppError.storageUnavailable }
    }
    private func persist() throws {
        try ensureWritable()
        try JSONEncoder().encode(state()).write(to: stateURL, options: .atomic)
    }
    private func save() {
        do { try persist() } catch { message = "数据未能保存：\(error.localizedDescription)" }
    }

    private func capture<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }
}

private enum PortfolioFallback {
    static let empty = try! Portfolio.calculate([])
}

enum AppError: LocalizedError {
    case notificationsDenied, storageUnavailable, bundleRequired
    var errorDescription: String? {
        switch self {
        case .notificationsDenied: return "请在系统设置 → 通知 → GoldPrice 中允许通知，再添加提醒。"
        case .storageUnavailable: return "本地数据文件暂时不可读，已停止写入以保护原文件。"
        case .bundleRequired: return "请使用打包后的 GoldPrice 应用来设置系统通知和登录自启。"
        }
    }
}
