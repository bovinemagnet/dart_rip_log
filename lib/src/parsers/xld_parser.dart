import '../models.dart';
import '../utils.dart';

// ---------------------------------------------------------------------------
// Header regexes
// ---------------------------------------------------------------------------

final _reVersion =
    RegExp(r'X Lossless Decoder version\s+(\S+(?:\s+\([^)]+\))?)',
        caseSensitive: false);
final _reDate = RegExp(
    r'XLD extraction logfile from\s+(\d{4}-\d{2}-\d{2})',
    caseSensitive: false);
final _reDrive = RegExp(r'Used drive\s*:\s*(.+)', caseSensitive: false);
final _reReadOffset =
    RegExp(r'Read offset correction\s*:\s*(-?\d+)', caseSensitive: false);
final _reGapStatus = RegExp(r'Gap status\s*:\s*(.+)', caseSensitive: false);
final _reMediaType =
    RegExp(r'Media type\s*:\s*(.+)', caseSensitive: false);

// ---------------------------------------------------------------------------
// Track-section regex
// ---------------------------------------------------------------------------

final _reTrackHeader = RegExp(r'^Track\s+(\d+)\s*$', caseSensitive: false);

// ---------------------------------------------------------------------------
// Per-track field regexes
// ---------------------------------------------------------------------------

final _reFilename =
    RegExp(r'Filename\s*:\s*(.+)', caseSensitive: false);
final _reCrc32 =
    RegExp(r'CRC32 hash\s*:\s*([0-9A-Fa-f]+)', caseSensitive: false);
final _reArV1 = RegExp(
    r'AccurateRip v1 signature\s*:\s*([0-9A-Fa-f]+)',
    caseSensitive: false);
final _reArV2 = RegExp(
    r'AccurateRip v2 signature\s*:\s*([0-9A-Fa-f]+)',
    caseSensitive: false);

// AccurateRip result lines (start with "->")
// e.g. "->Accurately ripped (v1+v2, confidence 3/3)"
final _reArVerified = RegExp(
    r'->\s*Accurately ripped\s*\(.*?confidence\s+(\d+)',
    caseSensitive: false);
final _reArNotVerified =
    RegExp(r'->\s*NOT verified as accurate', caseSensitive: false);
final _reArNotInDb =
    RegExp(r'->\s*Track not present in AccurateRip database', caseSensitive: false);

// XLD statistics block
final _reStatReadError =
    RegExp(r'Read error\s*:\s*(\d+)', caseSensitive: false);
final _reStatJitterError =
    RegExp(r'Jitter error.*?:\s*(\d+)', caseSensitive: false);
final _reStatDamagedSector =
    RegExp(r'Damaged sector count\s*:\s*(\d+)', caseSensitive: false);
final _reStatPeakLevel =
    RegExp(r'Peak level\s*:\s*([\d.]+)\s*%', caseSensitive: false);
final _reStatTrackQuality =
    RegExp(r'Track quality\s*:\s*([\d.]+)\s*%', caseSensitive: false);

/// Parse an XLD log from its string [content] and return a [RipLog].
RipLog parseXld(String content) {
  final normalised = normaliseLineEndings(content);
  final lines = normalised.split('\n');

  String? toolVersion;
  DateTime? extractionDate;
  String? driveName;
  int? readOffset;
  String? gapHandling;
  String? mediaType;
  final parsingErrors = <String>[];

  // Split into header + track sections.
  final trackSections = <List<String>>[];
  List<String>? currentTrack;
  final headerLines = <String>[];
  bool inTrackArea = false;

  for (final line in lines) {
    if (_reTrackHeader.hasMatch(line.trim())) {
      inTrackArea = true;
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
        toolVersion = m.group(1)?.trim();
        continue;
      }
    }
    if (extractionDate == null) {
      final m = _reDate.firstMatch(trimmed);
      if (m != null) {
        extractionDate = DateTime.tryParse(m.group(1)!);
        continue;
      }
    }
    if (driveName == null) {
      final m = _reDrive.firstMatch(trimmed);
      if (m != null) {
        driveName = m.group(1)?.trim();
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
    if (gapHandling == null) {
      final m = _reGapStatus.firstMatch(trimmed);
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
  }

  // ---- Parse tracks ----
  final tracks = <RipLogTrack>[];
  for (final section in trackSections) {
    final track = _parseTrackSection(section, parsingErrors);
    if (track != null) tracks.add(track);
  }

  final drive = driveName != null
      ? DriveInfo(name: driveName, readOffset: readOffset)
      : null;

  return RipLog(
    logFormat: RipLogFormat.xld,
    toolVersion: toolVersion,
    extractionDate: extractionDate,
    drive: drive,
    readOffset: readOffset,
    gapHandling: gapHandling,
    mediaType: mediaType,
    tracks: tracks,
    errors: parsingErrors,
  );
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

RipLogTrack? _parseTrackSection(
    List<String> lines, List<String> parsingErrors) {
  int? trackNumber;
  String? filename;
  double? peakLevel;
  double? trackQuality;
  String? copyCrc;
  String? arCrcV1;
  String? arCrcV2;
  AccurateRipStatus arStatus = AccurateRipStatus.notChecked;
  int? arConfidence;

  int readErrors = 0;
  int jitterErrors = 0;
  int damagedSectors = 0;

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

    if (copyCrc == null) {
      final m = _reCrc32.firstMatch(trimmed);
      if (m != null) {
        copyCrc = m.group(1)?.toUpperCase();
        continue;
      }
    }

    if (arCrcV1 == null) {
      final m = _reArV1.firstMatch(trimmed);
      if (m != null) {
        arCrcV1 = m.group(1)?.toUpperCase();
        continue;
      }
    }

    if (arCrcV2 == null) {
      final m = _reArV2.firstMatch(trimmed);
      if (m != null) {
        arCrcV2 = m.group(1)?.toUpperCase();
        continue;
      }
    }

    // AccurateRip — verified
    final mArVerified = _reArVerified.firstMatch(trimmed);
    if (mArVerified != null) {
      arStatus = AccurateRipStatus.verified;
      arConfidence = int.tryParse(mArVerified.group(1)!);
      continue;
    }

    // AccurateRip — not verified (mismatch)
    if (_reArNotVerified.hasMatch(trimmed)) {
      arStatus = AccurateRipStatus.mismatch;
      continue;
    }

    // AccurateRip — not in database
    if (_reArNotInDb.hasMatch(trimmed)) {
      arStatus = AccurateRipStatus.notInDatabase;
      continue;
    }

    // Statistics block
    final mRead = _reStatReadError.firstMatch(trimmed);
    if (mRead != null) {
      readErrors = int.tryParse(mRead.group(1)!) ?? 0;
      continue;
    }
    final mJitter = _reStatJitterError.firstMatch(trimmed);
    if (mJitter != null) {
      jitterErrors = int.tryParse(mJitter.group(1)!) ?? 0;
      continue;
    }
    final mDamaged = _reStatDamagedSector.firstMatch(trimmed);
    if (mDamaged != null) {
      damagedSectors = int.tryParse(mDamaged.group(1)!) ?? 0;
      continue;
    }
    if (peakLevel == null) {
      final m = _reStatPeakLevel.firstMatch(trimmed);
      if (m != null) {
        peakLevel = percentToFraction(m.group(1));
        continue;
      }
    }
    if (trackQuality == null) {
      final m = _reStatTrackQuality.firstMatch(trimmed);
      if (m != null) {
        trackQuality = percentToFraction(m.group(1));
        continue;
      }
    }
  }

  if (trackNumber == null) {
    parsingErrors.add('Could not extract track number from XLD section');
    return null;
  }

  return RipLogTrack(
    trackNumber: trackNumber,
    filename: filename,
    peakLevel: peakLevel,
    trackQuality: trackQuality,
    copyCrc: copyCrc,
    accurateRipStatus: arStatus,
    accurateRipCrcV1: arCrcV1,
    accurateRipCrcV2: arCrcV2,
    accurateRipConfidence: arConfidence,
    copyOk: arStatus == AccurateRipStatus.verified,
    errors: TrackErrors(
      readErrors: readErrors,
      jitterErrors: jitterErrors,
      damagedSectors: damagedSectors,
    ),
    logFormat: RipLogFormat.xld,
  );
}
