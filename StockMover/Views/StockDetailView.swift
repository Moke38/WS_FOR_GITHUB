import Charts
import SwiftUI

struct StockDetailView: View {
    let quote: StockQuote
    let loadChart: (String, ChartRange) async throws -> [PricePoint]

    @State private var range: ChartRange = .month
    @State private var points: [PricePoint] = []
    @State private var chartError: String?

    var body: some View {
        List {
            Section {
                header
                Picker("期間", selection: $range) {
                    ForEach(ChartRange.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                chart
                    .frame(height: 220)
            }

            let signals = InterestAnalyzer.signals(for: quote)
            if !signals.isEmpty {
                Section("注目ポイント") {
                    ForEach(signals, id: \.self) { signal in
                        HStack {
                            SignalBadge(signal: signal)
                            Text(description(for: signal))
                                .font(.footnote)
                        }
                    }
                }
            }

            Section("データ") {
                row("前日比", Format.price(quote.change, currency: quote.currency))
                row("出来高", Format.compact(quote.volume))
                row("平均出来高 (3か月)", Format.compact(quote.averageVolume))
                row("出来高 平均比", Format.ratio(quote.volumeRatio))
                row("52週高値", Format.price(quote.fiftyTwoWeekHigh, currency: quote.currency))
                row("52週安値", Format.price(quote.fiftyTwoWeekLow, currency: quote.currency))
                if let position = quote.fiftyTwoWeekPosition {
                    VStack(alignment: .leading) {
                        Text("52週レンジ内の位置").font(.subheadline)
                        ProgressView(value: position)
                    }
                }
                row("時価総額", Format.compact(quote.marketCap))
                if let exchange = quote.exchange {
                    row("市場", exchange)
                }
            }

            if let url = URL(string: "https://finance.yahoo.com/quote/\(quote.symbol)") {
                Section {
                    Link("Yahoo Finance で詳しく見る", destination: url)
                }
            }
        }
        .navigationTitle(quote.symbol)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: range) {
            do {
                chartError = nil
                points = try await loadChart(quote.symbol, range)
            } catch {
                // 期間切り替えでキャンセルされた古いリクエストの結果は無視する
                guard !Task.isCancelled else { return }
                chartError = error.localizedDescription
                points = []
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(quote.name).font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(Format.price(quote.price, currency: quote.currency))
                    .font(.largeTitle.monospacedDigit().bold())
                Text(Format.percent(quote.changePercent))
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Format.changeColor(quote.changePercent))
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        if let chartError {
            ContentUnavailableView("チャートを取得できません", systemImage: "chart.xyaxis.line",
                                   description: Text(chartError))
        } else if points.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let isUp = (points.last?.close ?? 0) >= (points.first?.close ?? 0)
            let lineColor: Color = isUp ? .green : .red
            let closes = points.map(\.close)
            Chart(points) { point in
                LineMark(x: .value("日時", point.date), y: .value("終値", point.close))
                    .foregroundStyle(lineColor)
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: (closes.min() ?? 0)...(closes.max() ?? 1))
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value).monospacedDigit()
        }
    }

    private func description(for signal: MoverSignal) -> String {
        switch signal {
        case .surge: "前日比 +\(Int(InterestAnalyzer.surgeThreshold))% 以上の上昇"
        case .plunge: "前日比 -\(Int(InterestAnalyzer.surgeThreshold))% 以上の下落"
        case .volumeSpike: "出来高が3か月平均の \(Format.ratio(quote.volumeRatio))"
        case .near52WeekHigh: "52週高値まで2%以内"
        case .near52WeekLow: "52週安値まで2%以内"
        }
    }
}

#Preview {
    NavigationStack {
        StockDetailView(quote: MockStockService.sampleQuotes[0]) { symbol, range in
            try await MockStockService().chart(symbol: symbol, range: range)
        }
    }
}
