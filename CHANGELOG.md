# Changelog

## 0.0.2

- Relicensed from GPL-3.0 to Apache-2.0.

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
