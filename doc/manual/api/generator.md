# generator API

## Purpose

`Luna-Flow/mare_mark/generator` makes benchmark inputs reproducible: it derives
independent seeds for datasets, repetitions and blocks from one run seed,
builds generation contexts, and fingerprints serialized inputs. The mixing
functions are derived in the [generator design](../design/generator.md).

Source: [`src/generator/generator.mbt`](../../../src/generator/generator.mbt).

## Importing

Add the packages to the `moon.pkg` of the package that uses them:

```moonbit nocheck
import {
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/generator",
}
```

The examples on this page call them through their default aliases (`@model`,
`@generator`).

## Seeds

### `derive_seed`

`derive_seed` derives a child seed from a parent seed, a domain name and an
index.

```mbti
pub fn derive_seed(UInt64, String, Int) -> UInt64
```

The result depends on all three arguments and on nothing else, uses only
wrapping 64-bit arithmetic, and is therefore identical on every target. Use a
different domain for every purpose ("dataset", "noise", the case id) so that
streams for different purposes are unrelated.

```moonbit
test "derived seeds" {
  let run_seed = 42UL
  let first = @generator.derive_seed(run_seed, "dataset", 0)
  let second = @generator.derive_seed(run_seed, "dataset", 1)
  let other = @generator.derive_seed(run_seed, "noise", 0)
  inspect(first == @generator.derive_seed(42UL, "dataset", 0), content="true")
  inspect(first != second && first != other, content="true")
}
```

### `measurement_seed`

`measurement_seed` derives the seed of one measurement from a run seed and its
dataset, repetition and block ids.

```mbti
pub fn measurement_seed(UInt64, Int, Int, Int) -> UInt64
```

It is
`derive_seed(derive_seed(derive_seed(seed, "dataset", d), "repetition", r), "block", b)`.

```moonbit
test "measurement seeds" {
  let a = @generator.measurement_seed(7UL, 0, 1, 2)
  let b = @generator.measurement_seed(7UL, 0, 2, 1)
  inspect(a != b, content="true")
  inspect(
    a == @generator.derive_seed(
      @generator.derive_seed(@generator.derive_seed(7UL, "dataset", 0), "repetition", 1),
      "block",
      2,
    ),
    content="true",
  )
}
```

## Contexts and generators

### `context`

`context` builds a `@model.GenerationContext`.

```mbti
pub fn[Scale] context(UInt64, String, String, @model.DatasetKey[Scale], String, String) -> @model.GenerationContext[Scale]
```

Arguments: seed, suite id, case id, dataset key, generator id and generator
version. It is the same as `@model.GenerationContext::new`.

### `Generator`

`Generator` bundles a generating function with its identity and fingerprint.

```mbti
pub struct Generator[Scale, Input] {
  id : String
  version : String
  generate : (@model.GenerationContext[Scale]) -> Input
  fingerprint : (Input) -> String
}
pub fn[Scale, Input] Generator::new(String, String, (@model.GenerationContext[Scale]) -> Input, (Input) -> String) -> Self[Scale, Input]
```

Bump `version` whenever `generate` changes the values it produces; the version
is part of the context and of the provenance of every input.

```moonbit
test "a generator" {
  let ramp : @generator.Generator[Int, Array[Int]] = @generator.Generator::new(
    "ramp",
    "1",
    context => Array::makei(context.dataset_key.scale, i => i),
    xs => @generator.stable_fingerprint(xs.map(x => x.to_string()).join(",")),
  )
  let context = @generator.context(1UL, "suite", "sum", @model.DatasetKey::new(4, 0), ramp.id, ramp.version)
  let input = (ramp.generate)(context)
  debug_inspect(input, content="[0, 1, 2, 3]")
  inspect((ramp.fingerprint)(input).has_prefix("sha256:"), content="true")
}
```

## Fingerprints

### `stable_fingerprint`

`stable_fingerprint` returns `"sha256:"` followed by the lowercase hex SHA-256
digest of the UTF-8 encoding of a string.

```mbti
pub fn stable_fingerprint(String) -> String
```

Serialize the input canonically first; the fingerprint identifies the
serialization, not the in-memory value. It is an unkeyed hash: it detects
accidental changes, it does not authenticate data.

```moonbit
test "fingerprint" {
  inspect(
    @generator.stable_fingerprint("abc"),
    content="sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
}
```
