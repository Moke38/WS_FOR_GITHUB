import {
  CATEGORIES, SIGNALS, SURGE_THRESHOLD, fiftyTwoWeekPosition, quotesForCategory, signals, volumeRatio,
} from "./analyzer.js";
import { demoChart, demoScreeners } from "./demo.js";

const SCREENERS = ["day_gainers", "day_losers", "most_actives", "small_cap_gainers"];
const RANGES = { "1d": "1日", "5d": "1週", "1mo": "1か月", "6mo": "6か月", "1y": "1年" };
const REFRESH_MS = 60_000;

const state = {
  byScreener: {},
  category: "interesting",
  minChange: 0,
  selected: null,
  range: "1mo",
  demo: false,
  loading: false,
  error: null,
};

const $ = (id) => document.getElementById(id);

// MARK: - 書式

const fmtPrice = (v, currency = "USD") =>
  v == null ? "—" : v.toLocaleString("ja-JP", { style: "currency", currency, minimumFractionDigits: 2, maximumFractionDigits: 2 });
const fmtPct = (v) => (v == null ? "—" : `${v > 0 ? "+" : ""}${v.toFixed(2)}%`);
const fmtCompact = (v) =>
  v == null ? "—" : v.toLocaleString("ja-JP", { notation: "compact", maximumFractionDigits: 1 });
const fmtRatio = (v) => (v == null ? "—" : `${v.toFixed(1)}倍`);
const tone = (v) => (v == null || v === 0 ? "flat" : v > 0 ? "up" : "down");

function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "class") node.className = v;
    else if (k.startsWith("on")) node.addEventListener(k.slice(2), v);
    else node.setAttribute(k, v);
  }
  node.append(...children.filter((c) => c != null));
  return node;
}

const badge = (key) => el("span", { class: `badge ${SIGNALS[key].tone}` }, SIGNALS[key].label);

// MARK: - データ取得

async function fetchJSON(url) {
  const res = await fetch(url);
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.error ?? `HTTP ${res.status}`);
  return body;
}

async function refresh() {
  if (state.loading) return;
  state.loading = true;
  $("refresh").disabled = true;
  try {
    const results = await Promise.allSettled(
      SCREENERS.map((id) => fetchJSON(`/api/screener?id=${id}`)),
    );
    const ok = results.some((r) => r.status === "fulfilled");
    if (ok) {
      state.byScreener = Object.fromEntries(
        SCREENERS.map((id, i) => [id, results[i].status === "fulfilled" ? results[i].value : []]),
      );
      state.demo = false;
      state.error = null;
    } else {
      state.error = results[0].reason?.message ?? "データを取得できませんでした";
      if (Object.keys(state.byScreener).length === 0 || state.demo) {
        state.byScreener = demoScreeners;
        state.demo = true;
      }
    }
    $("updated").textContent = `最終更新: ${new Date().toLocaleTimeString("ja-JP")}`;
  } finally {
    state.loading = false;
    $("refresh").disabled = false;
  }
  renderList();
  // 選択中の銘柄は最新の値に差し替える
  if (state.selected) {
    const latest = Object.values(state.byScreener).flat().find((q) => q.symbol === state.selected.symbol);
    if (latest) {
      state.selected = latest;
      renderDetail();
    }
  }
}

async function loadChart(symbol, range) {
  if (state.demo) return demoChart(symbol);
  return fetchJSON(`/api/chart?symbol=${encodeURIComponent(symbol)}&range=${range}`);
}

// MARK: - 一覧

function renderTabs() {
  const tabs = $("tabs");
  tabs.replaceChildren(
    ...Object.entries(CATEGORIES).map(([key, label]) =>
      el("button", {
        type: "button",
        role: "tab",
        "aria-selected": String(state.category === key),
        onclick: () => {
          state.category = key;
          renderTabs();
          renderList();
        },
      }, label),
    ),
  );
}

function renderList() {
  $("demo-banner").hidden = !state.demo;
  const quotes = quotesForCategory(state.byScreener, state.category, state.minChange);
  $("quote-rows").replaceChildren(
    ...quotes.map((q) =>
      el("tr", {
        class: state.selected?.symbol === q.symbol ? "selected" : "",
        tabindex: "0",
        onclick: () => select(q),
        onkeydown: (e) => { if (e.key === "Enter") select(q); },
      },
      el("td", {}, el("div", { class: "symbol" }, q.symbol), el("div", { class: "name" }, q.name)),
      el("td", { class: "num" }, fmtPrice(q.price, q.currency)),
      el("td", { class: `num ${tone(q.changePercent)}` }, fmtPct(q.changePercent)),
      el("td", { class: "num col-volume" }, fmtRatio(volumeRatio(q))),
      el("td", {}, el("div", { class: "badges" }, ...signals(q).map(badge))),
      )),
  );
  const empty = $("empty");
  empty.hidden = quotes.length > 0;
  empty.textContent = state.loading && Object.keys(state.byScreener).length === 0
    ? "読み込み中…"
    : `該当する銘柄がありません${state.error ? `（${state.error}）` : ""}`;
}

// MARK: - 詳細

function select(quote) {
  state.selected = quote;
  renderList();
  renderDetail();
}

function describe(key, q) {
  switch (key) {
    case "surge": return `前日比 +${SURGE_THRESHOLD}% 以上の上昇`;
    case "plunge": return `前日比 -${SURGE_THRESHOLD}% 以上の下落`;
    case "volumeSpike": return `出来高が3か月平均の ${fmtRatio(volumeRatio(q))}`;
    case "near52WeekHigh": return "52週高値まで2%以内";
    case "near52WeekLow": return "52週安値まで2%以内";
    default: return "";
  }
}

function renderDetail() {
  const q = state.selected;
  if (!q) return;
  const position = fiftyTwoWeekPosition(q);
  const rows = [
    ["前日比", fmtPrice(q.change, q.currency)],
    ["出来高", fmtCompact(q.volume)],
    ["平均出来高 (3か月)", fmtCompact(q.averageVolume)],
    ["出来高 平均比", fmtRatio(volumeRatio(q))],
    ["52週高値", fmtPrice(q.fiftyTwoWeekHigh, q.currency)],
    ["52週安値", fmtPrice(q.fiftyTwoWeekLow, q.currency)],
    ["時価総額", fmtCompact(q.marketCap)],
    ...(q.exchange ? [["市場", q.exchange]] : []),
  ];
  const sig = signals(q);
  const chartBox = el("div", { class: "chart", id: "chart" }, el("p", { class: "placeholder" }, "チャート読み込み中…"));

  $("detail").replaceChildren(
    el("div", { class: "detail-header" },
      el("h2", {}, q.symbol, el("span", { class: "name" }, q.name)),
      el("div", { class: "price-line" },
        el("span", { class: "big-price" }, fmtPrice(q.price, q.currency)),
        el("span", { class: `pct ${tone(q.changePercent)}` }, fmtPct(q.changePercent)),
      ),
    ),
    el("div", { class: "range-tabs", role: "tablist" },
      ...Object.entries(RANGES).map(([key, label]) =>
        el("button", {
          type: "button",
          role: "tab",
          "aria-selected": String(state.range === key),
          onclick: () => { state.range = key; renderDetail(); },
        }, label),
      ),
    ),
    chartBox,
    sig.length
      ? el("section", {},
        el("h3", {}, "注目ポイント"),
        el("ul", { class: "signals" }, ...sig.map((k) => el("li", {}, badge(k), describe(k, q)))))
      : null,
    el("section", {},
      el("h3", {}, "データ"),
      el("dl", { class: "stats" }, ...rows.flatMap(([k, v]) => [el("dt", {}, k), el("dd", {}, v)])),
      position == null ? null : el("div", { class: "range52" },
        el("span", {}, "52週レンジ内の位置"),
        el("div", { class: "bar" }, el("div", { class: "fill", style: `width:${(position * 100).toFixed(1)}%` })),
      ),
    ),
    el("a", { href: `https://finance.yahoo.com/quote/${encodeURIComponent(q.symbol)}`, target: "_blank", rel: "noopener" },
      "Yahoo Finance で詳しく見る ↗"),
  );

  const { symbol } = q;
  const { range } = state;
  loadChart(symbol, range)
    .then((points) => {
      // 待っている間に銘柄や期間が変わっていたら捨てる
      if (state.selected?.symbol !== symbol || state.range !== range) return;
      drawChart(chartBox, points, q.currency);
    })
    .catch((err) => {
      if (state.selected?.symbol !== symbol || state.range !== range) return;
      chartBox.replaceChildren(el("p", { class: "placeholder" }, `チャートを取得できません（${err.message}）`));
    });
}

// MARK: - チャート (SVG)

const SVG_NS = "http://www.w3.org/2000/svg";
const svg = (tag, attrs = {}) => {
  const node = document.createElementNS(SVG_NS, tag);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
  return node;
};

function drawChart(container, points, currency) {
  if (points.length < 2) {
    container.replaceChildren(el("p", { class: "placeholder" }, "チャートのデータがありません"));
    return;
  }
  const W = 600, H = 240, PAD = { top: 12, right: 12, bottom: 24, left: 12 };
  const closes = points.map((p) => p.close);
  const min = Math.min(...closes), max = Math.max(...closes);
  const span = max - min || 1;
  const x = (i) => PAD.left + (i / (points.length - 1)) * (W - PAD.left - PAD.right);
  const y = (v) => PAD.top + (1 - (v - min) / span) * (H - PAD.top - PAD.bottom);
  const dir = closes.at(-1) >= closes[0] ? "up" : "down";
  const line = points.map((p, i) => `${x(i).toFixed(1)},${y(p.close).toFixed(1)}`).join(" ");
  const area = `${x(0)},${H - PAD.bottom} ${line} ${x(points.length - 1)},${H - PAD.bottom}`;

  const root = svg("svg", { viewBox: `0 0 ${W} ${H}`, class: `chart-svg ${dir}`, role: "img", "aria-label": "価格チャート" });
  root.append(
    svg("polygon", { points: area, class: "area" }),
    svg("polyline", { points: line, class: "line" }),
  );
  const fmtDate = (t) => new Date(t * 1000).toLocaleDateString("ja-JP", { month: "numeric", day: "numeric" });
  for (const [i, anchor] of [[0, "start"], [points.length - 1, "end"]]) {
    const label = svg("text", { x: x(i), y: H - 6, "text-anchor": anchor, class: "axis" });
    label.textContent = fmtDate(points[i].time);
    root.append(label);
  }

  // マウスを乗せた位置の値を表示する
  const cursor = svg("line", { y1: PAD.top, y2: H - PAD.bottom, class: "cursor", visibility: "hidden" });
  const dot = svg("circle", { r: 4, class: "dot", visibility: "hidden" });
  root.append(cursor, dot);
  const tip = el("div", { class: "tooltip", hidden: "" });
  root.addEventListener("pointermove", (e) => {
    const rect = root.getBoundingClientRect();
    const px = ((e.clientX - rect.left) / rect.width) * W;
    const i = Math.round(((px - PAD.left) / (W - PAD.left - PAD.right)) * (points.length - 1));
    const p = points[Math.min(Math.max(i, 0), points.length - 1)];
    const idx = points.indexOf(p);
    cursor.setAttribute("x1", x(idx)); cursor.setAttribute("x2", x(idx));
    dot.setAttribute("cx", x(idx)); dot.setAttribute("cy", y(p.close));
    cursor.setAttribute("visibility", "visible"); dot.setAttribute("visibility", "visible");
    tip.hidden = false;
    tip.textContent = `${new Date(p.time * 1000).toLocaleString("ja-JP")}  ${fmtPrice(p.close, currency)}`;
  });
  root.addEventListener("pointerleave", () => {
    cursor.setAttribute("visibility", "hidden"); dot.setAttribute("visibility", "hidden");
    tip.hidden = true;
  });
  container.replaceChildren(root, tip);
}

// MARK: - 起動

$("min-change").addEventListener("change", (e) => {
  state.minChange = Number(e.target.value);
  renderList();
});
$("refresh").addEventListener("click", refresh);

renderTabs();
renderList();
refresh();
// タブが表示されている間だけ定期更新する
setInterval(() => { if (document.visibilityState === "visible") refresh(); }, REFRESH_MS);
document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible") refresh(); });
