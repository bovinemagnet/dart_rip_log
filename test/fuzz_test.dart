/// Property/fuzz tests for parser robustness (#21).
///
/// Feeds random slices, line deletions, and bit-flips of the real fixtures
/// to [parseRipLog] and asserts the "never throw on malformed content"
/// invariant: every mutation must yield a [RipLog] whose `toJson()` output
/// is JSON-encodable, without throwing.
///
/// All randomness is seeded so failures are reproducible; a failing input
/// is reported with its strategy, fixture, and iteration number.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dart_rip_log/dart_rip_log.dart';
import 'package:test/test.dart';

/// Deterministic seed — change only deliberately; failures reference it.
const _seed = 20260717;

/// Mutations per strategy per fixture.
const _iterations = 150;

/// Every `*.log` fixture, so a new format's fixture is fuzzed without
/// editing this file (#71).
final _fixtures = (Directory('test/fixtures')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((name) => name.endsWith('.log'))
        .toList()
      ..sort())
    .toList();

/// The tool signature line followed by a random contiguous slice of the
/// rest of [content].
///
/// Format detection needs the signature at the start of the input, so a
/// bare slice would almost never reach a parser (#65).
String _slice(String content, Random rng) {
  final split = content.indexOf('\n') + 1;
  final head = content.substring(0, split);
  final body = content.substring(split);
  if (body.isEmpty) return head;
  final a = rng.nextInt(body.length);
  final b = a + rng.nextInt(body.length - a + 1);
  return head + body.substring(a, b);
}

/// Delete up to 10 random lines from [content].
String _deleteLines(String content, Random rng) {
  final lines = const LineSplitter().convert(content);
  final deletions = 1 + rng.nextInt(10);
  for (var i = 0; i < deletions && lines.isNotEmpty; i++) {
    lines.removeAt(rng.nextInt(lines.length));
  }
  return lines.join('\n');
}

/// Flip a random bit in up to 10 random code units of [content].
String _bitFlip(String content, Random rng) {
  final units = content.codeUnits.toList();
  if (units.isEmpty) return content;
  final flips = 1 + rng.nextInt(10);
  for (var i = 0; i < flips; i++) {
    final pos = rng.nextInt(units.length);
    units[pos] = (units[pos] ^ (1 << rng.nextInt(16))) & 0xFFFF;
  }
  return String.fromCharCodes(units);
}

void main() {
  group('fuzz: parseRipLog never throws on', () {
    final strategies = <String, String Function(String, Random)>{
      'random slices': _slice,
      'random line deletions': _deleteLines,
      'random bit flips': _bitFlip,
    };

    test('fixture discovery finds every format', () {
      final formats = _fixtures
          .map((f) =>
              detectLogFormat(File('test/fixtures/$f').readAsStringSync()))
          .toSet();
      expect(
          formats,
          containsAll(
              RipLogFormat.values.toSet()..remove(RipLogFormat.unknown)));
    });

    for (final fixture in _fixtures) {
      test('random slices of $fixture reach the parser', () {
        // A slice that loses the signature line only exercises
        // detectLogFormat, never a parser (#65).
        final content = File('test/fixtures/$fixture').readAsStringSync();
        final format = detectLogFormat(content);
        final rng = Random(_seed);
        for (var i = 0; i < _iterations; i++) {
          expect(detectLogFormat(_slice(content, rng)), format,
              reason: 'iteration $i, seed $_seed');
        }
      });

      for (final entry in strategies.entries) {
        test('${entry.key} of $fixture', () {
          final content = File('test/fixtures/$fixture').readAsStringSync();
          final rng = Random(_seed);
          for (var i = 0; i < _iterations; i++) {
            final mutated = entry.value(content, rng);
            late RipLog log;
            expect(
              () => log = parseRipLog(mutated),
              returnsNormally,
              reason: 'strategy "${entry.key}", fixture $fixture, '
                  'iteration $i, seed $_seed',
            );
            expect(
              () => jsonEncode(log.toJson()),
              returnsNormally,
              reason: 'toJson after strategy "${entry.key}", '
                  'fixture $fixture, iteration $i, seed $_seed',
            );
          }
        });
      }
    }
  });
}
