# report design

## Design goal

A benchmark report must be reproducible from the audit record and safe to
share, and its conclusions must follow from rules the run declared. `report`
is a pure projection from the JSONL event stream to Plot IR (`ir_model`) and
from Plot IR to JSON, SVG, HTML and text. It shows the confirmatory timings of
every implementation at every scale, compares each implementation with a
baseline under the threshold and outlier policy recorded in the run, and never
lets an invalid measurement look like a valid one.

## Constraints

- The same JSONL must give the same bytes on every target, so the functions
  are pure and do no IO.
- The HTML must render without network access, years later.
- Strings in events come from payloads and may contain markup.
- Records come from different versions: `phase`, `scale`, `block_id`,
  `protocol` and `seed` may be missing, and a reader must still produce an
  honest report.
- A decision needs paired blocks, a threshold, an outlier policy and a seeded
  interval; it must be recomputable from the record alone.

## Mathematical background

### The projection

Let the stream be a sequence of events. Write $O$ for the observations with
`valid` true, `batch_sink` `"kept"`, and `phase` `"confirmatory"` or absent;
$X$ for the observations with `valid` true and `batch_sink` `"kept"` but
another phase; and $F$ for the set of keys
$(\text{case}, \text{implementation}, \text{dataset})$ of validations whose
status is `invalid` or `infrastructure_failure`. The observations that count
are

$$
O_F = \{\, o \in O \;:\; (\text{case}_o, \text{implementation}_o, \text{dataset}_o) \notin F \,\}.
$$

Each $o$ has a scale key $\kappa(o)$: its `scale` text when present, else its
`dataset_id`. Group $O_F$ by $g = (\text{case}, \kappa, \text{implementation})$
into the multisets $T_g$ of `elapsed_us` values. The plot of a case has one
point per group,

$$
\bigl(\kappa,\ \operatorname{med} T_g,\ \text{implementation}\bigr),
$$

with $\operatorname{med}$ the type-7 median of [`stats`](stats.md), and its
note counts $X$ (minus the failed keys) by phase. Groups, cases and
implementations keep their order of first appearance. Adding a failing
validation can only remove observations from groups, and adding an invalid,
discarded or exploratory observation changes no group: the projection is
monotone in the evidence against a timing.

### Coordinates

A plot occupies the rectangle $[76, 880] \times [102, 354]$ of a
$960 \times 420$ view box. On a categorical axis, with $m$ distinct x values in
order of first appearance, value $i$ is placed at

$$
X(i) = 76 + i\,\frac{804}{m - 1} \quad (m > 1), \qquad X(0) = 478 \quad (m = 1).
$$

On a linear axis every x is the text of a finite number $\nu$. With
$\nu_{\min}$ and $\nu_{\max}$ the extremes,

$$
X(\nu) = 76 + (\nu - \nu_{\min})\,\frac{804}{\nu_{\max} - \nu_{\min}} \quad (\nu_{\max} > \nu_{\min}), \qquad X(\nu) = 478 \quad (\nu_{\max} = \nu_{\min}),
$$

an increasing affine map, so the positions are in numeric order and distances
are proportional to differences of scale. Equal numbers with different text
(`"1e3"` and `"1000"`) share a position. The renderer sorts the values,
labels the first, and labels each next one only if it is at least 56 px to the
right of the last label, so labels never overlap.

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
$h - (h - \ell)\,j/4$, rounded to three decimals. On a categorical axis with
$m$ values, labels are drawn every $\lceil m/10\rceil$ values and at the last
one, so at most eleven labels are shown.

### Paired blocks

Fix a case, a scale and two implementations, the baseline $B$ and the
candidate $C$. For a block id $i$ let $T_B(i)$ and $T_C(i)$ be the timings of
$O_F$ with that block id. Block $i$ is complete when
$\lvert T_B(i)\rvert = \lvert T_C(i)\rvert = 1$; it gives the pair
$(b_i, c_i)$ and the paired delta $d_i = c_i - b_i$. With $I$ the block ids
seen in either implementation and $K \subseteq I$ the complete ones,
`blocks_incomplete` is $\lvert I \setminus K \rvert$.

Pairing by block is what makes the comparison robust to drift. In the model of
the [stats design](stats.md#paired-measurements),
$b_i = \mu_B + \beta_i + \varepsilon_i$ and
$c_i = \mu_C + \beta_i + \eta_i$ with a block effect $\beta_i$ shared by both
implementations, so

$$
d_i = (\mu_C - \mu_B) + (\eta_i - \varepsilon_i)
$$

does not contain $\beta_i$. The runner guarantees the shared $\beta_i$: inside
a block both implementations run one batch each, on the same dataset, in a
balanced order. Datasets that share a scale are pooled into one comparison;
the runner numbers blocks per scale, so blocks of different datasets have
different ids and never mix.

A failed validation of $B$ (or $C$) on dataset $D$ removes its timings of $D$
from $O_F$. The blocks of $D$ then hold the other implementation only and are
incomplete; no block of $D$ enters the decision. This holds for measurement
validations too: their evidence names the dataset.

### Outliers on paired deltas

Let $P$ be the outlier policy and $[\ell_P, u_P]$ its fences computed from the
multiset $\{d_i : i \in K\}$ (Tukey: $Q_1 - 1.5\,\mathrm{IQR}$ and
$Q_3 + 1.5\,\mathrm{IQR}$; MAD trim: $\operatorname{med} \pm 3\,\mathrm{MAD}$;
`ReportOnly`: the whole line). `@stats.filter_outliers` returns the deltas
inside the fences, and the report keeps the pairs

$$
U = \{\, i \in K : d_i \in \operatorname{filter}_P(d) \,\}.
$$

**This selects exactly the pairs whose delta survives.** The fences are fixed
once computed from all deltas, so the test "$\ell_P \le d_i \le u_P$" depends
on $d_i$ alone. If $d_i$ is kept, it is in the filtered multiset. If it is
removed, every delta equal to it fails the same test, so no value equal to
$d_i$ is in the filtered multiset. Membership of $d_i$ in the filtered deltas
is therefore equivalent to $d_i$ being kept, and $U$ is the set of surviving
pairs, with its multiplicity. `blocks_used` is $\lvert U\rvert$ and
`blocks_outliers` is $\lvert K\rvert - \lvert U\rvert$.

**Why the deltas and not the raw times.** A spike that hits both
implementations of a block is part of $\beta_i$ and cancels in $d_i$; the
block is a good pair, and filtering raw times would throw it away. A spike
that hits one implementation only moves $d_i$ and is what the filter should
catch. Filtering each implementation's times separately would also break
pairs, dropping $b_i$ but keeping $c_i$, and the comparison would no longer be
paired.

### The decision and the interval

Over $U$, with $m_b = \operatorname{med}\{b_i\}$ and
$m_d = \operatorname{med}\{d_i\}$, the relative delta is
$r = 100\,m_d/m_b$ and the decision is the rule of
[`stats.compare_paired`](stats.md#a-practical-threshold-instead-of-a-significance-test)
with threshold $t$ = `practical_delta_pct`: `Faster` when $r < 0$ and
$r \le -t$, `Slower` when $r > 0$ and $r \ge t$, `Equivalent` otherwise. The
bootstrap interval $[L, U]$ of $m_d$ in µs/op is mapped to percent by the same
scale,

$$
\Bigl[\,100\,\frac{L}{m_b},\ 100\,\frac{U}{m_b}\,\Bigr],
$$

so it can be read on the axis of $r$ and $t$. For $m_b > 0$ the map
$x \mapsto 100\,x/m_b$ is increasing, so the order of the bounds is kept and
$r$ lies in the percent interval exactly when $m_d$ lies in $[L, U]$. For
$m_b \le 0$ (or `NaN`) the map is not increasing or not defined and $r$ has no
meaning, so the row is `Invalid` before the bootstrap runs.

### The minimum of three blocks

With $n \le 2$ pairs the median is the mean of the pairs, so one disturbed
block moves it without bound, and the percentile interval is the range of the
data: for $n = 1$ every resample is $d_1$; for $n = 2$ the resampled median is
$d_{(1)}$, $\tfrac12(d_{(1)} + d_{(2)})$ or $d_{(2)}$ with probabilities
$\tfrac14, \tfrac12, \tfrac14$, so the 2.5 % and 97.5 % quantiles are
$d_{(1)}$ and $d_{(2)}$. Neither number says anything beyond the data. From
$n = 3$ on, one disturbed block cannot move the median outside the range of
the other deltas: for $n = 3$ the median is the middle value, which lies
between the two undisturbed ones whatever the third one does. Three is
therefore the fewest blocks for which the report decides. The interval is still weak
there: by the formula of the [stats design](stats.md#the-percentile-bootstrap)
the 95 % interval of three deltas is $[d_{(1)}, d_{(3)}]$ and covers the true
median with probability $2^{-3}\bigl(\binom31 + \binom32\bigr) = 75\,\%$, which
is why the note warns that the actual coverage can be well below the nominal
level with few blocks.

### Row seeds

Each row is resampled with its own seed

$$
s = \operatorname{FNV1a}_{64}\bigl(\texttt{mare\_mark/compare/v1} \,\Vert\, \text{␟} \,\Vert\, \text{run seed} \,\Vert\, \text{␟} \,\Vert\, \text{case} \,\Vert\, \text{␟} \,\Vert\, \text{scale} \,\Vert\, \text{␟} \,\Vert\, \text{baseline} \,\Vert\, \text{␟} \,\Vert\, \text{candidate}\bigr),
$$

over UTF-16 code units, with ␟ the unit separator U+001F and the run seed in
decimal. The hash uses only wrapping 64-bit arithmetic, so $s$, and with it the
interval, is the same on every target. Rows of one report differ in at least
one of case, scale and candidate; as long as these identifiers contain no
U+001F, their key texts differ, and different texts give different seeds up
to a 64-bit collision. A per-row seed makes a row's interval a function of
that row's data and key only: adding a candidate, a scale or a case to the
record does not shift another row's random stream. The prefix
`mare_mark/compare/v1` versions the derivation, so a later change of scheme
cannot silently reuse old streams.

## Design decisions

### A pure projection with the effects outside

*Problem.* Reports are regenerated after renderer changes and compared in
review. *Choice.* `document_from_jsonl`, `plot_json`, `plot_svg`, `html` and
`comparisons_text` take values and return strings; file IO, standard streams
and opening a browser live in the [`cli`](cli.md). *Why.* The same JSONL gives
the same bytes on every target, tests need no filesystem, and the HTML can be
produced inside a larger application.

### Confirmatory medians per scale

*Problem.* A plot of every raw observation mixes the exploratory phase, which
exists to look around, with the confirmatory one, and puts every dataset of a
scale at a different x. *Choice.* Plot only confirmatory observations, one
point per implementation and scale at the median of its timings, pooled over
the datasets and repetitions of that scale; count the left-out observations
in the note. *Why.* Decisions are made on the confirmatory phase, so the plot
shows the same data the comparisons use. The median matches the location the
decisions use and is robust to the rare large outliers timings have. Pooling
over datasets is what the experiment designs are for: the datasets of a scale
are samples of one input distribution. A record without `phase` predates the
field; its observations were confirmatory by intent, so they are kept. A phase
the reader does not know is excluded rather than guessed at.

### The scale on the x axis

*Problem.* Scales are integers, shapes, layouts or names, and the x value used
to be the dataset index. *Choice.* The x value is the scale text the runner
records with each observation; positive finite numeric values spanning at least
100x use a logarithmic axis, other finite numeric values use a linear axis, and
non-numeric values use a categorical axis in order of first appearance. Records
without `scale` fall back to `dataset_id`, and the axis label says so. The same
rule is applied independently to y values. *Why.* The reader asks how time
grows with the scale; the dataset index is an artefact of the run. Linear and
logarithmic placement show numeric growth without spacing 64 and 4096 equally;
names keep their order. The fallback keeps old records readable without
pretending that a dataset index is a scale.

### Failures remove timings and stay visible

*Problem.* A fast implementation that returns wrong results would look like a
win. *Choice.* A failing validation removes the timings of that
implementation for that case and dataset from the plot and from the
comparisons, and adds a mismatch row; minimized failures add a counterexample
row with the replay command. *Why.* The differential section sits above the
plots, so the reader sees why a series is missing or a comparison has
incomplete blocks.

### Decisions from the record

*Problem.* A report that only plots leaves the decision to whoever reads it,
with whatever threshold they have in mind. *Choice.* `document_from_jsonl`
compares every implementation with one baseline, per case and scale, with the
`practical_delta_pct` and `outlier_policy` of the recorded protocol and the
recorded run seed, using `stats.compare_paired_with_bootstrap`; the HTML shows
the table before the plots, and the CLI prints it. *Why.* The run declared how
it wants to be judged; using those settings makes the decision a function of
the record, recomputable by anyone. The settings, their source and the fixed
report constants (95 %, 10000 resamples, at least 3 blocks) are stated in the
note next to the table, so a reader never has to guess what produced a
decision.

### One baseline, chosen explicitly or by order

*Problem.* With $k$ implementations there are $k(k-1)/2$ pairs. *Choice.* One
baseline per report, by default the first implementation of each case, or the
one named by `baseline=`; an unknown name is an error. *Why.* A benchmark
usually asks "is the new code faster than the current one", which is one
baseline and $k - 1$ rows; all pairs would multiply rows and the chance of a
spurious decision. Rejecting an unknown baseline catches typos that would
otherwise produce a table of `Unknown` rows.

### Stated defaults for older records

*Problem.* Records written before the summary carried the protocol and seed
have neither. *Choice.* Compare them with a 1 % threshold, `ReportOnly` and
seed 0, mark `protocol_recorded` and `seed_recorded` false, and say so in the
note. *Why.* `ReportOnly` removes nothing, the safest choice when the run's
policy is unknown; 1 % is the threshold of the `QuickCheck` and `Development`
presets; seed 0 is as good as any fixed seed and is printed. A malformed
`protocol` or `seed`, unlike a missing one, is an error: it is a broken
record, not an old one.

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
JSON output carries `schema_version` `mmks_2`.

## Correctness and invariants

- **Determinism.** Every function is pure; equal inputs give equal strings,
  including the bootstrap intervals (seeded per row).
- **Exclusion.** No point and no pair comes from an observation that is
  invalid, discarded, not confirmatory, or covered by a failing validation
  (definition of $O_F$).
- **Pairing.** A used pair holds exactly one baseline and one candidate
  observation of the same case, scale and block; the outlier policy removes
  exactly the pairs whose delta is outside its fences (derived above), and
  `blocks_used + blocks_outliers` is the number of complete blocks.
- **Decided rows.** A row is `Faster`, `Slower` or `Equivalent` only with at
  least 3 used blocks, a positive baseline median and a successful bootstrap;
  every `Unknown` or `Invalid` row has a non-empty reason.
- **Containment.** For finite values, every point lies strictly inside the
  plot area, and every heatmap opacity lies in $(0.18, 0.90)$ (derived above).
- **Escaping.** All text originating from events, titles, units, series names,
  notes and comparison cells passes through the escape function before
  reaching SVG or HTML.
- **Complexity.** Parsing is linear in the stream size, except that each
  observation is checked against the list of failure keys,
  $O(\lvert O\rvert \cdot \lvert F\rvert)$, and grouping searches the groups of
  its case. A comparison of $n$ pairs costs $O(n^2)$ for the outlier
  membership test and $O(B\,n\log n)$ with $B = 10000$ for the bootstrap.
  Rendering a plot with $N$ points, $m$ x values and $S$ series is
  $O(N(m + S) + mSN)$ because line means are recomputed per cell.

## Alternatives rejected

- **A JavaScript charting library.** It would need scripts or a CDN and
  would make the output depend on a browser runtime.
- **Plotting every raw observation.** Mixes phases and datasets and hides the
  quantity the decision is about; the record keeps the raw values.
- **Deciding from the interval.** Would make the decision depend on the number
  of blocks; the decision is the practical rule on the point estimate, and the
  interval is shown next to it (see the [stats design](stats.md)).
- **Filtering raw times.** Breaks pairs and removes blocks whose disturbance
  cancels in the delta (derived above).
- **All pairs of implementations.** More rows, more spurious decisions, and
  rarely the question asked.
- **Treating failed implementations as zero or infinite time.** Both are
  misleading values on a timing axis.
- **One bootstrap stream for the whole report.** Adding a row would change the
  intervals of the others.

## Boundaries

- The JSONL projection builds one `Scaling` plot per case. Other plot kinds
  are rendered when a caller constructs them in Plot IR, but nothing derives
  them from events.
- Comparisons are against one baseline, per case and scale; pooling across
  scales or cases is not done.
- The confidence (95 %), the resamples (10000) and the minimum of 3 blocks
  are fixed by the report; the threshold, the outlier policy and the seed
  come from the record or from stated defaults.
- The interval does not model the dependence between neighbouring blocks that
  the rotation introduces, and its actual coverage with few blocks is below
  the nominal level.
- The target is passed in by the caller; it is not read from the stream.
- Environments are not compared: mixing records of different machines in one
  stream pools their observations.
- Styling, colours and layout are not a compatibility promise; the `mmks_2`
  JSON structure is.
