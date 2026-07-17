import '../models.dart';
import '../utils.dart';
import 'toc_parser.dart';

// ---------------------------------------------------------------------------
// Header regexes
// ---------------------------------------------------------------------------

final _reVersion =
    RegExp(r'Exact Audio Copy\s+(V[\d.]+)', caseSensitive: false);
final _reDate = RegExp(r'EAC extraction logfile from\s+(\d+\.\s+\w+\s+\d{4})',
    caseSensitive: false);
final _reDrive = RegExp(r'Used drive\s*:\s*(.+)', caseSensitive: false);
final _reDriveAdapter = RegExp(r'Adapter\s*:', caseSensitive: false);
final _reReadMode = RegExp(r'Read mode\s*:\s*(.+)', caseSensitive: false);
final _reReadOffset =
    RegExp(r'Read offset correction\s*:\s*(-?\d+)', caseSensitive: false);
final _reOverread = RegExp(r'Overread into Lead-In and Lead-Out\s*:\s*(\w+)',
    caseSensitive: false);
final _reGapHandling = RegExp(r'Gap handling\s*:\s*(.+)', caseSensitive: false);
final _reMediaType = RegExp(r'Used media\s*:\s*(.+)', caseSensitive: false);

// ---------------------------------------------------------------------------
// Footer regexes
// ---------------------------------------------------------------------------

// EAC footer AccurateRip summary phrasings. Mixed results emit one line
// per outcome (e.g. "3 track(s) accurately ripped" followed by
// "2 track(s) could not be verified as accurate") — all matching lines
// are collected and joined with '\n'.
final _reArSummary = RegExp(
    r'^((?:All tracks accurately ripped'
    r'|No tracks could be verified as accurate'
    r'|Some tracks could not be verified as accurate'
    r'|\d+\s+track\(s\)\s+accurately ripped'
    r'|\d+\s+track\(s\)\s+could not be verified as accurate).*)',
    caseSensitive: false);
final _reIntegrityHash =
    RegExp(r'==== Log checksum\s+([0-9A-Fa-f]+)', caseSensitive: false);

// EAC 0.95–0.99 put per-track AccurateRip results in a footer block:
//   Track  1  accurately ripped (confidence 2)  [1A2B3C4D]
//   Track  2  cannot be verified as accurate  [5E6F7A8B]
final _reFooterArVerified = RegExp(
    r'^Track\s+(\d+)\s+accurately ripped\s*'
    r'\(confidence\s+(\d+)\)\s+\[([0-9A-Fa-f]+)\]',
    caseSensitive: false);
final _reFooterArCannot = RegExp(
    r'^Track\s+(\d+)\s+cannot be verified as accurate\s+\[([0-9A-Fa-f]+)\]',
    caseSensitive: false);

/// Per-track AccurateRip result parsed from an EAC 0.95–0.99 footer block.
class _FooterArResult {
  final AccurateRipStatus status;
  final int? confidence;
  final String crcV1;
  const _FooterArResult(this.status, this.confidence, this.crcV1);
}

// ---------------------------------------------------------------------------
// Track-section regexes
// ---------------------------------------------------------------------------

final _reTrackHeader = RegExp(r'^Track\s+(\d+)\s*$', caseSensitive: false);
final _reRangeHeader =
    RegExp(r'^Range status and errors\s*$', caseSensitive: false);
final _reFilename = RegExp(r'Filename\s+(.+)', caseSensitive: false);
final _rePeakLevel = RegExp(r'Peak level\s+([\d.]+)\s*%', caseSensitive: false);
final _reTrackQuality =
    RegExp(r'(?:Track|Range) quality\s+([\d.]+)\s*%', caseSensitive: false);
final _reTestCrc = RegExp(r'Test CRC\s+([0-9A-Fa-f]+)', caseSensitive: false);
final _reCopyCrc = RegExp(r'Copy CRC\s+([0-9A-Fa-f]+)', caseSensitive: false);
final _reCopyOk = RegExp(r'Copy OK', caseSensitive: false);

// AccurateRip status lines
final _reArVerified = RegExp(
    r'Accurately ripped \(confidence\s+(\d+)\)\s+\[([0-9A-Fa-f]+)\]'
    r'(?:.*?\(AR v2 signature:\s*([0-9A-Fa-f]+)\))?',
    caseSensitive: false);
final _reArCannot = RegExp(
    r'Cannot be verified as accurate\s+\[([0-9A-Fa-f]+)\]',
    caseSensitive: false);
final _reArNotPresent =
    RegExp(r'Track not present in AccurateRip database', caseSensitive: false);

// Error statistics (EAC uses individual lines per error type)
final _reReadError = RegExp(r'Read error\s*:\s*(\d+)', caseSensitive: false);
final _reSkipError = RegExp(r'Skip error\s*:\s*(\d+)', caseSensitive: false);
final _reEdgeJitter =
    RegExp(r'Edge jitter error.*?:\s*(\d+)', caseSensitive: false);
final _reAtomJitter =
    RegExp(r'Atom jitter error.*?:\s*(\d+)', caseSensitive: false);
final _reDrift = RegExp(r'Drift error.*?:\s*(\d+)', caseSensitive: false);
final _reDropped =
    RegExp(r'Dropped bytes error.*?:\s*(\d+)', caseSensitive: false);
final _reDuplicated =
    RegExp(r'Duplicated bytes error.*?:\s*(\d+)', caseSensitive: false);
final _reInconsistent =
    RegExp(r'Inconsistency in error sectors.*?:\s*(\d+)', caseSensitive: false);

/// Parse an EAC log from its string [content] and return a [RipLog].
RipLog parseEac(String content) {
  final normalised = normaliseLineEndings(content);
  final lines = normalised.split('\n');

  String? toolVersion;
  DateTime? extractionDate;
  String? driveName;
  String? driveAdapter;
  String? readMode;
  int? readOffset;
  bool? overread;
  String? gapHandling;
  String? mediaType;
  final arSummaryLines = <String>[];
  String? integrityHash;
  final parsingErrors = <String>[];

  // Split into sections: header (before first "Track N") and track sections.
  // We do a single pass: collect header lines until first track header.
  final trackSections = <List<String>>[];
  List<String>? currentTrack;
  final headerLines = <String>[];
  bool inTrackArea = false;
  bool isRangeRip = false;

  // Footer AR block results (EAC 0.95–0.99 style), keyed by track number.
  // These lines are excluded from the track sections so they cannot
  // overwrite the last track's own AR fields.
  final footerAr = <int, _FooterArResult>{};

  for (final line in lines) {
    final trimmed = line.trim();
    final mFooterVerified = _reFooterArVerified.firstMatch(trimmed);
    if (mFooterVerified != null) {
      final n = int.tryParse(mFooterVerified.group(1)!);
      if (n != null) {
        footerAr[n] = _FooterArResult(
          AccurateRipStatus.verified,
          int.tryParse(mFooterVerified.group(2)!),
          mFooterVerified.group(3)!.toUpperCase(),
        );
      }
      continue;
    }
    final mFooterCannot = _reFooterArCannot.firstMatch(trimmed);
    if (mFooterCannot != null) {
      final n = int.tryParse(mFooterCannot.group(1)!);
      if (n != null) {
        footerAr[n] = _FooterArResult(
          AccurateRipStatus.mismatch,
          null,
          mFooterCannot.group(2)!.toUpperCase(),
        );
      }
      continue;
    }
    if (_reTrackHeader.hasMatch(trimmed)) {
      inTrackArea = true;
      if (currentTrack != null) trackSections.add(currentTrack);
      currentTrack = [line];
    } else if (_reRangeHeader.hasMatch(trimmed)) {
      inTrackArea = true;
      isRangeRip = true;
      if (currentTrack != null) trackSections.add(currentTrack);
      currentTrack = [line];
    } else if (inTrackArea) {
      currentTrack!.add(line);
    } else {
      headerLines.add(line);
    }
  }
  if (currentTrack != null) trackSections.add(currentTrack);

  // ---- Parse header ----
  for (final line in headerLines) {
    final trimmed = line.trim();
    if (toolVersion == null) {
      final m = _reVersion.firstMatch(trimmed);
      if (m != null) {
        toolVersion = m.group(1);
        continue;
      }
    }
    if (extractionDate == null) {
      final m = _reDate.firstMatch(trimmed);
      if (m != null) {
        extractionDate = _parseEacDate(m.group(1));
        continue;
      }
    }
    if (driveName == null) {
      final m = _reDrive.firstMatch(trimmed);
      if (m != null) {
        // EAC appends adapter/ID text to the drive line, e.g.
        // "ASUS BW-16D1HT   Adapter: 1   ID: 0" — split it off so the
        // name holds only the model and the adapter text goes to
        // DriveInfo.adapter.
        final raw = m.group(1)!.trim();
        final adapterStart = raw.indexOf(_reDriveAdapter);
        if (adapterStart > 0) {
          driveName = raw.substring(0, adapterStart).trim();
          driveAdapter = raw.substring(adapterStart).trim();
        } else {
          driveName = raw;
        }
        continue;
      }
    }
    if (readMode == null) {
      final m = _reReadMode.firstMatch(trimmed);
      if (m != null) {
        readMode = m.group(1)?.trim();
        continue;
      }
    }
    if (readOffset == null) {
      final m = _reReadOffset.firstMatch(trimmed);
      if (m != null) {
        readOffset = int.tryParse(m.group(1)!);
        continue;
      }
    }
    if (overread == null) {
      final m = _reOverread.firstMatch(trimmed);
      if (m != null) {
        overread = m.group(1)?.toLowerCase() == 'yes';
        continue;
      }
    }
    if (gapHandling == null) {
      final m = _reGapHandling.firstMatch(trimmed);
      if (m != null) {
        gapHandling = m.group(1)?.trim();
        continue;
      }
    }
    if (mediaType == null) {
      final m = _reMediaType.firstMatch(trimmed);
      if (m != null) {
        mediaType = m.group(1)?.trim();
        continue;
      }
    }
    // Footer fields can also appear in the "header" area (after all tracks)
    final mArSummary = _reArSummary.firstMatch(trimmed);
    if (mArSummary != null) {
      arSummaryLines.add(mArSummary.group(1)!.trim());
      continue;
    }
    if (integrityHash == null) {
      final m = _reIntegrityHash.firstMatch(trimmed);
      if (m != null) {
        integrityHash = m.group(1)?.trim();
        continue;
      }
    }
  }

  // ---- Parse tracks ----
  // TOC data is merged by track number. A range rip's single synthetic
  // track spans the whole disc, so per-track TOC rows do not apply.
  final toc = isRangeRip ? const <int, TocEntry>{} : parseTocTable(lines);
  final tracks = <RipLogTrack>[];
  for (final section in trackSections) {
    final track = _parseTrackSection(section, parsingErrors,
        isRange: isRangeRip, footerAr: footerAr, toc: toc);
    if (track != null) tracks.add(track);
  }

  // Footer may be in the last part of the file (after last track section).
  // The lines after last track are already captured inside the last track
  // section, but we also need to scan them for the summary/hash.
  if (trackSections.isNotEmpty) {
    for (final line in trackSections.last) {
      final trimmed = line.trim();
      final m = _reArSummary.firstMatch(trimmed);
      if (m != null) arSummaryLines.add(m.group(1)!.trim());
      if (integrityHash == null) {
        final mHash = _reIntegrityHash.firstMatch(trimmed);
        if (mHash != null) integrityHash = mHash.group(1)?.trim();
      }
    }
  }
  final arSummary = arSummaryLines.isEmpty ? null : arSummaryLines.join('\n');

  final drive = driveName != null
      ? DriveInfo(
          name: driveName, readOffset: readOffset, adapter: driveAdapter)
      : null;

  // Test-and-copy is derived: true if any track reported a test CRC,
  // false if there are tracks but none did. Null when there are no tracks.
  bool? testAndCopy;
  if (tracks.isNotEmpty) {
    testAndCopy = tracks.any((t) => t.testCrc != null);
  }

  return RipLog(
    logFormat: RipLogFormat.eac,
    toolVersion: toolVersion,
    extractionDate: extractionDate,
    drive: drive,
    readMode: readMode,
    readOffset: readOffset,
    overread: overread,
    gapHandling: gapHandling,
    mediaType: mediaType,
    tracks: tracks,
    accurateRipSummary: arSummary,
    integrityHash: integrityHash,
    errors: parsingErrors,
    testAndCopy: testAndCopy,
  );
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

RipLogTrack? _parseTrackSection(List<String> lines, List<String> parsingErrors,
    {bool isRange = false,
    Map<int, _FooterArResult> footerAr = const {},
    Map<int, TocEntry> toc = const {}}) {
  int? trackNumber = isRange ? 1 : null;
  String? filename;
  double? peakLevel;
  double? trackQuality;
  String? testCrc;
  String? copyCrc;
  AccurateRipStatus arStatus = AccurateRipStatus.notChecked;
  String? arCrcV1;
  String? arCrcV2;
  int? arConfidence;
  bool copyOk = false;

  int readErrors = 0;
  int skipErrors = 0;
  int edgeJitterErrors = 0;
  int atomJitterErrors = 0;
  int driftErrors = 0;
  int droppedBytes = 0;
  int duplicatedBytes = 0;
  int inconsistentErrorSectors = 0;

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    if (trackNumber == null) {
      final m = _reTrackHeader.firstMatch(trimmed);
      if (m != null) {
        trackNumber = int.tryParse(m.group(1)!);
        continue;
      }
    }

    if (filename == null) {
      final m = _reFilename.firstMatch(trimmed);
      if (m != null) {
        filename = m.group(1)?.trim();
        continue;
      }
    }

    if (peakLevel == null) {
      final m = _rePeakLevel.firstMatch(trimmed);
      if (m != null) {
        peakLevel = percentToFraction(m.group(1));
        continue;
      }
    }

    if (trackQuality == null) {
      final m = _reTrackQuality.firstMatch(trimmed);
      if (m != null) {
        trackQuality = percentToFraction(m.group(1));
        continue;
      }
    }

    if (testCrc == null) {
      final m = _reTestCrc.firstMatch(trimmed);
      if (m != null) {
        testCrc = m.group(1)?.toUpperCase();
        continue;
      }
    }

    if (copyCrc == null) {
      final m = _reCopyCrc.firstMatch(trimmed);
      if (m != null) {
        copyCrc = m.group(1)?.toUpperCase();
        continue;
      }
    }

    if (!copyOk && _reCopyOk.hasMatch(trimmed)) {
      copyOk = true;
      continue;
    }

    // AccurateRip — verified
    final mArVerified = _reArVerified.firstMatch(trimmed);
    if (mArVerified != null) {
      arStatus = AccurateRipStatus.verified;
      arConfidence = int.tryParse(mArVerified.group(1)!);
      arCrcV1 = mArVerified.group(2)?.toUpperCase();
      arCrcV2 = mArVerified.group(3)?.toUpperCase();
      continue;
    }

    // AccurateRip — cannot be verified (mismatch)
    final mArCannot = _reArCannot.firstMatch(trimmed);
    if (mArCannot != null) {
      arStatus = AccurateRipStatus.mismatch;
      arCrcV1 = mArCannot.group(1)?.toUpperCase();
      continue;
    }

    // AccurateRip — not present in database
    if (_reArNotPresent.hasMatch(trimmed)) {
      arStatus = AccurateRipStatus.notInDatabase;
      continue;
    }

    // Error statistics
    final mRead = _reReadError.firstMatch(trimmed);
    if (mRead != null) {
      readErrors = int.tryParse(mRead.group(1)!) ?? 0;
      continue;
    }
    final mSkip = _reSkipError.firstMatch(trimmed);
    if (mSkip != null) {
      skipErrors = int.tryParse(mSkip.group(1)!) ?? 0;
      continue;
    }
    final mEdge = _reEdgeJitter.firstMatch(trimmed);
    if (mEdge != null) {
      edgeJitterErrors = int.tryParse(mEdge.group(1)!) ?? 0;
      continue;
    }
    final mAtom = _reAtomJitter.firstMatch(trimmed);
    if (mAtom != null) {
      atomJitterErrors = int.tryParse(mAtom.group(1)!) ?? 0;
      continue;
    }
    final mDrift = _reDrift.firstMatch(trimmed);
    if (mDrift != null) {
      driftErrors = int.tryParse(mDrift.group(1)!) ?? 0;
      continue;
    }
    final mDropped = _reDropped.firstMatch(trimmed);
    if (mDropped != null) {
      droppedBytes = int.tryParse(mDropped.group(1)!) ?? 0;
      continue;
    }
    final mDuplicated = _reDuplicated.firstMatch(trimmed);
    if (mDuplicated != null) {
      duplicatedBytes = int.tryParse(mDuplicated.group(1)!) ?? 0;
      continue;
    }
    final mInconsistent = _reInconsistent.firstMatch(trimmed);
    if (mInconsistent != null) {
      inconsistentErrorSectors = int.tryParse(mInconsistent.group(1)!) ?? 0;
      continue;
    }
  }

  if (trackNumber == null) {
    parsingErrors.add('Could not extract track number from section');
    return null;
  }

  // Apply a footer-block AR result (EAC 0.95–0.99 style) when the track's
  // own section carried no inline AR line.
  final footerResult = footerAr[trackNumber];
  if (footerResult != null && arStatus == AccurateRipStatus.notChecked) {
    arStatus = footerResult.status;
    arConfidence = footerResult.confidence;
    arCrcV1 = footerResult.crcV1;
  }

  final tocEntry = toc[trackNumber];

  return RipLogTrack(
    trackNumber: trackNumber,
    filename: filename,
    peakLevel: peakLevel,
    trackQuality: trackQuality,
    copyCrc: copyCrc,
    testCrc: testCrc,
    accurateRipStatus: arStatus,
    accurateRipCrcV1: arCrcV1,
    accurateRipCrcV2: arCrcV2,
    accurateRipConfidence: arConfidence,
    copyOk: copyOk,
    errors: TrackErrors(
      readErrors: readErrors,
      skipErrors: skipErrors,
      edgeJitterErrors: edgeJitterErrors,
      atomJitterErrors: atomJitterErrors,
      driftErrors: driftErrors,
      droppedBytes: droppedBytes,
      duplicatedBytes: duplicatedBytes,
      inconsistentErrorSectors: inconsistentErrorSectors,
    ),
    logFormat: RipLogFormat.eac,
    startSector: tocEntry?.startSector,
    lengthSectors: tocEntry?.lengthSectors,
    durationSeconds: tocEntry?.durationSeconds,
  );
}

// EAC date format: "15. March 2026". Non-English EAC builds emit the same
// shape with localised month names — we accept each language's full name.
final _monthNames = <String, int>{
  // English
  'january': 1, 'february': 2, 'march': 3, 'april': 4, 'may': 5,
  'june': 6, 'july': 7, 'august': 8, 'september': 9, 'october': 10,
  'november': 11, 'december': 12,
  // German
  'januar': 1, 'februar': 2, 'märz': 3, 'maerz': 3, 'mai': 5,
  'juni': 6, 'juli': 7, 'oktober': 10, 'dezember': 12,
  // French
  'janvier': 1, 'février': 2, 'fevrier': 2, 'mars': 3, 'avril': 4,
  'juin': 6, 'juillet': 7, 'août': 8, 'aout': 8, 'septembre': 9,
  'octobre': 10, 'novembre': 11, 'décembre': 12, 'decembre': 12,
  // Spanish
  'enero': 1, 'febrero': 2, 'marzo': 3, 'abril': 4, 'mayo': 5,
  'junio': 6, 'julio': 7, 'agosto': 8, 'septiembre': 9, 'setiembre': 9,
  'octubre': 10, 'noviembre': 11, 'diciembre': 12,
  // Italian
  'gennaio': 1, 'febbraio': 2, 'aprile': 4, 'maggio': 5, 'giugno': 6,
  'luglio': 7, 'settembre': 9, 'ottobre': 10, 'dicembre': 12,
  // Dutch
  'januari': 1, 'februari': 2, 'maart': 3, 'augustus': 8,
  // Portuguese
  'janeiro': 1, 'fevereiro': 2, 'março': 3, 'marco': 3, 'maio': 5,
  'junho': 6, 'julho': 7, 'setembro': 9, 'outubro': 10, 'novembro': 11,
  'dezembro': 12,
};

DateTime? _parseEacDate(String? raw) {
  if (raw == null) return null;
  // e.g. "15. March 2026"
  final parts = raw.split(RegExp(r'[\s.]+'));
  if (parts.length < 3) return null;
  final day = int.tryParse(parts[0]);
  final month = _monthNames[parts[1].toLowerCase()];
  final year = int.tryParse(parts[2]);
  if (day == null || month == null || year == null) return null;
  return DateTime(year, month, day);
}
