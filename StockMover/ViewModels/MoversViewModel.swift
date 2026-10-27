import Foundation
import Observation

enum MoverCategory: String, CaseIterable, Identifiable {
    case interesting
    case gainers
    case losers
    case volume

    var id: String { rawValue }

    var label: String {
        switch self {
        case .interesting: "注目"
        case .gainers: "値上がり"
        case .losers: "値下がり"
        case .volume: "出来高"
        }
    }
}

@MainActor
@Observable
final class MoversViewModel {
    private(set) var quotesByScreener: [Screener: [StockQuote]] = [:]
    private(set) var isLoading = false
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?
    /// ネットワーク取得に失敗してデモデータを表示しているか
    private(set) var isShowingDemoData = false

    var category: MoverCategory = .interesting
    var minimumChangePercent: Double = 0

    private let service: StockService
    private let fallback: StockService = MockStockService()

    init(service: StockService) {
        self.service = service
    }

    var visibleQuotes: [StockQuote] {
        let base: [StockQuote] = switch category {
        case .interesting:
            InterestAnalyzer.rank(quotesByScreener.values.flatMap { $0 })
                .filter { !InterestAnalyzer.signals(for: $0).isEmpty }
        case .gainers:
            InterestAnalyzer.rank((quotesByScreener[.dayGainers] ?? []) + (quotesByScreener[.smallCapGainers] ?? []))
                .sorted { ($0.changePercent ?? 0) > ($1.changePercent ?? 0) }
        case .losers:
            (quotesByScreener[.dayLosers] ?? [])
                .sorted { ($0.changePercent ?? 0) < ($1.changePercent ?? 0) }
        case .volume:
            InterestAnalyzer.rank(quotesByScreener.values.flatMap { $0 })
                .sorted { ($0.volumeRatio ?? 0) > ($1.volumeRatio ?? 0) }
        }
        return base.filter { abs($0.changePercent ?? 0) >= minimumChangePercent }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            quotesByScreener = try await load(from: service)
            isShowingDemoData = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            if quotesByScreener.isEmpty, let demo = try? await load(from: fallback) {
                quotesByScreener = demo
                isShowingDemoData = true
            }
        }
        lastUpdated = .now
    }

    func chart(symbol: String, range: ChartRange) async throws -> [PricePoint] {
        try await (isShowingDemoData ? fallback : service).chart(symbol: symbol, range: range)
    }

    private nonisolated func load(from service: StockService) async throws -> [Screener: [StockQuote]] {
        try await withThrowingTaskGroup(of: (Screener, [StockQuote]).self) { group in
            for screener in Screener.allCases {
                group.addTask { (screener, try await service.quotes(for: screener, count: 25)) }
            }
            var result: [Screener: [StockQuote]] = [:]
            for try await (screener, quotes) in group {
                result[screener] = quotes
            }
            return result
        }
    }
}
