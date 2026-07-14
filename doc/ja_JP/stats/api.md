# `stats` API

- `summarize`: count、extrema、mean、median、MAD、quartile、IQR、population standard deviation。
- `paired_deltas`: candidate から baseline を引いた paired delta。
- `compare_paired`: relative median delta、speedup、quartile interval、decision、sample count。
- `filter_outliers`: report-only、Tukey fence、MAD trim。
- `is_faster`: `Faster` decision の判定。

正確な signature は `src/stats/pkg.generated.mbti` を参照してください。

