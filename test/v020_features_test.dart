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
}
