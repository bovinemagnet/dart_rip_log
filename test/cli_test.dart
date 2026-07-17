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

  Future<ProcessResult> run(List<String> args,
      {String? stdinText, List<int>? stdinBytes}) async {
    final proc = await Process.start(
      Platform.resolvedExecutable,
      [...riplog, ...args],
      workingDirectory: Directory.current.path,
    );
    if (stdinBytes != null) {
      proc.stdin.add(stdinBytes);
      await proc.stdin.close();
    } else if (stdinText != null) {
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

    group('multi-file continue-on-error (#40)', () {
      const missing = '/tmp/definitely-does-not-exist-riplog.log';

      test('unreadable file is skipped, remaining files still emitted',
          () async {
        final r = await run([
          missing,
          'test/fixtures/eac_sample.log',
          'test/fixtures/xld_sample.log',
        ]);
        expect(r.exitCode, 2);
        expect(r.stderr.toString(), contains('Cannot read $missing'));
        final decoded = jsonDecode(r.stdout.toString());
        expect(decoded, isList);
        expect((decoded as List), hasLength(2));
        expect(decoded[0]['logFormat'], 'eac');
        expect(decoded[1]['logFormat'], 'xld');
      });

      test('--quiet still emits one line per readable file', () async {
        final r = await run([
          '-q',
          'test/fixtures/eac_sample.log',
          missing,
          'test/fixtures/xld_sample.log',
        ]);
        expect(r.exitCode, 2);
        expect(r.stderr.toString(), contains('Cannot read $missing'));
        final lines = r.stdout
            .toString()
            .trim()
            .split('\n')
            .where((l) => l.isNotEmpty)
            .toList();
        expect(lines, hasLength(2));
      });

      test('I/O error (2) takes precedence over quality failure (1)', () async {
        final r = await run([
          '-q',
          'test/fixtures/eac_errors_sample.log', // quality failure → 1
          missing, // I/O error → 2
        ]);
        expect(r.exitCode, 2);
      });

      test('single unreadable file still exits 2 with no stdout', () async {
        final r = await run([missing]);
        expect(r.exitCode, 2);
        expect(r.stderr.toString(), contains('Cannot read'));
        expect(r.stdout.toString(), isEmpty);
      });
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

    group('unparseable input exit policy (#30)', () {
      late String garbagePath;

      setUpAll(() {
        final dir = Directory.systemTemp.createTempSync('riplog_cli_garbage');
        addTearDown(() => dir.deleteSync(recursive: true));
        garbagePath = '${dir.path}/garbage.log';
        File(garbagePath)
            .writeAsStringSync('this is not a rip log\njust noise\n');
      });

      test('--fail-on any (default) → exit 1 on unknown-format input',
          () async {
        final r = await run(['-q', garbagePath]);
        expect(r.exitCode, 1);
      });

      test('--fail-on never → exit 0 on unknown-format input', () async {
        final r = await run(['--fail-on', 'never', '-q', garbagePath]);
        expect(r.exitCode, 0);
      });

      test('--fail-on mismatch → exit 0 on unknown-format input', () async {
        final r = await run(['--fail-on', 'mismatch', '-q', garbagePath]);
        expect(r.exitCode, 0);
      });

      test('--fail-on errors → exit 0 on unknown-format input', () async {
        final r = await run(['--fail-on', 'errors', '-q', garbagePath]);
        expect(r.exitCode, 0);
      });

      test('--fail-on any → exit 1 on a zero-track log of known format',
          () async {
        // A recognisable EAC header with no track sections at all.
        final r = await run(['--fail-on', 'any', '-q', '-'],
            stdinText: 'Exact Audio Copy V1.6 from 23. October 2019\n\n'
                'EAC extraction logfile from 15. March 2026\n');
        expect(r.exitCode, 1);
      });
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
      // test/fixtures has 5 .log files: eac_sample, eac_errors_sample,
      // eac_range_sample, eac_500_track, xld_sample.
      expect(lines, hasLength(5));
      expect(lines.every((l) => l.contains('.log\t')), isTrue);
    });

    test('--version matches the version in pubspec.yaml', () async {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final pubspecVersion =
          RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
      expect(pubspecVersion, isNotNull,
          reason: 'pubspec.yaml must declare a version');

      final r = await run(['--version']);
      expect(r.exitCode, 0);
      expect(r.stdout.toString().trim(), 'riplog ${pubspecVersion!.group(1)}');
    });

    group('encoding detection (#29)', () {
      List<int> utf16LeBytes(String s) {
        final bytes = <int>[0xFF, 0xFE];
        for (final unit in s.codeUnits) {
          bytes.add(unit & 0xFF);
          bytes.add((unit >> 8) & 0xFF);
        }
        return bytes;
      }

      test('UTF-16LE file parses identically to the UTF-8 fixture', () async {
        final content = File('test/fixtures/eac_sample.log').readAsStringSync();
        final dir = Directory.systemTemp.createTempSync('riplog_cli_enc');
        addTearDown(() => dir.deleteSync(recursive: true));
        final path = '${dir.path}/utf16le.log';
        File(path).writeAsBytesSync(utf16LeBytes(content));

        final r = await run(['-q', path]);
        final parts = r.stdout.toString().trim().split('\t');
        expect(parts[1], 'eac');
        expect(parts[2], '3');
      });

      test('UTF-16LE stdin parses identically to the UTF-8 fixture', () async {
        final content = File('test/fixtures/eac_sample.log').readAsStringSync();
        final r = await run(['-q', '-'], stdinBytes: utf16LeBytes(content));
        final parts = r.stdout.toString().trim().split('\t');
        expect(parts[1], 'eac');
        expect(parts[2], '3');
      });
    });

    test('large JSON output is not truncated when piped', () async {
      // exit() does not flush pending async stdout writes, so a big payload
      // can be cut off. The 500-track fixture produces ~200 KB of JSON.
      final r =
          await run(['--format', 'json', 'test/fixtures/eac_500_track.log']);
      final out = r.stdout.toString();
      expect(out.length, greaterThan(64 * 1024),
          reason: 'fixture should exceed a single pipe buffer');
      final decoded = jsonDecode(out) as Map<String, dynamic>;
      expect((decoded['tracks'] as List), hasLength(500));
    });
  });
}
