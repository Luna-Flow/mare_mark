# env_detect design

## Design goal

A timing means something only together with the machine, runtime and build
that produced it, and a run id is useful only if it is unique. Writing that
description by hand is tedious, so it is often vague or copied from an older
run. `env_detect` fills an `EnvironmentSnapshot` from what the running process
can observe, says exactly which fields it could not observe, and lets the
caller state or correct any field. It does this without making the rest of
mare_mark depend on the host.

## Constraints

- `model` has no IO, and the runner must stay deterministic given its inputs,
  so neither may probe the host.
- What a process can learn depends on the target: native code can run
  commands, JavaScript on Node.js can ask the `os` module, a browser or a wasm
  host can do neither.
- Running a command on native goes through `moonbitlang/async`, which is
  asynchronous.
- A probe can be slow or hang (a `git` on a network file system, a missing
  binary on an unusual host); a benchmark must not wait for it indefinitely.
- Some fields describe the build or the benchmark, not the machine, and no
  probe can find them.
- A snapshot is compared by exact string equality
  (`@model.environment_compatible`), so a guessed value is as strong as an
  observed one.

## Mathematical background

### Time stamps from the epoch

`detect` reads the clock once, as $t$ milliseconds since 1970-01-01T00:00:00Z
(`@env.now()`), and derives both `timestamp` and `run_id` from that one value.
Converting $t$ to a calendar date is the only computation in the package. With
integer division,

$$
s = \lfloor t / 1000 \rfloor, \qquad
z_0 = \lfloor s / 86400 \rfloor, \qquad
\text{second of day} = s \bmod 86400 .
$$

The day number $z_0$ is converted with Howard Hinnant's `civil_from_days`.
Shift the origin to 0000-03-01, so that the leap day is the last day of its
year: 1970-01-01 is day $719468$ after that origin, so $z = z_0 + 719468$. The
Gregorian calendar repeats every 400 years of
$400 \cdot 365 + 97 = 146097$ days (97 leap years: 100 multiples of 4, minus
the 4 centuries, plus 1 multiple of 400), so

$$
e = \lfloor z / 146097 \rfloor, \qquad
d_e = z - 146097\,e \in [0, 146096]
$$

are the era and the day of the era. Inside an era a four-year cycle has
$1461$ days and ends with its leap day (day $1460$ of the cycle), a century has
$36524$ days because its last cycle has no leap day, and the fourth century
keeps it, so the era ends with a leap day at day $146096$. The three
correction terms below remove the leap days before $d_e$, which turns the day
of the era into a count in which every year has 365 days:

$$
y_e = \Bigl\lfloor \frac{d_e - \lfloor d_e/1460 \rfloor + \lfloor d_e/36524 \rfloor - \lfloor d_e/146096 \rfloor}{365} \Bigr\rfloor,
\qquad
d_y = d_e - \bigl(365\,y_e + \lfloor y_e/4 \rfloor - \lfloor y_e/100 \rfloor\bigr).
$$

The months from March to January have lengths $31, 30, 31, 30, 31$ repeating,
so five months span $153$ days and month $p$ (March $= 0$) starts on day
$\lfloor (153\,p + 2)/5 \rfloor$ of the shifted year: $0, 31, 61, 92, 122, 153,
184, 214, 245, 275, 306, 337$. Inverting that staircase,

$$
p = \Bigl\lfloor \frac{5\,d_y + 2}{153} \Bigr\rfloor, \qquad
\text{day} = d_y - \Bigl\lfloor \frac{153\,p + 2}{5} \Bigr\rfloor + 1, \qquad
\text{month} =
\begin{cases} p + 3 & p < 10 \\ p - 9 & p \ge 10 \end{cases},
$$

and the year is $y_e + 400\,e$, plus one for January and February, which
belong to the next calendar year. Every quantity is non-negative for
$0 \le t < 2^{63}$, so truncating division equals floor division here. The
tests check the epoch, the leap day 2000-02-29, the end of a day, and
2100-03-01 after the non-leap century year 2100.

### Run ids are ordered by time

A run id is $T(t)$, a hyphen, and a suffix, where $T(t)$ is the basic ISO 8601
form `YYYYMMDDTHHMMSSmmmZ`. Every field of $T(t)$ is a zero-padded decimal of
fixed width, ordered from the most to the least significant unit. For years
$0$ to $9999$, comparing two such strings character by character is comparing
the integers

$$
N(t) = Y\cdot 10^{13} + M\cdot 10^{11} + D\cdot 10^{9} + h\cdot 10^{7} + m\cdot 10^{5} + s\cdot 10^{3} + \mathit{ms},
$$

because two fixed-width digit strings first differ at the most significant
digit in which the numbers differ. $N$ is strictly increasing in $t$ (a later
millisecond has a later calendar field at the first unit that changes), so
$t < t' \Rightarrow T(t) < T(t')$ in lexicographic order: sorting run ids as
strings sorts them by start time. Ids of the same millisecond are ordered by
their suffix, that is arbitrarily.

### Run ids are unique

Two ids can be equal only if they share the millisecond and the suffix. The
suffix is 8 bytes from the platform's entropy source, uniform on $2^{64}$
values. For $k$ ids made in the same millisecond the union bound over the
$\binom{k}{2}$ pairs gives

$$
P(\text{some two collide}) \le \binom{k}{2}\, 2^{-64} < \frac{k^2}{2^{65}} ,
$$

below $3 \cdot 10^{-14}$ for $k = 1000$ runs started in one millisecond. Without
an entropy source the suffix is `seq<n>` with a per-process counter $n$: ids
of one process are distinct because $n$ strictly increases, but two processes
that start in the same millisecond produce the same first id. The API says so
rather than pretending to a guarantee it cannot give.

## Design decisions

### A separate package

*Problem.* Detecting the environment needs subprocesses, files, environment
variables, the clock and an entropy source; `model` must stay free of IO, and
the runner must stay a function of its inputs. *Options.* Probe in `model`;
probe inside `runner.run`; a separate package. *Choice.* A package that
depends on `model` and nothing else in mare_mark, and that nothing in
mare_mark depends on. *Why.* `model` keeps building and testing on every
target without host access, and the runner keeps taking a snapshot as an
argument, so a test can still pass a hand-written, fully deterministic one.
Detection is a convenience at the edge: the program that runs the benchmark
calls it once and hands the result in.

```text
model ◀── env_detect ◀── your benchmark program ──▶ runner ──▶ model
```

### Asynchronous on every target

*Problem.* On native, running `uname` or `git` uses
`@process.collect_output`, which is `async`; the other targets have nothing to
wait for. *Choice.* `detect` is `async` everywhere. *Why.* One signature on
every target keeps benchmark code portable. It is called in the same place as
`runner.run`, which is already asynchronous, so the requirement costs nothing
in practice. `new_run_id` needs no IO and stays an ordinary function.

### What each target can detect

Each field is probed where the platform offers a reliable source, then taken
from an environment variable, then left as a fallback.

| Field | native | JS on Node.js | JS in a browser | wasm, wasm-gc, LLVM |
| --- | --- | --- | --- | --- |
| `target`, `gc` | fixed by the compilation target | fixed | fixed | fixed |
| `runtime` | `"native"` | `"node " + process.versions.node` | none | `"native"` on LLVM, else none |
| `os` | `uname -sr` | `os.type() + " " + os.release()` | `OS` | `OS` |
| `hostname` | `uname -n` | `os.hostname()` | `HOSTNAME`, `COMPUTERNAME` | `HOSTNAME`, `COMPUTERNAME` |
| CPU model | `model name` in `/proc/cpuinfo`, else `sysctl -n machdep.cpu.brand_string` | `os.cpus()[0].model` | `PROCESSOR_IDENTIFIER` | `PROCESSOR_IDENTIFIER` |
| logical cores | `getconf _NPROCESSORS_ONLN` | `os.availableParallelism()` | `navigator.hardwareConcurrency` | `NUMBER_OF_PROCESSORS` |
| `revision` | `GITHUB_SHA`, `CI_COMMIT_SHA`, `GIT_COMMIT`, else `git rev-parse HEAD` | the variables | the variables | the variables |
| `toolchain` | `MARE_MARK_TOOLCHAIN` | the variable | the variable | the variable |

The environment variables of the `os`, `hostname`, CPU and core rows are also
the fallbacks on native and Node.js when the probe finds nothing. They are the
names Windows sets (`OS`, `COMPUTERNAME`, `PROCESSOR_IDENTIFIER`,
`NUMBER_OF_PROCESSORS`) and the one POSIX shells set (`HOSTNAME`), so a native
build on Windows, which has no `uname`, still describes itself. A browser has no environment variables, so there
the variables find nothing. On Node.js the `os` module is reached through
`process.getBuiltinModule`; versions without it fall back to
`navigator.hardwareConcurrency` for the cores and to the variables for the
rest.

For the revision the order is reversed: the CI variables come first. They name
the commit being built even when the checkout is shallow, detached, or not the
working directory of the benchmark, and they are free to read; `git` is the
fallback for a developer machine.

Values are trimmed, blank values count as missing, and a core count must be a
positive integer.

### Never invent a value

*Problem.* A field that cannot be detected still needs a value, because the
snapshot fields are plain strings and integers. *Options.* Fail; guess a
plausible value ("linux", the core count); write a marker and say so.
*Choice.* The marker `UNKNOWN` (`"unknown"`), `UNKNOWN_CONCURRENCY` (`0`), or
for `clock`, `device` and `frequency_policy` the documented defaults
`DEFAULT_CLOCK`, `DEFAULT_DEVICE` and `DEFAULT_FREQUENCY_POLICY`, and in every
case the field name in `undetected`. *Why.* Failing would stop a benchmark on
an unusual host for a field it may not care about. A guess is
indistinguishable from an observation in the record and in
`environment_compatible`, so two unknown machines would silently look
identical. The marker is visibly not an observation, and `undetected` lets the
caller decide which gaps matter; the three defaults are the conventions the
rest of mare_mark already uses (`PerformanceEnvironment::new`, the runner's
monotonic clock) and are listed because a convention is not an observation.

An overridden field is the caller's statement and is never listed. This makes
the invariant simple: a field is in `undetected` exactly when it holds its
fallback for lack of anything better.

### `concurrency` is the benchmark's, the cores are the machine's

*Problem.* `PerformanceEnvironment.concurrency` could be read as "how many
cores the machine has". *Choice.* It is the degree of parallelism of the
benchmark, is never detected, and the logical core count goes into the `cpu`
text: `"Apple M4 (10 logical cores)"`. *Why.* A sequential benchmark on a
ten-core machine runs one operation at a time; recording `10` would describe a
run that never happened, and two sequential runs on machines with different
core counts would differ in the wrong field. The core count is a property of
the machine and belongs with the CPU model, where it still separates
machines in `environment_compatible`. `UNKNOWN_CONCURRENCY` is `0` because
no benchmark runs with parallelism $0$.

### Memory management labels

`gc` is fixed by the target: `"rc"` on native, LLVM and wasm, where MoonBit
manages memory by reference counting, `"wasm-gc"` on wasm-gc, where the host
collector owns objects, and `"js-engine"` on JavaScript. It is a performance
field because allocation and deallocation costs differ between these schemes,
and it is always known, so it is never undetected.

### Bounded subprocesses

Every native probe runs under `@async.with_timeout_opt` with a limit of
5000 ms, and a probe that is missing, exits with a non-zero code, prints only
blanks or times out yields nothing, so its field falls back. At most five
commands run (`uname` twice, `getconf`, `sysctl` when `/proc/cpuinfo` has no
model, `git`), one after another, so `detect` returns within 25 seconds in the
worst case and within milliseconds normally. Five seconds is the default
timeout of a `ReplaySpec` as well: long enough for a cold `git` in a large
repository, short enough to notice.

### Overrides for every field

Every field, detected or not, has a labelled argument. A field that is passed
is not probed, so an override also avoids the cost of its probe and any
privacy concern about it (pass `hostname=` to keep a host name out of a
published record). Overrides are how the caller supplies the fields no probe
can see (`compiler_flags`, `dtype_abi`, `concurrency`, often `toolchain`) and
how a CI job pins a description that would otherwise change between
equivalent runners.

## Correctness and invariants

- **Total.** `detect` never raises; every probe failure becomes a fallback.
- **Undetected exactly.** A field is in `undetected` if and only if it was not
  overridden and holds its fallback because nothing was found; each name
  appears once, in snapshot order. `target`, `gc`, `timestamp` and `run_id`
  are never listed.
- **One instant.** `timestamp` and the time part of `run_id` come from the
  same clock reading: the run id is the timestamp with milliseconds added.
- **Ordering and uniqueness** of run ids as derived above; `seq<n>` ids are
  unique within a process.
- **Bounded time.** At most five subprocesses of at most 5 s each on native;
  no waiting elsewhere.
- **Calendar.** The UTC conversion is exact for $0 \le t < 2^{63}$ ms and
  formats with fixed width up to year 9999.

## Alternatives rejected

- **Detecting in `model` or `runner`.** Would put IO into the vocabulary or
  make a run depend on the host behind the caller's back.
- **Detecting `concurrency` from the core count.** Describes the machine, not
  the benchmark (see above).
- **Plausible defaults for undetected fields.** Indistinguishable from
  observations.
- **An error for undetected fields.** Stops benchmarks on unusual hosts; the
  caller can turn `undetected` into an error where it matters.
- **Reading CPU frequency, governor or turbo state.** Needs per-OS code and
  often privileges, and a single reading says little about a whole run;
  `frequency_policy` stays a declared value.
- **Caching the result in the process.** `timestamp` and `run_id` must be
  fresh for every run; the other probes are cheap.

## Boundaries

- It does not detect `compiler_flags`, `dtype_abi`, `concurrency`, `clock`,
  `device` or `frequency_policy`, and finds `toolchain` only through
  `MARE_MARK_TOOLCHAIN`.
- The revision is the commit, not the state of the working tree: uncommitted
  changes are not recorded, and `git` runs only on native.
- It does not pin threads, fix frequencies or check that the machine is idle;
  like the runner, it records and does not control.
- `detect` needs an async runtime, so it cannot run on wasm-gc; `new_run_id`
  runs there and uses `seq<n>` ids.
- Host names and OS releases end up in records that may be published; override
  them when that matters.
- Nothing in mare_mark calls `detect`; the program that runs the benchmark
  decides whether to use it.
