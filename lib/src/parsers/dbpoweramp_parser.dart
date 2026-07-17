/// Parser for dBpoweramp CD Ripper secure extraction logs.
///
/// The log starts with `dBpoweramp Release X.Y Digital Audio Extraction
/// Log from <locale date>` (2023+ builds carry a `YYYY-MM-DD` date-token
/// version instead of `Release X.Y`), followed by a `Drive & Settings`
/// section and an `Extraction Log` with one block per track:
///
///     Track 1:  Ripped LBA 0 to 16852 (3:44) in 0:14. Filename: C:\...
///       AccurateRip: Accurate (confidence 42)     [Pass 1]
///       CRC32: 3A7F19C2     AccurateRip CRC: 91B04D6E (CRCv2)  [DiscID: ...]
///
/// The header date is OS-locale formatted free text and deliberately not
/// parsed. dBpoweramp appends each rip to the same file, so a second
/// header ends parsing with a warning rather than merging two discs.
library;

import '../models.dart';

final _reHeader = RegExp(
    r'^dBpoweramp\s+(?:Release\s+)?(\S+)\s+Digital Audio Extraction Log');
final _reDrive =
    RegExp(r"Ripping with drive '(.+?)',\s*Drive offset:\s*(-?\d+),\s*"
        r'Overread Lead-in/out:\s*(\w+)');
final _rePass1 = RegExp(r'^Pass 1 Drive Speed:');

final _reTrack =
    RegExp(r'^Track\s+(\d+):\s+Ripped LBA\s+(\d+)\s+to\s+(\d+)\s+\([\d:]+\)\s+'
        r'in\s+[\d:]+\.\s+Filename:\s*(.+)$');
// Status line, e.g. `AccurateRip: Accurate (confidence 42)     [Pass 1]`,
// `Secure  [Pass 1 & 2, Ultra 1 to 3]`, `Insecure  [...]`, or the combined
// `AccurateRip: Inaccurate (confidence 200) Secure (Warning) [...]`.
final _reArAccurate =
    RegExp(r'^AccurateRip:\s+Accurate\s+\(confidence\s+(\d+)\)');
final _reArInaccurate = RegExp(r'^AccurateRip:\s+Inaccurate\b');
final _reSecure = RegExp(r'^Secure\b');
final _reInsecure = RegExp(r'^Insecure\b');
final _reCrc = RegExp(r'^CRC32:\s*([0-9A-Fa-f]{8})'
    r'(?:\s+AccurateRip CRC:\s*([0-9A-Fa-f]{8})\s*\(CRCv([12])\))?');
final _reAborted = RegExp(r'^\*\*\s*Aborted');
final _reUnrecoverable =
    RegExp(r'^\*\*\s*Reached Maximum\s+(\d+)\s+Unrecoverable Frames');
final _reSummary = RegExp(r'^\d+\s+Tracks Ripped\b.*');

class _TrackBlock {
  final int number;
  final int startLba;
  final int endLba;
  final String filename;
  AccurateRipStatus arStatus = AccurateRipStatus.notChecked;
  int? arConfidence;
  String? arCrcV1;
  String? arCrcV2;
  String? copyCrc;
  bool secure = false;
  bool insecure = false;
  bool aborted = false;
  int unrecoverableFrames = 0;

  _TrackBlock(this.number, this.startLba, this.endLba, this.filename);
}

/// Parse a dBpoweramp log from its string [content].
RipLog parseDbPoweramp(String content) {
  final lines = content.split(RegExp(r'\r\n|\r|\n'));

  String? toolVersion;
  String? driveName;
  int? readOffset;
  bool? overread;
  String? readMode;
  String? summary;
  final parsingErrors = <String>[];

  final blocks = <_TrackBlock>[];
  _TrackBlock? current;
  bool seenHeader = false;

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;

    final mHeader = _reHeader.firstMatch(line);
    if (mHeader != null) {
      if (seenHeader) {
        // dBpoweramp appends each rip to one file — only the first log is
        // parsed so two discs are never merged into one result.
        parsingErrors
            .add('File contains multiple dBpoweramp logs; parsed the first');
        break;
      }
      seenHeader = true;
      toolVersion = mHeader.group(1);
      continue;
    }

    final mDrive = _reDrive.firstMatch(line);
    if (mDrive != null) {
      driveName = mDrive.group(1);
      readOffset = int.tryParse(mDrive.group(2)!);
      overread = mDrive.group(3)!.toLowerCase() == 'yes';
      continue;
    }
    if (readMode == null && _rePass1.hasMatch(line)) {
      // Pass lines only appear for secure rips; burst rips write no
      // extraction log at all.
      readMode = 'Secure';
      continue;
    }

    final mTrack = _reTrack.firstMatch(line);
    if (mTrack != null) {
      current = _TrackBlock(
        int.parse(mTrack.group(1)!),
        int.parse(mTrack.group(2)!),
        int.parse(mTrack.group(3)!),
        mTrack.group(4)!.trim(),
      );
      blocks.add(current);
      continue;
    }

    if (current != null) {
      final mAccurate = _reArAccurate.firstMatch(line);
      if (mAccurate != null) {
        current.arStatus = AccurateRipStatus.verified;
        current.arConfidence = int.tryParse(mAccurate.group(1)!);
        continue;
      }
      if (_reArInaccurate.hasMatch(line)) {
        // The confidence on an Inaccurate line is the database submission
        // count, not a match confidence — not captured.
        current.arStatus = AccurateRipStatus.mismatch;
        continue;
      }
      if (_reSecure.hasMatch(line)) {
        current.secure = true;
        continue;
      }
      if (_reInsecure.hasMatch(line)) {
        current.insecure = true;
        continue;
      }
      final mCrc = _reCrc.firstMatch(line);
      if (mCrc != null) {
        current.copyCrc = mCrc.group(1)!.toUpperCase();
        final arCrc = mCrc.group(2)?.toUpperCase();
        if (arCrc != null) {
          if (mCrc.group(3) == '2') {
            current.arCrcV2 = arCrc;
          } else {
            current.arCrcV1 = arCrc;
          }
        }
        continue;
      }
      if (_reAborted.hasMatch(line)) {
        current.aborted = true;
        continue;
      }
      final mUnrecoverable = _reUnrecoverable.firstMatch(line);
      if (mUnrecoverable != null) {
        current.unrecoverableFrames =
            int.tryParse(mUnrecoverable.group(1)!) ?? 0;
        continue;
      }
    }

    if (summary == null) {
      final mSummary = _reSummary.firstMatch(line);
      if (mSummary != null) {
        summary = mSummary.group(0);
        continue;
      }
    }
  }

  final tracks = blocks.map(_toTrack).toList();
  if (tracks.isEmpty && toolVersion != null) {
    parsingErrors.add('No track sections found in dBpoweramp log');
  }

  return RipLog(
    logFormat: RipLogFormat.dbPoweramp,
    toolVersion: toolVersion,
    drive: driveName != null
        ? DriveInfo(name: driveName, readOffset: readOffset)
        : null,
    readMode: readMode,
    readOffset: readOffset,
    overread: overread,
    tracks: tracks,
    accurateRipSummary: summary,
    errors: parsingErrors,
    testAndCopy: tracks.isEmpty ? null : tracks.any((t) => t.testCrc != null),
  );
}

RipLogTrack _toTrack(_TrackBlock block) {
  // A track with no AccurateRip line but a Secure status ripped
  // consistently against a disc/track absent from the database.
  var arStatus = block.arStatus;
  if (arStatus == AccurateRipStatus.notChecked && block.secure) {
    arStatus = AccurateRipStatus.notInDatabase;
  }

  final lengthSectors = block.endLba - block.startLba;

  return RipLogTrack(
    trackNumber: block.number,
    filename: block.filename,
    copyCrc: block.copyCrc,
    accurateRipStatus: arStatus,
    accurateRipCrcV1: block.arCrcV1,
    accurateRipCrcV2: block.arCrcV2,
    accurateRipConfidence: block.arConfidence,
    copyOk: !block.insecure && !block.aborted,
    errors: TrackErrors(damagedSectors: block.unrecoverableFrames),
    logFormat: RipLogFormat.dbPoweramp,
    startSector: block.startLba,
    lengthSectors: lengthSectors > 0 ? lengthSectors : null,
    durationSeconds: lengthSectors > 0 ? lengthSectors / 75.0 : null,
  );
}
