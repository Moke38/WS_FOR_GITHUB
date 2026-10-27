# 値動きウォッチ (StockMover)

米国株の中から「面白い値動き」をしている銘柄を見つけて表示するアプリ。iOS 版（SwiftUI / iOS 17+）とブラウザ版があります。

## 機能

- **注目タブ**: 値上がり・値下がり・出来高上位・小型株値上がりのスクリーナー結果をまとめ、独自スコアで並べ替え
- **値上がり / 値下がり / 出来高** タブ
- 各銘柄に「急騰」「急落」「出来高急増」「52週高値圏」「52週安値圏」のバッジを表示
- 変動率フィルタ（±3% / ±5% / ±10% 以上）
- 銘柄詳細: Swift Charts による価格チャート（1日〜1年）、出来高の平均比、52週レンジ内の位置
- 引っ張って更新 + フォアグラウンド中は60秒ごとに自動更新
- 通信できないときはデモデータに切り替え

### 「面白さ」の判定 (`InterestAnalyzer`)

| シグナル | 条件 |
| --- | --- |
| 急騰 / 急落 | 前日比 ±5% 以上 |
| 出来高急増 | 当日出来高が3か月平均の3倍以上 |
| 52週高値圏 / 安値圏 | 52週高値・安値から2%以内 |

スコア = `|変動率%| + log2(出来高平均比) × 3 + (52週の節目なら +3)`

しきい値は `StockMover/Models/MoverSignal.swift` で変更できます。

## ビルド方法

Mac と Xcode 16 以降が必要です。

```sh
brew install xcodegen
xcodegen generate
open StockMover.xcodeproj
```

実機で動かす場合は Xcode の Signing & Capabilities で自分のチームを選び、Bundle Identifier を変更してください。

## ブラウザ版 (Windows / Mac / Linux)

`web/` フォルダにブラウザで使える版があります。機能と判定ロジックは iOS 版と同じです。

ブラウザから Yahoo Finance を直接呼ぶことはできない（CORS の制限）ため、付属の小さなサーバー `server.py` が中継します。Python の標準ライブラリだけで動くので、追加のインストールは不要です。

**Windows での使い方**

1. [Python](https://www.python.org/downloads/) 3.8 以降をインストール（インストーラーの「Add python.exe to PATH」にチェック）
2. `web\start.bat` をダブルクリック
3. ブラウザで http://127.0.0.1:8000 が自動的に開きます。終了するときはコンソールウィンドウで Ctrl+C

コマンドラインからは `python web/server.py`（`--port 9000` でポート変更、`--no-browser` でブラウザを開かない）。サーバーは `127.0.0.1` でだけ待ち受けるので、他の PC からはアクセスできません。

テスト: `cd web && python -m unittest discover -s tests && node --test tests/analyzer.test.mjs`

## データソースについて

Yahoo Finance の**非公式**エンドポイントを使っています。仕様変更で動かなくなったり、利用規約上の制約があったりするため、個人利用の範囲にとどめてください。App Store で配布する場合は、Finnhub・Polygon.io・Alpha Vantage などの正式な API に `StockService` プロトコルを実装して差し替えてください。

表示される情報は投資助言ではありません。
