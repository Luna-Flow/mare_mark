# `report` 設計

レポート backend は純粋な projection です。JSON は core encoder、SVG/HTML は
interpolation 前の text/attribute escape を使用し、filesystem には触れません。

renderer は point から category と series を抽出し、padding 付き Y range を計算します。
line は重複 category の平均を結びますが、raw point は tooltip 付き mark として残します。
HTML は remote asset を必要としません。

Plot IR の `x` は categorical なので、Pareto は現時点で numeric two-axis frontier
ではなく categorical scatter です。JSONL projection は scaling plot 一枚を生成します。

