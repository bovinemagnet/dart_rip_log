import 'dart:io';

import 'package:dart_rip_log/dart_rip_log.dart';
import 'package:test/test.dart';

void main() {
  group('CUERipper parser (EAC-style variant)', () {
    late RipLog log;
    setUpAll(() {
      log = parseRipLog(
          File('test/fixtures/cueripper_sample.log').readAsStringSync());
    });

    test('detects cueRipper format, not eac', () {
      expect(log.logFormat, RipLogFormat.cueRipper);
    });

    test('parses CUERipper version, not an EAC version', () {
      expect(log.toolVersion, '2.2.6');
    });

    test('parses EAC-style header fields', () {
      expect(log.extractionDate, DateTime(2025, 6, 12, 18, 42));
      expect(log.drive!.name, 'HL-DT-ST DVDRAM GH24NSD1');
      expect(log.readMode, 'Secure');
      expect(log.readOffset, 6);
      expect(log.overread, false);
      expect(log.gapHandling, 'Appended to previous track');
    });

    test('parses all five tracks with cueRipper track format', () {
      expect(log.tracks, hasLength(5));
      expect(log.errors, isEmpty);
      expect(
          log.tracks.map((t) => t.logFormat).toSet(), {RipLogFormat.cueRipper});
    });

    test('track 1: full quality data and TOC timing', () {
      final t = log.tracks[0];
      expect(t.trackNumber, 1);
      expect(t.filename, contains('01 - Sample Artist - Track One.wav'));
      expect(t.peakLevel, closeTo(0.962, 1e-9));
      expect(t.trackQuality, closeTo(1.0, 1e-9));
      expect(t.testCrc, '2B055AD7');
      expect(t.copyCrc, '2B055AD7');
      expect(t.accurateRipStatus, AccurateRipStatus.verified);
      expect(t.accurateRipConfidence, 27);
      expect(t.accurateRipCrcV1, 'A1B2C3D4');
      expect(t.copyOk, true);
      expect(t.startSector, 0);
      expect(t.lengthSectors, 20490);
    });

    test('track 3: AccurateRip mismatch', () {
      expect(log.tracks[2].accurateRipStatus, AccurateRipStatus.mismatch);
    });

    test('track 4: not present in the AccurateRip database', () {
      expect(log.tracks[3].accurateRipStatus, AccurateRipStatus.notInDatabase);
    });

    test('footer summary and test-and-copy', () {
      expect(log.accurateRipSummary, contains('3 track(s) accurately ripped'));
      expect(log.testAndCopy, true);
    });
  });

  group('CUERipper parser (native variant)', () {
    late RipLog log;
    setUpAll(() {
      log = parseRipLog(
          File('test/fixtures/cueripper_native_sample.log').readAsStringSync());
    });

    test('detects cueRipper format', () {
      expect(log.logFormat, RipLogFormat.cueRipper);
    });

    test('parses header fields', () {
      expect(log.toolVersion, '2.1.4');
      expect(log.extractionDate, DateTime(2012, 4, 25, 2, 9, 24));
      expect(log.drive!.name, 'hp       - DVDRAM GT31L');
      expect(log.readOffset, 103);
      expect(log.readMode, 'Secure');
    });

    test('parses four tracks from TOC + AR summary + CRC table', () {
      expect(log.tracks, hasLength(4));
      expect(log.errors, isEmpty);
    });

    test('track 1: sectors, filename, peak, CRC, AR result', () {
      final t = log.tracks[0];
      expect(t.trackNumber, 1);
      expect(t.filename, contains('01 - First Piece.flac'));
      expect(t.startSector, 0);
      expect(t.lengthSectors, 49762);
      expect(t.peakLevel, closeTo(0.973, 1e-9));
      expect(t.copyCrc, 'F57D3663');
      expect(t.accurateRipStatus, AccurateRipStatus.verified);
      expect(t.accurateRipConfidence, 6);
      expect(t.accurateRipCrcV1, '1C4D0BD3');
      expect(t.accurateRipCrcV2, '46837CE2');
      expect(t.logFormat, RipLogFormat.cueRipper);
    });

    test('track 4: zero-offset "No match" is a mismatch', () {
      expect(log.tracks[3].accurateRipStatus, AccurateRipStatus.mismatch);
    });

    test('offsetted AR rows do not override the zero-offset results', () {
      // Track 4 matched only at offset -1366 — that must not turn the
      // zero-offset "No match" into verified.
      expect(log.tracks[3].accurateRipStatus, AccurateRipStatus.mismatch);
      // Nor may the offset block's CRCs replace the zero-offset ones.
      expect(log.tracks[0].accurateRipCrcV1, '1C4D0BD3');
    });
  });

  group('CUERipper parser (variants)', () {
    test('disc not present in AccurateRip database', () {
      const content = '''
CUERipper v2.1.4 Copyright (C) 2008-12 Grigory Chudov
Extraction logfile from : 01/01/2020 10:00:00
Used drive              : TEST - DRIVE
Read offset correction  : 6
Secure mode             : 1
AccurateRip             : disk not present in database

TOC of the extracted CD

     Track |   Start  |  Length  | Start sector | End sector
    ---------------------------------------------------------
        1  |  0:00.00 |  1:00.00 |         0    |     4499

Destination files
    C:\\x\\01 - One.flac

End of status report
''';
      final log = parseRipLog(content);
      expect(log.logFormat, RipLogFormat.cueRipper);
      expect(log.tracks, hasLength(1));
      expect(log.tracks[0].accurateRipStatus, AccurateRipStatus.notInDatabase);
    });

    test('burst mode (Secure mode : 0) maps to Burst read mode', () {
      const content = '''
CUERipper v2.1.4 Copyright (C) 2008-12 Grigory Chudov
Extraction logfile from : 01/01/2020 10:00:00
Used drive              : TEST - DRIVE
Secure mode             : 0

TOC of the extracted CD

     Track |   Start  |  Length  | Start sector | End sector
    ---------------------------------------------------------
        1  |  0:00.00 |  1:00.00 |         0    |     4499

Destination files
    C:\\x\\01 - One.flac
''';
      final log = parseRipLog(content);
      expect(log.readMode, 'Burst');
    });
  });
}
