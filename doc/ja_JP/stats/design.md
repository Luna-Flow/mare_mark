# `stats` 設計

統計処理は明示的な配列に対する純粋な変換です。raw event は sink が所有するため、
filtering が履歴を書き換えることはありません。

`compare_paired` は paired median delta と practical percentage threshold を使います。
`Interval` は delta の quartile range であり、bootstrap/confidence interval では
ありません。空入力は neutral summary と `Unknown` を返します。

