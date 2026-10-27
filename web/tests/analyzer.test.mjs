import assert from "node:assert/strict";
import { test } from "node:test";
import { fiftyTwoWeekPosition, quotesForCategory, rank, signals } from "../static/analyzer.js";

const quote = ({ symbol = "TEST", pct = 0, price = 50, volume = 100, avgVolume = 100, high = 100, low = 10 } = {}) => ({
  symbol, name: symbol, price, changePercent: pct, volume, averageVolume: avgVolume,
  fiftyTwoWeekHigh: high, fiftyTwoWeekLow: low,
});

test("quiet stock has no signals", () => {
  assert.deepEqual(signals(quote()), []);
});

test("surge and plunge", () => {
  assert.deepEqual(signals(quote({ pct: 6 })), ["surge"]);
  assert.deepEqual(signals(quote({ pct: -5 })), ["plunge"]);
  assert.deepEqual(signals(quote({ pct: 4.9 })), []);
});

test("volume spike", () => {
  assert.deepEqual(signals(quote({ volume: 300 })), ["volumeSpike"]);
  assert.deepEqual(signals(quote({ volume: 290 })), []);
  assert.deepEqual(signals(quote({ volume: 300, avgVolume: 0 })), []);
  assert.deepEqual(signals(quote({ volume: null })), []);
});

test("52-week extremes", () => {
  assert.deepEqual(signals(quote({ price: 98.5 })), ["near52WeekHigh"]);
  assert.deepEqual(signals(quote({ price: 10.1 })), ["near52WeekLow"]);
});

test("rank dedupes and orders by score", () => {
  const ranked = rank([
    quote({ symbol: "A", pct: 1 }),
    quote({ symbol: "B", pct: 10 }),
    quote({ symbol: "A", pct: 1 }),
    quote({ symbol: "C", pct: 2, volume: 800 }), // 2 + log2(8)*3 = 11
  ]);
  assert.deepEqual(ranked.map((q) => q.symbol), ["C", "B", "A"]);
});

test("52-week position", () => {
  assert.equal(fiftyTwoWeekPosition(quote({ price: 55 })), 0.5);
  assert.equal(fiftyTwoWeekPosition(quote({ high: 10, low: 10 })), null);
});

test("categories", () => {
  const byScreener = {
    day_gainers: [quote({ symbol: "G1", pct: 3 }), quote({ symbol: "G2", pct: 9 })],
    small_cap_gainers: [quote({ symbol: "S1", pct: 15 })],
    day_losers: [quote({ symbol: "L1", pct: -2 }), quote({ symbol: "L2", pct: -12 })],
    most_actives: [quote({ symbol: "M1", pct: 0.5, volume: 500 })],
  };
  const symbols = (cat, min) => quotesForCategory(byScreener, cat, min).map((q) => q.symbol);
  assert.deepEqual(symbols("gainers"), ["S1", "G2", "G1"]);
  assert.deepEqual(symbols("losers"), ["L2", "L1"]);
  assert.deepEqual(symbols("volume")[0], "M1");
  assert.deepEqual(symbols("interesting"), ["S1", "L2", "G2", "M1"]);
  assert.deepEqual(symbols("gainers", 5), ["S1", "G2"]);
});
