# `runner` 設計

可変状態は prepared input と sink accumulation の内部に限定します。各 scale は一度
materialize し、implementation ごとに clone/prepare して balanced order で実行し、
block 完了後に reset します。

計時は payload と output fold を含み、`finish` と `Bench::keep` の前に停止します。
レポート生成と file IO は measurement closure に入りません。

すべての implementation に同じ warmup protocol を適用してから calibration を行います。
timed block は exploratory と confirmatory phase をまたいで一つの seeded balanced order
を継続し、完全な cycle ごとに各 implementation が各実行位置を一度ずつ占めます。
複数回の raw observation を保持し、robust summary には mean ではなく median を使います。

非同期 device 向けには、blocking `synchronize` hook を implementation に設定できます。
各 timed region の直前と直後に明示的に呼び出すため、queue 済み work の完了までを計測
できます。fixture allocation と reset は `SetupTiming` に従い、validation、event emit、
final sink conversion、report logging は常に計時外です。

Oracle/relational validation は計時外で実行します。`OperationResult.next_context` を
sequence 全体で引き継ぎ、setup frequency に従って prepare/reset します。危険な実装は
native subprocess で隔離し、timeout、exit status、stdout、stderr を保存します。
calibration は measurement phase の外で iteration bounds 内の target time を探索し、
elapsed time、target time、retry count を記録します。exploratory observation と固定予算の
confirmatory observation は別 phase です。

run summary は semantic、performance、provenance environment を保持します。
performance metadata は CPU、device、concurrency、clock、GC、frequency policy を含み、
比較前に `environment_compatible` が `true` であることを確認します。
