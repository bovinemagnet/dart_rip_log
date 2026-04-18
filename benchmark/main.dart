// Entry point for the rip-log benchmark harness.
//
// Usage:
//   dart run benchmark/main.dart            # full measurement (~20 s)
//   dart run benchmark/main.dart --smoke    # 1 iter per case (~1 s)
//
// Results print as a single grouped table once all cases complete.

import 'dart:io';

import 'src/cases.dart';
import 'src/fixtures.dart';
import 'src/reporter.dart';

void main(List<String> args) {
  final smoke = args.contains('--smoke');

  final fixtures = Fixtures.load();
  final emitter = TableScoreEmitter();
  final cases = buildCases(fixtures, emitter);

  for (final c in cases) {
    if (smoke) {
      // Skip warmup + the 2 s exercise loop; run the op once so we still
      // exercise the code path. Emit a sentinel score so the table shape
      // is unchanged.
      c.setup();
      c.run();
      c.teardown();
      emitter.emit(c.name, 0.0);
    } else {
      c.report();
    }
  }

  stdout.writeln();
  stdout.writeln(emitter.renderTable(
    fixtures: Fixtures.names,
    trackCountFor: const {'eac_500_track': Fixtures.eac500TrackCount},
  ));
  stdout.writeln();
}
