import Foundation

/// 1銘柄分の気配情報。Yahoo Finance のスクリーナー応答から生成する。
struct StockQuote: Identifiable, Hashable, Sendable {
    var id: String { symbol }

    let symbol: String
    let name: String
    let price: Double?
    let change: Double?
    let changePercent: Double?
    let volume: Double?
    let averageVolume: Double?
    let fiftyTwoWeekHigh: Double?
    let fiftyTwoWeekLow: Double?
    let marketCap: Double?
    let currency: String
    let exchange: String?

    // 本体に宣言して、同じシグネチャの memberwise init が合成されないようにする
    init(
        symbol: String, name: String, price: Double?, change: Double?, changePercent: Double?,
        volume: Double?, averageVolume: Double?, fiftyTwoWeekHigh: Double?, fiftyTwoWeekLow: Double?,
        marketCap: Double? = nil, currency: String = "USD", exchange: String? = nil
    ) {
        self.symbol = symbol
        self.name = name
        self.price = price
        self.change = change
        self.changePercent = changePercent
        self.volume = volume
        self.averageVolume = averageVolume
        self.fiftyTwoWeekHigh = fiftyTwoWeekHigh
        self.fiftyTwoWeekLow = fiftyTwoWeekLow
        self.marketCap = marketCap
        self.currency = currency
        self.exchange = exchange
    }

    /// 当日出来高 ÷ 3か月平均出来高
    var volumeRatio: Double? {
        guard let volume, let averageVolume, averageVolume > 0 else { return nil }
        return volume / averageVolume
    }

    /// 52週レンジ内での現在値の位置 (0 = 安値, 1 = 高値)
    var fiftyTwoWeekPosition: Double? {
        guard let price, let high = fiftyTwoWeekHigh, let low = fiftyTwoWeekLow, high > low else { return nil }
        return min(max((price - low) / (high - low), 0), 1)
    }
}

extension StockQuote: Decodable {
    private enum CodingKeys: String, CodingKey {
        case symbol, shortName, longName, currency, fullExchangeName
        case regularMarketPrice, regularMarketChange, regularMarketChangePercent
        case regularMarketVolume, averageDailyVolume3Month
        case fiftyTwoWeekHigh, fiftyTwoWeekLow, marketCap
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try c.decode(String.self, forKey: .symbol)
        name = (try? c.decodeIfPresent(String.self, forKey: .shortName))
            ?? (try? c.decodeIfPresent(String.self, forKey: .longName))
            ?? symbol
        price = c.flexibleDouble(.regularMarketPrice)
        change = c.flexibleDouble(.regularMarketChange)
        changePercent = c.flexibleDouble(.regularMarketChangePercent)
        volume = c.flexibleDouble(.regularMarketVolume)
        averageVolume = c.flexibleDouble(.averageDailyVolume3Month)
        fiftyTwoWeekHigh = c.flexibleDouble(.fiftyTwoWeekHigh)
        fiftyTwoWeekLow = c.flexibleDouble(.fiftyTwoWeekLow)
        marketCap = c.flexibleDouble(.marketCap)
        currency = (try? c.decodeIfPresent(String.self, forKey: .currency)) ?? "USD"
        exchange = try? c.decodeIfPresent(String.self, forKey: .fullExchangeName)
    }
}

private struct RawValue: Decodable {
    let raw: Double?
}

extension KeyedDecodingContainer {
    /// Yahoo は数値を `123.4` と `{"raw": 123.4, "fmt": "123.40"}` のどちらでも返すことがあるので両方受け付ける。
    func flexibleDouble(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(RawValue.self, forKey: key) { return value.raw }
        return nil
    }
}

/// チャート用の1データ点
struct PricePoint: Identifiable, Hashable, Sendable {
    var id: Date { date }
    let date: Date
    let close: Double
}
