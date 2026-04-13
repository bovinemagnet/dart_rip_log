@Tags(['cli'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Integration tests that shell out to `dart run bin/riplog.dart`.
/// Tagged `cli` so they can be skipped in lightweight CI runs:
///   dart test --exclude-tags cli
void main() {
  final riplog = ['run', 'bin/riplog.dart'];

  Future<ProcessResult> run(List<String> args, {String? stdinText}) async {
    final proc = await Process.start(
      Platform.resolvedExecutable,
      [...riplog, ...args],
      workingDirectory: Directory.current.path,
    );
    if (stdinText != null) {
      proc.stdin.write(stdinText);
      await proc.stdin.close();
    } else {
      await proc.stdin.close();
    }
    final stdoutFut = proc.stdout.transform(utf8.decoder).join();
    final stderrFut = proc.stderr.transform(utf8.decoder).join();
    final code = await proc.exitCode;
    return ProcessResult(proc.pid, code, await stdoutFut, await stderrFut);
  }

  group('riplog CLI', () {
    test('--version prints version and exits 0', () async {
      final r = await run(['--version']);
      expect(r.exitCode, 0);
      expect(r.stdout.toString(), contains('riplog '));
    });

    test('--help prints usage and exits 0', () async {
      final r = await run(['--help']);
      expect(r.exitCode, 0);
      expect(r.stdout.toString(), contains('Usage:'));
      expect(r.stdout.toString(), contains('--quiet'));
    });

    test('no args with no stdin → exit 2', () async {
      // We cannot truly simulate a terminal; supplying no stdin here
      // causes the CLI to read empty stdin → returns unknown format.
      // Instead test the unknown-option exit path.
      final r = await run(['--bogus']);
      expect(r.exitCode, 2);
    });

    test('--format json produces valid JSON', () async {
      final r = await run(['--format', 'json', 'test/fixtures/eac_sample.log']);
      expect(r.exitCode, anyOf(0, 1));
      final decoded = jsonDecode(r.stdout.toString());
      expect(decoded, isMap);
      expect((decoded as Map)['logFormat'], 'eac');
      expect(decoded['tracks'], isList);
    });

    test('--format text prints human-readable output', () async {
      final r = await run(['--format', 'text', 'test/fixtures/eac_sample.log']);
      expect(r.stdout.toString(), contains('Log format'));
      expect(r.stdout.toString(), contains('Track 1'));
    });

    test('--summary prints one line per track', () async {
      final r = await run(['--summary', 'test/fixtures/eac_sample.log']);
      final lines = r.stdout.toString().split('\n');
      expect(lines.where((l) => l.contains('Track ')).length, 3);
    });

    test('--quiet emits tab-separated fields', () async {
      final r = await run(['-q', 'test/fixtures/eac_sample.log']);
      final line = r.stdout.toString().trim().split('\n').first;
      final parts = line.split('\t');
      expect(parts, hasLength(5));
      expect(parts[1], 'eac');
      expect(parts[2], '3');
    });

    test('missing file → exit 2', () async {
      final r = await run(['/tmp/definitely-does-not-exist-riplog.log']);
      expect(r.exitCode, 2);
      expect(r.stderr.toString(), contains('Cannot read'));
    });

    test('invalid --format value → exit 2', () async {
      final r = await run(['--format', 'yaml', 'test/fixtures/eac_sample.log']);
      expect(r.exitCode, 2);
    });

    test('AR mismatch / errors → exit 1', () async {
      final r = await run(['-q', 'test/fixtures/eac_errors_sample.log']);
      expect(r.exitCode, 1);
    });

    test('stdin via "-" sentinel', () async {
      final content = await File('test/fixtures/eac_sample.log').readAsString();
      final r = await run(['-q', '-'], stdinText: content);
      final parts = r.stdout.toString().trim().split('\t');
      expect(parts[1], 'eac');
      expect(parts[2], '3');
    });

    test('piped stdin with no arg is read automatically', () async {
      final content = await File('test/fixtures/eac_sample.log').readAsString();
      final r = await run(['-q'], stdinText: content);
      final parts = r.stdout.toString().trim().split('\t');
      expect(parts[1], 'eac');
    });

    test('multiple files with default JSON → single top-level array', () async {
      final r = await run([
        'test/fixtures/eac_sample.log',
        'test/fixtures/xld_sample.log',
      ]);
      final decoded = jsonDecode(r.stdout.toString());
      expect(decoded, isList);
      expect((decoded as List), hasLength(2));
      expect(decoded[0]['logFormat'], 'eac');
      expect(decoded[1]['logFormat'], 'xld');
    });

    test('multiple files with --quiet → one line per file', () async {
      final r = await run([
        '-q',
        'test/fixtures/eac_sample.log',
        'test/fixtures/xld_sample.log',
      ]);
      final lines = r.stdout
          .toString()
          .trim()
          .split('\n')
          .where((l) => l.isNotEmpty)
          .toList();
      expect(lines, hasLength(2));
    });

    test('multiple files with --format text are prefixed with # <path>',
        () async {
      final r = await run([
        '--format',
        'text',
        'test/fixtures/eac_sample.log',
        'test/fixtures/xld_sample.log',
      ]);
      expect(r.stdout.toString(), contains('# test/fixtures/eac_sample.log'));
      expect(r.stdout.toString(), contains('# test/fixtures/xld_sample.log'));
    });

    test('--format ndjson: one JSON object per line', () async {
      final r = await run([
        '--format',
        'ndjson',
        'test/fixtures/eac_sample.log',
        'test/fixtures/xld_sample.log',
      ]);
      final lines = r.stdout
          .toString()
          .trim()
          .split('\n')
          .where((l) => l.isNotEmpty)
          .toList();
      expect(lines, hasLength(2));
      final first = jsonDecode(lines[0]) as Map<String, dynamic>;
      final second = jsonDecode(lines[1]) as Map<String, dynamic>;
      expect(first['logFormat'], 'eac');
      expect(second['logFormat'], 'xld');
    });

    test('--filter problems hides verified tracks in summary output', () async {
      final r = await run([
        '--summary',
        '--filter',
        'problems',
        'test/fixtures/eac_sample.log',
      ]);
      // eac_sample.log: track 1 verified (hidden), track 2 mismatch,
      // track 3 notInDatabase. With filter=problems only mismatches and
      // error tracks remain → track 2 shown, track 3 hidden.
      final trackLines = r.stdout
          .toString()
          .split('\n')
          .where((l) => l.contains('Track '))
          .toList();
      expect(trackLines, hasLength(1));
      expect(trackLines.first, contains('Track  2'));
    });

    test('--filter mismatch shows only mismatched tracks', () async {
      final r = await run([
        '--summary',
        '--filter',
        'mismatch',
        'test/fixtures/eac_sample.log',
      ]);
      final trackLines = r.stdout
          .toString()
          .split('\n')
          .where((l) => l.contains('Track '))
          .toList();
      expect(trackLines, hasLength(1));
      expect(trackLines.first, contains('mismatch'));
    });

    test('--fail-on never → exit 0 even on mismatch', () async {
      final r = await run([
        '--fail-on',
        'never',
        '-q',
        'test/fixtures/eac_errors_sample.log',
      ]);
      expect(r.exitCode, 0);
    });

    test('--fail-on mismatch → exit 1 only on AR mismatch', () async {
      // eac_errors_sample has an AR mismatch → should fail.
      final r = await run([
        '--fail-on',
        'mismatch',
        '-q',
        'test/fixtures/eac_errors_sample.log',
      ]);
      expect(r.exitCode, 1);
    });

    test('--fail-on errors triggers on track errors only', () async {
      // eac_sample has mismatches but no track error counts → with
      // fail-on=errors should exit 0.
      final r = await run([
        '--fail-on',
        'errors',
        '-q',
        'test/fixtures/eac_sample.log',
      ]);
      expect(r.exitCode, 0);
    });

    test('invalid --filter value → exit 2', () async {
      final r =
          await run(['--filter', 'bogus', 'test/fixtures/eac_sample.log']);
      expect(r.exitCode, 2);
    });

    test('invalid --fail-on value → exit 2', () async {
      final r =
          await run(['--fail-on', 'bogus', 'test/fixtures/eac_sample.log']);
      expect(r.exitCode, 2);
    });

    test('--color never produces no ANSI escape codes', () async {
      final r = await run([
        '--format',
        'text',
        '--color',
        'never',
        'test/fixtures/eac_sample.log',
      ]);
      expect(r.stdout.toString(), isNot(contains('\x1B[')));
    });

    test('--color always emits ANSI escape codes', () async {
      final r = await run([
        '--format',
        'text',
        '--color',
        'always',
        'test/fixtures/eac_sample.log',
      ]);
      expect(r.stdout.toString(), contains('\x1B['));
    });

    test('directory without --recursive → exit 2', () async {
      final r = await run(['test/fixtures']);
      expect(r.exitCode, 2);
    });

    test('--recursive walks directory for *.log files', () async {
      final r = await run(['-q', '--recursive', 'test/fixtures']);
      final lines = r.stdout
          .toString()
          .trim()
          .split('\n')
          .where((l) => l.isNotEmpty)
          .toList();
      // test/fixtures has 4 .log files: eac_sample, eac_errors_sample,
      // eac_range_sample, xld_sample.
      expect(lines, hasLength(4));
      expect(lines.every((l) => l.contains('.log\t')), isTrue);
    });
  });
}
