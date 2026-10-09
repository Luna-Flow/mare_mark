# ir_model design

## Design goal

Separate what a report says from how it is drawn. Plot IR is a small,
versioned data model that `report` produces from events and that any renderer
(the built-in SVG/HTML, a notebook, a dashboard) can consume.

## Constraints

- Scales are integers, shapes, layouts or names, so one axis type must cover
  them all.
- Documents are read by renderers that may be newer or older than the writer.
- The IR carries data only; it computes nothing.

## Mathematical background

A plot is a finite multiset of points $(x, y, s)$ with an $x$ given as text, a
real $y$ and a series label $s$. The renderer's line through a series is the
map

$$
x \mapsto \bar y_{s}(x) = \frac{1}{\lvert\{\,p : p.x = x,\ p.s = s\,\}\rvert} \sum_{p.x = x,\ p.s = s} p.y ,
$$

defined on the categories where the series has points. Because the points are
kept, any other summary (median, quantiles) can be computed from the same IR
without loss; a summary-only IR could not recover the points.

The axis is a choice of placement $X$ for the distinct x values
$v_1, \dots, v_m$ in order of first appearance. On a categorical axis
$X(v_i)$ depends only on $i$; on a linear axis $X(v) = a + b\,\nu(v)$ with
$\nu(v)$ the numeric value of the text and $b > 0$, so distances between
positions are proportional to differences of value and the order of the
positions is the numeric order, whatever the order of the points. The linear
placement is defined only when every $\nu(v_i)$ is a finite number, which is
why the renderer falls back to the categorical one otherwise.

## Design decisions

### Text x with a declared axis

*Problem.* Scales are integers, shapes, layouts or names, and numeric scales
read badly when spaced evenly: 64, 128 and 4096 look equally far apart.
*Options.* A typed x (number or string) per point; a text x with a per-plot
axis declaration. *Choice.* `x` is a string, and `Plot.x_axis` says whether
the values are categories or numbers (`AxisScale::Categorical` or `Linear`).
*Why.* One representation still covers every scale type and round-trips
through JSON without loss (a scale like `"1e3"` or `"0x10"` keeps the text the
producer chose), while the producer, which knows whether its scales are
numbers, decides how they are placed. `x_label` names the axis and `note`
says what the points are, so a reader of an exported plot does not need the
code that made it.

### Comparisons as data

*Problem.* A report shows decisions (`Faster`, `Slower`, ...) next to the
plots, and other renderers need them too. *Choice.* `ComparisonReport` and its
rows carry the decision, the point estimates, the interval, the block counts,
the seed and the settings with their source, all as plain values. *Why.* The
IR stays free of statistics: `report` computes the rows with `stats`, and a
notebook or dashboard reading the `mmks_1` JSON can show the same decisions
without recomputing them, or recompute them from the record and compare. The
settings travel with the rows because a decision is meaningless without its
threshold, outlier policy and confidence.

### Raw points, not summaries

Points carry raw values; interval and summary plots are just plots whose
points are summaries, labelled by `interval_kind`. The IR does not have to
know which statistic produced a number.

### Differential evidence next to plots

The `DifferentialReport` lives in the same document as the plots. A renderer
cannot show the timings of a run without having the correctness evidence of the
same run at hand.

### A version in every document

`schema_version` is set by `PlotDocument::new` to `mmks_2` and written into the
JSON form, so consumers can reject documents they do not understand.

## Correctness and invariants

- `PlotDocument::new` always sets `schema_version` to `V2`; V1 is deprecated
  because it has no y-axis scale field.
- `DifferentialReport::empty()` has no rows and zero counts.
- `DifferentialReport::empty()` and `ComparisonReport::empty()` have no rows
  and zero counts.
- `Plot::new` without the optional arguments gives a categorical axis with no
  label and no note, the plots documents had before these fields existed.
- Records are plain data: no validation, no derived fields.

## Alternatives rejected

- **Renderer-inferred axes.** Rejected because a consumer must be able to
  reproduce the writer's coordinate mapping from the IR alone. Each plot
  carries both axis scales.
- **A typed x per point.** Mixed types in one plot have no meaningful
  placement, and JSON would lose the producer's text of a number.
- **A plotting library's specification format.** Would tie the IR to one
  renderer.

## Boundaries

- No rendering (that is `report`), no parsing, no statistics; comparison rows
  are stored, not computed.
- The corpus total is not checked against the other counts.
- `PlotKind::Pareto` is a categorical scatter; there is no two-axis frontier
  in the IR.
