import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:dart_rip_log/dart_rip_log.dart';

import 'fixtures.dart';
import 'reporter.dart';

/// A [BenchmarkBase] whose measured body is a closure.
///
/// Keeping one class and parameterising the op avoids nine
/// near-identical subclasses for (3 fixtures x 3 ops).
class RipLogBenchmark extends BenchmarkBase {
  RipLogBenchmark(super.name, this._op, {required super.emitter});

  final void Function() _op;

  @override
  void run() => _op();
}

/// Build the full set of nine cases for the given [fixtures], emitting
/// into [emitter]. Names follow the `<fixture>.<op>` convention expected
/// by [TableScoreEmitter].
///
/// `toJson` cases receive a parse result computed once at setup time, so
/// they measure serialisation in isolation rather than parse+serialise.
List<RipLogBenchmark> buildCases(Fixtures fixtures, ScoreEmitter emitter) {
  final cases = <RipLogBenchmark>[];

  final contentByFixture = fixtures.asMap();
  for (final entry in contentByFixture.entries) {
    final fx = entry.key;
    final content = entry.value;

    // Guard: if detection ever regresses to `unknown` on a real fixture,
    // parseRipLog would silently return an empty RipLog and the benchmark
    // would measure nothing meaningful.
    final detected = detectLogFormat(content);
    if (detected == RipLogFormat.unknown) {
      throw StateError(
        'Fixture "$fx" no longer detects as a known format. '
        'Fix the fixture or the detector before benchmarking.',
      );
    }

    final parsed = parseRipLog(content);

    cases.add(RipLogBenchmark(
      '$fx.detect',
      () => detectLogFormat(content),
      emitter: emitter,
    ));
    cases.add(RipLogBenchmark(
      '$fx.parse',
      () => parseRipLog(content),
      emitter: emitter,
    ));
    cases.add(RipLogBenchmark(
      '$fx.toJson',
      () => toJson(parsed),
      emitter: emitter,
    ));
  }

  return cases;
}
