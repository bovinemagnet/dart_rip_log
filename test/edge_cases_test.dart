import 'dart:io';

import 'package:dart_rip_log/dart_rip_log.dart';
import 'package:test/test.dart';

void main() {
  // -------------------------------------------------------------------------
  // XLD edge cases
  // -------------------------------------------------------------------------
  group('XLD edge cases', () {
    test('no AccurateRip block → status notChecked', () {
      const log = '''
X Lossless Decoder version 20230916 (153.8)

XLD extraction logfile from 2026-01-01 00:00:00 +0900

Used drive : Some Drive

Track 01
Filename : /test.flac
CRC32 hash               : AAAAAAAA
Statistics
 Read error                           : 0
 Peak level                           : 50.0 %
 Track quality                        : 99.0 %
''';
      final t = parseRipLog(log).tracks.first;
      expect(t.accurateRipStatus, AccurateRipStatus.notChecked);
      expect(t.accurateRipCrcV1, isNull);
      expect(t.accurateRipCrcV2, isNull);
    });

    test('AR v1-only (no v2 signature line) → v2 CRC null', () {
      const log = '''
X Lossless Decoder version 20230916 (153.8)

XLD extraction logfile from 2026-01-01 00:00:00 +0900

Used drive : Some Drive

Track 01
Filename : /test.flac
CRC32 hash               : AAAAAAAA
AccurateRip v1 signature : F4E2268A
->Accurately ripped (v1, confidence 5/5)
Statistics
 Read error                           : 0
 Peak level                           : 50.0 %
 Track quality                        : 99.0 %
''';
      final t = parseRipLog(log).tracks.first;
      expect(t.accurateRipCrcV1, 'F4E2268A');
      expect(t.accurateRipCrcV2, isNull);
      expect(t.accurateRipConfidence, 5);
    });

    test('Statistics in unusual order → all still captured', () {
      const log = '''
X Lossless Decoder version 20230916 (153.8)

XLD extraction logfile from 2026-01-01 00:00:00 +0900

Used drive : Some Drive

Track 01
Filename : /test.flac
CRC32 hash               : AAAAAAAA
AccurateRip v1 signature : F4E2268A
AccurateRip v2 signature : BBBBBBBB
->Accurately ripped (v1+v2, confidence 3/3)
Statistics
 Track quality                        : 99.0 %
 Peak level                           : 42.0 %
 Damaged sector count                 : 7
 Jitter error (maybe fixed)           : 2
 Read error                           : 1
''';
      final t = parseRipLog(log).tracks.first;
      expect(t.peakLevel, closeTo(0.42, 0.0001));
      expect(t.trackQuality, closeTo(0.99, 0.0001));
      expect(t.errors.readErrors, 1);
      expect(t.errors.jitterErrors, 2);
      expect(t.errors.damagedSectors, 7);
    });

    test('multiple tracks with mixed AR states parse independently', () {
      const log = '''
X Lossless Decoder version 20230916 (153.8)

XLD extraction logfile from 2026-01-01 00:00:00 +0900

Used drive : Some Drive

Track 01
Filename : /a.flac
CRC32 hash               : 11111111
->Accurately ripped (v2, confidence 2/4)
Statistics
 Read error : 0
 Peak level : 50.0 %
 Track quality : 99.0 %

Track 02
Filename : /b.flac
CRC32 hash               : 22222222
->Track not present in AccurateRip database
Statistics
 Read error : 0
 Peak level : 50.0 %
 Track quality : 99.0 %

Track 03
Filename : /c.flac
CRC32 hash               : 33333333
->NOT verified as accurate (total 1 results)
Statistics
 Read error : 0
 Peak level : 50.0 %
 Track quality : 99.0 %
''';
      final tracks = parseRipLog(log).tracks;
      expect(tracks, hasLength(3));
      expect(tracks[0].accurateRipStatus, AccurateRipStatus.verified);
      expect(tracks[0].accurateRipConfidence, 2);
      expect(tracks[1].accurateRipStatus, AccurateRipStatus.notInDatabase);
      expect(tracks[2].accurateRipStatus, AccurateRipStatus.mismatch);
    });
  });

  // -------------------------------------------------------------------------
  // EAC edge cases
  // -------------------------------------------------------------------------
  group('EAC edge cases', () {
    test('multi-word read mode preserved', () {
      const log = '''
Exact Audio Copy V1.6 from 23. October 2019

EAC extraction logfile from 15. March 2026

Used drive : Some Drive

Read mode             : Secure with NO C2, accurate stream, disable cache

Track  1

     Filename C:\\x.flac
     Copy CRC DEADBEEF
     Copy OK
''';
      final r = parseRipLog(log);
      expect(r.readMode, 'Secure with NO C2, accurate stream, disable cache');
    });

    test('AccurateRip line appearing before Copy CRC still captured', () {
      const log = '''
Exact Audio Copy V1.6 from 23. October 2019

EAC extraction logfile from 15. March 2026

Used drive : Some Drive

Track  1

     Filename C:\\x.flac
     Peak level 50.0 %
     Accurately ripped (confidence 1)  [F4E2268A]
     Copy CRC DEADBEEF
     Copy OK
''';
      final t = parseRipLog(log).tracks.first;
      expect(t.accurateRipStatus, AccurateRipStatus.verified);
      expect(t.accurateRipCrcV1, 'F4E2268A');
      expect(t.copyCrc, 'DEADBEEF');
    });

    test('German month name in date is parsed', () {
      const log = '''
Exact Audio Copy V1.6 from 23. October 2019

EAC extraction logfile from 15. Oktober 2026

Used drive : Some Drive

Track  1

     Filename C:\\x.flac
     Copy OK
''';
      final r = parseRipLog(log);
      expect(r.extractionDate, DateTime(2026, 10, 15));
    });

    test('French month name in date is parsed', () {
      const log = '''
Exact Audio Copy V1.6 from 23. October 2019

EAC extraction logfile from 3. Octobre 2026

Used drive : Some Drive
''';
      expect(parseRipLog(log).extractionDate, DateTime(2026, 10, 3));
    });

    test('Spanish month name in date is parsed', () {
      const log = '''
Exact Audio Copy V1.6 from 23. October 2019

EAC extraction logfile from 7. Diciembre 2026

Used drive : Some Drive
''';
      expect(parseRipLog(log).extractionDate, DateTime(2026, 12, 7));
    });

    test('AR confidence with multi-digit number', () {
      const log = '''
Exact Audio Copy V1.6 from 23. October 2019

EAC extraction logfile from 15. March 2026

Used drive : Some Drive

Track  1

     Filename C:\\x.flac
     Copy CRC DEADBEEF
     Accurately ripped (confidence 142)  [F4E2268A]
     Copy OK
''';
      final t = parseRipLog(log).tracks.first;
      expect(t.accurateRipConfidence, 142);
    });

    test('testAndCopy true when any track has a test CRC', () {
      const log = '''
Exact Audio Copy V1.6 from 23. October 2019

EAC extraction logfile from 15. March 2026

Used drive : Some Drive

Track  1

     Filename C:\\x.flac
     Test CRC DEADBEEF
     Copy CRC DEADBEEF
     Copy OK
''';
      expect(parseRipLog(log).testAndCopy, isTrue);
    });

    test('testAndCopy false when tracks exist but no test CRC', () {
      const log = '''
Exact Audio Copy V1.6 from 23. October 2019

EAC extraction logfile from 15. March 2026

Used drive : Some Drive

Track  1

     Filename C:\\x.flac
     Copy CRC DEADBEEF
     Copy OK
''';
      expect(parseRipLog(log).testAndCopy, isFalse);
    });

    test('testAndCopy null when no tracks parsed', () {
      const log = '''
Exact Audio Copy V1.6 from 23. October 2019

EAC extraction logfile from 15. March 2026

Used drive : Some Drive
''';
      expect(parseRipLog(log).testAndCopy, isNull);
    });

    test('negative read offset captured', () {
      const log = '''
Exact Audio Copy V1.6 from 23. October 2019

EAC extraction logfile from 15. March 2026

Used drive : Some Drive

Read offset correction                      : -48
''';
      expect(parseRipLog(log).readOffset, -48);
    });
  });

  // -------------------------------------------------------------------------
  // XLD AccurateRip summary block
  // -------------------------------------------------------------------------
  group('XLD AccurateRip summary', () {
    test('DiscID on "AccurateRip Summary" line is captured', () {
      const log = '''
X Lossless Decoder version 20230916 (153.8)

XLD extraction logfile from 2026-01-01 00:00:00 +0900

Used drive : Some Drive

AccurateRip Summary (DiscID: 001a2b3c-001e4f5a-000c7b8d)
  Track 01 : OK (confidence 12)
  Total submissions: 42

Track 01
Filename : /a.flac
CRC32 hash               : AAAAAAAA
->Accurately ripped (v1+v2, confidence 12/12)
Statistics
 Read error : 0
 Peak level : 50.0 %
 Track quality : 99.0 %
''';
      final r = parseRipLog(log);
      expect(r.accurateRipDiscId, '001a2b3c-001e4f5a-000c7b8d');
      expect(r.accurateRipTotalSubmissions, 42);
    });

    test('Missing AR summary → null disc ID and submissions', () {
      const log = '''
X Lossless Decoder version 20230916 (153.8)

XLD extraction logfile from 2026-01-01 00:00:00 +0900

Used drive : Some Drive

Track 01
Filename : /a.flac
CRC32 hash : AAAAAAAA
''';
      final r = parseRipLog(log);
      expect(r.accurateRipDiscId, isNull);
      expect(r.accurateRipTotalSubmissions, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Unicode filenames
  // -------------------------------------------------------------------------
  group('Unicode filenames', () {
    String buildEacFixture(String filename) => '''
Exact Audio Copy V1.6 from 23. October 2019

EAC extraction logfile from 15. March 2026

Used drive : Some Drive

Track  1

     Filename $filename
     Peak level 50.0 %
     Copy CRC DEADBEEF
     Copy OK
''';

    test('accented Latin filename preserved', () {
      final path = r'C:\Music\Björk\Jóga.flac';
      final t = parseRipLog(buildEacFixture(path)).tracks.first;
      expect(t.filename, path);
    });

    test('CJK filename preserved', () {
      const path = '/音楽/坂本龍一/戦場のメリークリスマス.flac';
      final t = parseRipLog(buildEacFixture(path)).tracks.first;
      expect(t.filename, path);
    });

    test('emoji filename preserved', () {
      const path = '/music/🎵 the track 🎶.flac';
      final t = parseRipLog(buildEacFixture(path)).tracks.first;
      expect(t.filename, path);
    });

    test('XLD Unicode filename preserved', () {
      const path = '/Musique/Éléphant/café.flac';
      const log = '''
X Lossless Decoder version 20230916 (153.8)

XLD extraction logfile from 2026-01-01 00:00:00 +0900

Used drive : Some Drive

Track 01
Filename : /Musique/Éléphant/café.flac
CRC32 hash               : AAAAAAAA
->Accurately ripped (v1+v2, confidence 1/1)
Statistics
 Read error : 0
 Peak level : 50.0 %
 Track quality : 99.0 %
''';
      final t = parseRipLog(log).tracks.first;
      expect(t.filename, path);
    });

    test('BOM at start of file does not break detection', () {
      final bom = '\uFEFF';
      final content = '${bom}Exact Audio Copy V1.6 from 23. October 2019\n'
          'Track  1\n     Filename x.flac\n     Copy OK\n';
      final r = parseRipLog(content);
      expect(r.logFormat, RipLogFormat.eac);
      expect(r.tracks, hasLength(1));
    });
  });

  // -------------------------------------------------------------------------
  // Performance smoke
  // -------------------------------------------------------------------------
  group('Performance', () {
    test('500-track EAC log parses in under 1 second', () {
      final buf = StringBuffer()
        ..writeln('Exact Audio Copy V1.6 from 23. October 2019')
        ..writeln('')
        ..writeln('EAC extraction logfile from 15. March 2026')
        ..writeln('')
        ..writeln('Used drive : Some Drive')
        ..writeln('');
      for (var i = 1; i <= 500; i++) {
        buf
          ..writeln('Track  $i')
          ..writeln('')
          ..writeln('     Filename C:\\track_$i.flac')
          ..writeln('     Peak level 90.0 %')
          ..writeln('     Track quality 99.9 %')
          ..writeln(
              '     Copy CRC ${i.toRadixString(16).padLeft(8, '0').toUpperCase()}')
          ..writeln('     Accurately ripped (confidence 1)  [AAAAAAAA]')
          ..writeln('     Copy OK')
          ..writeln('');
      }
      buf.writeln('All tracks accurately ripped');

      final sw = Stopwatch()..start();
      final log = parseRipLog(buf.toString());
      sw.stop();

      expect(log.tracks, hasLength(500));
      expect(sw.elapsedMilliseconds, lessThan(1000),
          reason: 'Parsing 500 tracks should comfortably be <1s; '
              'regression indicates O(n^2) or similar.');
    });
  });

  // -------------------------------------------------------------------------
  // Convenience edge cases
  // -------------------------------------------------------------------------
  group('Convenience edge cases', () {
    test('isFullyVerified on empty RipLog → true', () {
      const log = RipLog(logFormat: RipLogFormat.unknown);
      expect(isFullyVerified(log), isTrue);
    });

    test('isFullyVerified on notChecked-only track → false', () {
      const log = RipLog(
        logFormat: RipLogFormat.eac,
        tracks: [RipLogTrack(trackNumber: 1)],
      );
      expect(isFullyVerified(log), isFalse);
    });

    test('isFullyVerified on notInDatabase track → false', () {
      const log = RipLog(
        logFormat: RipLogFormat.eac,
        tracks: [
          RipLogTrack(
              trackNumber: 1,
              accurateRipStatus: AccurateRipStatus.notInDatabase),
        ],
      );
      expect(isFullyVerified(log), isFalse);
    });

    test('tracksWithErrors on empty log → empty', () {
      const log = RipLog(logFormat: RipLogFormat.unknown);
      expect(tracksWithErrors(log), isEmpty);
    });

    test('tracksWithArMismatch on empty log → empty', () {
      const log = RipLog(logFormat: RipLogFormat.unknown);
      expect(tracksWithArMismatch(log), isEmpty);
    });

    test('toJson on unknown-format log is still valid JSON-compatible', () {
      const log = RipLog(logFormat: RipLogFormat.unknown);
      final json = toJson(log);
      expect(json['logFormat'], 'unknown');
      expect(json['tracks'], isEmpty);
      expect(
          () => File.fromUri(Uri.parse('file:///dev/null')), returnsNormally);
    });

    test('RipLogTrack default log format is unknown', () {
      const t = RipLogTrack(trackNumber: 1);
      expect(t.logFormat, RipLogFormat.unknown);
      expect(t.errors.hasErrors, isFalse);
      expect(t.copyOk, isFalse);
    });
  });
}
