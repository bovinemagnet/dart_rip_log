/// Shared parsing of the `TOC of the extracted CD` table that both EAC
/// and XLD logs emit:
///
///      Track |   Start  |  Length  | Start sector | End sector
///     ---------------------------------------------------------
///         1  |  0:00.00 |  4:32.15 |         0    |    20414
///
/// EAC writes times as `m:ss.ff`, XLD as `mm:ss:ff` — both are minutes,
/// seconds, frames (75 frames per second).
library;

final _reTocHeader = RegExp(r'TOC of the extracted CD', caseSensitive: false);
final _reTocRow = RegExp(
    r'^(\d+)\s*\|\s*([\d:.]+)\s*\|\s*([\d:.]+)\s*\|\s*(\d+)\s*\|\s*(\d+)');

/// One track's timing data from the TOC table.
class TocEntry {
  final int startSector;
  final int lengthSectors;
  final double durationSeconds;

  const TocEntry({
    required this.startSector,
    required this.lengthSectors,
    required this.durationSeconds,
  });
}

/// Parse the TOC table out of [lines], keyed by track number.
///
/// Returns an empty map when no `TOC of the extracted CD` header is
/// present. `durationSeconds` comes from the length column when it
/// parses as minutes/seconds/frames, otherwise from `lengthSectors / 75`.
Map<int, TocEntry> parseTocTable(List<String> lines) {
  final entries = <int, TocEntry>{};
  var seenHeader = false;
  for (final line in lines) {
    final trimmed = line.trim();
    if (!seenHeader) {
      seenHeader = _reTocHeader.hasMatch(trimmed);
      continue;
    }
    final m = _reTocRow.firstMatch(trimmed);
    if (m == null) continue;
    final trackNumber = int.tryParse(m.group(1)!);
    final startSector = int.tryParse(m.group(4)!);
    final endSector = int.tryParse(m.group(5)!);
    if (trackNumber == null || startSector == null || endSector == null) {
      continue;
    }
    final lengthSectors = endSector - startSector + 1;
    entries[trackNumber] = TocEntry(
      startSector: startSector,
      lengthSectors: lengthSectors,
      durationSeconds: _parseMsf(m.group(3)!) ?? lengthSectors / 75.0,
    );
  }
  return entries;
}

/// Parse a `m:ss.ff` / `mm:ss:ff` time to seconds. Frames are 1/75 s.
double? _parseMsf(String raw) {
  final parts = raw.split(RegExp(r'[:.]'));
  if (parts.length != 3) return null;
  final minutes = int.tryParse(parts[0]);
  final seconds = int.tryParse(parts[1]);
  final frames = int.tryParse(parts[2]);
  if (minutes == null || seconds == null || frames == null) return null;
  return minutes * 60 + seconds + frames / 75.0;
}
