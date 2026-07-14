# 快速上手

## 生成报告

仓库内样例可以执行当前已打通的端到端路径：

```sh
moon run src/cli --target native -- report \
  testdata/report/sample.jsonl report.html
```

命令读取 observation 与 summary JSONL 事件，构造 scaling Plot IR，并写出内嵌
SVG 与 CSS 的自包含 HTML。

## 直接组合 package

```moonbit nocheck
import {
  "Luna-Flow/mare_mark/model"
  "Luna-Flow/mare_mark/runner"
  "Luna-Flow/mare_mark/stats"
  "Luna-Flow/mare_mark/report"
}
```

用 `runner.run_case` 产生原始测量，保留事件流，再把配对数组交给
`stats.compare_paired`；报告端先构造 Plot IR，再调用 `report.plot_svg` 或
`report.html`。

CLI 有意只处理 artifact。`replay` 会在 native target 读取
`validation_failure` JSONL 并执行其中记录的 worker 命令；应用通过 MoonBit API
组合并执行 typed case。这样参数解析、文件系统访问和报告渲染不会进入 benchmark
计时路径。
