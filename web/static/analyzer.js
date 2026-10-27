// 「面白い値動き」の判定とスコア計算。iOS 版の InterestAnalyzer と同じロジック。

export const SURGE_THRESHOLD = 5; // %
export const VOLUME_SPIKE_THRESHOLD = 3; // 平均比 倍
export const FIFTY_TWO_WEEK_MARGIN = 0.02; // 高値/安値から 2% 以内

export const SIGNALS = {
  surge: { label: "急騰", tone: "up" },
  plunge: { label: "急落", tone: "down" },
  volumeSpike: { label: "出来高急増", tone: "warn" },
  near52WeekHigh: { label: "52週高値圏", tone: "up" },
  near52WeekLow: { label: "52週安値圏", tone: "down" },
};

const isNum = (v) => typeof v === "number" && Number.isFinite(v);

export function volumeRatio(q) {
  return isNum(q.volume) && isNum(q.averageVolume) && q.averageVolume > 0
    ? q.volume / q.averageVolume
    : null;
}

export function fiftyTwoWeekPosition(q) {
  const { price, fiftyTwoWeekHigh: high, fiftyTwoWeekLow: low } = q;
  if (!isNum(price) || !isNum(high) || !isNum(low) || high <= low) return null;
  return Math.min(Math.max((price - low) / (high - low), 0), 1);
}

export function signals(q) {
  const result = [];
  if (isNum(q.changePercent)) {
    if (q.changePercent >= SURGE_THRESHOLD) result.push("surge");
    if (q.changePercent <= -SURGE_THRESHOLD) result.push("plunge");
  }
  const ratio = volumeRatio(q);
  if (ratio !== null && ratio >= VOLUME_SPIKE_THRESHOLD) result.push("volumeSpike");
  if (isNum(q.price)) {
    const high = q.fiftyTwoWeekHigh;
    const low = q.fiftyTwoWeekLow;
    if (isNum(high) && high > 0 && q.price >= high * (1 - FIFTY_TWO_WEEK_MARGIN)) result.push("near52WeekHigh");
    if (isNum(low) && low > 0 && q.price <= low * (1 + FIFTY_TWO_WEEK_MARGIN)) result.push("near52WeekLow");
  }
  return result;
}

// 変動率の大きさ・出来高の異常さ・52週の節目を合算したスコア
export function score(q) {
  let s = Math.abs(q.changePercent ?? 0);
  const ratio = volumeRatio(q);
  if (ratio !== null && ratio > 1) s += Math.log2(ratio) * 3;
  const sig = signals(q);
  if (sig.includes("near52WeekHigh") || sig.includes("near52WeekLow")) s += 3;
  return s;
}

// 重複を除いてスコア順に並べる
export function rank(quotes) {
  const seen = new Set();
  return quotes
    .filter((q) => !seen.has(q.symbol) && seen.add(q.symbol))
    .sort((a, b) => score(b) - score(a));
}

export const CATEGORIES = {
  interesting: "注目",
  gainers: "値上がり",
  losers: "値下がり",
  volume: "出来高",
};

export function quotesForCategory(byScreener, category, minimumChangePercent = 0) {
  const all = Object.values(byScreener).flat();
  const pct = (q) => q.changePercent ?? 0;
  let list;
  switch (category) {
    case "gainers":
      list = rank([...(byScreener.day_gainers ?? []), ...(byScreener.small_cap_gainers ?? [])])
        .sort((a, b) => pct(b) - pct(a));
      break;
    case "losers":
      list = [...(byScreener.day_losers ?? [])].sort((a, b) => pct(a) - pct(b));
      break;
    case "volume":
      list = rank(all).sort((a, b) => (volumeRatio(b) ?? 0) - (volumeRatio(a) ?? 0));
      break;
    default:
      list = rank(all).filter((q) => signals(q).length > 0);
  }
  return list.filter((q) => Math.abs(pct(q)) >= minimumChangePercent);
}
