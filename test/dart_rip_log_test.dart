import 'dart:io';
import 'package:dart_rip_log/dart_rip_log.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Minimal inline log strings — no file I/O needed for unit tests
// ---------------------------------------------------------------------------

const _eacMinimal = '''
Exact Audio Copy V1.6 from 23. October 2019

EAC extraction logfile from 15. March 2026

Used drive            : ASUS BW-16D1HT   Adapter: 1   ID: 0

Read mode             : Secure
Read offset correction                      : 6
Overread into Lead-In and Lead-Out          : No
Gap handling                                : Appended to previous track

Track  1

     Filename C:\\Music\\TestAlbum\\01 - Track One.flac

     Peak level 96.2 %
     Track quality 99.8 %
     Test CRC 882B01BE
     Copy CRC 882B01BE
     Accurately ripped (confidence 1)  [F4E2268A]
     Copy OK


Track  2

     Filename C:\\Music\\TestAlbum\\02 - Track Two.flac

     Peak level 75.0 %
     Track quality 100.0 %
     Copy CRC AABBCCDD
     Cannot be verified as accurate  [12345678]
     Copy OK


Track  3

     Filename C:\\Music\\TestAlbum\\03 - Track Three.flac

     Peak level 80.5 %
     Track quality 98.5 %
     Copy CRC 11223344
     Track not present in AccurateRip database
     Copy OK


All tracks accurately ripped

End of status report

==== Log checksum ABCDEF1234567890ABCDEF1234567890 ====
''';

const _xldMinimal = '''
X Lossless Decoder version 20230916 (153.8)

XLD extraction logfile from 2026-03-15 12:34:56 +0900

Used drive        : PIONEER BD-RW BDR-212V (revision 1.04)
Read offset correction  : 6
Gap status              : Analyzed, Appended to previous track

Track 01
Filename : /Music/TestAlbum/01 - Track One.flac

CRC32 hash               : 882B01BE
AccurateRip v1 signature : F4E2268A
AccurateRip v2 signature : A1B2C3D4
->Accurately ripped (v1+v2, confidence 3/3)
Statistics
 Read error                           : 0
 Jitter error (maybe fixed)           : 0
 Damaged sector count                 : 0
 Peak level                           : 96.2 %
 Track quality                        : 100.0 %

Track 02
Filename : /Music/TestAlbum/02 - Track Two.flac

CRC32 hash               : AABBCCDD
AccurateRip v1 signature : F1F2F3F4
AccurateRip v2 signature : 0A0B0C0D
->NOT verified as accurate (total 3 results)
Statistics
 Read error                           : 2
 Jitter error (maybe fixed)           : 1
 Damaged sector count                 : 0
 Peak level                           : 75.3 %
 Track quality                        : 98.5 %
''';

void main() {
  // -------------------------------------------------------------------------
  // Format detection
  // -------------------------------------------------------------------------
  group('detectLogFormat', () {
    test('EAC log returns RipLogFormat.eac', () {
      expect(detectLogFormat(_eacMinimal), RipLogFormat.eac);
    });

    test('XLD log returns RipLogFormat.xld', () {
      expect(detectLogFormat(_xldMinimal), RipLogFormat.xld);
    });

    test('Unknown content returns RipLogFormat.unknown', () {
      expect(detectLogFormat('some random text'), RipLogFormat.unknown);
    });

    test('Empty string returns RipLogFormat.unknown', () {
      expect(detectLogFormat(''), RipLogFormat.unknown);
    });

    test('CUERipper log returns RipLogFormat.cueRipper', () {
      expect(detectLogFormat('CUERipper v2.1.7'), RipLogFormat.cueRipper);
    });

    test('Whipper log returns RipLogFormat.whipper', () {
      expect(detectLogFormat('Log created by: whipper 0.10.0'),
          RipLogFormat.whipper);
    });

    test('dBpoweramp log returns RipLogFormat.dbPoweramp', () {
      expect(detectLogFormat('dBpoweramp CD Ripper'), RipLogFormat.dbPoweramp);
    });
  });

  // -------------------------------------------------------------------------
  // EAC — header parsing
  // -------------------------------------------------------------------------
  group('EAC header parsing', () {
    late RipLog log;
    setUp(() => log = parseRipLog(_eacMinimal));

    test('log format is eac', () {
      expect(log.logFormat, RipLogFormat.eac);
    });

    test('tool version extracted', () {
      expect(log.toolVersion, 'V1.6');
    });

    test('extraction date parsed', () {
      expect(log.extractionDate, DateTime(2026, 3, 15));
    });

    test('drive name extracted', () {
      expect(log.drive, isNotNull);
      expect(log.drive!.name, contains('ASUS BW-16D1HT'));
    });

    test('read mode extracted', () {
      expect(log.readMode, 'Secure');
    });

    test('read offset extracted', () {
      expect(log.readOffset, 6);
    });

    test('overread extracted (No → false)', () {
      expect(log.overread, false);
    });

    test('gap handling extracted', () {
      expect(log.gapHandling, 'Appended to previous track');
    });
  });

  // -------------------------------------------------------------------------
  // EAC — track parsing
  // -------------------------------------------------------------------------
  group('EAC track parsing', () {
    late RipLog log;
    setUp(() => log = parseRipLog(_eacMinimal));

    test('three tracks parsed', () {
      expect(log.tracks, hasLength(3));
    });

    test('tracks are in order', () {
      expect(log.tracks.map((t) => t.trackNumber), [1, 2, 3]);
    });

    test('track 1: filename with backslash path', () {
      expect(log.tracks[0].filename,
          contains('01 - Track One.flac'));
    });

    test('track 1: peak level as fraction', () {
      expect(log.tracks[0].peakLevel, closeTo(0.962, 0.0001));
    });

    test('track 1: track quality as fraction', () {
      expect(log.tracks[0].trackQuality, closeTo(0.998, 0.0001));
    });

    test('track 1: copy CRC', () {
      expect(log.tracks[0].copyCrc, '882B01BE');
    });

    test('track 1: test CRC', () {
      expect(log.tracks[0].testCrc, '882B01BE');
    });

    test('track 1: AccurateRip verified', () {
      expect(log.tracks[0].accurateRipStatus, AccurateRipStatus.verified);
    });

    test('track 1: AccurateRip confidence', () {
      expect(log.tracks[0].accurateRipConfidence, 1);
    });

    test('track 1: AccurateRip CRC v1', () {
      expect(log.tracks[0].accurateRipCrcV1, 'F4E2268A');
    });

    test('track 1: Copy OK', () {
      expect(log.tracks[0].copyOk, isTrue);
    });

    test('track 1: log format is eac', () {
      expect(log.tracks[0].logFormat, RipLogFormat.eac);
    });

    test('track 2: AccurateRip mismatch', () {
      expect(log.tracks[1].accurateRipStatus, AccurateRipStatus.mismatch);
    });

    test('track 2: AccurateRip CRC v1 from mismatch line', () {
      expect(log.tracks[1].accurateRipCrcV1, '12345678');
    });

    test('track 3: AccurateRip not in database', () {
      expect(log.tracks[2].accurateRipStatus, AccurateRipStatus.notInDatabase);
    });
  });

  // -------------------------------------------------------------------------
  // EAC — footer parsing
  // -------------------------------------------------------------------------
  group('EAC footer parsing', () {
    late RipLog log;
    setUp(() => log = parseRipLog(_eacMinimal));

    test('accurateRipSummary extracted', () {
      expect(log.accurateRipSummary, 'All tracks accurately ripped');
    });

    test('integrityHash extracted', () {
      expect(log.integrityHash, 'ABCDEF1234567890ABCDEF1234567890');
    });
  });

  // -------------------------------------------------------------------------
  // EAC — test+copy mode
  // -------------------------------------------------------------------------
  group('EAC test+copy mode', () {
    const testCopyLog = '''
Exact Audio Copy V1.6 from 23. October 2019

EAC extraction logfile from 15. March 2026

Used drive : Some Drive

Track  1

     Filename C:\\Music\\track01.flac
     Peak level 90.0 %
     Track quality 99.9 %
     Test CRC DEADBEEF
     Copy CRC DEADBEEF
     Accurately ripped (confidence 2)  [CAFEBABE]
     Copy OK
''';

    test('test CRC and copy CRC both parsed', () {
      final log = parseRipLog(testCopyLog);
      expect(log.tracks[0].testCrc, 'DEADBEEF');
      expect(log.tracks[0].copyCrc, 'DEADBEEF');
    });
  });

  // -------------------------------------------------------------------------
  // EAC — error counts
  // -------------------------------------------------------------------------
  group('EAC error counts', () {
    const errorLog = '''
Exact Audio Copy V1.6 from 23. October 2019

EAC extraction logfile from 1. January 2025

Used drive : Bad Drive

Track  1

     Filename C:\\Music\\track01.flac
     Peak level 50.0 %
     Track quality 75.0 %
     Copy CRC FFFFFFFF
     Read error                         : 3
     Skip error                         : 1
     Edge jitter error (maybe fixed)    : 2
     Atom jitter error (maybe fixed)    : 0
     Drift error                        : 0
     Dropped bytes error                : 0
     Duplicated bytes error             : 0
     Inconsistency in error sectors     : 0
     Copy OK
''';

    test('read errors parsed', () {
      final log = parseRipLog(errorLog);
      expect(log.tracks[0].errors.readErrors, 3);
    });

    test('skip errors parsed', () {
      final log = parseRipLog(errorLog);
      expect(log.tracks[0].errors.skipErrors, 1);
    });

    test('edge jitter errors parsed', () {
      final log = parseRipLog(errorLog);
      expect(log.tracks[0].errors.edgeJitterErrors, 2);
    });

    test('hasErrors is true when errors present', () {
      final log = parseRipLog(errorLog);
      expect(log.tracks[0].errors.hasErrors, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // XLD — header parsing
  // -------------------------------------------------------------------------
  group('XLD header parsing', () {
    late RipLog log;
    setUp(() => log = parseRipLog(_xldMinimal));

    test('log format is xld', () {
      expect(log.logFormat, RipLogFormat.xld);
    });

    test('tool version extracted (with build number)', () {
      expect(log.toolVersion, '20230916 (153.8)');
    });

    test('extraction date parsed', () {
      expect(log.extractionDate?.year, 2026);
      expect(log.extractionDate?.month, 3);
      expect(log.extractionDate?.day, 15);
    });

    test('drive name extracted', () {
      expect(log.drive, isNotNull);
      expect(log.drive!.name, contains('PIONEER BD-RW BDR-212V'));
    });

    test('read offset extracted', () {
      expect(log.readOffset, 6);
    });

    test('gap handling extracted', () {
      expect(log.gapHandling, contains('Appended to previous track'));
    });
  });

  // -------------------------------------------------------------------------
  // XLD — track parsing
  // -------------------------------------------------------------------------
  group('XLD track parsing', () {
    late RipLog log;
    setUp(() => log = parseRipLog(_xldMinimal));

    test('two tracks parsed', () {
      expect(log.tracks, hasLength(2));
    });

    test('tracks are in order', () {
      expect(log.tracks.map((t) => t.trackNumber), [1, 2]);
    });

    test('track 1: filename with forward-slash path', () {
      expect(log.tracks[0].filename, contains('01 - Track One.flac'));
    });

    test('track 1: CRC32 hash', () {
      expect(log.tracks[0].copyCrc, '882B01BE');
    });

    test('track 1: AR v1 signature', () {
      expect(log.tracks[0].accurateRipCrcV1, 'F4E2268A');
    });

    test('track 1: AR v2 signature', () {
      expect(log.tracks[0].accurateRipCrcV2, 'A1B2C3D4');
    });

    test('track 1: AR verified', () {
      expect(log.tracks[0].accurateRipStatus, AccurateRipStatus.verified);
    });

    test('track 1: AR confidence', () {
      expect(log.tracks[0].accurateRipConfidence, 3);
    });

    test('track 1: statistics — read errors = 0', () {
      expect(log.tracks[0].errors.readErrors, 0);
    });

    test('track 1: statistics — jitter errors = 0', () {
      expect(log.tracks[0].errors.jitterErrors, 0);
    });

    test('track 1: statistics — damaged sectors = 0', () {
      expect(log.tracks[0].errors.damagedSectors, 0);
    });

    test('track 1: peak level from statistics block', () {
      expect(log.tracks[0].peakLevel, closeTo(0.962, 0.0001));
    });

    test('track 1: track quality from statistics block', () {
      expect(log.tracks[0].trackQuality, closeTo(1.0, 0.0001));
    });

    test('track 2: AR mismatch', () {
      expect(log.tracks[1].accurateRipStatus, AccurateRipStatus.mismatch);
    });

    test('track 2: statistics — read errors = 2', () {
      expect(log.tracks[1].errors.readErrors, 2);
    });

    test('track 2: statistics — jitter errors = 1', () {
      expect(log.tracks[1].errors.jitterErrors, 1);
    });

    test('track 2: log format is xld', () {
      expect(log.tracks[1].logFormat, RipLogFormat.xld);
    });
  });

  // -------------------------------------------------------------------------
  // XLD — AccurateRip status variants
  // -------------------------------------------------------------------------
  group('XLD AccurateRip status variants', () {
    RipLogTrack parseOneTrack(String arLine) {
      final content = '''
X Lossless Decoder version 20230916 (153.8)

XLD extraction logfile from 2026-01-01 00:00:00 +0900

Used drive : Some Drive

Track 01
Filename : /test.flac
CRC32 hash               : AAAAAAAA
AccurateRip v1 signature : 11111111
AccurateRip v2 signature : 22222222
$arLine
Statistics
 Read error                           : 0
 Peak level                           : 50.0 %
 Track quality                        : 99.0 %
''';
      return parseRipLog(content).tracks.first;
    }

    test('v1+v2 confidence 3/3 → verified, confidence 3', () {
      final t = parseOneTrack('->Accurately ripped (v1+v2, confidence 3/3)');
      expect(t.accurateRipStatus, AccurateRipStatus.verified);
      expect(t.accurateRipConfidence, 3);
    });

    test('v1 confidence 5/5 → verified, confidence 5', () {
      final t = parseOneTrack('->Accurately ripped (v1, confidence 5/5)');
      expect(t.accurateRipStatus, AccurateRipStatus.verified);
      expect(t.accurateRipConfidence, 5);
    });

    test('v2 confidence 2/4 → verified, confidence 2', () {
      final t = parseOneTrack('->Accurately ripped (v2, confidence 2/4)');
      expect(t.accurateRipStatus, AccurateRipStatus.verified);
      expect(t.accurateRipConfidence, 2);
    });

    test('NOT verified → mismatch', () {
      final t = parseOneTrack('->NOT verified as accurate (total 3 results)');
      expect(t.accurateRipStatus, AccurateRipStatus.mismatch);
    });

    test('not present in database → notInDatabase', () {
      final t = parseOneTrack('->Track not present in AccurateRip database');
      expect(t.accurateRipStatus, AccurateRipStatus.notInDatabase);
    });
  });

  // -------------------------------------------------------------------------
  // Convenience functions
  // -------------------------------------------------------------------------
  group('Convenience functions', () {
    test('isFullyVerified: all verified → true', () {
      final log = parseRipLog(_xldMinimal.replaceAll(
          '->NOT verified as accurate (total 3 results)',
          '->Accurately ripped (v1+v2, confidence 1/1)'));
      expect(isFullyVerified(log), isTrue);
    });

    test('isFullyVerified: one mismatch → false', () {
      expect(isFullyVerified(parseRipLog(_xldMinimal)), isFalse);
    });

    test('isFullyVerified: empty tracks → true', () {
      const unknown = 'X Lossless Decoder version 1.0\n\nXLD extraction logfile from 2026-01-01\n\nUsed drive : Drive A\n';
      final log = parseRipLog(unknown);
      expect(isFullyVerified(log), isTrue);
    });

    test('tracksWithErrors: returns tracks with errors', () {
      final log = parseRipLog(_xldMinimal);
      final errTracks = tracksWithErrors(log);
      expect(errTracks, hasLength(1));
      expect(errTracks.first.trackNumber, 2);
    });

    test('tracksWithErrors: none when no errors', () {
      final noErrLog = '''
X Lossless Decoder version 20230916 (153.8)

XLD extraction logfile from 2026-01-01 00:00:00 +0900
Used drive : D
Track 01
Filename : /a.flac
CRC32 hash : AABBCCDD
->Accurately ripped (v1+v2, confidence 1/1)
Statistics
 Read error : 0
 Jitter error (maybe fixed) : 0
 Damaged sector count : 0
 Peak level : 50.0 %
 Track quality : 99.0 %
''';
      final log = parseRipLog(noErrLog);
      expect(tracksWithErrors(log), isEmpty);
    });

    test('tracksWithArMismatch: returns mismatched tracks', () {
      final log = parseRipLog(_xldMinimal);
      final mismatched = tracksWithArMismatch(log);
      expect(mismatched, hasLength(1));
      expect(mismatched.first.trackNumber, 2);
    });

    test('tracksWithArMismatch: empty when none mismatched', () {
      final allVerified = _xldMinimal.replaceAll(
          '->NOT verified as accurate (total 3 results)',
          '->Accurately ripped (v1+v2, confidence 1/1)');
      expect(tracksWithArMismatch(parseRipLog(allVerified)), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Error tolerance
  // -------------------------------------------------------------------------
  group('Error tolerance', () {
    test('truncated log (header only, no tracks) → empty tracks list', () {
      const headerOnly = '''
Exact Audio Copy V1.6 from 23. October 2019

EAC extraction logfile from 15. March 2026

Used drive : ASUS BW-16D1HT
''';
      final log = parseRipLog(headerOnly);
      expect(log.tracks, isEmpty);
      expect(log.logFormat, RipLogFormat.eac);
    });

    test('missing fields → null, not failure', () {
      const sparse = '''
Exact Audio Copy V1.6 from 23. October 2019

EAC extraction logfile from 15. March 2026

Track  1

     Filename C:\\sparse.flac
     Copy OK
''';
      final log = parseRipLog(sparse);
      final t = log.tracks.first;
      expect(t.peakLevel, isNull);
      expect(t.trackQuality, isNull);
      expect(t.copyCrc, isNull);
    });

    test('garbled lines → skipped, no crash', () {
      const garbled = '''
Exact Audio Copy V1.6 from 23. October 2019

EAC extraction logfile from 15. March 2026

Track  1
     @@@@@@GARBAGE@@@@@@
     ???
     Filename C:\\test.flac
     Peak level 50.0 %
     Copy OK
''';
      expect(() => parseRipLog(garbled), returnsNormally);
    });

    test('CRLF line endings → parsed correctly', () {
      final crlf = _eacMinimal.replaceAll('\n', '\r\n');
      final log = parseRipLog(crlf);
      expect(log.tracks, hasLength(3));
      expect(log.toolVersion, 'V1.6');
    });

    test('LF line endings → parsed correctly', () {
      final log = parseRipLog(_eacMinimal);
      expect(log.tracks, hasLength(3));
    });

    test('mixed line endings → parsed correctly', () {
      // Mix CRLF in header, LF in tracks
      final mixed = _eacMinimal
          .split('\n')
          .take(10)
          .map((l) => '$l\r\n')
          .join() +
          _eacMinimal.split('\n').skip(10).join('\n');
      expect(() => parseRipLog(mixed), returnsNormally);
    });
  });

  // -------------------------------------------------------------------------
  // TrackErrors
  // -------------------------------------------------------------------------
  group('TrackErrors', () {
    test('default has no errors', () {
      const errors = TrackErrors();
      expect(errors.hasErrors, isFalse);
    });

    test('hasErrors true when readErrors > 0', () {
      const errors = TrackErrors(readErrors: 1);
      expect(errors.hasErrors, isTrue);
    });

    test('toJson includes all fields', () {
      const errors = TrackErrors(readErrors: 2, jitterErrors: 1);
      final json = errors.toJson();
      expect(json['readErrors'], 2);
      expect(json['jitterErrors'], 1);
      expect(json['hasErrors'], isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Serialisation
  // -------------------------------------------------------------------------
  group('Serialisation', () {
    test('toJson produces valid map with expected keys', () {
      final log = parseRipLog(_eacMinimal);
      final json = toJson(log);
      expect(json['logFormat'], 'eac');
      expect(json['toolVersion'], 'V1.6');
      expect(json['tracks'], isList);
      expect((json['tracks'] as List).length, 3);
    });

    test('toJson track has accurateRipStatus as string', () {
      final log = parseRipLog(_eacMinimal);
      final track = (toJson(log)['tracks'] as List).first as Map;
      expect(track['accurateRipStatus'], 'verified');
    });

    test('toJson extractionDate is ISO-8601 string', () {
      final log = parseRipLog(_eacMinimal);
      final json = toJson(log);
      expect(json['extractionDate'], isA<String>());
      expect(DateTime.tryParse(json['extractionDate'] as String), isNotNull);
    });

    test('RipLog.toJson and toJson() produce same result', () {
      final log = parseRipLog(_eacMinimal);
      expect(log.toJson(), equals(toJson(log)));
    });
  });

  // -------------------------------------------------------------------------
  // Integration tests — file I/O
  // -------------------------------------------------------------------------
  group('File I/O integration', () {
    test('parseRipLogFile reads EAC log from disk', () async {
      final path =
          '${Directory.current.path}/test/fixtures/eac_sample.log';
      if (!File(path).existsSync()) {
        // Skip if fixture is not available in this environment.
        return;
      }
      final log = await parseRipLogFile(path);
      expect(log.logFormat, RipLogFormat.eac);
      expect(log.tracks, isNotEmpty);
    });

    test('parseRipLogFile reads XLD log from disk', () async {
      final path =
          '${Directory.current.path}/test/fixtures/xld_sample.log';
      if (!File(path).existsSync()) {
        return;
      }
      final log = await parseRipLogFile(path);
      expect(log.logFormat, RipLogFormat.xld);
      expect(log.tracks, isNotEmpty);
    });

    test('parseRipLogFile throws for non-existent path', () async {
      expect(
        () => parseRipLogFile('/non/existent/file.log'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('parseRipLogFile using temp file round-trip', () async {
      final tmpDir = await Directory.systemTemp.createTemp('riplog_test_');
      final tmpFile = File('${tmpDir.path}/test.log');
      await tmpFile.writeAsString(_eacMinimal);
      try {
        final log = await parseRipLogFile(tmpFile.path);
        expect(log.logFormat, RipLogFormat.eac);
        expect(log.tracks, hasLength(3));
      } finally {
        await tmpDir.delete(recursive: true);
      }
    });
  });

  // -------------------------------------------------------------------------
  // Real-world fixture tests
  // -------------------------------------------------------------------------
  group('Real-world fixture logs', () {
    test('full EAC fixture: multi-track, mixed AR results', () {
      final path =
          '${Directory.current.path}/test/fixtures/eac_sample.log';
      if (!File(path).existsSync()) return;
      final content = File(path).readAsStringSync();
      final log = parseRipLog(content);
      expect(log.logFormat, RipLogFormat.eac);
      expect(log.tracks.length, greaterThanOrEqualTo(2));
    });

    test('full XLD fixture: multi-track, statistics blocks', () {
      final path =
          '${Directory.current.path}/test/fixtures/xld_sample.log';
      if (!File(path).existsSync()) return;
      final content = File(path).readAsStringSync();
      final log = parseRipLog(content);
      expect(log.logFormat, RipLogFormat.xld);
      expect(log.tracks.length, greaterThanOrEqualTo(1));
    });
  });
}
