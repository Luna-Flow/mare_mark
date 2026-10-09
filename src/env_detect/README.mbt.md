# `env_detect`

Fills a `model.EnvironmentSnapshot` from what the running process can learn,
so a run needs no hand-written environment.

`detect()` is asynchronous and never fails. It reports the compilation target,
memory management and runtime, and probes the OS, hostname, CPU model and
logical core count (`uname`, `getconf`, `/proc/cpuinfo` or `sysctl` on native;
Node's `os` module on JavaScript; `OS`, `HOSTNAME` / `COMPUTERNAME`,
`PROCESSOR_IDENTIFIER` and `NUMBER_OF_PROCESSORS` elsewhere). The timestamp is
the current UTC time (`YYYY-MM-DDTHH:MM:SSZ`), the revision comes from
`GITHUB_SHA`, `CI_COMMIT_SHA` or `GIT_COMMIT`, else `git rev-parse HEAD` on
native, and the toolchain from `MARE_MARK_TOOLCHAIN`. The run id is
`YYYYMMDDTHHMMSSmmmZ-<16 hex digits of entropy>` (`-seq<n>` without an
entropy source).

Nothing is invented: a field that cannot be detected holds `UNKNOWN`
(`UNKNOWN_CONCURRENCY` for the core count, `DEFAULT_CLOCK`, `DEFAULT_DEVICE`
or `DEFAULT_FREQUENCY_POLICY` for the fields that are never detected) and its
name is listed in `undetected`. Every field can be overridden by a labelled
argument; the `model` constructors remain for fully hand-written snapshots.

```moonbit nocheck
///|
async test "detect with overrides" {
  let detected = @env_detect.detect(
    toolchain="moonc 0.10",
    compiler_flags="release",
  )
  inspect(detected.snapshot.semantic.toolchain, content="moonc 0.10")
  inspect(detected.undetected.contains("toolchain"), content="false")
  inspect(detected.undetected.contains("dtype_abi"), content="true")
}
```
