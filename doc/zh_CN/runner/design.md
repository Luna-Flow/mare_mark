# `runner` 设计

Runner 把可变状态限制在 prepared input 与 sink 累计内部。每个 scale 只 materialize
一次，再为各实现 clone/prepare，按 balanced order 执行，完整 block 结束后 reset。

计时覆盖 payload 执行与输出 fold；时钟停止后才调用 `finish` 和 `Bench::keep`。
报告渲染与文件 IO 不进入测量闭包。

Oracle/relational validation 在计时外执行；`OperationResult.next_context` 在序列中逐步
传递，fixture 按 setup frequency 对称 prepare/reset。危险实现通过 native 子进程隔离，
记录 timeout、退出状态、stdout 与 stderr。calibration 在 measurement phase 外于
iteration 上下限之间搜索目标时间，并记录 elapsed time、target time 与 retry count。
exploratory observation 与固定预算 confirmatory observation 分属不同 phase。
