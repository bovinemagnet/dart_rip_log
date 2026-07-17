/// Parser for CUERipper logs (github.com/gchudov/cuetools.net).
///
/// CUERipper writes one of two layouts, both starting with a
/// `CUERipper vX.Y.Z Copyright (C) … Grigory Chudov` line:
///
/// * **EAC-style** (the default, `createEACLOG = true`): body identical to
///   a genuine EAC log — delegated to the EAC parser with the format
///   tagged as [RipLogFormat.cueRipper].
/// * **Native**: `Extraction logfile from : MM/DD/YYYY HH:MM:SS` header,
///   TOC table, `Destination files` list, and an `AccurateRip summary`
///   block with per-track `[v1crc|v2crc] (c1+c2/total) Status` rows plus a
///   final `Track Peak [ CRC32 ]` table.
library;

import '../models.dart';
import '../utils.dart';
import 'eac_parser.dart';
import 'toc_parser.dart';

final _reVersion = RegExp(r'^CUERipper\s+v?([\d.]+)', caseSensitive: false);

// ---------------------------------------------------------------------------
// Native-variant header regexes
// ---------------------------------------------------------------------------

final _reDate = RegExp(
    r'Extraction logfile from\s*:\s*(\d{2})/(\d{2})/(\d{4})\s+(\d{2}):(\d{2}):(\d{2})');
final _reDrive = RegExp(r'Used drive\s*:\s*(.+)');
final _reReadOffset = RegExp(r'Read offset correction\s*:\s*(-?\d+)');
final _reSecureMode = RegExp(r'Secure mode\s*:\s*(\d+)');
final _reArHeader = RegExp(r'AccurateRip\s*:\s*(.+)');

// ---------------------------------------------------------------------------
// Native-variant body regexes
// ---------------------------------------------------------------------------

final _reDestinationFiles = RegExp(r'^Destination files\s*$');
final _reOffsetted = RegExp(r'^Offsetted by\s+-?\d+:');
// Zero-offset AR summary row: ` 01     [1c4d0bd3|46837ce2] (06+03/15) Status`
final _reArRow = RegExp(
    r'^(\d+)\s+\[([0-9A-Fa-f]{8})\|([0-9A-Fa-f]{8})\]\s+\((\d+)\+(\d+)/\d+\)\s+(.+)$');
final _reArNotPresent = RegExp(r'disk not present in database');
// Peak/CRC table row: ` 01   97.3 [F57D3663] [ED6E98C0]`
final _reCrcRow =
    RegExp(r'^(\d+)\s+([\d.]+)\s+\[([0-9A-Fa-f]{8})\]\s+\[([0-9A-Fa-f]{8})\]');

/// Parse a CUERipper log from its string [content].
RipLog parseCueRipper(String content) {
  final normalised = normaliseLineEndings(content);
  final lines = normalised.split('\n');

  String? toolVersion;
  for (final line in lines.take(5)) {
    final m = _reVersion.firstMatch(line.trim());
    if (m != null) {
      toolVersion = m.group(1);
      break;
    }
  }

  // The default CUERipper configuration emits an EAC-shaped log.
  if (normalised.contains('EAC extraction logfile')) {
    return parseEac(content,
        format: RipLogFormat.cueRipper, toolVersion: toolVersion);
  }

  return _parseNative(lines, toolVersion);
}

class _NativeArResult {
  final AccurateRipStatus status;
  final int? confidence;
  final String crcV1;
  final String crcV2;
  const _NativeArResult(this.status, this.confidence, this.crcV1, this.crcV2);
}

RipLog _parseNative(List<String> lines, String? toolVersion) {
  DateTime? extractionDate;
  String? driveName;
  int? readOffset;
  String? readMode;
  bool discNotInDatabase = false;
  final parsingErrors = <String>[];

  final filenames = <String>[];
  final arResults = <int, _NativeArResult>{};
  final peaks = <int, double>{};
  final crcs = <int, String>{};

  bool inDestinationFiles = false;
  bool inOffsetted = false;

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) {
      inDestinationFiles = false;
      continue;
    }

    if (extractionDate == null) {
      final m = _reDate.firstMatch(line);
      if (m != null) {
        // Invariant-culture MM/DD/YYYY HH:MM:SS.
        extractionDate = DateTime(
          int.parse(m.group(3)!),
          int.parse(m.group(1)!),
          int.parse(m.group(2)!),
          int.parse(m.group(4)!),
          int.parse(m.group(5)!),
          int.parse(m.group(6)!),
        );
        continue;
      }
    }
    if (driveName == null) {
      final m = _reDrive.firstMatch(line);
      if (m != null) {
        driveName = m.group(1)!.trimRight();
        continue;
      }
    }
    if (readOffset == null) {
      final m = _reReadOffset.firstMatch(line);
      if (m != null) {
        readOffset = int.tryParse(m.group(1)!);
        continue;
      }
    }
    if (readMode == null) {
      final m = _reSecureMode.firstMatch(line);
      if (m != null) {
        // Secure mode is CUERipper's CorrectionQuality: 0 = burst.
        readMode = m.group(1) == '0' ? 'Burst' : 'Secure';
        continue;
      }
    }
    {
      final m = _reArHeader.firstMatch(line);
      if (m != null && _reArNotPresent.hasMatch(m.group(1)!)) {
        discNotInDatabase = true;
        continue;
      }
    }

    if (_reDestinationFiles.hasMatch(line)) {
      inDestinationFiles = true;
      continue;
    }
    if (inDestinationFiles) {
      filenames.add(line);
      continue;
    }

    // Only the zero-offset AR rows describe this rip; rows under an
    // `Offsetted by N:` heading are alternative pressings.
    if (_reOffsetted.hasMatch(line)) {
      inOffsetted = true;
      continue;
    }
    if (!inOffsetted) {
      final m = _reArRow.firstMatch(line);
      if (m != null) {
        final track = int.parse(m.group(1)!);
        final status = m.group(6)!.trim();
        arResults[track] = _NativeArResult(
          status.startsWith('Accurately ripped')
              ? AccurateRipStatus.verified
              : status.startsWith('No match')
                  ? AccurateRipStatus.mismatch
                  : AccurateRipStatus.notChecked,
          int.tryParse(m.group(4)!),
          m.group(2)!.toUpperCase(),
          m.group(3)!.toUpperCase(),
        );
        continue;
      }
    }

    final mCrc = _reCrcRow.firstMatch(line);
    if (mCrc != null) {
      final track = int.parse(mCrc.group(1)!);
      peaks[track] = percentToFraction(mCrc.group(2)) ?? 0;
      crcs[track] = mCrc.group(3)!.toUpperCase();
      continue;
    }
  }

  final toc = parseTocTable(lines);
  final trackNumbers = toc.keys.toList()..sort();
  // A native log without a TOC (truncated) still yields tracks for any
  // destination files found.
  if (trackNumbers.isEmpty && filenames.isNotEmpty) {
    trackNumbers.addAll(List.generate(filenames.length, (i) => i + 1));
  }

  final tracks = <RipLogTrack>[];
  for (final n in trackNumbers) {
    final tocEntry = toc[n];
    final ar = arResults[n];
    tracks.add(RipLogTrack(
      trackNumber: n,
      filename: n - 1 < filenames.length ? filenames[n - 1] : null,
      peakLevel: peaks[n],
      copyCrc: crcs[n],
      accurateRipStatus: ar?.status ??
          (discNotInDatabase
              ? AccurateRipStatus.notInDatabase
              : AccurateRipStatus.notChecked),
      accurateRipCrcV1: ar?.crcV1,
      accurateRipCrcV2: ar?.crcV2,
      accurateRipConfidence:
          ar?.status == AccurateRipStatus.verified ? ar?.confidence : null,
      // The native log has no per-track status line; a listed track was
      // extracted.
      copyOk: true,
      logFormat: RipLogFormat.cueRipper,
      startSector: tocEntry?.startSector,
      lengthSectors: tocEntry?.lengthSectors,
      durationSeconds: tocEntry?.durationSeconds,
    ));
  }

  if (tracks.isEmpty && toolVersion != null) {
    parsingErrors.add('No track data found in CUERipper log');
  }

  return RipLog(
    logFormat: RipLogFormat.cueRipper,
    toolVersion: toolVersion,
    extractionDate: extractionDate,
    drive: driveName != null
        ? DriveInfo(name: driveName, readOffset: readOffset)
        : null,
    readMode: readMode,
    readOffset: readOffset,
    tracks: tracks,
    errors: parsingErrors,
    testAndCopy: tracks.isEmpty ? null : tracks.any((t) => t.testCrc != null),
  );
}
