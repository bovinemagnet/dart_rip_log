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
}
