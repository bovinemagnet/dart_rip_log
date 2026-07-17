import 'dart:io';

import 'package:dart_rip_log/dart_rip_log.dart';
import 'package:test/test.dart';

/// Parser-level tests for the 0.2.0 fix batch (#31–#37).
void main() {
  group('EAC drive name / adapter split (#31)', () {
    test('drive name excludes adapter text; adapter is populated', () {
      final log =
          parseRipLog(File('test/fixtures/eac_sample.log').readAsStringSync());
      expect(log.drive, isNotNull);
      expect(log.drive!.name, 'ASUS BW-16D1HT');
      expect(log.drive!.adapter, 'Adapter: 1   ID: 0');
    });

    test('drive line without adapter text keeps full name, null adapter', () {
      final log = parseRipLog('Exact Audio Copy V1.6 from 23. October 2019\n'
          'EAC extraction logfile from 15. March 2026\n'
          'Used drive            : PIONEER BD-RW BDR-212D\n');
      expect(log.drive!.name, 'PIONEER BD-RW BDR-212D');
      expect(log.drive!.adapter, isNull);
    });
  });

  group('EAC AccurateRip footer summary variants (#32)', () {
    String eacLogWithFooter(String footer) =>
        'Exact Audio Copy V1.6 from 23. October 2019\n'
        '\n'
        'EAC extraction logfile from 15. March 2026\n'
        '\n'
        'Used drive            : ASUS BW-16D1HT   Adapter: 1   ID: 0\n'
        '\n'
        'Track  1\n'
        '\n'
        '     Filename C:\\Music\\01 - One.flac\n'
        '     Peak level 96.2 %\n'
        '     Copy CRC 882B01BE\n'
        '     Cannot be verified as accurate  [12345678]\n'
        '     Copy OK\n'
        '\n'
        '$footer'
        '\n'
        'End of status report\n';

    test('"No tracks could be verified as accurate" is captured', () {
      final log = parseRipLog(eacLogWithFooter('No tracks could be verified as '
          'accurate\n'));
      expect(log.accurateRipSummary, 'No tracks could be verified as accurate');
    });

    test('"Some tracks could not be verified as accurate" is captured', () {
      final log =
          parseRipLog(eacLogWithFooter('Some tracks could not be verified '
              'as accurate\n'));
      expect(log.accurateRipSummary,
          'Some tracks could not be verified as accurate');
    });

    test('mixed multi-line summary is joined into one string', () {
      final log = parseRipLog(eacLogWithFooter('3 track(s) accurately ripped\n'
          '2 track(s) could not be verified as accurate\n'));
      expect(
          log.accurateRipSummary,
          '3 track(s) accurately ripped\n'
          '2 track(s) could not be verified as accurate');
    });

    test('all-verified summary is still captured (existing behaviour)', () {
      final log = parseRipLog(eacLogWithFooter('All tracks accurately '
          'ripped\n'));
      expect(log.accurateRipSummary, 'All tracks accurately ripped');
    });
  });

  group('EAC 0.95–0.99 footer AccurateRip block (#33)', () {
    // Older EAC puts per-track AR results in a footer block instead of
    // inline under each track.
    final content = 'Exact Audio Copy V0.99 from 23. October 2019\n'
        '\n'
        'EAC extraction logfile from 15. March 2026\n'
        '\n'
        'Used drive            : ASUS BW-16D1HT   Adapter: 1   ID: 0\n'
        '\n'
        'Track  1\n'
        '\n'
        '     Filename C:\\Music\\01 - One.flac\n'
        '     Peak level 96.2 %\n'
        '     Copy CRC 882B01BE\n'
        '     Copy OK\n'
        '\n'
        'Track  2\n'
        '\n'
        '     Filename C:\\Music\\02 - Two.flac\n'
        '     Peak level 75.0 %\n'
        '     Copy CRC AABBCCDD\n'
        '     Copy OK\n'
        '\n'
        '---- AccurateRip summary ----\n'
        '\n'
        'Track  1  accurately ripped (confidence 2)  [1A2B3C4D]\n'
        'Track  2  cannot be verified as accurate  [5E6F7A8B]\n'
        '\n'
        'End of status report\n';

    test('footer AR results map to the right tracks by number', () {
      final log = parseRipLog(content);
      expect(log.tracks, hasLength(2));

      final t1 = log.tracks[0];
      expect(t1.accurateRipStatus, AccurateRipStatus.verified);
      expect(t1.accurateRipConfidence, 2);
      expect(t1.accurateRipCrcV1, '1A2B3C4D');

      final t2 = log.tracks[1];
      expect(t2.accurateRipStatus, AccurateRipStatus.mismatch);
      expect(t2.accurateRipCrcV1, '5E6F7A8B');
      expect(t2.accurateRipConfidence, isNull);
    });

    test('footer AR lines do not pollute the last track\'s own fields', () {
      final log = parseRipLog(content);
      final t2 = log.tracks[1];
      // Without the fix the last track was overwritten by every footer
      // line in turn — track 2 must keep its own copy CRC and not
      // inherit track 1's confidence.
      expect(t2.copyCrc, 'AABBCCDD');
      expect(t2.accurateRipCrcV1, isNot('1A2B3C4D'));
    });
  });

  group('TOC table parsing (#34)', () {
    test('EAC tracks carry startSector / lengthSectors / durationSeconds', () {
      final log =
          parseRipLog(File('test/fixtures/eac_sample.log').readAsStringSync());
      expect(log.tracks, hasLength(3));

      final t1 = log.tracks[0];
      expect(t1.startSector, 0);
      expect(t1.lengthSectors, 20415);
      // 4:32.15 → 4*60 + 32 + 15/75 = 272.2 s
      expect(t1.durationSeconds, closeTo(272.2, 0.001));

      final t2 = log.tracks[1];
      expect(t2.startSector, 20415);
      expect(t2.lengthSectors, 16875);
      expect(t2.durationSeconds, closeTo(225.0, 0.001));

      final t3 = log.tracks[2];
      expect(t3.startSector, 37290);
      expect(t3.lengthSectors, 23280);
      expect(t3.durationSeconds, closeTo(310.4, 0.001));
    });

    test('XLD tracks carry startSector / lengthSectors / durationSeconds', () {
      final log =
          parseRipLog(File('test/fixtures/xld_sample.log').readAsStringSync());
      expect(log.tracks, hasLength(2));

      final t1 = log.tracks[0];
      expect(t1.startSector, 0);
      expect(t1.lengthSectors, 14627);
      // 03:14:52 → 3*60 + 14 + 52/75 s
      expect(t1.durationSeconds, closeTo(194.693, 0.001));

      final t2 = log.tracks[1];
      expect(t2.startSector, 14627);
      expect(t2.lengthSectors, 18148);
      expect(t2.durationSeconds, closeTo(241.973, 0.001));
    });

    test('logs without a TOC table leave the fields null', () {
      final log = parseRipLog(
          File('test/fixtures/eac_errors_sample.log').readAsStringSync());
      for (final t in log.tracks) {
        expect(t.startSector, isNull);
        expect(t.lengthSectors, isNull);
        expect(t.durationSeconds, isNull);
      }
    });
  });

  group('EAC extraction time-of-day (#36)', () {
    test('date line with ", HH:MM" carries hour and minute', () {
      final log = parseRipLog('Exact Audio Copy V1.6 from 23. October 2019\n'
          'EAC extraction logfile from 15. March 2026, 20:32\n');
      expect(log.extractionDate, DateTime(2026, 3, 15, 20, 32));
    });

    test('date-only line still yields midnight', () {
      final log = parseRipLog('Exact Audio Copy V1.6 from 23. October 2019\n'
          'EAC extraction logfile from 15. March 2026\n');
      expect(log.extractionDate, DateTime(2026, 3, 15));
    });
  });
}
