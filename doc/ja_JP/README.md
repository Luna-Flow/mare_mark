# Mare Mark ドキュメント

このドキュメントは `0.1.0` の実装状況を説明します。公開名とシグネチャの基準は
各 package の `pkg.generated.mbti` です。

[はじめに](./getting_started.md)、[アーキテクチャ](./architecture.md)、
[検証](./verification.md)の順に読むことを推奨します。

## 主要 package

- Runner: [API](./runner/api.md)、[チュートリアル](./runner/tutorial.md)、[設計](./runner/design.md)
- 統計: [API](./stats/api.md)、[チュートリアル](./stats/tutorial.md)、[設計](./stats/design.md)
- レポート: [API](./report/api.md)、[チュートリアル](./report/tutorial.md)、[設計](./report/design.md)

## その他の package

`model`、`generator`、`fixture`、`event`、`ir_sink`、`experiment`、
`ir_model`、`tune`、`tune_gemm`、`cli` はアーキテクチャ文書で概説します。
今後の package 文書も実装と生成インターフェースに合わせて拡張します。

Mare Mark は 1.0 未満です。`mmk-plot-v2` と JSONL フィールドはバージョン付き
artifact ですが、全 package の長期互換性はまだ保証しません。
