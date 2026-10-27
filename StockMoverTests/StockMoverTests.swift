import XCTest
@testable import StockMover

final class InterestAnalyzerTests: XCTestCase {
    private func quote(
        _ symbol: String = "TEST", pct: Double? = 0, price: Double? = 50,
        volume: Double? = 100, avgVolume: Double? = 100, high: Double? = 100, low: Double? = 10
    ) -> StockQuote {
        StockQuote(symbol: symbol, name: symbol, price: price, change: nil, changePercent: pct,
                   volume: volume, averageVolume: avgVolume, fiftyTwoWeekHigh: high, fiftyTwoWeekLow: low)
    }

    func testQuietStockHasNoSignals() {
        XCTAssertEqual(InterestAnalyzer.signals(for: quote()), [])
    }

    func testSurgeAndPlunge() {
        XCTAssertEqual(InterestAnalyzer.signals(for: quote(pct: 6)), [.surge])
        XCTAssertEqual(InterestAnalyzer.signals(for: quote(pct: -5)), [.plunge])
        XCTAssertEqual(InterestAnalyzer.signals(for: quote(pct: 4.9)), [])
    }

    func testVolumeSpike() {
        XCTAssertEqual(InterestAnalyzer.signals(for: quote(volume: 300, avgVolume: 100)), [.volumeSpike])
        XCTAssertEqual(InterestAnalyzer.signals(for: quote(volume: 290, avgVolume: 100)), [])
        XCTAssertEqual(InterestAnalyzer.signals(for: quote(volume: 300, avgVolume: 0)), [])
    }

    func testFiftyTwoWeekExtremes() {
        XCTAssertEqual(InterestAnalyzer.signals(for: quote(price: 98.5)), [.near52WeekHigh])
        XCTAssertEqual(InterestAnalyzer.signals(for: quote(price: 10.1)), [.near52WeekLow])
    }

    func testRankDeduplicatesAndOrdersByScore() {
        let ranked = InterestAnalyzer.rank([
            quote("A", pct: 1),
            quote("B", pct: 10),
            quote("A", pct: 1),
            quote("C", pct: 2, volume: 800, avgVolume: 100), // 2 + log2(8)*3 = 11
        ])
        XCTAssertEqual(ranked.map(\.symbol), ["C", "B", "A"])
    }

    func testFiftyTwoWeekPosition() {
        XCTAssertEqual(quote(price: 55, high: 100, low: 10).fiftyTwoWeekPosition!, 0.5, accuracy: 1e-9)
        XCTAssertNil(quote(high: 10, low: 10).fiftyTwoWeekPosition)
    }
}

final class YahooDecodingTests: XCTestCase {
    func testDecodesScreenerWithPlainAndRawNumbers() throws {
        let json = """
        {"finance":{"result":[{"quotes":[
          {"symbol":"AAA","shortName":"Alpha","regularMarketPrice":12.5,"regularMarketChangePercent":7.2,
           "regularMarketVolume":3000,"averageDailyVolume3Month":1000,"currency":"USD"},
          {"symbol":"BBB","longName":"Beta Inc","regularMarketPrice":{"raw":3.25,"fmt":"3.25"},
           "regularMarketChangePercent":{"raw":-8.1,"fmt":"-8.10%"}}
        ]}],"error":null}}
        """.data(using: .utf8)!

        let quotes = try YahooFinanceService.decodeScreener(json)
        XCTAssertEqual(quotes.map(\.symbol), ["AAA", "BBB"])
        XCTAssertEqual(quotes[0].name, "Alpha")
        XCTAssertEqual(quotes[0].volumeRatio, 3)
        XCTAssertEqual(quotes[1].name, "Beta Inc")
        XCTAssertEqual(quotes[1].price, 3.25)
        XCTAssertEqual(quotes[1].changePercent, -8.1)
        XCTAssertNil(quotes[1].volume)
    }

    func testDecodesChartSkippingNulls() throws {
        let json = """
        {"chart":{"result":[{"meta":{},"timestamp":[1700000000,1700086400,1700172800],
          "indicators":{"quote":[{"close":[10.0,null,12.5]}]}}],"error":null}}
        """.data(using: .utf8)!

        let points = try YahooFinanceService.decodeChart(json)
        XCTAssertEqual(points.map(\.close), [10.0, 12.5])
        XCTAssertEqual(points.last?.date, Date(timeIntervalSince1970: 1700172800))
    }

    func testEmptyScreenerThrows() {
        let json = #"{"finance":{"result":[],"error":null}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try YahooFinanceService.decodeScreener(json))
    }
}
