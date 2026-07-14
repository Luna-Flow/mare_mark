# `runner` 設計

可変状態は prepared input と sink accumulation の内部に限定します。各 scale は一度
materialize し、implementation ごとに clone/prepare して balanced order で実行し、
block 完了後に reset します。

計時は payload と output fold を含み、`finish` と `Bench::keep` の前に停止します。
レポート生成と file IO は measurement closure に入りません。

Oracle/relational validation は計時外で実行します。`OperationResult.next_context` を
sequence 全体で引き継ぎ、setup frequency に従って prepare/reset します。危険な実装は
native subprocess で隔離し、timeout、exit status、stdout、stderr を保存します。
calibration は measurement phase の外で iteration bounds 内の target time を探索し、
elapsed time、target time、retry count を記録します。exploratory observation と固定予算の
confirmatory observation は別 phase です。
