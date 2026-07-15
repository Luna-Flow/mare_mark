# mare_mark ドキュメント

このドキュメントは `0.3.0` の実装状況を説明します。公開名とシグネチャの基準は
各 package の `pkg.generated.mbti` です。

[はじめに](./getting_started.md)、[アーキテクチャ](./architecture.md)、
[Package reference](./package_reference.md)、[検証](./verification.md)の順に読むことを推奨します。

## 主要 package

- Runner: [API](./runner/api.md)、[チュートリアル](./runner/tutorial.md)、[設計](./runner/design.md)
- 統計: [API](./stats/api.md)、[チュートリアル](./stats/tutorial.md)、[設計](./stats/design.md)
- レポート: [API](./report/api.md)、[チュートリアル](./report/tutorial.md)、[設計](./report/design.md)

## Package map

| 境界 | Package |
| --- | --- |
| Protocol と event | `model`、`event`、`ir_sink` |
| 入力と lifecycle | `generator`、`fixture` |
| 検証と測定 | `experiment`、`runner` |
| 分析と表示 | `stats`、`ir_model`、`report` |
| 探索 policy | `tune`、`tune_gemm` |
| Native の file/process effect | `cli` |

## その他の package

各 package の責務、測定境界、安定性は [Package reference](./package_reference.md)
にまとめています。正確な公開名とシグネチャは各 package の
`pkg.generated.mbti` を基準にします。

mare_mark は 1.0 未満です。Plot schema `mmks_1` と JSONL artifact version
`mmka_1` は明示的な互換性マーカーですが、全 package の長期互換性はまだ保証しません。
