import Foundation

/// Yahoo Finance の定義済みスクリーナー
enum Screener: String, CaseIterable, Sendable {
    case dayGainers = "day_gainers"
    case dayLosers = "day_losers"
    case mostActives = "most_actives"
    case smallCapGainers = "small_cap_gainers"
}

enum ChartRange: String, CaseIterable, Identifiable, Sendable {
    case day = "1d"
    case week = "5d"
    case month = "1mo"
    case sixMonths = "6mo"
    case year = "1y"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: "1日"
        case .week: "1週"
        case .month: "1か月"
        case .sixMonths: "6か月"
        case .year: "1年"
        }
    }

    var interval: String {
        switch self {
        case .day: "5m"
        case .week: "30m"
        case .month, .sixMonths: "1d"
        case .year: "1wk"
        }
    }
}

protocol StockService: Sendable {
    func quotes(for screener: Screener, count: Int) async throws -> [StockQuote]
    func chart(symbol: String, range: ChartRange) async throws -> [PricePoint]
}
