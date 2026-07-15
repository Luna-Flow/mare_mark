# `stats` 設計

統計処理は明示的な配列に対する純粋な変換です。raw event は sink が所有するため、
filtering が履歴を書き換えることはありません。

`compare_paired` は paired median delta と practical percentage threshold を使います。
既定の `Interval` は互換性のため delta の quartile range を保持します。
`compare_paired_with_bootstrap` は paired delta を復元抽出し、明示的な seed、
resample count、confidence level に基づく percentile interval を返します。

不正な bootstrap 入力は `BootstrapError` で表現します。現在の実装は BCa、
studentized、hierarchical bootstrap ではありません。`summarize` の空入力は neutral
summary のままですが、bootstrap の空 sample は拒否されます。
