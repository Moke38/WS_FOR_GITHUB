"""値動きウォッチ (ブラウザ版) のローカルサーバー。

ブラウザからは CORS の制約で Yahoo Finance を直接呼べないため、
このサーバーが静的ファイルの配信と API の中継を行う。標準ライブラリのみで動作する。

    python server.py            # http://127.0.0.1:8000 をブラウザで開く
    python server.py --port 9000 --no-browser
"""

import argparse
import json
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

STATIC_DIR = Path(__file__).resolve().parent / "static"
YAHOO_BASE = "https://query1.finance.yahoo.com"
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"

SCREENERS = {"day_gainers", "day_losers", "most_actives", "small_cap_gainers"}
# 期間 -> 足の間隔
RANGES = {"1d": "5m", "5d": "30m", "1mo": "1d", "6mo": "1d", "1y": "1wk"}
SYMBOL_PATTERN = re.compile(r"^[A-Za-z0-9.\-=^]{1,15}$")
CACHE_SECONDS = 30

QUOTE_FIELDS = {
    "price": "regularMarketPrice",
    "change": "regularMarketChange",
    "changePercent": "regularMarketChangePercent",
    "volume": "regularMarketVolume",
    "averageVolume": "averageDailyVolume3Month",
    "fiftyTwoWeekHigh": "fiftyTwoWeekHigh",
    "fiftyTwoWeekLow": "fiftyTwoWeekLow",
    "marketCap": "marketCap",
}


def number(value):
    """Yahoo は数値を 123.4 と {"raw": 123.4, "fmt": "..."} のどちらでも返すので両方受け付ける。"""
    if isinstance(value, dict):
        value = value.get("raw")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
    return None


def normalize_screener(payload):
    results = (payload.get("finance") or {}).get("result") or []
    if not results:
        raise ValueError("スクリーナーの結果が空です")
    quotes = []
    for raw in results[0].get("quotes") or []:
        symbol = raw.get("symbol")
        if not symbol:
            continue
        quote = {
            "symbol": symbol,
            "name": raw.get("shortName") or raw.get("longName") or symbol,
            "currency": raw.get("currency") or "USD",
            "exchange": raw.get("fullExchangeName"),
        }
        for key, source in QUOTE_FIELDS.items():
            quote[key] = number(raw.get(source))
        quotes.append(quote)
    return quotes


def normalize_chart(payload):
    results = (payload.get("chart") or {}).get("result") or []
    if not results:
        raise ValueError("チャートの結果が空です")
    result = results[0]
    timestamps = result.get("timestamp") or []
    series = (result.get("indicators") or {}).get("quote") or [{}]
    closes = series[0].get("close") or []
    return [
        {"time": int(t), "close": float(c)}
        for t, c in zip(timestamps, closes)
        if isinstance(c, (int, float))
    ]


class YahooClient:
    def __init__(self, base=YAHOO_BASE):
        self.base = base
        self._cache = {}
        self._lock = threading.Lock()

    def _get_json(self, path, params):
        url = f"{self.base}{path}?{urllib.parse.urlencode(params)}"
        now = time.monotonic()
        with self._lock:
            cached = self._cache.get(url)
            if cached and now - cached[0] < CACHE_SECONDS:
                return cached[1]
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(request, timeout=15) as response:
            payload = json.load(response)
        with self._lock:
            self._cache[url] = (now, payload)
        return payload

    def screener(self, screener_id, count=25):
        payload = self._get_json(
            "/v1/finance/screener/predefined/saved",
            {"scrIds": screener_id, "count": count, "lang": "en-US", "region": "US"},
        )
        return normalize_screener(payload)

    def chart(self, symbol, range_):
        payload = self._get_json(
            f"/v8/finance/chart/{urllib.parse.quote(symbol)}",
            {"range": range_, "interval": RANGES[range_]},
        )
        return normalize_chart(payload)


class Handler(SimpleHTTPRequestHandler):
    client = YahooClient()
    # Windows ではレジストリの設定次第で .js が text/plain になり、ES モジュールが読めなくなるため固定する
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".js": "text/javascript",
        ".css": "text/css",
        ".html": "text/html",
    }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(STATIC_DIR), **kwargs)

    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        if not url.path.startswith("/api/"):
            return super().do_GET()
        query = urllib.parse.parse_qs(url.query)
        try:
            if url.path == "/api/screener":
                screener_id = (query.get("id") or [""])[0]
                if screener_id not in SCREENERS:
                    return self._send_json(400, {"error": "不明なスクリーナーです"})
                return self._send_json(200, self.client.screener(screener_id))
            if url.path == "/api/chart":
                symbol = (query.get("symbol") or [""])[0]
                range_ = (query.get("range") or ["1mo"])[0]
                if not SYMBOL_PATTERN.match(symbol) or range_ not in RANGES:
                    return self._send_json(400, {"error": "パラメータが不正です"})
                return self._send_json(200, self.client.chart(symbol, range_))
            return self._send_json(404, {"error": "見つかりません"})
        except urllib.error.HTTPError as error:
            return self._send_json(502, {"error": f"データ取得エラー (HTTP {error.code})"})
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            return self._send_json(502, {"error": f"データ取得エラー ({error})"})
        except ValueError as error:
            return self._send_json(502, {"error": str(error)})

    def _send_json(self, status, body):
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format, *args):
        # API 以外のアクセスログは出さない
        if self.path.startswith("/api/"):
            super().log_message(format, *args)


def main():
    parser = argparse.ArgumentParser(description="値動きウォッチ (ブラウザ版)")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--no-browser", action="store_true", help="起動時にブラウザを開かない")
    args = parser.parse_args()

    # 外部からはアクセスさせない
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    url = f"http://127.0.0.1:{args.port}/"
    print(f"値動きウォッチを起動しました: {url}  (終了するには Ctrl+C)")
    if not args.no_browser:
        threading.Timer(0.5, webbrowser.open, args=(url,)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
