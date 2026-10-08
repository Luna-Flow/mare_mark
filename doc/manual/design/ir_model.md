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

A plot is a finite multiset of points $(x, y, s)$ with a categorical $x$, a
real $y$ and a series label $s$. The renderer's line through a series is the
map

$$
x \mapsto \bar y_{s}(x) = \frac{1}{\lvert\{\,p : p.x = x,\ p.s = s\,\}\rvert} \sum_{p.x = x,\ p.s = s} p.y ,
$$

defined on the categories where the series has points. Because the points are
kept, any other summary (median, quantiles) can be computed from the same IR
without loss; a summary-only IR could not recover the points.

## Design decisions

### Categorical x

*Problem.* Scales are integers, shapes, layouts or names. *Choice.* `x` is a
string. *Why.* One representation covers every scale type, and the order of
first appearance is the order the producer chose. Numeric spacing would need a
scale type in the IR.

### Raw points, not summaries

Points carry raw values; interval and summary plots are just plots whose
points are summaries, labelled by `interval_kind`. The IR does not have to
know which statistic produced a number.

### Differential evidence next to plots

The `DifferentialReport` lives in the same document as the plots. A renderer
cannot show the timings of a run without having the correctness evidence of the
same run at hand.

### A version in every document

`schema_version` is set by `PlotDocument::new` to `mmks_1` and written into the
JSON form, so consumers can reject documents they do not understand.

## Correctness and invariants

- `PlotDocument::new` always sets `schema_version` to `V1`.
- `DifferentialReport::empty()` has no rows and zero counts.
- Records are plain data: no validation, no derived fields.

## Alternatives rejected

- **Numeric axes with units.** Postponed; see above.
- **A plotting library's specification format.** Would tie the IR to one
  renderer.

## Boundaries

- No rendering (that is `report`), no parsing, no statistics.
- The corpus total is not checked against the other counts.
- `PlotKind::Pareto` is a categorical scatter; there is no two-axis frontier
  in the IR.
