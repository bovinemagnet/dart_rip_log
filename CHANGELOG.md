# Changelog

## 0.0.5

- CLI: `--format ndjson` — streaming-friendly one-JSON-object-per-line
  output (useful with jq and log pipelines).
- CLI: `--filter <mode>` — hide non-problem tracks in `--format text`
  / `--summary` output. Values: `all` (default), `mismatch`, `errors`,
  `problems` (mismatch or error counts).
- CLI: `--fail-on <policy>` — choose which conditions trigger exit 1.
  Values: `any` (default, current behaviour), `mismatch`, `errors`,
  `never`. Useful for tuning CI pipelines.
- CLI: `-r` / `--recursive` — walk directories for `*.log` files
  instead of requiring individual paths.
- CLI: `--color <mode>` — `auto` (default, based on `stdout.hasTerminal`
  and `NO_COLOR`), `always`, `never`. Colours AR status (verified →
  green, mismatch → red, notInDatabase → yellow, notChecked → dim)
  and the `ERRORS` label.
- CLI tests grown to 27 (all covered by the new flags). Total suite: 190.

## 0.0.4

- EAC: parse localised month names in the extraction date. Coverage for
  English, German, French, Spanish, Italian, Dutch, and Portuguese.
- `RipLog.testAndCopy` — new field, derived from the presence of per-track
  `Test CRC` lines. `null` when no tracks were parsed, otherwise `true`
  if any track recorded a test CRC (test + copy mode) or `false`
  (copy-only mode).
- `RipLog.accurateRipDiscId` and `RipLog.accurateRipTotalSubmissions` —
  new fields populated from XLD's `AccurateRip Summary` / `DiscID:` /
  `Total submissions:` lines. Serialised in the JSON output when present.
- 178 tests (7 new covering localised dates, test+copy derivation, and
  the AR summary block).

## 0.0.3

- Added `fromJson` constructors on `RipLog`, `RipLogTrack`, `TrackErrors`,
  and `DriveInfo`, completing the JSON round-trip. Unknown enum values
  degrade to `unknown` / `notChecked` rather than throwing, so logs
  serialised by a newer library version remain readable on older
  versions.
- Models now implement `==` and `hashCode` (field-wise), so two parsed
  logs can be compared directly and used as map keys / in sets.
- New diff utility `compareRipLogs(a, b)` returns a structured
  `RipLogDiff` with per-field entries (`tracks[N].copyCrc`,
  `tracks[N].errors.readErrors`, etc.). Tracks present on only one side
  are reported as `trackAdded` / `trackRemoved`. Parser-level warnings
  in `RipLog.errors` are intentionally ignored so re-parses on a newer
  library don't surface as diffs. Exported types: `compareRipLogs`,
  `RipLogDiff`, `RipLogDiffEntry`, `RipLogDiffKind`.
- Test suite grown to 171 tests (round-trip, equality, diff).

## 0.0.2

- Relicensed from GPL-3.0 to Apache-2.0.
- Added GitHub Actions CI (analyze + test on Linux/macOS/Windows against
  stable and beta Dart SDKs, plus a `dart pub publish --dry-run` gate).
- Added dartdoc generation to CI to keep the public API documented.
- Added a release workflow that publishes prebuilt `riplog` binaries for
  Linux x64, macOS arm64, and Windows x64 on every `v*` tag.
- README now carries CI, pub, and licence badges.

## 0.0.1

- Initial release.
- Full EAC parser: header metadata, per-track fields, AccurateRip v1 and
  optional v2 signature capture, full error-statistics block, summary and
  log-checksum footer, Range-rip (single-track whole-disc) logs.
- Full XLD parser: header, per-track CRC32/AR v1/v2, Statistics block.
- Format detection and scaffolded parsers for CUERipper, whipper, and
  dBpoweramp (tool version captured; full per-track parsing pending
  sample logs).
- Convenience helpers: `isFullyVerified`, `tracksWithErrors`,
  `tracksWithArMismatch`, `toJson`.
- Command-line tool `riplog`:
  - JSON, text, and one-line summary output.
  - `--help`, `--version`, `--quiet`/`-q` flags.
  - Accepts multiple files (emits a JSON array) and reads from stdin
    (`-` or when piped).
  - Non-zero exit code on AR mismatch or track errors, for scripting / CI use.
- Tolerant of malformed input (truncated files, garbled lines, mixed line
  endings) — never throws on log content.
- Test suite: 155 tests covering unit parsing, CLI integration, JSON-shape
  goldens, Unicode filenames, and a parse-throughput smoke test.
