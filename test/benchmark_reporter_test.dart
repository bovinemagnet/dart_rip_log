import 'package:test/test.dart';

import '../benchmark/src/reporter.dart';

void main() {
  group('TableScoreEmitter', () {
    test('emit stores scores keyed by test name', () {
      final e = TableScoreEmitter();
      e.emit('eac_sample.parse', 42.5);
      expect(e.scoreFor('eac_sample.parse'), 42.5);
      expect(e.scoreFor('missing'), isNull);
    });

    test('renderTable prints one row per fixture with three op columns', () {
      final e = TableScoreEmitter()
        ..emit('eac_sample.detect', 1.0)
        ..emit('eac_sample.parse', 10.0)
        ..emit('eac_sample.toJson', 2.0)
        ..emit('xld_sample.detect', 1.5)
        ..emit('xld_sample.parse', 12.0)
        ..emit('xld_sample.toJson', 2.5)
        ..emit('eac_500_track.detect', 3.0)
        ..emit('eac_500_track.parse', 5000.0)
        ..emit('eac_500_track.toJson', 500.0);

      final table = e.renderTable(
        fixtures: ['eac_sample', 'xld_sample', 'eac_500_track'],
        trackCountFor: {'eac_500_track': 500},
      );

      expect(table, contains('Fixture'));
      expect(table, contains('detect'));
      expect(table, contains('parse'));
      expect(table, contains('toJson'));
      expect(table, contains('eac_sample'));
      expect(table, contains('xld_sample'));
      expect(table, contains('eac_500_track'));
      // 5000 us / 500 tracks = 10.00 us/track
      expect(table, contains('10.00'));
      // Non-500-track rows show N/A in the per-track column
      final lines = table.split('\n');
      final eacSmallRow = lines.firstWhere((l) => l.startsWith('eac_sample'));
      expect(eacSmallRow, contains('N/A'));
    });

    test('renderTable shows - for missing scores rather than throwing', () {
      final e = TableScoreEmitter()..emit('eac_sample.parse', 5.0);
      final table = e.renderTable(
        fixtures: ['eac_sample'],
        trackCountFor: const {},
      );
      // detect and toJson were never emitted
      expect(table, contains('-'));
      expect(table, contains('5.00'));
    });
  });
}
