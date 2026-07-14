# `report` 设计

报告后端是纯投影。JSON 使用 core 结构化 encoder；SVG 与 HTML 在插值前转义文本和
属性。任何 report 函数都不访问文件系统。

Renderer 从 point 推导类别与系列，计算带 padding 的动态 Y 范围；连接线使用重复类别
均值，但每个原始 point 都保留为带 tooltip 的 mark。HTML 不依赖远程资源。

Plot IR 的 `x` 仍是类别，因此 Pareto 当前是类别 scatter，而非数值双轴 frontier。
JSONL 投影当前只创建一张 scaling 图，target 由调用方显式提供。

