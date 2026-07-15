# はじめに

## レポート生成

実装済みの end-to-end 経路は同梱 fixture で確認できます。

```sh
moon run src/cli --target native -- report \
  testdata/report/sample.jsonl report.html
```

このコマンドは observation と summary の JSONL event を読み、scaling Plot IR を
構築し、SVG と CSS を内包する HTML を出力します。

```moonbit nocheck
import {
  "Luna-Flow/mare_mark/model"
  "Luna-Flow/mare_mark/runner"
  "Luna-Flow/mare_mark/stats"
  "Luna-Flow/mare_mark/report"
}
```

`runner.single_step` で immutable description を作って `compile` し、plan と
`RunContext` を `runner.run` に渡します。event stream を保存してから配列を
`stats.compare_paired` に渡します。レポートは Plot IR を構築して
`report.plot_svg` または `report.html` に渡します。

CLI は artifact のみを扱います。`replay` は native target で
`validation_failure` JSONL に記録された worker command を実行し、typed case の
構築と実行は MoonBit API から行います。これにより引数解析、filesystem access、
report rendering は benchmark の計時経路に入りません。
