import SwiftUI

struct MoversListView: View {
    @Bindable var viewModel: MoversViewModel
    @Environment(\.scenePhase) private var scenePhase

    /// 自動更新の間隔 (秒)
    private let refreshInterval: Duration = .seconds(60)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("カテゴリ", selection: $viewModel.category) {
                        ForEach(MoverCategory.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if viewModel.isShowingDemoData {
                    Section {
                        Label("データを取得できなかったため、デモデータを表示しています", systemImage: "wifi.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    ForEach(viewModel.visibleQuotes) { quote in
                        NavigationLink(value: quote) {
                            StockRowView(quote: quote)
                        }
                    }
                } footer: {
                    footer
                }
            }
            .overlay {
                if viewModel.visibleQuotes.isEmpty {
                    if viewModel.isLoading {
                        ProgressView("読み込み中…")
                    } else {
                        ContentUnavailableView(
                            "該当する銘柄がありません",
                            systemImage: "chart.line.flattrend.xyaxis",
                            description: Text(viewModel.errorMessage ?? "条件を変えてみてください")
                        )
                    }
                }
            }
            .navigationTitle("値動きウォッチ")
            .navigationDestination(for: StockQuote.self) { quote in
                StockDetailView(quote: quote, loadChart: viewModel.chart)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    filterMenu
                }
            }
            .refreshable { await viewModel.refresh() }
            .task(id: scenePhase) {
                // フォアグラウンドにいる間だけ定期更新する
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    await viewModel.refresh()
                    try? await Task.sleep(for: refreshInterval)
                }
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("最低変動率", selection: $viewModel.minimumChangePercent) {
                Text("すべて").tag(0.0)
                Text("±3%以上").tag(3.0)
                Text("±5%以上").tag(5.0)
                Text("±10%以上").tag(10.0)
            }
        } label: {
            Image(systemName: viewModel.minimumChangePercent > 0
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let lastUpdated = viewModel.lastUpdated {
                Text("最終更新: \(lastUpdated.formatted(date: .omitted, time: .standard))")
            }
            Text("データ: Yahoo Finance（遅延あり）。投資判断はご自身の責任で行ってください。")
        }
        .font(.caption2)
    }
}

struct StockRowView: View {
    let quote: StockQuote

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(quote.symbol).font(.headline)
                    Text(quote.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.price(quote.price, currency: quote.currency))
                        .font(.subheadline.monospacedDigit())
                    Text(Format.percent(quote.changePercent))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Format.changeColor(quote.changePercent))
                }
            }
            let signals = InterestAnalyzer.signals(for: quote)
            if !signals.isEmpty || quote.volumeRatio != nil {
                HStack(spacing: 4) {
                    ForEach(signals, id: \.self) { SignalBadge(signal: $0) }
                    Spacer()
                    if let ratio = quote.volumeRatio {
                        Text("出来高 \(Format.ratio(ratio))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    MoversListView(viewModel: MoversViewModel(service: MockStockService()))
}
