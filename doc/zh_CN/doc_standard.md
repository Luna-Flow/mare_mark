# 文档标准

文档只描述当前分支已经实现的能力，不把规划中的 API 写成现状。

## 结构

- 本地化文档位于 `doc/en_US`、`doc/zh_CN` 和 `doc/ja_JP`。
- 英文是结构基线，翻译保持相同相对路径。
- 每个已文档化的包使用 `api.md`、`design.md` 和 `tutorial.md`。
- `README.mbt.md` 是包内的简短入口。
- MoonBit 公开签名以 `pkg.generated.mbti` 为准。

`api.md` 说明可调用行为，`tutorial.md` 给出最短真实流程，`design.md` 记录职责、
不变量、副作用和限制，`verification.md` 记录可复现证据而不夸大覆盖。

命令、标识符、包路径、schema 名和版本号不翻译。能力只有在代码与针对性测试都
覆盖后，才能写成已完成。

