import 'models.dart';

/// One change between two [RipLog]s.
class RipLogDiffEntry {
  /// Dotted path to the field that differs, e.g. `toolVersion`,
  /// `tracks[3].copyCrc`, or `tracks[0].errors.readErrors`.
  final String path;

  /// The value in the "left" (first) log, or `null` if only the right log
  /// has it.
  final Object? left;

  /// The value in the "right" (second) log, or `null` if only the left log
  /// has it.
  final Object? right;

  /// The kind of change.
  final RipLogDiffKind kind;

  const RipLogDiffEntry({
    required this.path,
    required this.left,
    required this.right,
    required this.kind,
  });

  @override
  String toString() => '$path: $kind ($left → $right)';
}

/// Classification of a single [RipLogDiffEntry].
enum RipLogDiffKind {
  /// Field present on both sides with different values.
  changed,

  /// Field present on the left only.
  removed,

  /// Field present on the right only.
  added,

  /// A whole track number exists on one side only.
  trackAdded,

  /// A whole track number exists on the other side only.
  trackRemoved,
}

/// Structured diff between two parsed rip logs.
///
/// Empty [entries] means the two logs are equal for all diff-tracked fields.
class RipLogDiff {
  final List<RipLogDiffEntry> entries;

  const RipLogDiff(this.entries);

  /// `true` when there are no differences between the two logs.
  bool get isEmpty => entries.isEmpty;

  /// `true` when at least one difference was recorded.
  bool get isNotEmpty => entries.isNotEmpty;

  /// Differences confined to track-level fields (CRC, AR status, errors).
  List<RipLogDiffEntry> get trackDifferences =>
      entries.where((e) => e.path.startsWith('tracks')).toList();

  /// Differences in log-level header/footer fields.
  List<RipLogDiffEntry> get headerDifferences =>
      entries.where((e) => !e.path.startsWith('tracks')).toList();
}

/// Compare two [RipLog]s and return a structured [RipLogDiff].
///
/// Useful for verifying that a re-rip matches a prior rip: every track CRC,
/// AccurateRip status, and error count is surfaced as a separate entry.
///
/// Tracks are matched by [RipLogTrack.trackNumber]; a track present on only
/// one side is reported as [RipLogDiffKind.trackAdded] or
/// [RipLogDiffKind.trackRemoved] rather than emitting one diff entry per
/// missing field.
///
/// Parser-level warnings in [RipLog.errors] are intentionally ignored so
/// that a re-parse of the same log on a newer library version does not
/// show as a difference. [RipLog.source] is also ignored — it is
/// lineage metadata (with a wall-clock timestamp) that has nothing to
/// do with the rip itself.
RipLogDiff compareRipLogs(RipLog left, RipLog right) {
  final entries = <RipLogDiffEntry>[];

  void diff(String path, Object? a, Object? b) {
    if (a == b) return;
    final kind = a == null
        ? RipLogDiffKind.added
        : b == null
            ? RipLogDiffKind.removed
            : RipLogDiffKind.changed;
    entries.add(RipLogDiffEntry(path: path, left: a, right: b, kind: kind));
  }

  diff('logFormat', left.logFormat, right.logFormat);
  diff('toolVersion', left.toolVersion, right.toolVersion);
  diff('extractionDate', left.extractionDate, right.extractionDate);
  diff('drive', left.drive, right.drive);
  diff('readMode', left.readMode, right.readMode);
  diff('readOffset', left.readOffset, right.readOffset);
  diff('overread', left.overread, right.overread);
  diff('gapHandling', left.gapHandling, right.gapHandling);
  diff('mediaType', left.mediaType, right.mediaType);
  diff('accurateRipSummary', left.accurateRipSummary, right.accurateRipSummary);
  diff('integrityHash', left.integrityHash, right.integrityHash);

  final leftByNumber = {for (final t in left.tracks) t.trackNumber: t};
  final rightByNumber = {for (final t in right.tracks) t.trackNumber: t};
  final allNumbers = {...leftByNumber.keys, ...rightByNumber.keys}.toList()
    ..sort();

  for (final n in allNumbers) {
    final l = leftByNumber[n];
    final r = rightByNumber[n];
    if (l == null) {
      entries.add(RipLogDiffEntry(
          path: 'tracks[$n]',
          left: null,
          right: r,
          kind: RipLogDiffKind.trackAdded));
      continue;
    }
    if (r == null) {
      entries.add(RipLogDiffEntry(
          path: 'tracks[$n]',
          left: l,
          right: null,
          kind: RipLogDiffKind.trackRemoved));
      continue;
    }
    _diffTrack('tracks[$n]', l, r, entries);
  }

  return RipLogDiff(entries);
}

void _diffTrack(
    String base, RipLogTrack a, RipLogTrack b, List<RipLogDiffEntry> entries) {
  void d(String field, Object? x, Object? y) {
    if (x == y) return;
    final kind = x == null
        ? RipLogDiffKind.added
        : y == null
            ? RipLogDiffKind.removed
            : RipLogDiffKind.changed;
    entries.add(
        RipLogDiffEntry(path: '$base.$field', left: x, right: y, kind: kind));
  }

  d('filename', a.filename, b.filename);
  d('peakLevel', a.peakLevel, b.peakLevel);
  d('trackQuality', a.trackQuality, b.trackQuality);
  d('copyCrc', a.copyCrc, b.copyCrc);
  d('testCrc', a.testCrc, b.testCrc);
  d('accurateRipStatus', a.accurateRipStatus, b.accurateRipStatus);
  d('accurateRipCrcV1', a.accurateRipCrcV1, b.accurateRipCrcV1);
  d('accurateRipCrcV2', a.accurateRipCrcV2, b.accurateRipCrcV2);
  d('accurateRipConfidence', a.accurateRipConfidence, b.accurateRipConfidence);
  d('copyOk', a.copyOk, b.copyOk);
  d('startSector', a.startSector, b.startSector);
  d('lengthSectors', a.lengthSectors, b.lengthSectors);
  d('durationSeconds', a.durationSeconds, b.durationSeconds);

  _diffTrackErrors('$base.errors', a.errors, b.errors, entries);
}

void _diffTrackErrors(
    String base, TrackErrors a, TrackErrors b, List<RipLogDiffEntry> entries) {
  void d(String field, int x, int y) {
    if (x == y) return;
    entries.add(RipLogDiffEntry(
        path: '$base.$field', left: x, right: y, kind: RipLogDiffKind.changed));
  }

  d('readErrors', a.readErrors, b.readErrors);
  d('skipErrors', a.skipErrors, b.skipErrors);
  d('jitterErrors', a.jitterErrors, b.jitterErrors);
  d('edgeJitterErrors', a.edgeJitterErrors, b.edgeJitterErrors);
  d('atomJitterErrors', a.atomJitterErrors, b.atomJitterErrors);
  d('driftErrors', a.driftErrors, b.driftErrors);
  d('droppedBytes', a.droppedBytes, b.droppedBytes);
  d('duplicatedBytes', a.duplicatedBytes, b.duplicatedBytes);
  d('inconsistentErrorSectors', a.inconsistentErrorSectors,
      b.inconsistentErrorSectors);
  d('damagedSectors', a.damagedSectors, b.damagedSectors);
}
