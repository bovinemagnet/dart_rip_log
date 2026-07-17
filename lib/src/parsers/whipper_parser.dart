/// Parser for whipper logs (github.com/whipper-team/whipper).
///
/// whipper 0.8+ writes its log as a YAML document: two header lines, then
/// top-level sections (`Ripping phase information:`, `CD metadata:`,
/// `TOC:`, `Tracks:`, `Conclusive status report:`) with two-space
/// indentation per level, ending with a `SHA-256 hash:` trailer. whipper
/// ≤0.7 wrote the same layout as hand-built plain text with `Yes`/`No`
/// booleans and a `%+d` read offset — both variants are handled here.
library;

import '../models.dart';
import '../utils.dart';

final _reVersion = RegExp(r'^Log created by:\s*whipper\s+(\S+)');
final _reDate = RegExp(r'^Log creation date:\s*(.+)$');
final _reSha256 = RegExp(r'^SHA-256 hash:\s*([0-9A-Fa-f]{64})');

// Section-relative fields (matched against trimmed lines).
final _reDrive = RegExp(r'^Drive:\s*(.+)$');
final _reReadOffset = RegExp(r'^Read offset correction:\s*([+-]?\d+)');
final _reOverread = RegExp(r'^Overread into lead-out:\s*(\S+)');
final _reGapDetection = RegExp(r'^Gap detection:\s*(.+)$');

// Numbered block header inside `TOC:` / `Tracks:` (e.g. `  1:`).
final _reNumberedBlock = RegExp(r'^(\d+):$');

// TOC block fields.
final _reStartSector = RegExp(r'^Start sector:\s*(\d+)');
final _reEndSector = RegExp(r'^End sector:\s*(\d+)');

// Track block fields.
final _reFilename = RegExp(r'^Filename:\s*(.+)$');
final _rePeakLevel = RegExp(r'^Peak level:\s*([\d.]+)\s*$');
final _reQuality = RegExp(r'^Extraction quality:\s*([\d.]+)\s*%');
final _reTestCrc = RegExp(r'^Test CRC:\s*([0-9A-Fa-f]{8})');
final _reCopyCrc = RegExp(r'^Copy CRC:\s*([0-9A-Fa-f]{8})');
final _reStatus = RegExp(r'^Status:\s*(.+)$');

// AccurateRip sub-blocks.
final _reArBlock = RegExp(r'^AccurateRip v([12]):');
final _reArResult = RegExp(r'^Result:\s*(.+)$');
final _reArConfidence = RegExp(r'^Confidence:\s*(\d+)');
final _reArLocalCrc = RegExp(r'^Local CRC:\s*([0-9A-Fa-f]+)');

// Conclusive status report fields.
final _reArSummary = RegExp(r'^AccurateRip summary:\s*(.+)$');

/// Strip the optional YAML single-quoting ruamel adds to values that
/// contain `: `.
String _unquote(String value) {
  if (value.length >= 2 && value.startsWith("'") && value.endsWith("'")) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

bool? _parseBool(String value) {
  switch (value.toLowerCase()) {
    case 'true':
    case 'yes':
      return true;
    case 'false':
    case 'no':
      return false;
  }
  return null;
}

/// One AccurateRip result block (`AccurateRip v1:` / `AccurateRip v2:`).
class _ArResult {
  String? result;
  int? confidence;
  String? localCrc;

  bool get exactMatch =>
      result?.contains('exact match') == true &&
      result?.contains('NO exact match') != true;
  bool get foundNoMatch => result?.contains('NO exact match') == true;
  bool get notInDatabase =>
      result?.contains('not present in AccurateRip database') == true;
}

class _TrackBlock {
  final int number;
  String? filename;
  double? peakLevel;
  double? quality;
  String? testCrc;
  String? copyCrc;
  String? status;
  final ar = <int, _ArResult>{};

  _TrackBlock(this.number);
}

/// Parse a whipper log from its string [content].
RipLog parseWhipper(String content) {
  final lines = normaliseLineEndings(content).split('\n');

  String? toolVersion;
  DateTime? extractionDate;
  String? driveName;
  int? readOffset;
  bool? overread;
  String? gapHandling;
  String? arSummary;
  String? integrityHash;
  final parsingErrors = <String>[];

  // Top-level section tracking: a non-indented `Something:` line starts a
  // new section; numbered blocks live two spaces deep inside TOC/Tracks.
  String section = '';
  final tocSectors = <int, (int, int)>{}; // number -> (start, end)
  final trackBlocks = <_TrackBlock>[];
  int? currentToc;
  _TrackBlock? currentTrack;
  int? currentArVersion;

  for (final raw in lines) {
    if (raw.trim().isEmpty) continue;
    final indent = raw.length - raw.trimLeft().length;
    final line = raw.trim();

    if (indent == 0) {
      currentToc = null;
      currentTrack = null;
      currentArVersion = null;

      var m = _reVersion.firstMatch(line);
      if (m != null) {
        toolVersion = m.group(1);
        continue;
      }
      m = _reDate.firstMatch(line);
      if (m != null) {
        extractionDate = DateTime.tryParse(_unquote(m.group(1)!.trim()));
        continue;
      }
      m = _reSha256.firstMatch(line);
      if (m != null) {
        integrityHash = m.group(1)!.toUpperCase();
        continue;
      }
      if (line.endsWith(':')) section = line;
      continue;
    }

    // Numbered block headers inside TOC / Tracks.
    final mBlock = _reNumberedBlock.firstMatch(line);
    if (mBlock != null && indent == 2) {
      final number = int.parse(mBlock.group(1)!);
      currentArVersion = null;
      if (section == 'TOC:') {
        currentToc = number;
        currentTrack = null;
      } else if (section == 'Tracks:') {
        currentTrack = _TrackBlock(number);
        trackBlocks.add(currentTrack);
        currentToc = null;
      }
      continue;
    }

    if (currentToc != null) {
      final mStart = _reStartSector.firstMatch(line);
      if (mStart != null) {
        final prev = tocSectors[currentToc];
        tocSectors[currentToc] = (int.parse(mStart.group(1)!), prev?.$2 ?? -1);
        continue;
      }
      final mEnd = _reEndSector.firstMatch(line);
      if (mEnd != null) {
        final prev = tocSectors[currentToc];
        tocSectors[currentToc] = (prev?.$1 ?? 0, int.parse(mEnd.group(1)!));
        continue;
      }
      continue;
    }

    if (currentTrack != null) {
      final mAr = _reArBlock.firstMatch(line);
      if (mAr != null) {
        currentArVersion = int.parse(mAr.group(1)!);
        currentTrack.ar[currentArVersion] = _ArResult();
        continue;
      }
      // Fields inside an AccurateRip sub-block are one level deeper (6
      // spaces) than track fields (4 spaces).
      if (currentArVersion != null && indent >= 6) {
        final ar = currentTrack.ar[currentArVersion]!;
        var m = _reArResult.firstMatch(line);
        if (m != null) {
          ar.result = _unquote(m.group(1)!.trim());
          continue;
        }
        m = _reArConfidence.firstMatch(line);
        if (m != null) {
          ar.confidence = int.tryParse(m.group(1)!);
          continue;
        }
        m = _reArLocalCrc.firstMatch(line);
        if (m != null) {
          ar.localCrc = m.group(1)!.toUpperCase();
          continue;
        }
        continue;
      }
      currentArVersion = null;

      var m = _reFilename.firstMatch(line);
      if (m != null) {
        currentTrack.filename = _unquote(m.group(1)!.trim());
        continue;
      }
      m = _rePeakLevel.firstMatch(line);
      if (m != null) {
        // whipper peak levels are already fractions in [0, 1].
        currentTrack.peakLevel = double.tryParse(m.group(1)!);
        continue;
      }
      m = _reQuality.firstMatch(line);
      if (m != null) {
        currentTrack.quality = percentToFraction(m.group(1));
        continue;
      }
      m = _reTestCrc.firstMatch(line);
      if (m != null) {
        currentTrack.testCrc = m.group(1)!.toUpperCase();
        continue;
      }
      m = _reCopyCrc.firstMatch(line);
      if (m != null) {
        currentTrack.copyCrc = m.group(1)!.toUpperCase();
        continue;
      }
      m = _reStatus.firstMatch(line);
      if (m != null) {
        currentTrack.status = _unquote(m.group(1)!.trim());
        continue;
      }
      continue;
    }

    // Section-level fields (Ripping phase information, Conclusive status
    // report, ...).
    var m = _reDrive.firstMatch(line);
    if (m != null && driveName == null) {
      driveName = m.group(1)!.trim();
      continue;
    }
    m = _reReadOffset.firstMatch(line);
    if (m != null && readOffset == null) {
      readOffset = int.tryParse(m.group(1)!);
      continue;
    }
    m = _reOverread.firstMatch(line);
    if (m != null && overread == null) {
      overread = _parseBool(m.group(1)!);
      continue;
    }
    m = _reGapDetection.firstMatch(line);
    if (m != null && gapHandling == null) {
      gapHandling = m.group(1)!.trim();
      continue;
    }
    m = _reArSummary.firstMatch(line);
    if (m != null && arSummary == null) {
      arSummary = _unquote(m.group(1)!.trim());
      continue;
    }
  }

  final tracks = <RipLogTrack>[];
  for (final block in trackBlocks) {
    tracks.add(_toTrack(block, tocSectors[block.number]));
  }
  if (trackBlocks.isEmpty && toolVersion != null) {
    parsingErrors.add('No track sections found in whipper log');
  }

  final drive = driveName != null
      ? DriveInfo(name: driveName, readOffset: readOffset)
      : null;

  return RipLog(
    logFormat: RipLogFormat.whipper,
    toolVersion: toolVersion,
    extractionDate: extractionDate,
    drive: drive,
    readOffset: readOffset,
    overread: overread,
    gapHandling: gapHandling,
    tracks: tracks,
    accurateRipSummary: arSummary,
    integrityHash: integrityHash,
    testAndCopy: tracks.isEmpty ? null : tracks.any((t) => t.testCrc != null),
    errors: parsingErrors,
  );
}

RipLogTrack _toTrack(_TrackBlock block, (int, int)? toc) {
  final v1 = block.ar[1];
  final v2 = block.ar[2];

  // A v1 OR v2 exact match verifies the track (they are independent
  // checksum algorithms); prefer the v2 confidence when both match.
  AccurateRipStatus arStatus;
  int? arConfidence;
  if (v2?.exactMatch == true) {
    arStatus = AccurateRipStatus.verified;
    arConfidence = v2!.confidence;
  } else if (v1?.exactMatch == true) {
    arStatus = AccurateRipStatus.verified;
    arConfidence = v1!.confidence;
  } else if (v1?.foundNoMatch == true || v2?.foundNoMatch == true) {
    // whipper's Confidence on a no-match block is the database submission
    // count, not a match confidence — leave it out.
    arStatus = AccurateRipStatus.mismatch;
  } else if (v1?.notInDatabase == true || v2?.notInDatabase == true) {
    arStatus = AccurateRipStatus.notInDatabase;
  } else {
    arStatus = AccurateRipStatus.notChecked;
  }

  int? startSector;
  int? lengthSectors;
  double? durationSeconds;
  if (toc != null && toc.$2 >= toc.$1) {
    startSector = toc.$1;
    lengthSectors = toc.$2 - toc.$1 + 1;
    durationSeconds = lengthSectors / 75.0;
  }

  return RipLogTrack(
    trackNumber: block.number,
    filename: block.filename,
    peakLevel: block.peakLevel,
    trackQuality: block.quality,
    testCrc: block.testCrc,
    copyCrc: block.copyCrc,
    accurateRipStatus: arStatus,
    accurateRipCrcV1: v1?.localCrc,
    accurateRipCrcV2: v2?.localCrc,
    accurateRipConfidence: arConfidence,
    copyOk: block.status == null || block.status == 'Copy OK',
    logFormat: RipLogFormat.whipper,
    startSector: startSector,
    lengthSectors: lengthSectors,
    durationSeconds: durationSeconds,
  );
}
