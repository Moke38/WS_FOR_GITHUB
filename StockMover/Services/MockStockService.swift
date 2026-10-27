import Foundation

/// オフライン時やプレビュー用のダミーデータ
struct MockStockService: StockService {
    static let sampleQuotes: [StockQuote] = [
        StockQuote(symbol: "NVDA", name: "NVIDIA Corporation", price: 182.4, change: 14.1, changePercent: 8.38,
                   volume: 612_000_000, averageVolume: 210_000_000, fiftyTwoWeekHigh: 184.0, fiftyTwoWeekLow: 86.6),
        StockQuote(symbol: "TSLA", name: "Tesla, Inc.", price: 251.3, change: -18.9, changePercent: -6.99,
                   volume: 180_000_000, averageVolume: 95_000_000, fiftyTwoWeekHigh: 488.5, fiftyTwoWeekLow: 182.0),
        StockQuote(symbol: "PLTR", name: "Palantir Technologies", price: 41.2, change: 4.6, changePercent: 12.57,
                   volume: 140_000_000, averageVolume: 38_000_000, fiftyTwoWeekHigh: 42.0, fiftyTwoWeekLow: 15.7),
        StockQuote(symbol: "INTC", name: "Intel Corporation", price: 19.1, change: -2.3, changePercent: -10.75,
                   volume: 260_000_000, averageVolume: 60_000_000, fiftyTwoWeekHigh: 45.0, fiftyTwoWeekLow: 18.9),
        StockQuote(symbol: "AAPL", name: "Apple Inc.", price: 228.0, change: 1.1, changePercent: 0.48,
                   volume: 52_000_000, averageVolume: 55_000_000, fiftyTwoWeekHigh: 237.2, fiftyTwoWeekLow: 164.1),
        StockQuote(symbol: "SMCI", name: "Super Micro Computer", price: 38.6, change: 6.9, changePercent: 21.77,
                   volume: 95_000_000, averageVolume: 22_000_000, fiftyTwoWeekHigh: 122.9, fiftyTwoWeekLow: 17.3),
    ]

    func quotes(for screener: Screener, count: Int) async throws -> [StockQuote] {
        let quotes: [StockQuote] = switch screener {
        case .dayGainers, .smallCapGainers:
            Self.sampleQuotes.filter { ($0.changePercent ?? 0) > 0 }
                .sorted { ($0.changePercent ?? 0) > ($1.changePercent ?? 0) }
        case .dayLosers:
            Self.sampleQuotes.filter { ($0.changePercent ?? 0) < 0 }
                .sorted { ($0.changePercent ?? 0) < ($1.changePercent ?? 0) }
        case .mostActives:
            Self.sampleQuotes.sorted { ($0.volume ?? 0) > ($1.volume ?? 0) }
        }
        return Array(quotes.prefix(count))
    }

    func chart(symbol: String, range: ChartRange) async throws -> [PricePoint] {
        let base = Self.sampleQuotes.first { $0.symbol == symbol }?.price ?? 100
        // hashValue は起動ごとに変わるので、銘柄コードから決定的なシードを作る
        let seed = symbol.unicodeScalars.reduce(UInt64(5381)) { $0 &* 33 &+ UInt64($1.value) }
        var generator = SeededGenerator(seed: seed)
        var value = base * 0.85
        let now = Date()
        return (0..<60).map { i in
            value *= 1 + Double.random(in: -0.03...0.035, using: &generator)
            return PricePoint(date: now.addingTimeInterval(Double(i - 60) * 86_400), close: value)
        }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
