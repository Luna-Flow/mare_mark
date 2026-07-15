# `stats` API

- `summarize`: count、extrema、mean、median、MAD、quartile、IQR、population standard deviation。
- `paired_deltas`: candidate から baseline を引いた paired delta。
- `compare_paired`: relative median delta、speedup、quartile interval、decision、sample count。
- `bootstrap_interval`: 明示的な seed、resample count、confidence level、interval mode から決定的な percentile bootstrap interval を返します。
- `compare_paired_with_bootstrap`: paired baseline/candidate measurement にその interval を適用します。
- `filter_outliers`: report-only、Tukey fence、MAD trim。
- `is_faster`: `Faster` decision の判定。

Bootstrap 関数は `Result` を返し、`BootstrapError` が空 sample、pair 数の不一致、
不正な設定、非有限値を区別します。

正確な signature は `src/stats/pkg.generated.mbti` を参照してください。
