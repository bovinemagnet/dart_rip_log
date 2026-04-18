# Benchmark harness — design

**Issue:** [#22](https://github.com/bovinemagnet/dart_rip_log/issues/22) (milestone 0.2.0)
**Date:** 2026-04-18
**Author:** Paul Snow

## Problem

`dart_rip_log` has no benchmarks. The only performance signal today is a
`<1 s` floor assertion on a synthetic 500-track EAC log inside
`test/edge_cases_test.dart`. That guards against catastrophic regressions
(O(n²)) but cannot surface a 30 % slowdown or tell us whether a change hurts
`detectLogFormat`, the parser, or `toJson`.

Issue #22 asks for a checked-in `benchmark/` using `package:benchmark_harness`
covering at least EAC small, EAC 500-track, and XLD small, so regressions
become visible.

## Goals

- A `dart run benchmark/main.dart` harness that measures `detectLogFormat`,
  `parseRipLog`, and `toJson` against three fixtures.
- Deterministic, diffable input: the 500-track log is a checked-in file, not
  generated at run time.
- Readable output a human can eyeball: grouped per-fixture table with
  µs/track for the 500-track case.
- The existing 500-track smoke test in `test/edge_cases_test.dart` shares the
  same fixture — one source of truth.
- No CI enforcement, no baseline comparison. The harness is run locally when
  you want to check a change.

## Non-goals

- No CI benchmark job, no baseline file, no regression threshold in CI
  (beyond the existing `<1 s` smoke).
- No `--filter`, `--json`, or `--iterations` flags in v1.
- No memory or allocation measurement.
- No benchmarks for the not-yet-implemented parsers (whipper, CUERipper,
  dBpoweramp).

## Design

### Layout

```
benchmark/
  main.dart                   entry point
  src/
    fixtures.dart             loads the three fixture files once
    cases.dart                nine BenchmarkBase subclasses
    reporter.dart             custom ScoreEmitter + table printer
tool/
  gen_500_track_fixture.dart  regenerates test/fixtures/eac_500_track.log
test/
  fixtures/
    eac_500_track.log         new, ~50 KB, checked in
  benchmark_smoke_test.dart   new, runs `dart run benchmark/main.dart --smoke`
```

No changes under `lib/`. The harness consumes the public API only.

### Dependencies

Add one dev dependency to `pubspec.yaml`:

```yaml
dev_dependencies:
  benchmark_harness: ^2.3.0
```

Runtime dependencies remain zero.

### Fixtures

Three fixtures feed nine cases:

| Fixture            | File                              | Size     | Role              |
|--------------------|-----------------------------------|----------|-------------------|
| `eac_sample`       | `test/fixtures/eac_sample.log`    | ~2 KB    | EAC small         |
| `xld_sample`       | `test/fixtures/xld_sample.log`    | ~2 KB    | XLD small         |
| `eac_500_track`    | `test/fixtures/eac_500_track.log` | ~50 KB   | EAC 500-track     |

The 500-track fixture is the same synthetic EAC content that
`test/edge_cases_test.dart` currently builds with a `StringBuffer` — header
plus 500 `Track N` blocks (filename, peak, quality, copy CRC, AR confidence,
`Copy OK`) and a trailing `All tracks accurately ripped`.

It is generated once by a small helper (`tool/gen_500_track_fixture.dart`)
and committed. Regenerating is a deliberate act, not a test-time side
effect.

### Cases

Nine `BenchmarkBase` subclasses — three operations × three fixtures:

| Operation         | What it measures                                        |
|-------------------|---------------------------------------------------------|
| `detect`          | `detectLogFormat(content)`                              |
| `parse`           | `parseRipLog(content)` (end-to-end, includes detect)    |
| `toJson`          | `toJson(parseResult)` with `parseResult` precomputed in `setup` |

`benchmark_harness` defaults (10 warm-up runs, measure for ≥2 s) are kept.
File I/O is done once at process start, before any case runs, so it is not
measured.

### Output

A custom `ScoreEmitter` swallows `benchmark_harness`'s per-case print and
stores `(fixture, op) → µs`. After all nine complete, `main.dart` prints a
grouped table:

```
Fixture              detect       parse       toJson      parse µs/track
-------------------  -----------  ----------  ----------  --------------
eac_sample                X.X µs    X.XX µs    X.XX µs             N/A
xld_sample                X.X µs    X.XX µs    X.XX µs             N/A
eac_500_track             X.X µs  XXX.XX µs   XX.XX µs         X.XX µs
```

The µs/track column is only populated for the 500-track case and is
`parse µs ÷ 500`. It is the number humans will eyeball for regressions.

### Smoke mode

`dart run benchmark/main.dart --smoke` short-circuits each case to one
warm-up iteration and one measured iteration, finishing the full suite in
~1 s. A new `test/benchmark_smoke_test.dart` spawns this as a subprocess
and asserts:

- exit code is 0,
- stdout contains the three fixture names and the table header.

Purpose: catch benchmark bit-rot (e.g. a public-API rename that breaks
`benchmark/`) without running the full benchmark in CI.

### Existing smoke test

`test/edge_cases_test.dart`'s `500-track EAC log parses in under 1 second`
test swaps its `StringBuffer` generation for
`File('test/fixtures/eac_500_track.log').readAsStringSync()`. The `<1 s`
assertion stays. The test and the benchmark now share one input.

### Error handling

- Missing fixture file → `File.readAsStringSync` throws. Stack trace is
  acceptable UX for a dev-only tool.
- `detectLogFormat` returning `RipLogFormat.unknown` for a real fixture →
  the benchmark's `setup` asserts and fails loudly. Without this,
  `parseRipLog` would silently return an empty `RipLog` and the benchmark
  would measure nothing meaningful.

### README

One-line addition to the Commands section of `README.md`:

```
- Run benchmarks: `dart run benchmark/main.dart`
```

## Testing

- `test/benchmark_smoke_test.dart` — covers that the harness compiles, runs,
  and prints the expected surface.
- The existing 500-track smoke in `test/edge_cases_test.dart` — still
  passes after the fixture migration, covers the fixture load path.
- Manual: run `dart run benchmark/main.dart` locally before and after a
  parser change to eyeball the table.

## Trade-offs

- **No baseline comparison.** Chose print-only (Q1=A) because baseline
  tracking is meaningful infra (storage, PR comments, stability against
  noisy runners) and the issue's bar is "make regressions visible", not
  "block regressions". Can be added later as a `--json` output mode feeding
  a separate CI job.
- **Shared 500-track fixture couples test and benchmark.** Upside: one
  source of truth. Downside: the benchmark directory depends on a file
  under `test/`. Acceptable for a single-package dev tool; the benchmark
  is never published.
- **`setup` for `toJson` precomputes the parse.** This means the `toJson`
  case measures serialisation in isolation, not the realistic
  "parse + serialise" path. The `parse` case already covers end-to-end;
  isolating `toJson` is what makes the breakdown useful.
