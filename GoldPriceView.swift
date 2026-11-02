import SwiftUI
import Charts
import GoldPriceCore

enum AppTab: String, CaseIterable {
    case market = "行情", portfolio = "持仓", alerts = "提醒", settings = "设置"
    var icon: String {
        switch self {
        case .market: return "chart.xyaxis.line"
        case .portfolio: return "tray.full"
        case .alerts: return "bell"
        case .settings: return "slider.horizontal.3"
        }
    }
}

enum PanelLayout {
    static let width: CGFloat = 380
    static let height: CGFloat = 580
}

enum Palette {
    static let gold = Color(red: 0.72, green: 0.48, blue: 0.15)
    static let lilac = Color(red: 0.58, green: 0.46, blue: 0.75)
    static let mint = Color(red: 0.26, green: 0.59, blue: 0.48)
    static let rise = Color(red: 0.80, green: 0.36, blue: 0.38)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let background = Color(nsColor: .windowBackgroundColor)
}

private func money(_ number: Decimal, digits: Int = 2, signed: Bool = false) -> String {
    String(format: signed ? "%+.\(digits)f" : "%.\(digits)f", number.doubleValue)
}

private func number(_ text: String) -> Decimal? {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard clean.range(of: #"^[0-9]+(?:\.[0-9]{1,8})?$"#, options: .regularExpression) != nil else { return nil }
    return Decimal(string: clean, locale: Locale(identifier: "en_US_POSIX"))
}

private struct SoftCard: ViewModifier {
    var tint: Color = .clear
    func body(content: Content) -> some View {
        content.padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface)
            .overlay(RoundedRectangle(cornerRadius: 14).fill(tint.opacity(0.06)))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.045), lineWidth: 1))
    }
}

private struct GoldBuddy: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(LinearGradient(colors: [Color(red: 1, green: 0.86, blue: 0.49), Color(red: 0.98, green: 0.73, blue: 0.38)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 32, height: 32)
            .rotationEffect(.degrees(-5))
            .overlay(VStack(spacing: 6) {
                HStack(spacing: 10) { Circle().frame(width: 3.5, height: 3.5); Circle().frame(width: 3.5, height: 3.5) }
                Capsule().frame(width: 7, height: 2)
            }.foregroundStyle(Color.brown.opacity(0.8)))
            .overlay(alignment: .topTrailing) { Image(systemName: "sparkle").font(.system(size: 11)).foregroundStyle(Palette.gold).offset(x: 5, y: -4) }
            .accessibilityLabel("小金块")
    }
}

@MainActor
struct GoldPriceView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                GoldBuddy()
                VStack(alignment: .leading, spacing: 3) {
                    Text("GoldPrice").font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("招行黄金账户 · 伦敦现货").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await store.refresh(forceHistory: true) } } label: {
                    Group {
                        if store.isRefreshing { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.clockwise").font(.system(size: 14, weight: .medium)) }
                    }.frame(width: 30, height: 30)
                }
                .buttonStyle(.plain).disabled(store.isRefreshing).help("刷新行情")
            }.padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)

            HStack(spacing: 5) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Button { store.activeTab = tab } label: {
                        Label(tab.rawValue, systemImage: tab.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(store.activeTab == tab ? Palette.surface : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(store.activeTab == tab ? Palette.gold : .secondary)
                    }.buttonStyle(.plain)
                }
            }.padding(4).background(Color.primary.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 12).padding(.bottom, 9)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let message = store.message {
                        HStack(alignment: .top) {
                            Image(systemName: "info.circle").foregroundStyle(Palette.gold)
                            Text(message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 2)
                            Button { store.message = nil } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain)
                        }.padding(12).background(Palette.gold.opacity(0.09)).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    switch store.activeTab {
                    case .market:
                        MarketScreen(store: store)
                    case .portfolio: PortfolioScreen(store: store)
                    case .alerts: AlertsScreen(store: store)
                    case .settings: SettingsScreen(store: store)
                    }
                }.padding(.horizontal, 12).padding(.bottom, 10)
            }

            HStack {
                Circle().fill(store.isRefreshing ? Palette.gold : Palette.mint).frame(width: 5, height: 5)
                Text(store.isRefreshing ? "正在更新行情" : "每 \(store.preferences.refreshSeconds) 秒更新")
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }.buttonStyle(.plain)
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 15).padding(.vertical, 8)
        }
        .frame(width: PanelLayout.width, height: PanelLayout.height)
        .background(Palette.background)
        .tint(Palette.gold)
    }
}

@MainActor
private struct MarketScreen: View {
    @ObservedObject var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sourceButton("国内黄金", market: .domestic)
                sourceButton("伦敦现货", market: .london)
                Spacer()
            }
            if store.chartMarket == .domestic {
                HStack(spacing: 8) {
                    QuoteCard(store: store, channel: .cmbBuy)
                    QuoteCard(store: store, channel: .cmbSell)
                }
            } else { QuoteCard(store: store, channel: .london) }

            if let error = store.channelErrors[store.chartMarket == .domestic ? "cmb" : "london"] {
                Label(error, systemImage: "wifi.exclamationmark").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let error = store.channelErrors["\(store.chartMarket.rawValue)-\(store.chartRange == .day ? "minute" : "daily")"] {
                Label(error, systemImage: "chart.line.downtrend.xyaxis").font(.system(size: 11)).foregroundStyle(.secondary)
            }

            TrendCard(snapshot: store.trendSnapshot, market: store.chartMarket, range: store.chartRange,
                      isLoading: store.isLoadingHistory, selectRange: { store.chartRange = $0 })
                .id("\(store.chartMarket.rawValue)-\(store.chartRange.rawValue)")
        }
    }

    private func sourceButton(_ title: String, market: TrendMarket) -> some View {
        let selected = store.chartMarket == market
        return Button { store.chartMarket = market } label: {
            Text(title).font(.system(size: 11, weight: selected ? .semibold : .regular))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(selected ? Palette.gold.opacity(0.11) : .clear)
                .foregroundStyle(selected ? Palette.gold : .secondary).clipShape(Capsule())
        }.buttonStyle(.plain)
    }
}

private struct TrendCard: View {
    let snapshot: TrendSnapshot
    let market: TrendMarket
    let range: TrendRange
    let isLoading: Bool
    let selectRange: (TrendRange) -> Void
    @State private var inspectedPoint: PricePoint?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("金价趋势").font(.system(size: 13, weight: .semibold))
                    Text("\(market.title) · \(market.unit)").font(.system(size: 9)).foregroundStyle(.secondary)
                    Text("公开历史 · 东方财富").font(.system(size: 8)).foregroundStyle(Palette.gold)
                }
                Spacer(minLength: 4)
                if let inspectedPoint {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(String(format: "%.2f", inspectedPoint.value))
                            .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text(inspectedPoint.date, format: .dateTime.year().month().day().hour().minute())
                            .font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            HStack(spacing: 2) {
                ForEach(TrendRange.allCases) { item in
                    Button { selectRange(item) } label: {
                        Text(item.rawValue).font(.system(size: 10, weight: .medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(range == item ? Palette.gold.opacity(0.13) : .clear)
                            .foregroundStyle(range == item ? Palette.gold : .secondary)
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
            if snapshot.points.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: isLoading ? "hourglass" : "chart.line.uptrend.xyaxis")
                        .font(.system(size: 22)).foregroundStyle(Palette.gold.opacity(0.6))
                    Text(isLoading ? "正在读取历史行情…" : "暂无行情，可刷新重试")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).frame(height: 145)
            } else {
                TrendPlot(snapshot: snapshot, onInspection: { inspectedPoint = $0 })
                    .equatable().frame(height: 145)
                if let first = snapshot.points.first, let last = snapshot.points.last {
                    HStack {
                        Text(first.date, format: .dateTime.year().month().day())
                        Spacer()
                        Text(last.date, format: .dateTime.year().month().day())
                    }.font(.system(size: 8)).foregroundStyle(.tertiary)
                }
            }
            Text(market == .domestic
                 ? "上金所 Au99.99 行情，与招行买卖报价存在价差。"
                 : "伦敦现货 XAU · 美元/盎司")
                .font(.system(size: 9)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.modifier(SoftCard())
    }
}

/// Hover changes only the overlay and readout; keep the 600-point plot intact.
private struct TrendPlot: View, Equatable {
    let snapshot: TrendSnapshot
    let onInspection: (PricePoint?) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.snapshot == rhs.snapshot }

    var body: some View {
        Chart {
            ForEach(snapshot.points) { point in
                AreaMark(x: .value("时间", point.date), yStart: .value("下界", snapshot.bounds.lowerBound), yEnd: .value("价格", point.value))
                    .foregroundStyle(LinearGradient(colors: [Palette.gold.opacity(0.19), Palette.gold.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("时间", point.date), y: .value("价格", point.value))
                    .foregroundStyle(Palette.gold).lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            if snapshot.points.count == 1, let point = snapshot.points.first {
                PointMark(x: .value("时间", point.date), y: .value("价格", point.value)).foregroundStyle(Palette.gold)
            }
        }
        .chartYScale(domain: snapshot.bounds)
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(anchor: .top) {
                    if let date = value.as(Date.self) {
                        Text(date, format: axisFormat).font(.system(size: 8)).fixedSize()
                    }
                }
            }
        }
        .chartOverlay { proxy in
            ChartInspectionOverlay(proxy: proxy, snapshot: snapshot, onInspection: onInspection)
        }
    }

    private var axisFormat: Date.FormatStyle {
        let span = (snapshot.points.last?.date.timeIntervalSince(snapshot.points.first?.date ?? Date())) ?? 0
        let locale = Locale(identifier: "en_US_POSIX")
        if span > 370 * 86400 { return .dateTime.year().locale(locale) }
        if span > 2 * 86400 { return .dateTime.month(.twoDigits).day(.twoDigits).locale(locale) }
        return .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale)
    }
}

private struct ChartInspectionOverlay: View {
    let proxy: ChartProxy
    let snapshot: TrendSnapshot
    let onInspection: (PricePoint?) -> Void
    @State private var selected: PricePoint?

    var body: some View {
        GeometryReader { geometry in
            let plot = geometry[proxy.plotAreaFrame]
            ZStack(alignment: .topLeading) {
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard plot.contains(location), let date: Date = proxy.value(atX: location.x - plot.minX) else {
                                inspect(nil); return
                            }
                            inspect(snapshot.nearest(to: date))
                        case .ended: inspect(nil)
                        }
                    }
                if let selected, let x = proxy.position(forX: selected.date), let y = proxy.position(forY: selected.value) {
                    Path { path in
                        path.move(to: CGPoint(x: plot.minX + x, y: plot.minY))
                        path.addLine(to: CGPoint(x: plot.minX + x, y: plot.maxY))
                    }.stroke(Palette.gold.opacity(0.3), lineWidth: 1).allowsHitTesting(false)
                    Circle().fill(Palette.gold).frame(width: 5, height: 5)
                        .position(x: plot.minX + x, y: plot.minY + y).allowsHitTesting(false)
                }
            }
        }
        .onChange(of: snapshot) { value in
            if let selected { inspect(value.nearest(to: selected.date)) }
        }
    }

    private func inspect(_ point: PricePoint?) {
        guard point != selected else { return }
        selected = point
        onInspection(point)
    }
}

@MainActor
private struct QuoteCard: View {
    @ObservedObject var store: AppStore
    let channel: QuoteChannel
    private var quote: MarketQuote? { store.quote(channel) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(channel == .london ? "伦敦现货金" : channel == .cmbBuy ? "客户买入价" : "客户卖出价")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer(minLength: 5)
                Button { store.setDisplayChannel(channel) } label: {
                    Image(systemName: store.preferences.displayChannel == channel ? "pin.fill" : "pin").font(.system(size: 11))
                }.buttonStyle(.plain).foregroundStyle(Palette.gold).help("将此价格展示在状态栏")
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(quote.map { money($0.price) } ?? "—")
                    .font(.system(size: channel.isDomestic ? 24 : 28, weight: .semibold, design: .rounded)).monospacedDigit()
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text(channel.unit).font(.system(size: 9)).foregroundStyle(.secondary)
            }.textSelection(.enabled)
            HStack(spacing: 4) {
                Circle().fill(quote.map { $0.isFresh(at: Date()) ? Palette.mint : Palette.gold } ?? .secondary).frame(width: 5, height: 5)
                if let quote {
                    Text(quote.isMarketOpen == false ? "非报价时段" : quote.isFresh(at: Date()) ? "最新报价" : "最近报价")
                    Spacer(minLength: 1)
                    Text(quote.timestamp, format: .dateTime.hour().minute().second())
                } else { Text("等待行情") }
            }.font(.system(size: 9)).foregroundStyle(.secondary)
            if let change = quote?.changePercent {
                Text("较昨收 \(money(change, signed: true))%")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(change >= 0 ? Palette.rise : Palette.mint)
            }

        }.modifier(SoftCard(tint: channel == .cmbBuy ? Palette.gold : channel == .cmbSell ? Palette.mint : Palette.lilac))
    }
}

@MainActor
private struct PortfolioScreen: View {
    @ObservedObject var store: AppStore
    @State private var tradeKind: TradeKind?
    @State private var deleting: Trade?
    private var portfolio: Portfolio { store.portfolio }
    private var quote: MarketQuote? { store.quote(.cmbSell) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("持仓浮动收益").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Text("按招行客户卖出价估值").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                if let quote, portfolio.grams > 0 {
                    let profit = portfolio.unrealizedProfit(sellPrice: quote.price)
                    HStack(alignment: .firstTextBaseline) {
                        Text("¥ \(money(profit, signed: true))").font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                        if let rate = portfolio.unrealizedReturn(sellPrice: quote.price) {
                            Text("\(money(rate, signed: true))%").font(.system(size: 12, weight: .medium))
                        }
                    }.foregroundStyle(profit >= 0 ? Palette.rise : Palette.mint)
                } else {
                    Text(portfolio.grams == 0 ? "还没有持仓" : "等待招行报价")
                        .font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                }
                HStack(spacing: 24) {
                    stat("持有克数", "\(money(portfolio.grams, digits: 4)) g")
                    stat("持仓均价", portfolio.grams > 0 ? "¥ \(money(portfolio.averageCost)) /g" : "—")
                }
                Divider().opacity(0.45)
                HStack {
                    stat("持仓市值", quote.map { "¥ \(money(portfolio.grams * $0.price))" } ?? "—")
                    Spacer()
                    stat("已实现收益", "¥ \(money(portfolio.realizedProfit, signed: true))")
                }
                if let quote, !quote.isFresh(at: Date()) {
                    Text("估值采用最近一次报价：\(quote.timestamp.formatted(date: .numeric, time: .shortened))")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.modifier(SoftCard(tint: Palette.lilac))

            HStack(spacing: 10) {
                Button { tradeKind = .buy } label: { Label("记一笔买入", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 7) }
                    .buttonStyle(.borderedProminent)
                Button { tradeKind = .sell } label: { Label("记一笔卖出", systemImage: "minus").frame(maxWidth: .infinity).padding(.vertical, 7) }
                    .buttonStyle(.bordered).disabled(portfolio.grams <= 0)
            }

            HStack { Text("交易记录").font(.system(size: 14, weight: .semibold)); Spacer(); Text("\(store.trades.count) 笔").font(.system(size: 10)).foregroundStyle(.secondary) }
            if store.trades.isEmpty {
                Text("记录实际成交的克数、单价和手续费，持仓均价会自动计算。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).modifier(SoftCard())
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(store.trades.sorted { $0.date > $1.date }) { trade in
                        HStack(spacing: 12) {
                            Text(trade.kind == .buy ? "买" : "卖").font(.system(size: 12, weight: .medium))
                                .foregroundStyle(trade.kind == .buy ? Palette.rise : Palette.mint)
                                .frame(width: 30, height: 30).background((trade.kind == .buy ? Palette.rise : Palette.mint).opacity(0.08)).clipShape(Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(money(trade.grams, digits: 4)) g × ¥\(money(trade.pricePerGram))").font(.system(size: 12, weight: .medium)).monospacedDigit()
                                Text("\(trade.date.formatted(date: .abbreviated, time: .shortened)) · 费用 ¥\(money(trade.fee))").font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Button { deleting = trade } label: { Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.secondary) }.buttonStyle(.plain).help("删除这笔记录")
                        }.padding(12).background(Palette.surface).clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
        .sheet(isPresented: Binding(get: { tradeKind != nil }, set: { if !$0 { tradeKind = nil } })) {
            TradeEditor(store: store, kind: tradeKind ?? .buy)
        }
        .confirmationDialog("删除这笔交易记录？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("删除记录", role: .destructive) {
                if let deleting { do { try store.removeTrade(deleting.id) } catch { store.message = error.localizedDescription } }
                deleting = nil
            }
        } message: { Text("删除后会重新计算持仓。无法删除会导致历史卖出超出持仓的记录。") }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
        }
    }
}

@MainActor
private struct TradeEditor: View {
    @ObservedObject var store: AppStore
    let kind: TradeKind
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var grams = ""
    @State private var price = ""
    @State private var fee = "0"
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(kind == .buy ? "记一笔买入" : "记一笔卖出").font(.system(size: 20, weight: .semibold, design: .rounded))
            Text("录入实际成交，仅用于个人持仓记账。").font(.system(size: 11)).foregroundStyle(.secondary)
            DatePicker("成交时间", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
            field("成交克数", text: $grams, unit: "克")
            field("成交单价", text: $price, unit: "元/克")
            field("手续费合计", text: $fee, unit: "元")
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(Palette.rise).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存记录") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(18).frame(width: 350).tint(Palette.gold)
            .onAppear { price = store.quote(kind == .buy ? .cmbBuy : .cmbSell).map { money($0.price) } ?? "" }
    }

    private func field(_ title: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(title).font(.system(size: 12)).frame(width: 86, alignment: .leading)
            TextField("请输入", text: text).textFieldStyle(.roundedBorder)
            Text(unit).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 35, alignment: .leading)
        }
    }

    private func save() {
        guard let grams = number(grams), let price = number(price), let fee = number(fee) else {
            error = "请填写有效数字，最多支持 8 位小数。"; return
        }
        do {
            try store.addTrade(Trade(date: date, kind: kind, grams: grams, pricePerGram: price, fee: fee))
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

@MainActor
private struct AlertsScreen: View {
    @ObservedObject var store: AppStore
    @State private var channel: QuoteChannel = .cmbSell
    @State private var direction: AlertDirection = .above
    @State private var target = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                Label("到价提醒", systemImage: "bell.badge").font(.system(size: 15, weight: .semibold))
                Picker("金价渠道", selection: $channel) { ForEach(QuoteChannel.allCases) { Text($0.title).tag($0) } }
                HStack {
                    Picker("条件", selection: $direction) { ForEach(AlertDirection.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 125)
                    TextField("目标价格", text: $target).textFieldStyle(.roundedBorder)
                    Text(channel.unit).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if let error { Text(error).font(.system(size: 11)).foregroundStyle(Palette.rise).fixedSize(horizontal: false, vertical: true) }
                Button {
                    guard let value = number(target), value > 0 else { error = "请填写大于 0 的目标价格。"; return }
                    isSaving = true
                    error = nil
                    Task {
                        do {
                            try await store.addAlert(PriceRule(channel: channel, direction: direction, target: value))
                            target = ""
                        } catch { self.error = error.localizedDescription }
                        isSaving = false
                    }
                } label: { Text(isSaving ? "正在保存…" : "添加提醒").frame(maxWidth: .infinity).padding(.vertical, 5) }
                    .buttonStyle(.borderedProminent).disabled(isSaving)
                Text("每条提醒到价后通知一次；重新开启可再次提醒。价格已经满足条件时，将在下次成功刷新后通知。")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.modifier(SoftCard(tint: Palette.lilac))

            HStack {
                Text("我的提醒").font(.system(size: 14, weight: .semibold))
                Spacer()
                Label(store.notificationAllowed ? "系统通知已允许" : "添加时需允许系统通知", systemImage: store.notificationAllowed ? "checkmark.circle" : "bell.slash")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            if store.alerts.isEmpty {
                Text("设置一个你关心的价格，到了就提醒你。").font(.system(size: 12)).foregroundStyle(.secondary).modifier(SoftCard())
            }
            ForEach(store.alerts) { rule in
                HStack(spacing: 12) {
                    Image(systemName: rule.firedAt == nil ? "bell" : "checkmark.circle").foregroundStyle(Palette.gold)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(rule.channel.shortTitle) \(rule.direction.symbol) \(money(rule.target))").font(.system(size: 13, weight: .medium))
                        Text(rule.firedAt.map { "已提醒 · \($0.formatted(date: .abbreviated, time: .shortened))" } ?? (rule.isEnabled ? "等待到价 · \(rule.channel.unit)" : "已暂停"))
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 2)
                    Toggle("开启提醒", isOn: Binding(get: { rule.isEnabled }, set: { store.toggleAlert(rule.id, enabled: $0) })).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    Button { store.removeAlert(rule.id) } label: { Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.secondary) }.buttonStyle(.plain).help("删除提醒")
                }.padding(14).background(Palette.surface).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            Text("应用需运行且 Mac 处于唤醒状态。过期报价不会触发提醒；专注模式可能影响通知展示。")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.task { await store.updateNotificationPermission() }
    }
}

@MainActor
private struct SettingsScreen: View {
    @ObservedObject var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 18) {
                Text("按你的习惯来").font(.system(size: 15, weight: .semibold))
                Picker("状态栏展示", selection: Binding(get: { store.preferences.displayChannel }, set: { store.setDisplayChannel($0) })) {
                    ForEach(QuoteChannel.allCases) { Text($0.title).tag($0) }
                }
                Picker("刷新间隔", selection: Binding(get: { store.preferences.refreshSeconds }, set: { store.setRefreshSeconds($0) })) {
                    ForEach([5, 15, 30, 60], id: \.self) { Text("\($0) 秒").tag($0) }
                }
                Divider()
                Toggle("登录 Mac 后自动启动", isOn: Binding(get: { store.loginEnabled }, set: { store.setLoginEnabled($0) })).toggleStyle(.switch).controlSize(.small)
                Text("把应用放进“应用程序”文件夹后，可在这里开启。").font(.system(size: 10)).foregroundStyle(.secondary)
            }.modifier(SoftCard())

            VStack(alignment: .leading, spacing: 14) {
                Text("数据与计算口径").font(.system(size: 14, weight: .semibold))
                Text("持仓使用移动加权均价：买入计入成交金额与显式手续费；卖出按原均价结转成本，剩余均价不变。浮动收益按招行客户卖出价估值，已实现收益单独列出。")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("交易记录和提醒保存在本机。伦敦金使用美元/盎司，招行使用人民币/克，两种单位分别展示。")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button { store.exportData() } label: { Label("导出数据备份", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
            }.modifier(SoftCard())
            HStack {
                Text("GoldPrice · Abbylolo 定制版").font(.system(size: 10))
                Spacer()
                Link("源代码", destination: URL(string: "https://github.com/Abbylolo/GoldPrice")!).font(.system(size: 10))
            }.foregroundStyle(.secondary).padding(.horizontal, 3)
        }
    }
}
