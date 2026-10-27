import Foundation

/// 「面白い値動き」と判定する理由
enum MoverSignal: String, CaseIterable, Hashable, Sendable {
    case surge
    case plunge
    case volumeSpike
    case near52WeekHigh
    case near52WeekLow

    var label: String {
        switch self {
        case .surge: "急騰"
        case .plunge: "急落"
        case .volumeSpike: "出来高急増"
        case .near52WeekHigh: "52週高値圏"
        case .near52WeekLow: "52週安値圏"
        }
    }

    var symbolName: String {
        switch self {
        case .surge: "arrow.up.right"
        case .plunge: "arrow.down.right"
        case .volumeSpike: "chart.bar.fill"
        case .near52WeekHigh: "flag.checkered"
        case .near52WeekLow: "exclamationmark.triangle"
        }
    }
}

/// 銘柄ごとの「面白さ」を判定・スコア化する
enum InterestAnalyzer {
    static let surgeThreshold = 5.0          // %
    static let volumeSpikeThreshold = 3.0    // 平均比 倍
    static let fiftyTwoWeekMargin = 0.02     // 高値/安値から 2% 以内

    static func signals(for quote: StockQuote) -> [MoverSignal] {
        var result: [MoverSignal] = []
        if let pct = quote.changePercent {
            if pct >= surgeThreshold { result.append(.surge) }
            if pct <= -surgeThreshold { result.append(.plunge) }
        }
        if let ratio = quote.volumeRatio, ratio >= volumeSpikeThreshold {
            result.append(.volumeSpike)
        }
        if let price = quote.price {
            if let high = quote.fiftyTwoWeekHigh, high > 0, price >= high * (1 - fiftyTwoWeekMargin) {
                result.append(.near52WeekHigh)
            }
            if let low = quote.fiftyTwoWeekLow, low > 0, price <= low * (1 + fiftyTwoWeekMargin) {
                result.append(.near52WeekLow)
            }
        }
        return result
    }

    /// 変動率の大きさ・出来高の異常さ・52週の節目を合算したスコア
    static func score(for quote: StockQuote) -> Double {
        var score = abs(quote.changePercent ?? 0)
        if let ratio = quote.volumeRatio, ratio > 1 {
            score += log2(ratio) * 3
        }
        let signals = signals(for: quote)
        if signals.contains(.near52WeekHigh) || signals.contains(.near52WeekLow) {
            score += 3
        }
        return score
    }

    /// 重複を除いてスコア順に並べる
    static func rank(_ quotes: [StockQuote]) -> [StockQuote] {
        var seen = Set<String>()
        return quotes
            .filter { seen.insert($0.symbol).inserted }
            .sorted { score(for: $0) > score(for: $1) }
    }
}
