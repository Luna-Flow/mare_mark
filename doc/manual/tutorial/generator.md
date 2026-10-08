# generator tutorial

This tutorial makes benchmark inputs reproducible: one run seed becomes
independent seeds per dataset, a fixture uses them to generate inputs, and a
fingerprint records exactly what was measured. Every example is a complete
test.

## Quick start

```sh
moon add Luna-Flow/mare_mark@0.3.0
```

```text
import {
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/generator",
  "Luna-Flow/mare_mark/fixture",
}
```

```moonbit
test "one run seed, many dataset seeds" {
  let run_seed = 2026UL
  let seeds = [0, 1, 2].map(id => @generator.derive_seed(run_seed, "dataset", id))
  inspect(seeds[0] != seeds[1] && seeds[1] != seeds[2], content="true")
  inspect(seeds[2] == @generator.derive_seed(2026UL, "dataset", 2), content="true")
}
```

## Everyday tasks

### Generate random inputs from a derived seed

Use the derived seed to drive any pseudo-random generator. This example uses a
small linear congruential generator so that it needs no other package:

```moonbit
fn random_array(seed : UInt64, length : Int) -> Array[Int] {
  let mut state = seed
  Array::makei(length, _ => {
    state = state * 6364136223846793005UL + 1442695040888963407UL
    (state >> 33).to_int() % 1000
  })
}

test "reproducible random input" {
  let seed = @generator.derive_seed(42UL, "sort-input", 0)
  let first = random_array(seed, 5)
  let again = random_array(seed, 5)
  inspect(first == again, content="true")
  inspect(first.length(), content="5")
}
```

### Generate inside a fixture

The runner hands the fixture a `GenerationContext` that holds the run seed, the
case id and the dataset key. Derive the dataset seed there:

```moonbit
test "a seeded fixture" {
  let fixture : @fixture.Fixture[Int, Array[Int], Array[Int]] = @fixture.Fixture::immutable(
    "random-ints",
    "1",
    context => {
      let seed = @generator.derive_seed(context.seed, context.case_id, context.dataset_key.dataset_id)
      random_array(seed, context.dataset_key.scale)
    },
    xs => @generator.stable_fingerprint(xs.map(x => x.to_string()).join(",")),
  )
  let context = @generator.context(42UL, "suite", "sort", @model.DatasetKey::new(8, 0), fixture.id, fixture.version)
  let input = @fixture.materialize(fixture, context)
  inspect(input.length(), content="8")
  inspect(input == @fixture.materialize(fixture, context), content="true")
}
```

### Record what was measured

Fingerprint a canonical serialization of the input and keep it with the
results. The runner puts the fixture's fingerprint into every validation event
and every failure artifact:

```moonbit
test "fingerprints identify serializations" {
  let a = @generator.stable_fingerprint("[1,2,3]")
  let b = @generator.stable_fingerprint("[1, 2, 3]")
  inspect(a.length(), content="71")
  inspect(a == b, content="false")
}
```

The two strings describe the same array but are different serializations, so
choose one canonical form.

### Seeds per measurement

When an experiment draws noise per block, derive it from all three ids:

```moonbit
test "per-measurement seeds" {
  let seeds = [
    @generator.measurement_seed(1UL, 0, 0, 0),
    @generator.measurement_seed(1UL, 0, 0, 1),
    @generator.measurement_seed(1UL, 0, 1, 0),
    @generator.measurement_seed(1UL, 1, 0, 0),
  ]
  let distinct = seeds.all(s => seeds.filter(t => t == s).length() == 1)
  inspect(distinct, content="true")
}
```

## Going further

- Wrap a generating function and its fingerprint in a `@generator.Generator`
  and bump its `version` whenever the values change.
- The [generator design](../design/generator.md) proves that different indices
  and different run seeds never produce the same derived seed.

## Common pitfalls

- **Using `context.seed` directly for every dataset.** All datasets would draw
  the same stream; derive per dataset.
- **Hashing non-canonical text.** Maps and floats need a fixed order and
  format before fingerprinting.
- **Treating fingerprints as signatures.** They are unkeyed.

## Next steps

- [generator API](../api/generator.md), [generator design](../design/generator.md).
- [fixture tutorial](fixture.md) for the lifecycle around generated inputs.
