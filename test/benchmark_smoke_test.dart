@Tags(['cli'])
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'benchmark harness runs under --smoke and prints the expected surface',
    () {
      final result = Process.runSync(
        Platform.resolvedExecutable,
        ['run', 'benchmark/main.dart', '--smoke'],
      );

      expect(
        result.exitCode,
        0,
        reason: 'stdout:\n${result.stdout}\n---\nstderr:\n${result.stderr}',
      );

      final out = result.stdout.toString();
      expect(out, contains('Fixture'));
      expect(out, contains('detect'));
      expect(out, contains('parse'));
      expect(out, contains('toJson'));
      expect(out, contains('eac_sample'));
      expect(out, contains('xld_sample'));
      expect(out, contains('eac_500_track'));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
