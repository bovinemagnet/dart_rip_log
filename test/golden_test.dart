import 'dart:convert';
import 'dart:io';

import 'package:dart_rip_log/dart_rip_log.dart';
import 'package:test/test.dart';

/// Golden tests: pin the public JSON shape of `toJson(log)` per fixture.
///
/// If a parser change intentionally changes the JSON shape, regenerate
/// goldens with:
///
///   for f in eac_sample eac_errors_sample eac_range_sample xld_sample; do \
///     dart run bin/riplog.dart --format json test/fixtures/$f.log \
///       > test/fixtures/$f.expected.json; \
///   done
void main() {
  const fixtures = [
    'eac_sample',
    'eac_errors_sample',
    'eac_range_sample',
    'xld_sample',
  ];

  for (final name in fixtures) {
    test('$name: toJson matches golden', () {
      final logPath = 'test/fixtures/$name.log';
      final goldenPath = 'test/fixtures/$name.expected.json';
      if (!File(logPath).existsSync() || !File(goldenPath).existsSync()) {
        return;
      }
      final log = parseRipLog(File(logPath).readAsStringSync());
      final actual = toJson(log);
      final expected = jsonDecode(File(goldenPath).readAsStringSync())
          as Map<String, dynamic>;
      expect(actual, equals(expected),
          reason:
              'JSON shape drift in $name. Regenerate golden if intentional.');
    });
  }
}
