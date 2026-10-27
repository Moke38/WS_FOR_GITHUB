import Foundation

/// Yahoo Finance の非公式エンドポイントからデータを取得する。
/// 仕様は予告なく変わる可能性があるため、本番運用では正式なマーケットデータ API への置き換えを推奨。
struct YahooFinanceService: StockService {
    enum ServiceError: LocalizedError {
        case badStatus(Int)
        case emptyResult

        var errorDescription: String? {
            switch self {
            case .badStatus(let code): "サーバーエラー (HTTP \(code))"
            case .emptyResult: "データが見つかりませんでした"
            }
        }
    }

    var session: URLSession = .shared
    var baseURL = URL(string: "https://query1.finance.yahoo.com")!

    func quotes(for screener: Screener, count: Int) async throws -> [StockQuote] {
        var components = URLComponents(
            url: baseURL.appending(path: "v1/finance/screener/predefined/saved"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "scrIds", value: screener.rawValue),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "lang", value: "en-US"),
            URLQueryItem(name: "region", value: "US"),
        ]
        let data = try await fetch(components.url!)
        return try Self.decodeScreener(data)
    }

    func chart(symbol: String, range: ChartRange) async throws -> [PricePoint] {
        var components = URLComponents(
            url: baseURL.appending(path: "v8/finance/chart").appending(path: symbol),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "range", value: range.rawValue),
            URLQueryItem(name: "interval", value: range.interval),
        ]
        let data = try await fetch(components.url!)
        return try Self.decodeChart(data)
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        // 既定の User-Agent だと拒否されることがある
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ServiceError.badStatus(http.statusCode)
        }
        return data
    }

    // MARK: - Decoding

    private struct ScreenerResponse: Decodable {
        struct Finance: Decodable { let result: [Result]? }
        struct Result: Decodable { let quotes: [StockQuote]? }
        let finance: Finance
    }

    private struct ChartResponse: Decodable {
        struct Chart: Decodable { let result: [Result]? }
        struct Result: Decodable {
            let timestamp: [TimeInterval]?
            let indicators: Indicators
        }
        struct Indicators: Decodable { let quote: [Series] }
        struct Series: Decodable { let close: [Double?]? }
        let chart: Chart
    }

    static func decodeScreener(_ data: Data) throws -> [StockQuote] {
        let response = try JSONDecoder().decode(ScreenerResponse.self, from: data)
        guard let quotes = response.finance.result?.first?.quotes else { throw ServiceError.emptyResult }
        return quotes
    }

    static func decodeChart(_ data: Data) throws -> [PricePoint] {
        let response = try JSONDecoder().decode(ChartResponse.self, from: data)
        guard let result = response.chart.result?.first,
              let timestamps = result.timestamp,
              let closes = result.indicators.quote.first?.close
        else { throw ServiceError.emptyResult }
        return zip(timestamps, closes).compactMap { time, close in
            close.map { PricePoint(date: Date(timeIntervalSince1970: time), close: $0) }
        }
    }
}
