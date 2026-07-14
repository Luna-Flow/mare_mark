# `runner` 设计

Runner 把可变状态限制在 prepared input 与 sink 累计内部。每个 scale 只 materialize
一次，再为各实现 clone/prepare，按 balanced order 执行，完整 block 结束后 reset。

计时覆盖 payload 执行与输出 fold；时钟停止后才调用 `finish` 和 `Bench::keep`。
报告渲染与文件 IO 不进入测量闭包。

每个实现先执行同一套 warmup 协议，再进入 calibration。计时 block 在 exploratory 与
confirmatory phase 之间延续同一个 seeded balanced order；每个完整周期中，各实现恰好
占据每个执行位置一次。Runner 保留多次原始观测，稳健汇总使用 median 而不是 mean。

异步设备可为实现提供阻塞式 `synchronize` 钩子。Runner 在每个计时区间的前后显式调用
该钩子，使排队任务在计时结束前完成。fixture 分配与 reset 是否计时由 `SetupTiming`
决定；校验、事件写入、最终 sink 转换和报告日志始终在计时区间外。

Oracle/relational validation 在计时外执行；`OperationResult.next_context` 在序列中逐步
传递，fixture 按 setup frequency 对称 prepare/reset。危险实现通过 native 子进程隔离，
记录 timeout、退出状态、stdout 与 stderr。calibration 在 measurement phase 外于
iteration 上下限之间搜索目标时间，并记录 elapsed time、target time 与 retry count。
exploratory observation 与固定预算 confirmatory observation 分属不同 phase。

运行摘要保留 semantic、performance 与 provenance 环境；performance 元数据包括 CPU、
device、concurrency、clock、GC 与 frequency policy。跨环境比较前应要求
`environment_compatible` 返回 `true`。
