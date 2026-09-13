<!-- zhc-i18n 源: README.md 基线: 55556d611cf2892b 时间: 2026-09-13 -->

# zhc — 自国の言葉で倉頡（Cangjie）を書こう

Language / Langue / Sprache / Idioma / 언어 / 言語 / Язык：[中文](../../../README.md) · [English](../en/README.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md) · [Español](../es/README.md) · [한국어](../ko/README.md) · **日本語** · [Русский](../ru/README.md) · [العربية](../ar/README.md)

**zhc** は倉頡（Cangjie）プログラミング言語の母語学習フレームワークです。方言ソース
コード（中国語 `.zc`、日本語 `.jc`、フランス語 `.fc` など）を標準倉頡コードへ
トランスパイルし、コンパイラの英語診断を選択した言語の学習向けメッセージに翻訳します
（エラーコード → メッセージテーブル → 型のローカライズ → 修正例）。方言は `ZHCLANG`
環境変数で切り替え（既定 `zh`）、すべての動作は**言語パック**が主導します。

## クイックスタート（約 10 分）

**1. 倉頡 SDK のインストール**（唯一の外部依存）：cangjie-lang.cn/download から
**1.0.5** をダウンロードし、同梱の `envsetup.sh` を実行して `cjc` と `cjpm` を
`PATH` に通します。確認：

```bash
cjc --version    # Cangjie Compiler: 1.0.5 (cjnative)
```

**2. zhc のビルド**（ネットワーク不要、サードパーティ依存なし）：

```bash
cd zhc
cjpm build       # target/release/bin/main を生成
```

**3. 最初のプログラムを実行**（同梱の日本語方言サンプル）：

```bash
export ZHC_LANG_PACKS=$PWD        # リポジトリルート基準：zhc/
zhc run examples/ja-hello.jc
# ✅ Compilation OK: replaced 7 dialect identifier(s).
# こんにちは、日本！
# 数: 42
```

## 自国語で書く

`zhc/lang-packs/<コード>/` に言語パックがある言語はすべて使えます — `zh`/`en`（完全レベル）、`ru`/`ja`/`ko`/`fr`/`es`/`de`（標準レベル）、`ar`（RTL デモ）の 9 パックを同梱。たとえば
日本語（`ZHCLANG=ja`、拡張子 `.jc`）：

```jc
メイン() {
    おく 名前: 文字列 = "Cangjie"
    ひょうじ("こんにちは、${名前}！")
}
```

実行：`ZHCLANG=ja zhc run hello.jc`。ドイツ語・スペイン語などの方言も同じ方式で
動作します（`Haupt/Lege/Zeige`、`principal/defina/mostrar` など）。

## サードパーティライブラリの翻訳

ライブラリ API のマッピングは共有翻訳リポジトリにあり、ソースツリーには含まれません
— 必要な言語とライブラリだけを取得します：

```bash
zhc share list                     # 共有レジストリを閲覧
zhc share fetch csv4cj --lang ja   # 自分の言語のマッピングだけダウンロード
zhc share publish 自分のマッピング.toml   # 自分の翻訳を共有する
```

ダウンロードされたマッピングはチェックサム + 品質ゲート（形式、公式名検査、予約語
衝突）を通過してから `~/.zhc/lang-packs/<言語>/crates/` にインストールされます。
翻訳が無い場合は中国語へ優雅にフォールバックし、どちらでもプログラムは動作します。

## 用語（日本語ドキュメント全体で統一）

| 日本語 | コード/ドキュメント表記 | 備考 |
|---|---|---|
| 方言 | `.zc` `.jc` `.fc` … | 母語で書いた倉頡コード |
| 言語パック | `lang-packs/<コード>/` | キーワード/エイリアス表 + 診断 + UI 文言 |
| マッピング | `crates/<言語>/<ライブラリ>.toml` | 母語名 = 公式 API 名 |
| トランスパイル | `zhc run` / `zhc check` | 方言 → 標準倉頡 |
| 共有リポジトリ | `zhc share …` | 翻訳の一元レジストリ |
| 基準線 | `zh@<チェックサム>` | zh 原本の同期フィンガープリント |

## さらに学ぶ

- チュートリアル（正本、中国語）：[中国語で倉頡を設計する — 正本チュートリアル](../../../docs/中文仓颉程序设计/README.md)
- 言語パック開発とコントリビュート：[言語パック開発ガイド](../../../docs/语言包开发.md)
- ローカリゼーション範囲と同期メカニズム：[docs/i18n/README.md](../README.md)
- チュートリアル日本語ガイド：[チュートリアル導学（第 0 課）](tutorial-00.md)
- トラブルシューティング: `zhc doctor` — 6 項目の環境セルフチェック（コンパイラ、ビルド、言語パック、書き込み可能 dir、共有ソース、cjlint）を母語の修正案つきで実行。
