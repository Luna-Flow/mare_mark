# stats design

## Design goal

Benchmark timings are skewed, heavy-tailed and correlated with the moment they
were taken. `stats` gives decisions that survive these properties: robust
location estimates, comparisons on paired measurements, an explicit practical
threshold, and an interval whose randomness is pinned by a seed. Every function
is a pure transformation of arrays, so a decision can be recomputed from the
raw observations kept in the event stream.

## Mathematical background

### Order statistics and the sample quantile

Let $x_1, \dots, x_n$ be a sample and $x_{(1)} \le \dots \le x_{(n)}$ its order
statistics. The package uses one quantile definition everywhere, the linear
interpolation of Hyndman and Fan's type 7:[^hf]

$$
h = (n-1)\,p, \qquad
Q(p) = x_{(\lfloor h\rfloor+1)} + (h-\lfloor h\rfloor)\bigl(x_{(\lfloor h\rfloor+2)} - x_{(\lfloor h\rfloor+1)}\bigr), \qquad 0 \le p \le 1 .
$$

[^hf]: R. J. Hyndman and Y. Fan, "Sample quantiles in statistical packages", *The American Statistician* 50(4), 1996. Type 7 is the default of R and NumPy.

Three properties follow directly from the formula and are used below.

1. **Range.** $Q(p)$ is a convex combination of two adjacent order statistics,
   so $x_{(1)} \le Q(p) \le x_{(n)}$, with $Q(0) = x_{(1)}$ and $Q(1) = x_{(n)}$.
2. **Monotonicity.** $Q$ is the piecewise linear interpolation of the
   non-decreasing sequence $x_{(1)}, \dots, x_{(n)}$ at the nodes
   $p = k/(n-1)$, so $p \le p'$ implies $Q(p) \le Q(p')$.
3. **Affine equivariance.** For $y_i = a + b\,x_i$ with $b > 0$, sorting
   commutes with the map and convex combinations commute with affine maps, so
   $Q_y(p) = a + b\,Q_x(p)$. Rescaling timings from µs to ns rescales every
   quantile, median, IQR and MAD by the same factor.

For $p = 1/2$ the formula gives the usual median: $x_{(m+1)}$ for $n = 2m+1$, and
$\tfrac12(x_{(m)} + x_{(m+1)})$ for $n = 2m$.

### Location and spread

`summarize` reports two families of estimators side by side:

| Classical | Robust |
| --- | --- |
| $\bar x = \frac1n \sum_i x_i$ | $\operatorname{med}(x) = Q(1/2)$ |
| $s_n = \sqrt{\frac1n \sum_i (x_i - \bar x)^2}$ | $\mathrm{IQR} = Q(3/4) - Q(1/4)$, $\mathrm{MAD} = \operatorname{med}_i \lvert x_i - \operatorname{med}(x)\rvert$ |

The breakdown point of an estimator is the largest fraction of the sample that
can be moved arbitrarily far without moving the estimate arbitrarily far. It is
$0$ for $\bar x$ and $s_n$ (one value suffices), $1/4$ for the quartiles and the
IQR, and $1/2$ for the median and the MAD. A single descheduled run moves the
mean of a benchmark; it cannot move the median unless half of the runs are
affected.

$s_n$ divides by $n$: it is the standard deviation of the sample viewed as a
population, a descriptive quantity. As an estimator of $\sigma^2$ it is biased,
because

$$
\begin{aligned}
\sum_i (x_i - \bar x)^2 &= \sum_i (x_i - \mu)^2 - n(\bar x - \mu)^2, \\
\mathbb E\Bigl[\sum_i (x_i - \bar x)^2\Bigr] &= n\sigma^2 - n\cdot\frac{\sigma^2}{n} = (n-1)\,\sigma^2 ,
\end{aligned}
$$

so $\mathbb E[s_n^2] = \frac{n-1}{n}\sigma^2$. Multiply $s_n^2$ by $n/(n-1)$ when
you need the unbiased variance.

The MAD is reported unscaled. For normally distributed data with standard
deviation $\sigma$, $\operatorname{med}\lvert X - \mu\rvert = z_{3/4}\,\sigma$
with $z_{3/4} = \Phi^{-1}(3/4) \approx 0.6745$, so
$1.4826\cdot\mathrm{MAD}$ estimates $\sigma$ and $\mathrm{IQR} \approx 1.349\,\sigma$.

### Paired measurements

The runner measures every implementation once per block, in a rotated order
(see the [runner design](runner.md)). Model a baseline timing $b_i$ and a
candidate timing $c_i$ from block $i$ as

$$
b_i = \mu_b + \beta_i + \varepsilon_i, \qquad c_i = \mu_c + \beta_i + \eta_i ,
$$

where $\beta_i$ is the block effect shared by both (machine state, frequency,
cache contents) with variance $\sigma_\beta^2$, and $\varepsilon_i$, $\eta_i$ are
independent noise with variances $\sigma_\varepsilon^2$, $\sigma_\eta^2$. The
paired delta cancels the block effect:

$$
d_i = c_i - b_i = (\mu_c - \mu_b) + (\eta_i - \varepsilon_i), \qquad
\operatorname{Var}(d_i) = \sigma_\varepsilon^2 + \sigma_\eta^2 ,
$$

whereas a difference taken across blocks $i \ne j$ has variance
$\sigma_\varepsilon^2 + \sigma_\eta^2 + 2\sigma_\beta^2$. When drift between
blocks dominates the noise inside a block, pairing removes most of the
variance. `compare_paired` therefore summarizes the deltas $d_i$, never the two
samples separately.

### The percentile bootstrap

Let $\hat F_n$ be the empirical distribution of the deltas and
$\hat\theta = \operatorname{med}(d)$. A bootstrap resample $d^*$ draws $n$
values from $\hat F_n$ with replacement; its median is $\hat\theta^*$. Write
$\hat G(x) = P^*(\hat\theta^* \le x)$ for the bootstrap distribution. The
percentile interval at confidence $1-\alpha$ is

$$
\bigl[\hat G^{-1}(\alpha/2),\ \hat G^{-1}(1-\alpha/2)\bigr].
$$

It is exact under the following condition. Suppose an increasing map $\varphi$
exists such that $W = \varphi(\hat\theta) - \varphi(\theta)$ has a distribution
$H$ symmetric about $0$, and the same $H$ describes
$\varphi(\hat\theta^*) - \varphi(\hat\theta)$ under resampling. Then
$\hat G^{-1}(q) = \varphi^{-1}\bigl(\varphi(\hat\theta) + H^{-1}(q)\bigr)$ and

$$
\begin{aligned}
\theta \le \hat G^{-1}(1-\tfrac\alpha2)
&\iff -W \le H^{-1}(1-\tfrac\alpha2)
\iff W \ge H^{-1}(\tfrac\alpha2), \\
\theta \ge \hat G^{-1}(\tfrac\alpha2)
&\iff -W \ge H^{-1}(\tfrac\alpha2)
\iff W \le H^{-1}(1-\tfrac\alpha2),
\end{aligned}
$$

using $H^{-1}(q) = -H^{-1}(1-q)$. The coverage is
$P\bigl(H^{-1}(\alpha/2) \le W \le H^{-1}(1-\alpha/2)\bigr) = 1-\alpha$. The
interval never needs to know $\varphi$, which is why it is
transformation-respecting.[^et] In general the condition holds only
approximately, and the coverage error of the percentile interval is of order
$n^{-1/2}$.

[^et]: B. Efron and R. J. Tibshirani, *An Introduction to the Bootstrap*, Chapman & Hall, 1993, §13.3 and §14.

For the median the bootstrap distribution can be written down exactly. Take
$n = 2m+1$ distinct values. $\hat\theta^* \le x_{(k)}$ holds exactly when at least
$m+1$ of the $n$ draws are at most $x_{(k)}$, and each draw is with probability
$k/n$, so

$$
\hat G\bigl(x_{(k)}\bigr) = \sum_{j=m+1}^{n} \binom{n}{j}\Bigl(\frac kn\Bigr)^{j}\Bigl(1-\frac kn\Bigr)^{n-j}.
$$

$\hat G$ is a step function on the data points (on midpoints of adjacent order
statistics when $n$ is even). The interval endpoints therefore land on, or
between, observed deltas, and with few blocks they move in coarse steps.

The derivation of both results in full, with the discreteness bound, is in the
attachment:

[Percentile bootstrap of the median paired delta](../../attachments/design_stats_bootstrap.typ)

## Design decisions

### Medians as the default centre

*Problem.* Timing distributions have a hard lower bound (the work itself) and a
long right tail (interrupts, page faults, frequency changes). *Options.* Mean,
trimmed mean, median. *Choice.* The median for every decision, with the mean
kept in `SummaryStats` as a diagnostic. *Why.* Its breakdown point is $1/2$, it
is affine equivariant, and the distance between mean and median signals a tail
that deserves a look in the report.

### Paired deltas instead of two independent samples

*Problem.* Machine state drifts between blocks. *Options.* Compare
$\operatorname{med}(c) - \operatorname{med}(b)$; compare the paired deltas.
*Choice.* `compare_paired` computes $d_i = c_i - b_i$ and summarizes
$\operatorname{med}(d)$. *Why.* The variance derivation above: the block effect
cancels in $d_i$ and stays in an unpaired difference. The cost is a contract:
index $i$ of both arrays must come from the same dataset, repetition and block.
`paired_deltas` truncates to the shorter array and `compare_paired` marks
unequal lengths `Invalid`, so a broken alignment is visible instead of being
silently repaired.

### The relative delta and the speedup

*Problem.* Gates are stated in percent, people read speedups. *Choice.* With
$m_b = \operatorname{med}(b)$ and $m_d = \operatorname{med}(d)$,

$$
r = 100\,\frac{m_d}{m_b}, \qquad
s = \frac{m_b}{m_b + m_d} = \frac{1}{1 + m_d/m_b} = \frac{1}{1 + r/100}.
$$

Both are functions of the same two medians, so they never disagree: $s$ is
decreasing in $r$ on $r > -100$, and for a threshold $0 \le t < 100$

$$
r \le -t \iff 1 + \frac{r}{100} \le 1 - \frac{t}{100} \iff s \ge \frac{1}{1 - t/100}.
$$

A threshold of $t = 2$ declares the candidate `Faster` exactly when
$s \ge 1.0204$. When the candidate is a constant shift of the baseline,
$c_i = b_i + \delta$, then $m_b + m_d = \operatorname{med}(c)$ and $s$ is the
ratio of the medians; in general $m_b + m_d$ is a robust estimate of the typical
candidate time built from the paired data. The guards $m_b = 0 \Rightarrow r = 0$
and $m_d = 0 \Rightarrow s = 1$ keep degenerate input finite; $r = -100$
($m_b + m_d = 0$) still gives an infinite speedup.

### A practical threshold instead of a significance test

*Problem.* With enough repetitions any difference becomes statistically
significant, including a 0.1 % change nobody would act on. *Options.* A
$t$-test or Wilcoxon test; an equivalence test (TOST); a practical threshold
on the point estimate. *Choice.* The decision is the three-way rule

$$
\text{Faster} \iff r \le -t, \qquad
\text{Slower} \iff r \ge t, \qquad
\text{Equivalent} \iff -t < r < t ,
$$

checked after `Invalid` (unequal lengths) and `Unknown` (no pairs). *Why.* The
threshold states the question the user is asking ("is it at least 2 % faster?")
in the unit of the decision, the rule is reproducible from two medians, and it
does not reward running more repetitions. For $t > 0$ the three regions
partition $\mathbb R$. For $t = 0$ the first two overlap at $r = 0$, and because
`Faster` is tested first an exact tie is reported as `Faster`; use a positive
threshold. Uncertainty is reported next to the decision through the interval,
not folded into it.

### Seeded percentile bootstrap of the median delta

*Problem.* A reader of a report needs to see how stable the median delta is,
and the number must be the same when the report is regenerated. *Choice.*
`bootstrap_interval` draws $B$ resamples with an explicit seed and returns the
type-7 quantiles $Q^*(\alpha/2)$ and $Q^*(1-\alpha/2)$ of the $B$ resampled
medians. *Why.* The percentile method needs no variance formula for the median
(which would need a density estimate), it is transformation-respecting, and it
is cheap: $O(B\,n\log n)$.

The random stream is generated by a 64-bit xorshift step followed by a
multiplication:

$$
x \leftarrow x \oplus (x \gg 12), \quad
x \leftarrow x \oplus (x \ll 25), \quad
x \leftarrow x \oplus (x \gg 27), \quad
x \leftarrow 2685821657736338717 \cdot x \bmod 2^{64}.
$$

These are the constants of Marsaglia–Vigna xorshift64\*, but the multiplied
value is fed back as the next state, so the classical period result for
xorshift64\* does not carry over. What does carry over: each xorshift step is
an invertible linear map over $\mathrm{GF}(2)^{64}$ (a unipotent triangular
matrix), and multiplication by an odd constant is invertible modulo $2^{64}$, so
one step is a permutation of the 64-bit words that fixes $0$. That is why seed
`0` is replaced by the constant `88172645463393265`. The generator uses only
wrapping 64-bit integer arithmetic, so the stream is identical on every target.

A state $x$ is mapped to an index by $j = x \bmod n$. Writing
$2^{64} = qn + r$ with $0 \le r < n$, the residues $j < r$ are hit $q+1$ times and
the others $q$ times, so for a uniformly distributed state

$$
\frac{P(j)}{1/n} \in \Bigl[\frac{qn}{2^{64}},\ \frac{(q+1)n}{2^{64}}\Bigr], \qquad
\Bigl\lvert\frac{P(j)}{1/n} - 1\Bigr\rvert \le \frac{n}{2^{64}} .
$$

For a million deltas the bias is below $10^{-13}$, far below the Monte Carlo
error of the interval.

*Choosing $B$.* An endpoint estimated from $B$ resampled medians has a
standard error of order $\sqrt{p(1-p)/B}$ in probability units, with
$p = \alpha/2$. For a 95 % interval and $B = 2000$ this is about $0.35$
percentage points of the 2.5 % tail mass. Use $B \ge 1000$ for 95 % intervals and keep
the seed and $B$ with the experiment configuration.

### Outlier views instead of outlier deletion

*Problem.* Reports want plots without one 50 ms page-fault spike; decisions
must not depend on which points someone chose to hide. *Choice.*
`filter_outliers` returns a filtered copy under an explicit `OutlierPolicy`, and
nothing in the runner or the event stream applies it. *Why.* The raw data stay
auditable, and the policy is a named value that can be recorded. The two
non-trivial policies have known false-flag rates on clean normal data:

$$
\begin{aligned}
\text{Tukey:}&\quad Q(3/4) + 1.5\,\mathrm{IQR} \approx \mu + (0.6745 + 1.5\cdot 1.349)\,\sigma = \mu + 2.698\,\sigma,
&\quad P(\lvert Z\rvert > 2.698) &\approx 0.70\,\%, \\
\text{MAD trim:}&\quad 3\,\mathrm{MAD} \approx 3\cdot 0.6745\,\sigma = 2.024\,\sigma,
&\quad P(\lvert Z\rvert > 2.024) &\approx 4.3\,\% .
\end{aligned}
$$

Because the MAD is unscaled, the MAD trim is about four times more aggressive
than the Tukey fence on normal data. It is also degenerate when more than half
of the values coincide: the MAD is then $0$ and only values equal to the median
survive.

### Errors as values

Invalid bootstrap input returns `Err(BootstrapError)`. An empty or non-finite
sample would otherwise yield a plausible-looking interval of zeros or `NaN`.
`summarize` and `compare_paired` stay total: they return neutral values
(`count == 0`, `Unknown`, `Invalid`) that a caller can test.

## Correctness and invariants

- **Inputs are not modified.** `summarize` sorts a copy; `filter_outliers`
  returns a new array; the bootstrap sorts each resample, never the input.
- **Range.** By the range property of $Q$, `median`, `q1` and `q3` lie in
  $[x_{(1)}, x_{(n)}]$. Every resampled
  median lies in $[\min d, \max d]$ because it is a quantile of values drawn from
  $d$; the interval endpoints are quantiles of those medians, hence
  $\min d \le$ `low` $\le$ `high` $\le \max d$.
- **Order.** For $0 < \gamma < 100$, $\alpha/2 < 1 - \alpha/2$, and monotonicity
  of $Q$ gives `low` $\le$ `high`.
- **Determinism.** The bootstrap is a function of (values, seed, $B$,
  $\gamma$). Sorting finite doubles is deterministic, and the generator uses
  wrapping integer arithmetic, so the same inputs give bit-identical bounds on
  every target.
- **Floating-point error.** The mean is a left-to-right sum. With
  $u = 2^{-53}$ and $\gamma_k = ku/(1-ku)$, the standard bound
  $\lvert \mathrm{fl}(\sum x_i) - \sum x_i\rvert \le \gamma_{n-1}\sum \lvert x_i\rvert$
  becomes a relative error of at most $\gamma_{n-1} \approx n u$ for positive
  timings. The variance uses the two-pass formula $\sum (x_i - \bar x)^2$, which
  avoids the cancellation of the one-pass $\sum x_i^2 - n\bar x^2$.[^higham]
- **Complexity.** `summarize` is $O(n\log n)$; `compare_paired` is
  $O(n\log n)$; `bootstrap_interval` is $O(B\,n\log n + B\log B)$;
  `filter_outliers` is $O(n\log n)$.

[^higham]: N. J. Higham, *Accuracy and Stability of Numerical Algorithms*, 2nd ed., SIAM, 2002, §4.2 and §1.9.

## Alternatives rejected

- **BCa and studentized bootstrap.** They reduce the coverage error to order
  $n^{-1}$ but need a jackknife acceleration estimate or a variance estimate
  for every resample; for the median both are unstable with the small $n$ that
  benchmarks have. Not implemented.
- **Hierarchical bootstrap.** Resampling datasets, then repetitions, matches
  `HierarchicalDatasetsAndRepeats` better, but the comparison functions take
  flat arrays. Callers can still resample per dataset themselves.
- **Hodges–Lehmann estimator.** The median of pairwise Walsh averages is more
  efficient under symmetry, but costs $O(n^2)$ and is harder to explain in a
  report.
- **Hypothesis tests ($t$, Welch, Mann–Whitney).** Rejected for the decision as
  explained above; their $p$-values answer a different question.
- **Scaled MAD.** Multiplying by 1.4826 assumes normality; the unscaled value
  is reported and the factor is documented instead.

## Boundaries

- The decision uses the point estimate and the threshold only; the interval is
  reported, not used to decide. There is no equivalence test.
- Comparisons take flat arrays. Pairing, phase separation (exploratory or
  confirmatory) and environment compatibility are the caller's job.
- The bootstrap interval is in the unit of the deltas; the decision is in
  percent. Divide by $\operatorname{med}(b)$ to compare them.
- The bootstrap assumes exchangeable deltas. Rotation order makes neighbouring
  blocks dependent; the interval does not model that.
- `filter_outliers` is never applied automatically, and `OutlierPolicy` in a
  `RunProtocol` is a recorded intent, not an action.
- Non-finite values are rejected only by the bootstrap functions.
