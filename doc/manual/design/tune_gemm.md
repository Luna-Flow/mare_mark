# tune_gemm design

## Design goal

`tune_gemm` is the reference domain for `tune`: a problem where blocking
parameters matter, correctness can be checked exactly, and every candidate can
be serialized. It shows the full tuning discipline (validate before timing,
account for workspace, test tails, record the configuration and the
environment) on matrix multiplication, without depending on hardware-specific
kernels.

## Constraints

- The kernels must run on every MoonBit backend, so they use scalar code
  only.
- The built-in kernel must be checkable against the reference with tolerance
  `0`.
- Inputs must be reproducible from a seed on every target.

## Mathematical background

### The product and its layouts

For each batch $b$, $C_b = A_b B_b$ with
$c_{ij} = \sum_{l=0}^{k-1} a_{il}\, b_{lj}$, which costs $2mnk$ floating-point
operations. A measured time of $t$ µs per operation therefore corresponds to

$$
\text{GFLOP/s} = \frac{2\,m\,n\,k\cdot\text{batch}}{t \cdot 10^{3}} .
$$

An $r \times c$ matrix stores element $(i, j)$ of batch $b$ at
$b\,rc + i\,c + j$ in row-major and $b\,rc + j\,r + i$ in column-major layout;
both maps are bijections from index triples onto $[0, \text{batch}\cdot rc)$, so
every layout combination describes the same mathematical product.

### Blocking and workspace

`gemm_blocked` partitions the iteration space into $mc \times nc \times kc$
blocks and each block into $mr \times nr$ register tiles. One block touches an
$mc \times kc$ block of $A$, a $kc \times nc$ panel of $B$ and an $mc \times nc$
block of $C$:

$$
W = 8\,(mc\cdot kc + kc\cdot nc + mc\cdot nc) \ \text{bytes},
\qquad
I = \frac{2\, mc\, nc\, kc}{W} = \frac{mc\, nc\, kc}{4\,(mc\cdot kc + kc\cdot nc + mc\cdot nc)} \ \text{flop/byte}.
$$

For a cube $mc = nc = kc = s$, $W = 24 s^2$ and $I = s/12$: larger blocks reuse
each loaded value more often, until $W$ exceeds the cache that should hold it.
That trade-off is what tuning searches, and `workspace_bytes` is $W$, used by
`valid_candidate` as a hard limit. The largest default candidate,
$128 \times 128 \times 64$, needs $W = 8(8192 + 8192 + 16384) = 262144$ bytes.[^goto]

[^goto]: K. Goto and R. A. van de Geijn, "Anatomy of high-performance matrix multiplication", *ACM TOMS* 34(3), 2008.

### Exactness of the blocked kernel

For every entry, `gemm_reference` computes

$$
\hat c_{ij} = \mathrm{fl}\bigl(\cdots\mathrm{fl}(\mathrm{fl}(0 + a_{i0} b_{0j}) + a_{i1} b_{1j}) \cdots + a_{i,k-1} b_{k-1,j}\bigr).
$$

`gemm_blocked` starts each entry at $0.0$ in the first $k$ block, stores the
partial sum in $C$ (a double, so storing is exact), reloads it in the next $k$
block and continues in increasing $l$. It performs the same operations on the
same operands in the same order, so the two results are bitwise identical as
long as the compiler treats both loops alike (in particular, does not contract
one of them into fused multiply-adds). Packing only copies values. The
correctness check can therefore use tolerance $0$ for the built-in kernel.

A kernel that reorders the summation (a vectorized microkernel, a different
loop order) is only close. With unit roundoff $u = 2^{-53}$ and
$\gamma_k = ku/(1 - ku)$, any order of summation satisfies[^higham]

$$
\lvert \hat c_{ij} - c_{ij}\rvert \le \gamma_k \sum_l \lvert a_{il}\rvert\,\lvert b_{lj}\rvert ,
$$

so two such kernels differ by at most $2\gamma_k \sum_l \lvert a_{il}\rvert\lvert b_{lj}\rvert$.
With entries from `reproducible_matrix`, $\lvert a\rvert, \lvert b\rvert \le 1$
and the bound is $2\gamma_k k \approx 2k^2 u$: for $k = 64$, about $9.1\cdot 10^{-13}$.
That is the absolute tolerance to pass to `validate_gemm` for a reordering
kernel on these inputs.

[^higham]: N. J. Higham, *Accuracy and Stability of Numerical Algorithms*, 2nd ed., SIAM, 2002, §3.1.

### Reproducible inputs

`reproducible_matrix(seed, r, c, layout)` runs the 64-bit linear congruential
generator

$$
x_{j+1} = 6364136223846793005\, x_j + 1442695040888963407 \pmod{2^{64}}, \qquad x_0 = \text{seed} \oplus \mathtt{0x9E3779B97F4A7C15},
$$

and maps each state $x_1, x_2, \dots$ (the state is advanced before the first
value is drawn) to $v = \bigl((x \gg 32) \bmod 2001\bigr)/1000 - 1$. The
multiplier is $\equiv 1 \pmod 4$ and the increment is odd, so by the
Hull–Dobell theorem the generator has the full period $2^{64}$. The 32-bit
value $x \gg 32$ is reduced modulo 2001: since $2^{32} = 2146410 \cdot 2001 + 886$,
886 of the 2001 values are slightly more likely, by a relative
$1/2146410 \approx 4.7\cdot 10^{-7}$. Entries are $j/1000 - 1$ for
$j \in \{0, \dots, 2000\}$, evaluated in double precision, so they lie in
$[-1, 1]$ and are multiples of $0.001$ up to rounding. The logical matrix is generated in row-major order and then stored
in the requested layout, so the layout does not change the values.

### Tails

Edge tiles handle $m$, $n$ or $k$ that are not multiples of the block sizes.
`boundary_shapes` returns $m - 1$, $m$ and $m + 1$: for $m$ a multiple of $mr$,
these exercise a short tile, an exact fit and a one-row tail.

## Design decisions

### A portable scalar kernel

*Problem.* Real GEMM tuning depends on SIMD microkernels that differ per
target. *Choice.* One scalar blocked kernel, with `microkernel_id` as a label.
*Why.* The package demonstrates and tests the tuning machinery on every
backend; a harness can map the label to its own kernels.

### Validate before measuring

`gemm_is_correct` runs the candidate and compares with the reference before
the candidate is ever timed. `execute_candidate` returns `None` for invalid
candidates or shapes instead of a result that would look like a fast, empty
multiplication.

### Workspace as a hard constraint

The memory a candidate needs is computed from its parameters and checked
against a limit before execution, so the search never selects a configuration
that cannot run in the target's memory budget.

### Explicit timing scope

`TimingScope` and `AllocationMode` are part of the candidate and of its id, so
"compute only" and "end to end" results are never compared as if they measured
the same thing.

### Serialized configurations

`config_json` writes everything needed to repeat a tuning run, with 64-bit
values as strings and a schema version `mmkts_1`. Together with a
`GemmEnvironment` it says where a tuned result is valid.

## Correctness and invariants

- `gemm_blocked` equals `gemm_reference` bit for bit under the condition above;
  the tests check all eight layout combinations with tails.
- `workspace_bytes(c) <= limit` for every valid candidate.
- `enumerate_gemm_candidates` returns the same 486 candidates in the same
  order, all valid for the limit 262144.
- `reproducible_matrix` depends only on its arguments; the row-major and
  column-major results describe the same logical matrix.
- `validate_gemm` counts every element of a length difference as a mismatch,
  so truncated results are never valid.

## Alternatives rejected

- **Target-specific microkernels.** Not portable across MoonBit backends.
- **Relative tolerances in validation.** Entries of $C$ can be near zero; the
  absolute bound above is the honest one for bounded inputs.
- **Generating inputs with the platform random generator.** Not reproducible
  across targets.

## Boundaries

- Only `m_n_k` loop order and scalar code; the three microkernel ids run the
  same loop.
- `pack_operand` copies a whole operand into row-major order; it does not
  build cache-sized packed panels.
- `allocation_mode`, `timing_scope` and `reuse_count` are descriptive: the
  kernel allocates its result on every call; the harness decides what to time.
- No search loop: `tune` and the application drive the search.
- `reproducible_matrix` makes one matrix; batched operands are concatenated by
  the caller.
