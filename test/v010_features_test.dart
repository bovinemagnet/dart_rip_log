import 'dart:io';

import 'package:dart_rip_log/dart_rip_log.dart';
import 'package:test/test.dart';

void main() {
  // -------------------------------------------------------------------------
  // LogSource lineage
  // -------------------------------------------------------------------------
  group('LogSource', () {
    test('parseRipLogFile attaches a LogSource', () async {
      final log = await parseRipLogFile('test/fixtures/eac_sample.log');
      expect(log.source, isNotNull);
      expect(log.source!.byteSize, greaterThan(0));
      expect(log.source!.lineCount, greaterThan(0));
      expect(log.source!.parserName, 'eac');
      expect(log.source!.parsedAt.isUtc, isTrue);
    });

    test('parseRipLog (string) does not attach a source', () {
      final log =
          parseRipLog(File('test/fixtures/eac_sample.log').readAsStringSync());
      expect(log.source, isNull);
    });

    test('withSource returns a copy with the given source', () {
      const base = RipLog(logFormat: RipLogFormat.eac);
      final src = LogSource(
        byteSize: 100,
        lineCount: 5,
        parserName: 'eac',
        parsedAt: DateTime.utc(2026, 1, 1),
      );
      final withSrc = base.withSource(src);
      expect(withSrc.source, src);
      expect(base.source, isNull);
    });

    test('LogSource round-trips through JSON', () {
      final src = LogSource(
        byteSize: 1024,
        lineCount: 42,
        parserName: 'xld',
        parsedAt: DateTime.utc(2026, 6, 15, 12, 30),
      );
      final round = LogSource.fromJson(src.toJson());
      expect(round, equals(src));
    });

    test('source is ignored by compareRipLogs', () {
      const base = RipLog(logFormat: RipLogFormat.eac);
      final a = base.withSource(LogSource(
          byteSize: 1,
          lineCount: 1,
          parserName: 'eac',
          parsedAt: DateTime.utc(2026, 1, 1)));
      final b = base.withSource(LogSource(
          byteSize: 9999,
          lineCount: 9999,
          parserName: 'xld',
          parsedAt: DateTime.utc(2027, 5, 5)));
      expect(compareRipLogs(a, b).isEmpty, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Track timing
  // -------------------------------------------------------------------------
  group('Track timing', () {
    test('startSector / lengthSectors / durationSeconds serialise when set',
        () {
      const t = RipLogTrack(
        trackNumber: 1,
        startSector: 150,
        lengthSectors: 22350,
        durationSeconds: 298.0,
      );
      final json = t.toJson();
      expect(json['startSector'], 150);
      expect(json['lengthSectors'], 22350);
      expect(json['durationSeconds'], 298.0);
      final round = RipLogTrack.fromJson(json);
      expect(round, equals(t));
    });

    test('timing fields are omitted from JSON when null', () {
      const t = RipLogTrack(trackNumber: 1);
      final json = t.toJson();
      expect(json.containsKey('startSector'), isFalse);
      expect(json.containsKey('lengthSectors'), isFalse);
      expect(json.containsKey('durationSeconds'), isFalse);
    });

    test('compareRipLogs reports timing field changes', () {
      const a = RipLog(
        logFormat: RipLogFormat.eac,
        tracks: [RipLogTrack(trackNumber: 1, lengthSectors: 1000)],
      );
      const b = RipLog(
        logFormat: RipLogFormat.eac,
        tracks: [RipLogTrack(trackNumber: 1, lengthSectors: 2000)],
      );
      final diff = compareRipLogs(a, b);
      expect(diff.entries, hasLength(1));
      expect(diff.entries.first.path, 'tracks[1].lengthSectors');
    });
  });

  // -------------------------------------------------------------------------
  // RipLogQuality aggregate
  // -------------------------------------------------------------------------
  group('RipLogQuality', () {
    test('empty tracks → unknown', () {
      const log = RipLog(logFormat: RipLogFormat.eac);
      expect(log.quality, RipLogQuality.unknown);
    });

    test('all tracks verified → allVerified', () {
      const log = RipLog(
        logFormat: RipLogFormat.eac,
        tracks: [
          RipLogTrack(
              trackNumber: 1, accurateRipStatus: AccurateRipStatus.verified),
          RipLogTrack(
              trackNumber: 2, accurateRipStatus: AccurateRipStatus.verified),
        ],
      );
      expect(log.quality, RipLogQuality.allVerified);
    });

    test('some verified, some notInDatabase → partiallyVerified', () {
      const log = RipLog(
        logFormat: RipLogFormat.eac,
        tracks: [
          RipLogTrack(
              trackNumber: 1, accurateRipStatus: AccurateRipStatus.verified),
          RipLogTrack(
              trackNumber: 2,
              accurateRipStatus: AccurateRipStatus.notInDatabase),
        ],
      );
      expect(log.quality, RipLogQuality.partiallyVerified);
    });

    test('any mismatch → mismatches', () {
      const log = RipLog(
        logFormat: RipLogFormat.eac,
        tracks: [
          RipLogTrack(
              trackNumber: 1, accurateRipStatus: AccurateRipStatus.verified),
          RipLogTrack(
              trackNumber: 2, accurateRipStatus: AccurateRipStatus.mismatch),
        ],
      );
      expect(log.quality, RipLogQuality.mismatches);
    });

    test('any error count wins over mismatch → errors', () {
      const log = RipLog(
        logFormat: RipLogFormat.eac,
        tracks: [
          RipLogTrack(
              trackNumber: 1, accurateRipStatus: AccurateRipStatus.mismatch),
          RipLogTrack(
              trackNumber: 2,
              accurateRipStatus: AccurateRipStatus.verified,
              errors: TrackErrors(readErrors: 5)),
        ],
      );
      expect(log.quality, RipLogQuality.errors);
    });

    test('real fixtures have expected quality', () {
      final eac =
          parseRipLog(File('test/fixtures/eac_sample.log').readAsStringSync());
      expect(eac.quality, RipLogQuality.mismatches);

      final withErrors = parseRipLog(
          File('test/fixtures/eac_errors_sample.log').readAsStringSync());
      expect(withErrors.quality, RipLogQuality.errors);
    });

    test('quality is emitted in toJson output', () {
      const log = RipLog(
        logFormat: RipLogFormat.eac,
        tracks: [
          RipLogTrack(
              trackNumber: 1, accurateRipStatus: AccurateRipStatus.verified),
        ],
      );
      expect(log.toJson()['quality'], 'allVerified');
    });
  });
}
