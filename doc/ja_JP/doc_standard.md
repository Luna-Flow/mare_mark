# ドキュメント標準

ドキュメントには現在の branch で実装済みの機能だけを記載します。

- locale 文書は `doc/en_US`、`doc/zh_CN`、`doc/ja_JP` に置きます。
- 英語を構造上の基準とし、翻訳は同じ相対パスを保ちます。
- 各 package は `api.md`、`design.md`、`tutorial.md` を使用します。
- `README.mbt.md` は package 内の短い入口です。
- MoonBit の公開シグネチャは `pkg.generated.mbti` を基準とします。

`api.md` は呼び出し可能な動作、`tutorial.md` は最短の実用フロー、`design.md` は
責務・不変条件・effect・制限、`verification.md` は再現可能な証拠を扱います。

コマンド、識別子、package path、schema 名、version は翻訳しません。コードと
対象テストが存在しない機能を完成済みとして記載してはいけません。

