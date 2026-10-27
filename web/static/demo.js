// 通信できないときに表示するダミーデータ (iOS 版の MockStockService と同じ内容)

const q = (symbol, name, price, change, changePercent, volume, averageVolume, fiftyTwoWeekHigh, fiftyTwoWeekLow) => ({
  symbol, name, price, change, changePercent, volume, averageVolume, fiftyTwoWeekHigh, fiftyTwoWeekLow,
  marketCap: null, currency: "USD", exchange: null,
});

const SAMPLE = [
  q("NVDA", "NVIDIA Corporation", 182.4, 14.1, 8.38, 612e6, 210e6, 184.0, 86.6),
  q("TSLA", "Tesla, Inc.", 251.3, -18.9, -6.99, 180e6, 95e6, 488.5, 182.0),
  q("PLTR", "Palantir Technologies", 41.2, 4.6, 12.57, 140e6, 38e6, 42.0, 15.7),
  q("INTC", "Intel Corporation", 19.1, -2.3, -10.75, 260e6, 60e6, 45.0, 18.9),
  q("AAPL", "Apple Inc.", 228.0, 1.1, 0.48, 52e6, 55e6, 237.2, 164.1),
  q("SMCI", "Super Micro Computer", 38.6, 6.9, 21.77, 95e6, 22e6, 122.9, 17.3),
];

const pct = (x) => x.changePercent ?? 0;

export const demoScreeners = {
  day_gainers: SAMPLE.filter((x) => pct(x) > 0).sort((a, b) => pct(b) - pct(a)),
  small_cap_gainers: [],
  day_losers: SAMPLE.filter((x) => pct(x) < 0).sort((a, b) => pct(a) - pct(b)),
  most_actives: [...SAMPLE].sort((a, b) => b.volume - a.volume),
};

export function demoChart(symbol) {
  const base = SAMPLE.find((x) => x.symbol === symbol)?.price ?? 100;
  // 銘柄コードから決定的な乱数列を作る
  let state = [...symbol].reduce((h, c) => (h * 33 + c.charCodeAt(0)) >>> 0, 5381) || 1;
  const rand = () => {
    state ^= state << 13; state >>>= 0;
    state ^= state >>> 17;
    state ^= state << 5; state >>>= 0;
    return state / 0xffffffff;
  };
  const now = Math.floor(Date.now() / 1000);
  let value = base * 0.85;
  return Array.from({ length: 60 }, (_, i) => {
    value *= 1 + (rand() * 0.065 - 0.03);
    return { time: now + (i - 60) * 86400, close: value };
  });
}
