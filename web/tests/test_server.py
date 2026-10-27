import json
import sys
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import server  # noqa: E402


class NormalizeTests(unittest.TestCase):
    def test_screener_accepts_plain_and_raw_numbers(self):
        payload = {"finance": {"result": [{"quotes": [
            {"symbol": "AAA", "shortName": "Alpha", "regularMarketPrice": 12.5,
             "regularMarketChangePercent": 7.2, "regularMarketVolume": 3000,
             "averageDailyVolume3Month": 1000},
            {"symbol": "BBB", "longName": "Beta Inc",
             "regularMarketPrice": {"raw": 3.25, "fmt": "3.25"}},
            {"shortName": "no symbol"},
        ]}]}}
        quotes = server.normalize_screener(payload)
        self.assertEqual([q["symbol"] for q in quotes], ["AAA", "BBB"])
        self.assertEqual(quotes[0]["name"], "Alpha")
        self.assertEqual(quotes[0]["volume"], 3000.0)
        self.assertEqual(quotes[0]["currency"], "USD")
        self.assertEqual(quotes[1]["name"], "Beta Inc")
        self.assertEqual(quotes[1]["price"], 3.25)
        self.assertIsNone(quotes[1]["changePercent"])

    def test_empty_screener_raises(self):
        with self.assertRaises(ValueError):
            server.normalize_screener({"finance": {"result": []}})

    def test_chart_skips_nulls(self):
        payload = {"chart": {"result": [{
            "timestamp": [1, 2, 3],
            "indicators": {"quote": [{"close": [10.0, None, 12.5]}]},
        }]}}
        self.assertEqual(server.normalize_chart(payload),
                         [{"time": 1, "close": 10.0}, {"time": 3, "close": 12.5}])


class FakeClient:
    def screener(self, screener_id, count=25):
        return [{"symbol": "AAA", "screener": screener_id}]

    def chart(self, symbol, range_):
        raise urllib.error.URLError("offline")


class HandlerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        handler = type("TestHandler", (server.Handler,), {"client": FakeClient()})
        cls.httpd = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        cls.base = f"http://127.0.0.1:{cls.httpd.server_address[1]}"
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()

    def get(self, path):
        try:
            with urllib.request.urlopen(self.base + path) as res:
                return res.status, res.headers, res.read()
        except urllib.error.HTTPError as error:
            return error.code, error.headers, error.read()

    def test_screener_proxy(self):
        status, _, body = self.get("/api/screener?id=day_gainers")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body), [{"symbol": "AAA", "screener": "day_gainers"}])

    def test_rejects_unknown_screener_and_bad_symbol(self):
        self.assertEqual(self.get("/api/screener?id=../etc")[0], 400)
        self.assertEqual(self.get("/api/chart?symbol=A%2FB&range=1mo")[0], 400)
        self.assertEqual(self.get("/api/chart?symbol=AAPL&range=10y")[0], 400)

    def test_upstream_failure_is_502(self):
        status, _, body = self.get("/api/chart?symbol=AAPL&range=1mo")
        self.assertEqual(status, 502)
        self.assertIn("error", json.loads(body))

    def test_serves_js_as_javascript(self):
        status, headers, _ = self.get("/app.js")
        self.assertEqual(status, 200)
        self.assertEqual(headers.get_content_type(), "text/javascript")


if __name__ == "__main__":
    unittest.main()
