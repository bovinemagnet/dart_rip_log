import 'dart:io';

import 'package:dart_rip_log/dart_rip_log.dart';
import 'package:test/test.dart';

void main() {
  group('whipper parser (fixture)', () {
    late RipLog log;
    setUpAll(() {
      log = parseRipLog(
          File('test/fixtures/whipper_sample.log').readAsStringSync());
    });

    test('detects whipper format', () {
      expect(log.logFormat, RipLogFormat.whipper);
    });

    test('parses header fields', () {
      expect(log.toolVersion, '0.10.0');
      expect(log.extractionDate, DateTime.utc(2021, 6, 14, 9, 41, 37));
      expect(log.drive, isNotNull);
      expect(log.drive!.name, 'HL-DT-STBD-RE  WH14NS40 (revision 1.03)');
      expect(log.readOffset, 6);
      expect(log.overread, false);
      expect(log.gapHandling, 'cdrdao 1.2.4');
    });

    test('parses footer fields', () {
      expect(log.accurateRipSummary,
          'Some tracks could not be verified as accurate (1/4 got no match)');
      expect(
          log.integrityHash,
          'A900FDC1978A2C3F141DB61F31B8647F'
          'BCA71A5EDDABD3D59895077D0E8AD272');
      expect(log.testAndCopy, true);
    });

    test('parses all four tracks with no warnings', () {
      expect(log.tracks, hasLength(4));
      expect(log.errors, isEmpty);
    });

    test('track 1: fully verified with v1+v2 exact matches', () {
      final t = log.tracks[0];
      expect(t.trackNumber, 1);
      expect(t.filename,
          './Sample Artist - Sample Album/01. Sample Artist - First Track.flac');
      expect(t.peakLevel, closeTo(0.876341, 1e-9));
      expect(t.trackQuality, closeTo(1.0, 1e-9));
      expect(t.testCrc, '8A5F3C21');
      expect(t.copyCrc, '8A5F3C21');
      expect(t.accurateRipStatus, AccurateRipStatus.verified);
      // v2 match wins for the reported confidence.
      expect(t.accurateRipConfidence, 11);
      expect(t.accurateRipCrcV1, '95E6A189');
      expect(t.accurateRipCrcV2, '113FA733');
      expect(t.copyOk, true);
      expect(t.logFormat, RipLogFormat.whipper);
    });

    test('track 1: TOC timing data', () {
      final t = log.tracks[0];
      expect(t.startSector, 0);
      expect(t.lengthSectors, 20712);
      expect(t.durationSeconds, closeTo(20712 / 75, 1e-9));
    });

    test('track 3: v1 mismatch but v2 exact match is still verified', () {
      final t = log.tracks[2];
      expect(t.accurateRipStatus, AccurateRipStatus.verified);
      expect(t.accurateRipConfidence, 9);
      // Local CRCs, not the remote ones.
      expect(t.accurateRipCrcV1, '5D91F6A2');
      expect(t.accurateRipCrcV2, 'D4B7250E');
    });

    test('track 4: absent from the AccurateRip database', () {
      final t = log.tracks[3];
      expect(t.accurateRipStatus, AccurateRipStatus.notInDatabase);
      expect(t.accurateRipConfidence, isNull);
    });
  });

  group('whipper parser (variants)', () {
    test('v1 found with no exact match and no v2 match is a mismatch', () {
      const content = '''
Log created by: whipper 0.9.0 (internal logger)
Log creation date: 2020-01-01T00:00:00Z

Tracks:
  1:
    Filename: ./x/01. Track.flac
    Peak level: 0.5
    Copy CRC: AAAAAAAA
    AccurateRip v1:
      Result: Found, NO exact match
      Confidence: 3
      Local CRC: 11111111
      Remote CRC: 22222222
    AccurateRip v2:
      Result: Track not present in AccurateRip database
    Status: Copy OK
''';
      final log = parseRipLog(content);
      expect(log.tracks, hasLength(1));
      expect(log.tracks[0].accurateRipStatus, AccurateRipStatus.mismatch);
      expect(log.tracks[0].accurateRipConfidence, isNull);
    });

    test('CRC-mismatch status clears copyOk', () {
      const content = '''
Log created by: whipper 0.10.0 (internal logger)
Log creation date: 2020-01-01T00:00:00Z

Tracks:
  1:
    Filename: ./x/01. Track.flac
    Test CRC: AAAAAAAA
    Copy CRC: BBBBBBBB
    Status: Error, CRC mismatch
''';
      final log = parseRipLog(content);
      expect(log.tracks[0].copyOk, false);
    });

    test('0.8/0.9 "Health Status" capitalisation is tolerated', () {
      const content = '''
Log created by: whipper 0.9.0 (internal logger)
Log creation date: 2020-01-01T00:00:00Z

Tracks:
  1:
    Filename: ./x/01. Track.flac
    Status: Copy OK

Conclusive status report:
  AccurateRip summary: All tracks accurately ripped
  Health Status: No errors occurred
  EOF: End of status report
''';
      final log = parseRipLog(content);
      expect(log.accurateRipSummary, 'All tracks accurately ripped');
    });

    test('0.7.x plain-text offset "+6" and Yes/No booleans', () {
      const content = '''
Log created by: whipper 0.7.3 (internal logger)
Log creation date: 2019-01-01T00:00:00Z

Ripping phase information:
  Drive: PLEXTOR CD-R PX-W5224A (revision 1.04)
  Read offset correction: +6
  Overread into lead-out: No

Tracks:
  1:
    Filename: ./x/01. Track.flac
    Status: Copy OK
''';
      final log = parseRipLog(content);
      expect(log.readOffset, 6);
      expect(log.overread, false);
    });

    test('TOC numbers are not mistaken for track sections', () {
      const content = '''
Log created by: whipper 0.10.0 (internal logger)
Log creation date: 2020-01-01T00:00:00Z

TOC:
  1:
    Start: 00:00:00
    Length: 01:00:00
    Start sector: 0
    End sector: 4499

Tracks:
  1:
    Filename: ./x/01. Track.flac
    Status: Copy OK
''';
      final log = parseRipLog(content);
      expect(log.tracks, hasLength(1));
      expect(log.tracks[0].startSector, 0);
      expect(log.tracks[0].lengthSectors, 4500);
    });

    test('quoted YAML values are unquoted', () {
      const content = '''
Log created by: whipper 0.10.0 (internal logger)
Log creation date: 2020-01-01T00:00:00Z

Tracks:
  1:
    Filename: './x/01. Track: With Colon.flac'
    Status: Copy OK
''';
      final log = parseRipLog(content);
      expect(log.tracks[0].filename, './x/01. Track: With Colon.flac');
    });
  });
}
