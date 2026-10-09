# report design

## Design goal

A benchmark report must be reproducible from the audit record and safe to
share. `report` is a pure projection from the JSONL event stream to Plot IR
(`ir_model`) and from Plot IR to JSON, SVG and HTML. It never decides what is
fast; it shows what the stream contains, and it never lets an invalid
measurement look like a valid one.

## Constraints

- The same JSONL must give the same bytes on every target, so the functions
  are pure and do no IO.
- The HTML must render without network access, years later.
- Strings in events come from payloads and may contain markup.

## Mathematical background

### The projection

Let the stream be a sequence of events. Write $O$ for the observations with
`valid` true and `batch_sink` `"kept"`, and $F$ for the set of keys
$(\text{case}, \text{implementation}, \text{dataset})$ of validations whose
status is `invalid` or `infrastructure_failure`. The plotted points are

$$
P = \{\, (\text{dataset}_o, \text{elapsed}_o, \text{implementation}_o) \;:\; o \in O,\ (\text{case}_o, \text{implementation}_o, \text{dataset}_o) \notin F \,\},
$$

in stream order. The projection is monotone in the evidence against a point:
adding a failing validation can only remove points, adding an invalid
observation adds none.

### Coordinates

A plot occupies the rectangle $[76, 880] \times [102, 354]$ of a
$960 \times 420$ view box. With $m$ distinct x categories in order of first
appearance, category $i$ is placed at

$$
X(i) = 76 + i\,\frac{804}{m - 1} \quad (m > 1), \qquad X(0) = 478 \quad (m = 1).
$$

Let $v_{\min}$ and $v_{\max}$ be the extreme y values. The y range is padded,

$$
[\ell, h] =
\begin{cases}
[v_{\min} - 0.08\,w,\ v_{\max} + 0.08\,w], & w = v_{\max} - v_{\min} > 0, \\[2pt]
[v - \pi,\ v + \pi],\quad \pi = 0.1\max(\lvert v\rvert, 1), & v_{\min} = v_{\max} = v,
\end{cases}
$$

and $[0, 1]$ for an empty plot. For finite values and in exact arithmetic,
$h - \ell > 0$ in every case, so the linear map

$$
Y(v) = 354 - (v - \ell)\,\frac{252}{h - \ell}
$$

is well defined, and for every plotted value $\ell < v < h$, which places every
point strictly inside the plot area. In floating point the padding can be lost
to rounding when $w$ is tiny compared with $\lvert v\rvert$, and an infinite or
`NaN` value breaks the bounds; the renderer does not filter them. Heatmap cells use the opacity
$0.18 + 0.72\,(v - \ell)/(h - \ell)$, which therefore lies strictly between
$0.18$ and $0.90$: no cell is invisible and none is fully saturated.

Grid lines are drawn at $Y = 102 + 63j$ for $j = 0, \dots, 4$ with tick value
$h - (h - \ell)\,j/4$, rounded to three decimals; magnitudes below $0.001$ or
from $10^{15}$ up keep their shortest round-trip form, because rounding would
erase or overflow them. With $m$ categories, labels
are drawn every $\lceil m/10\rceil$ categories and at the last one, so at most
eleven labels are shown.

## Design decisions

### A pure projection with the effects outside

*Problem.* Reports are regenerated after renderer changes and compared in
review. *Choice.* `document_from_jsonl`, `plot_json`, `plot_svg` and `html`
take values and return strings; file IO, standard streams and opening a
browser live in the [`cli`](cli.md). *Why.* The same JSONL gives the same
bytes on every target, tests need no filesystem, and the HTML can be produced
inside a larger application.

### Failures remove series and stay visible

*Problem.* A fast implementation that returns wrong results would look like a
win. *Choice.* A failing validation removes the points of that implementation
for that case and dataset, and adds a mismatch row; minimized failures add a
counterexample row with the replay command. *Why.* The differential section
sits above the plots, so the reader sees why a series is missing.

### Raw points with mean lines

*Problem.* Summaries hide distributions, raw clouds hide trends. *Choice.*
Every observation is drawn with a tooltip, and for line kinds the per-category
mean connects the categories. *Why.* The mean of the drawn points is the
centre of mass the eye already estimates; robust statistics and decisions
belong to `stats` and can be added as further plots. The line is a guide, not
an estimate the report vouches for.

### Axis selection for scaling plots

`PlotPoint.x` remains text so a scale can be an integer, shape, layout or name.
For scaling plots, finite numeric x values are ordered numerically and placed
on a linear axis unless all are positive and `max / min >= 100`; then x uses
`log10(x)`. Y is evaluated independently by the same rule. This span is at
least two decades and gives multiplicative changes equal distances because
log10(b) - log10(a) = log10(b / a). If any
value on an axis is non-finite or non-positive, or if the positive finite
values span less than 100×, that axis stays linear. A nonnumeric x axis stays
categorical in first-appearance order. Heatmaps also keep categorical x.

Log-axis ticks lie within the observed data range, and labels stay at least
56 px apart on x and 28 px apart on y. Every power of ten in range is labelled;
when decades are closer than that spacing, only the powers whose exponent is
divisible by the smallest k that keeps them apart are labelled, so the labels
stay uniform. The `2 × 10^k` and `5 × 10^k` ticks are added only when a decade
is wide enough to keep every label that far apart. A range that holds no
`1, 2, 5 × 10^k` value labels its endpoints, and a single value is labelled at
the centre of the axis. Grid lines are drawn only at labelled ticks, so their
number stays bounded however many decades the data span. Tick labels use the
same number format as linear axes. The SVG records each chosen axis scale in
Plot IR and JSON, and the plot note and axis label identify any log transform.

### Escaping order

Text is escaped by replacing `&`, `<`, `>`, `"` and `'` in this order. `&`
must be first: replacing it after `<` would turn the produced `&lt;` into
`&amp;lt;`. Since every later replacement introduces only `&` that is already
part of an entity, the result decodes back to the input exactly once. The same
function escapes element text and attribute values.

### Self-contained output

The HTML embeds its CSS and inline SVG, loads no fonts, scripts or images, and
declares `color-scheme: light`. It can be attached to an issue or archived with
the JSONL and still render identically in ten years.

### Version gate

A line whose `artifact_version` is a string other than `mmka_1` is rejected
with its line number. Lines without the field are accepted, so hand-written
fixtures and earlier streams stay readable; a non-string version is an error.
JSON output carries `schema_version` `mmks_2` and each plot's x and y axis
scales. This version change lets consumers distinguish documents whose y-axis
mapping is explicit from older `mmks_1` documents.

## Correctness and invariants

- **Determinism.** Every function is pure; equal inputs give equal strings.
- **Exclusion.** No point comes from an observation that is invalid, discarded
  or covered by a failing validation (definition of $P$).
- **Containment.** For finite values, every point lies strictly inside the
  plot area, and every heatmap opacity lies in $(0.18, 0.90)$ (derived above).
- **Escaping.** All text originating from events, titles, units and series
  names passes through the escape function before reaching SVG or HTML.
- **Complexity.** Parsing is linear in the stream size, except that each point
  is checked against the list of failure keys, $O(\lvert O\rvert \cdot \lvert F\rvert)$.
  Rendering a plot with $N$ points, $m$ categories and $S$ series is
  $O(N(m + S) + mSN)$ because line means are recomputed per cell.

## Alternatives rejected

- **A JavaScript charting library.** It would need scripts or a CDN and
  would make the output depend on a browser runtime.
- **Rendering only summaries.** Hides bimodality and outliers.
- **One axis policy for both dimensions.** Rejected because x and y can have
  different ranges and need independent scale choices.
- **Treating failed implementations as zero or infinite time.** Both are
  misleading values on a timing axis.

## Boundaries

- The JSONL projection builds one `Scaling` plot. Other plot kinds are rendered
  when a caller constructs them in Plot IR, but nothing derives them from
  events yet.
- Observations of exploratory and confirmatory phases are plotted together, and
  the x value is the dataset index, not the scale.
- The target is passed in by the caller; it is not read from the stream.
- No statistics, decisions or environment comparison are computed here.
- Styling, colours and layout are not a compatibility promise; the `mmks_2`
  JSON structure is.
