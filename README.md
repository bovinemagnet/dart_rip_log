# dart_rip_log

A pure Dart library that parses CD rip log files from the major CD-ripping tools
(EAC, XLD) into structured, JSON-serialisable quality data. Extracts
AccurateRip verification status, CRC-32 checksums, peak levels, track quality,
and per-track error statistics.

Zero runtime dependencies beyond the Dart SDK.

## Features

- Auto-detects the log format from the log content.
- **EAC** (Exact Audio Copy) — full parser, including:
  - Header: tool version, extraction date, drive, read mode, read offset,
    overread, gap handling, media type.
  - Per track: filename, peak level, track quality, test/copy CRCs, Copy OK.
  - AccurateRip: `verified` (with confidence, v1 CRC and optional v2 signature),
    `mismatch`, `notInDatabase`.
  - Full error-statistics block (read / skip / edge jitter / atom jitter /
    drift / dropped bytes / duplicated bytes / inconsistency).
  - Footer: summary line and log checksum.
  - Range-rip logs (single-track whole-disc extractions).
- **XLD** (X Lossless Decoder) — full parser, including per-track AR v1/v2
  signatures and the `Statistics` block.
- **CUERipper**, **whipper**, **dBpoweramp** — format detection and scaffolded
  parsers (tool version captured; full per-track parsing pending real-world
  sample logs).
- Tolerant of malformed input: truncated files, garbled lines, CRLF/LF/mixed
  line endings, and missing fields return a best-effort `RipLog` rather than
  throwing.
- `toJson()` on every model for easy serialisation.
- Command-line tool (`bin/riplog.dart`) for quick inspection.

## Installing

Add to your `pubspec.yaml`:

```yaml
dependencies:
  dart_rip_log: ^0.0.1
```

Then:

```sh
dart pub get
```

## Quick start

```dart
import 'dart:io';
import 'package:dart_rip_log/dart_rip_log.dart';

Future<void> main(List<String> args) async {
  final log = await parseRipLogFile(args.first);

  print('Format:  ${log.logFormat.name}');
  print('Tool:    ${log.toolVersion}');
  print('Tracks:  ${log.tracks.length}');
  print('Verified: ${isFullyVerified(log)}');

  for (final track in tracksWithArMismatch(log)) {
    print('  ! Track ${track.trackNumber} did not verify against AccurateRip');
  }
}
```

### Parsing from a string

```dart
final log = parseRipLog(logContent);
if (log.logFormat == RipLogFormat.unknown) {
  // Format could not be identified — handle gracefully.
}
```

### Convenience helpers

- `isFullyVerified(log)` — `true` when every track has AccurateRip status
  `verified`.
- `tracksWithErrors(log)` — tracks whose `TrackErrors.hasErrors` is true.
- `tracksWithArMismatch(log)` — tracks whose AccurateRip check failed.
- `toJson(log)` — JSON-compatible `Map<String, dynamic>`.

## Command-line tool

Install globally:

```sh
dart pub global activate dart_rip_log
```

Then:

```sh
riplog --format json my_rip.log          # pretty-printed JSON (default)
riplog --format text my_rip.log          # human-readable
riplog --summary my_rip.log              # one line per track
riplog -q *.log                          # tab-separated one line per file
cat my_rip.log | riplog -q -             # read from stdin
riplog --help                            # full usage
riplog --version
```

Exit codes are scripting-friendly: `0` = all tracks verified and error-free,
`1` = AR mismatch or track errors detected, `2` = bad arguments or I/O error.
With multiple files the JSON output is an array; with `--format text` or
`--summary` each file is prefixed with `# <path>`.

## Data model

| Class                  | Purpose                                         |
| ---------------------- | ----------------------------------------------- |
| `RipLog`               | Top-level result — header fields + tracks.      |
| `RipLogTrack`          | Per-track quality data (unified across formats).|
| `TrackErrors`          | Per-track error counters.                       |
| `DriveInfo`            | Optical drive name, read offset, adapter.       |
| `RipLogFormat` (enum)  | `eac`, `xld`, `cueRipper`, `whipper`, `dbPoweramp`, `unknown`. |
| `AccurateRipStatus` (enum) | `verified`, `mismatch`, `notInDatabase`, `notChecked`. |

## Error tolerance

The library never throws on malformed *content*. It may still throw at the
file-I/O layer — for example, `parseRipLogFile` will throw a
`FileSystemException` when given a non-UTF-8 binary file. On truncated,
garbled, or partially-unknown input the parser returns a `RipLog` with
whatever it could extract; any parsing warnings are collected in
`RipLog.errors`.

## JSON shape

Calling `toJson(log)` (or `log.toJson()`) returns a stable, JSON-compatible
`Map<String, dynamic>`. The shape is pinned by golden tests in
`test/fixtures/*.expected.json` — any intentional change requires regenerating
the goldens. Top-level keys:

```
logFormat, toolVersion, extractionDate, drive, readMode, readOffset,
overread, gapHandling, mediaType, tracks[], accurateRipSummary,
integrityHash, errors[]
```

Each track includes: `trackNumber, filename, peakLevel, trackQuality, copyCrc,
testCrc, accurateRipStatus, accurateRipCrcV1, accurateRipCrcV2,
accurateRipConfidence, copyOk, errors{}, logFormat`. Numeric peak/quality
values are fractions in `[0.0, 1.0]`. Dates are ISO-8601 strings. Optional
fields are omitted when null.

## Running the tests

```sh
dart test                         # full suite (unit + CLI integration)
dart test --exclude-tags cli      # fast: skip shell-out tests
```

The test suite covers header/track/footer parsing, AccurateRip variants,
per-track error statistics, line-ending tolerance, Unicode filenames
(Latin accents, CJK, emoji), a 500-track performance smoke, CLI behaviour,
and JSON-shape golden tests.

## Contributing

Issues and pull requests welcome on
[GitHub](https://github.com/bovinemagnet/dart_rip_log). Additional
real-world log samples from CUERipper, whipper, and dBpoweramp would be
especially valuable for finishing those parsers.

## Licence

Apache-2.0. See [LICENSE](LICENSE).
