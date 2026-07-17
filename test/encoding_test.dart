import 'dart:convert';
import 'dart:io';

import 'package:dart_rip_log/dart_rip_log.dart';
import 'package:test/test.dart';

/// Encoding-detection tests (#29): real EAC logs are UTF-16LE with a BOM.
/// `parseRipLogFile` must sniff the BOM and decode UTF-16LE, UTF-16BE and
/// UTF-8-with-BOM identically to plain UTF-8, and fall back to Latin-1
/// rather than throwing on non-UTF-8 bytes.
void main() {
  late Directory tempDir;
  late String asciiContent;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('riplog_encoding_test');
    asciiContent = File('test/fixtures/eac_sample.log').readAsStringSync();
  });

  tearDownAll(() {
    tempDir.deleteSync(recursive: true);
  });

  List<int> utf16LeBytes(String s, {bool bom = true}) {
    final bytes = <int>[if (bom) 0xFF, if (bom) 0xFE];
    for (final unit in s.codeUnits) {
      bytes.add(unit & 0xFF);
      bytes.add((unit >> 8) & 0xFF);
    }
    return bytes;
  }

  List<int> utf16BeBytes(String s) {
    final bytes = <int>[0xFE, 0xFF];
    for (final unit in s.codeUnits) {
      bytes.add((unit >> 8) & 0xFF);
      bytes.add(unit & 0xFF);
    }
    return bytes;
  }

  Future<String> writeTemp(String name, List<int> bytes) async {
    final path = '${tempDir.path}/$name';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  /// toJson with the run-dependent `source` block removed, so parses of
  /// the same content via different encodings compare equal.
  Map<String, dynamic> jsonWithoutSource(RipLog log) =>
      toJson(log)..remove('source');

  group('parseRipLogFile encoding detection', () {
    late Map<String, dynamic> expected;

    setUpAll(() async {
      final asciiPath = await writeTemp('ascii.log', utf8.encode(asciiContent));
      expected = jsonWithoutSource(await parseRipLogFile(asciiPath));
      // Sanity: the reference parse must be a real EAC parse.
      expect(expected['logFormat'], 'eac');
    });

    test('UTF-16LE with BOM parses identically to UTF-8', () async {
      final path = await writeTemp('utf16le.log', utf16LeBytes(asciiContent));
      final log = await parseRipLogFile(path);
      expect(jsonWithoutSource(log), equals(expected));
    });

    test('UTF-16BE with BOM parses identically to UTF-8', () async {
      final path = await writeTemp('utf16be.log', utf16BeBytes(asciiContent));
      final log = await parseRipLogFile(path);
      expect(jsonWithoutSource(log), equals(expected));
    });

    test(
        'UTF-8 with BOM parses identically and BOM does not break '
        'format detection', () async {
      final path = await writeTemp(
          'utf8bom.log', [0xEF, 0xBB, 0xBF, ...utf8.encode(asciiContent)]);
      final log = await parseRipLogFile(path);
      expect(log.logFormat, RipLogFormat.eac);
      expect(jsonWithoutSource(log), equals(expected));
    });

    test('non-UTF-8 bytes fall back to Latin-1 instead of throwing', () async {
      // 0xE9 is é in Latin-1 but an invalid standalone byte in UTF-8.
      final content = asciiContent.replaceFirst('Test Artist', 'Beyoncé');
      final bytes = latin1.encode(content);
      final path = await writeTemp('latin1.log', bytes);
      final log = await parseRipLogFile(path);
      expect(log.logFormat, RipLogFormat.eac);
      expect(log.tracks, hasLength(3));
    });
  });
}
