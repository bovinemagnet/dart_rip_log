import 'dart:io';

import 'package:dart_rip_log/dart_rip_log.dart';
import 'package:test/test.dart';

void main() {
  group('dBpoweramp parser (fixture)', () {
    late RipLog log;
    setUpAll(() {
      log = parseRipLog(
          File('test/fixtures/dbpoweramp_sample.log').readAsStringSync());
    });

    test('detects dBpoweramp format', () {
      expect(log.logFormat, RipLogFormat.dbPoweramp);
    });

    test('parses header fields', () {
      expect(log.toolVersion, '17.2');
      expect(log.drive!.name, 'E:   [HL-DT-ST - DVDRAM GP60NB50 ]');
      expect(log.readOffset, 6);
      expect(log.overread, false);
      expect(log.readMode, 'Secure');
    });

    test('parses all ten tracks with no warnings', () {
      expect(log.tracks, hasLength(10));
      expect(log.errors, isEmpty);
    });

    test('summary line captured', () {
      expect(log.accurateRipSummary,
          '10 Tracks Ripped: 8 Accurate, 1 Secure, 1 Inaccurate');
    });

    test('track 1: LBA range, filename, CRCs, AR verified', () {
      final t = log.tracks[0];
      expect(t.trackNumber, 1);
      expect(t.filename,
          r'C:\Music\Example Artist\Sample Album\01 - First Song.flac');
      expect(t.startSector, 0);
      expect(t.lengthSectors, 16852);
      expect(t.durationSeconds, closeTo(16852 / 75, 1e-9));
      expect(t.copyCrc, '3A7F19C2');
      expect(t.accurateRipStatus, AccurateRipStatus.verified);
      expect(t.accurateRipConfidence, 42);
      expect(t.accurateRipCrcV2, '91B04D6E');
      expect(t.copyOk, true);
      expect(t.logFormat, RipLogFormat.dbPoweramp);
    });

    test('track 8: Secure with no AR result is notInDatabase', () {
      final t = log.tracks[7];
      expect(t.accurateRipStatus, AccurateRipStatus.notInDatabase);
      expect(t.copyOk, true);
      expect(t.copyCrc, '9283B65C');
    });

    test('track 9: Inaccurate is a mismatch but still a secure copy', () {
      final t = log.tracks[8];
      expect(t.accurateRipStatus, AccurateRipStatus.mismatch);
      expect(t.copyOk, true);
    });

    test('track 10: Insecure + aborted clears copyOk', () {
      final t = log.tracks[9];
      expect(t.copyOk, false);
      expect(t.accurateRipStatus, AccurateRipStatus.notChecked);
    });
  });

  group('dBpoweramp parser (variants)', () {
    test('date-versioned 2023+ header', () {
      const content = 'dBpoweramp 2024-05-30 Digital Audio Extraction Log from '
          'Samstag, 5. Oktober 2024 17:36\n';
      final log = parseRipLog(content);
      expect(log.logFormat, RipLogFormat.dbPoweramp);
      expect(log.toolVersion, '2024-05-30');
    });

    test('Release without minor version (R15)', () {
      const content = 'dBpoweramp Release 15 Digital Audio Extraction Log '
          'from Montag, 30. Juni 2014 09:05\n';
      expect(parseRipLog(content).toolVersion, '15');
    });

    test('CRCv1 AccurateRip CRC goes to the v1 field', () {
      const content = '''
dBpoweramp Release 14.2 Digital Audio Extraction Log from 05 December 2012 08:23 PM

Track 1:  Ripped LBA 0 to 4500 (1:00) in 0:05. Filename: C:\\x\\01 - One.flac
  AccurateRip: Accurate (confidence 5)     [Pass 1]
  CRC32: AAAAAAAA     AccurateRip CRC: BBBBBBBB (CRCv1)
''';
      final log = parseRipLog(content);
      expect(log.tracks, hasLength(1));
      expect(log.tracks[0].accurateRipCrcV1, 'BBBBBBBB');
      expect(log.tracks[0].accurateRipCrcV2, isNull);
    });

    test('unrecoverable frames map to damaged sectors', () {
      const content = '''
dBpoweramp Release 15 Digital Audio Extraction Log from 21 September 2010 10:45 PM

Track 1:  Ripped LBA 0 to 4500 (1:00) in 3:05. Filename: C:\\x\\01 - One.flac
  Insecure  [Pass 1 & 2, Re-Rip 12 Frames]
  ** Reached Maximum 3 Unrecoverable Frames For This Track
''';
      final log = parseRipLog(content);
      expect(log.tracks[0].copyOk, false);
      expect(log.tracks[0].errors.damagedSectors, 3);
    });

    test('appended second log in the same file is not merged', () {
      final first =
          File('test/fixtures/dbpoweramp_sample.log').readAsStringSync();
      final combined = '$first\n$first';
      final log = parseRipLog(combined);
      expect(log.tracks, hasLength(10));
      expect(log.errors.any((e) => e.contains('multiple')), isTrue);
    });
  });
}
