import 'package:benchmark_harness/benchmark_harness.dart';

/// A [ScoreEmitter] that collects benchmark scores in memory so the
/// harness can print a single grouped table at the end instead of one
/// line per case.
///
/// Case names are expected to be `<fixture>.<op>`, e.g. `eac_sample.parse`.
class TableScoreEmitter implements ScoreEmitter {
  final Map<String, double> _scores = {};

  @override
  void emit(String testName, double value) {
    _scores[testName] = value;
  }

  /// Microseconds per run for a case, or `null` if never emitted.
  double? scoreFor(String testName) => _scores[testName];

  /// Render a grouped table: one row per fixture, columns per op, plus a
  /// trailing `parse µs/track` column populated only for fixtures listed
  /// in [trackCountFor].
  String renderTable({
    required List<String> fixtures,
    required Map<String, int> trackCountFor,
  }) {
    const ops = ['detect', 'parse', 'toJson'];
    const fixtureWidth = 20;
    const colWidth = 12;
    const perTrackWidth = 16;

    String fmt(double? v) => v == null ? '-' : v.toStringAsFixed(2);

    final header = [
      'Fixture'.padRight(fixtureWidth),
      ...ops.map((o) => o.padLeft(colWidth)),
      'parse µs/track'.padLeft(perTrackWidth),
    ].join('  ');

    final sep = [
      '-' * fixtureWidth,
      ...ops.map((_) => '-' * colWidth),
      '-' * perTrackWidth,
    ].join('  ');

    final rows = <String>[];
    for (final fx in fixtures) {
      final cells = <String>[fx.padRight(fixtureWidth)];
      for (final op in ops) {
        cells.add(fmt(_scores['$fx.$op']).padLeft(colWidth));
      }
      final count = trackCountFor[fx];
      final parseScore = _scores['$fx.parse'];
      String perTrack;
      if (count == null || count == 0 || parseScore == null) {
        perTrack = 'N/A';
      } else {
        perTrack = (parseScore / count).toStringAsFixed(2);
      }
      cells.add(perTrack.padLeft(perTrackWidth));
      rows.add(cells.join('  '));
    }

    return [header, sep, ...rows].join('\n');
  }
}
