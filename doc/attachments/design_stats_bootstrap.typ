#set document(title: "Percentile bootstrap of the median paired delta")
#set page(paper: "a4", margin: 2.2cm, numbering: "1")
#set text(size: 10.5pt)
#set par(justify: true)
#set heading(numbering: "1.")
#set math.equation(numbering: "(1)")

#let definition(body) = block(inset: (left: 0.8em), stroke: (left: 0.5pt + gray))[*Definition.* #body]
#let proposition(name, body) = block(inset: (left: 0.8em), stroke: (left: 0.5pt + gray))[*#name.* #body]
#let proof(body) = [_Proof._ #body #h(1fr) $square$]

#align(center)[
  #text(size: 15pt, weight: "bold")[Percentile bootstrap of the median paired delta]

  mare_mark `stats` design note
]

This note supports the `stats` design page. It states what
`bootstrap_interval` computes, proves the invariants the page relies on, and
derives the exact bootstrap distribution of the median so that a small case can
be checked by hand.

= Setting

Let $d = (d_1, dots, d_n)$ be the paired deltas, $d_i = c_i - b_i$, and
$d_((1)) <= dots <= d_((n))$ their order statistics. For $0 <= p <= 1$ the type-7
quantile of a finite sample $y$ of size $k$ is

$ Q_y (p) = y_((floor(h) + 1)) + (h - floor(h)) (y_((floor(h) + 2)) - y_((floor(h) + 1))), quad h = (k - 1) p, $

with the convention that the second term vanishes when $h$ is an integer.
`bootstrap_interval(d, seed, B, gamma)` performs the following steps.

+ For $b = 1, dots, B$, draw indices $j_1, dots, j_n$ from the seeded
  generator and set $theta^*_b = Q_(d^*) (1 \/ 2)$ with
  $d^* = (d_(j_1), dots, d_(j_n))$.
+ Sort $theta^*_1, dots, theta^*_B$ and return
  $L = Q_(theta^*) (alpha \/ 2)$, $U = Q_(theta^*) (1 - alpha \/ 2)$ with
  $alpha = 1 - gamma \/ 100$.

= Invariants

#proposition("Lemma 1 (range)")[
  For every sample $y$ and every $p$, $min_i y_i <= Q_y (p) <= max_i y_i$, and
  $p |-> Q_y (p)$ is non-decreasing.
]

#proof[
  $Q_y (p)$ is $(1 - w) y_((i)) + w y_((i + 1))$ with $w in [0, 1)$, a convex
  combination of two order statistics, which lie in $[y_((1)), y_((k))]$. On
  each interval $[i \/ (k - 1), (i + 1) \/ (k - 1)]$ the map is affine with slope
  $(k - 1)(y_((i + 1)) - y_((i))) >= 0$, and it is continuous at the nodes.
]

#proposition("Proposition 2 (bounds)")[
  For $0 < gamma < 100$, $min_i d_i <= L <= U <= max_i d_i$.
]

#proof[
  Each $d^*$ consists of values of $d$, so by Lemma 1
  $theta^*_b in [min d^*, max d^*] subset [min d, max d]$. Applying Lemma 1 to
  the sample $theta^*$ places $L$ and $U$ in $[min_b theta^*_b, max_b theta^*_b]$.
  Finally $alpha \/ 2 < 1 - alpha \/ 2$ because $alpha < 1$, and monotonicity
  gives $L <= U$.
]

= The exact bootstrap distribution of the median

#proposition("Proposition 3")[
  Let $n = 2m + 1$ and let the deltas be distinct. Under resampling with
  replacement, the resampled median $theta^*$ takes only the values
  $d_((1)), dots, d_((n))$, and

  $ hat(G)(d_((k))) = P^*(theta^* <= d_((k))) = sum_(j = m + 1)^n binom(n, j) (k / n)^j (1 - k / n)^(n - j). $
]

#proof[
  For odd $n$ the type-7 median of $d^*$ is its middle order statistic, which is
  one of the drawn values. The event $theta^* <= d_((k))$ holds exactly when at
  least $m + 1$ of the $n$ draws are among the $k$ smallest values. Draws are
  independent and each falls among them with probability $k \/ n$, so the count
  is $"Bin"(n, k \/ n)$.
]

For even $n = 2m$ the resampled median is the midpoint of the $m$-th and
$(m + 1)$-th resampled order statistics, so $theta^*$ takes values in the set
of midpoints $(d_((i)) + d_((j))) \/ 2$ with $i <= j$. In both cases $hat(G)$ is a
step function, and the interval endpoints are observed deltas or midpoints of
two of them.

As a worked case, take $n = 5$. Proposition 3 gives
$hat(G)(d_((1))) = 0.058$, $hat(G)(d_((2))) = 0.317$, $hat(G)(d_((3))) = 0.683$,
$hat(G)(d_((4))) = 0.942$ and $hat(G)(d_((5))) = 1$. Since
$hat(G)(d_((1))) > 0.025$, the exact 95 % percentile interval is
$[d_((1)), d_((5))]$: with five blocks the interval for the median is the whole
range of the deltas.

= Coverage of the percentile interval

#proposition("Proposition 4 (Efron)")[
  Suppose there is an increasing map $phi$ and a distribution $H$, symmetric
  about $0$, such that $W = phi(hat(theta)) - phi(theta) ~ H$ and
  $phi(theta^*) - phi(hat(theta)) ~ H$ under resampling. Then the percentile
  interval $[hat(G)^(-1)(alpha \/ 2), hat(G)^(-1)(1 - alpha \/ 2)]$ covers
  $theta$ with probability exactly $1 - alpha$.
]

#proof[
  From the second assumption,
  $hat(G)(x) = H(phi(x) - phi(hat(theta)))$, so
  $hat(G)^(-1)(q) = phi^(-1)(phi(hat(theta)) + H^(-1)(q))$. Since $phi$ is
  increasing,
  $theta <= hat(G)^(-1)(1 - alpha \/ 2) <==> -W <= H^(-1)(1 - alpha \/ 2) <==> W >= H^(-1)(alpha \/ 2)$
  by symmetry, and likewise
  $theta >= hat(G)^(-1)(alpha \/ 2) <==> W <= H^(-1)(1 - alpha \/ 2)$. The
  probability of both is $H(H^(-1)(1 - alpha \/ 2)) - H(H^(-1)(alpha \/ 2)) = 1 - alpha$.
]

When the assumption holds only asymptotically, the coverage error of the
two-sided percentile interval is of order $n^(-1 \/ 2)$ in general
(Efron and Tibshirani, _An Introduction to the Bootstrap_, 1993, ch. 14). The
discreteness of Proposition 3 adds an error that does not vanish with $B$; it
only vanishes as $n$ grows.

= Monte Carlo error

The returned endpoints are quantiles of $B$ draws from $hat(G)$, not of
$hat(G)$ itself. Let $q$ be the $p$-quantile of $hat(G)$ and $N$ the number of
the $B$ draws that are at most $q$. Then $N ~ "Bin"(B, hat(G)(q))$, so the
fraction of draws below the true endpoint has standard deviation
$sqrt(hat(G)(q)(1 - hat(G)(q)) \/ B)$. For $p = 0.025$ and $B = 2000$ that is
$0.0035$: the reported 95 % endpoints are the true bootstrap endpoints of an
interval whose tail masses are $2.5 plus.minus 0.35$ %. Because $hat(G)$ is a step
function, the endpoint usually equals the exact one once $B$ exceeds a few
hundred.

= Index generation

Indices are $j = x mod n$ for 64-bit states $x$. Write $2^64 = q n + r$ with
$0 <= r < n$. Exactly $r$ residues are produced by $q + 1$ states and the
others by $q$ states. For a uniformly distributed state,

$ abs(P(j) dot n - 1) <= n / 2^64 , $

which is below $10^(-13)$ for $n <= 10^6$.
