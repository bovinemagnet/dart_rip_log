import 'dart:io';

import 'package:dart_rip_log/dart_rip_log.dart';
import 'package:test/test.dart';

void main() {
  const fixtures = [
    'eac_sample',
    'eac_errors_sample',
    'eac_range_sample',
    'xld_sample',
  ];

  group('fromJson round-trip', () {
    for (final name in fixtures) {
      test('$name: fromJson(toJson(log)) == log', () {
        final path = 'test/fixtures/$name.log';
        if (!File(path).existsSync()) return;
        final log = parseRipLog(File(path).readAsStringSync());
        final roundTripped = RipLog.fromJson(log.toJson());
        expect(roundTripped, equals(log));
        expect(roundTripped.hashCode, log.hashCode);
      });
    }

    test('unknown enum values degrade gracefully', () {
      final json = {
        'logFormat': 'some_future_format',
        'tracks': [
          {
            'trackNumber': 1,
            'accurateRipStatus': 'some_new_state',
            'copyOk': true,
            'errors': <String, dynamic>{},
            'logFormat': 'whatever',
          }
        ],
        'errors': <String>[],
      };
      final log = RipLog.fromJson(json);
      expect(log.logFormat, RipLogFormat.unknown);
      expect(log.tracks.first.accurateRipStatus, AccurateRipStatus.notChecked);
      expect(log.tracks.first.logFormat, RipLogFormat.unknown);
    });

    test('partial errors map tolerated', () {
      final errors = TrackErrors.fromJson({'readErrors': 4, 'jitterErrors': 2});
      expect(errors.readErrors, 4);
      expect(errors.jitterErrors, 2);
      expect(errors.damagedSectors, 0);
      expect(errors.hasErrors, isTrue);
    });
  });

  group('equality', () {
    test('identical parses of same log are equal', () {
      final content = File('test/fixtures/eac_sample.log').readAsStringSync();
      expect(parseRipLog(content), equals(parseRipLog(content)));
      expect(parseRipLog(content).hashCode, parseRipLog(content).hashCode);
    });

    test('different logs are not equal', () {
      final eac =
          parseRipLog(File('test/fixtures/eac_sample.log').readAsStringSync());
      final xld =
          parseRipLog(File('test/fixtures/xld_sample.log').readAsStringSync());
      expect(eac, isNot(equals(xld)));
    });

    test('RipLogTrack equality is field-wise', () {
      const a = RipLogTrack(trackNumber: 1, copyCrc: 'AAAA');
      const b = RipLogTrack(trackNumber: 1, copyCrc: 'AAAA');
      const c = RipLogTrack(trackNumber: 1, copyCrc: 'BBBB');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('TrackErrors and DriveInfo equality', () {
      expect(const TrackErrors(readErrors: 1),
          equals(const TrackErrors(readErrors: 1)));
      expect(const DriveInfo(name: 'X', readOffset: 6),
          equals(const DriveInfo(name: 'X', readOffset: 6)));
    });
  });

  group('compareRipLogs', () {
    RipLog load(String name) =>
        parseRipLog(File('test/fixtures/$name.log').readAsStringSync());

    test('identical log compares as empty diff', () {
      final a = load('eac_sample');
      final b = load('eac_sample');
      final diff = compareRipLogs(a, b);
      expect(diff.isEmpty, isTrue);
      expect(diff.trackDifferences, isEmpty);
      expect(diff.headerDifferences, isEmpty);
    });

    test('different logs produce populated diff', () {
      final diff = compareRipLogs(load('eac_sample'), load('xld_sample'));
      expect(diff.isNotEmpty, isTrue);
      expect(diff.headerDifferences, isNotEmpty);
      // Different track counts → at least one trackAdded/trackRemoved.
      expect(
          diff.entries.any((e) =>
              e.kind == RipLogDiffKind.trackAdded ||
              e.kind == RipLogDiffKind.trackRemoved),
          isTrue);
    });

    test('track CRC change reported at tracks[N].copyCrc', () {
      const a = RipLog(
        logFormat: RipLogFormat.eac,
        tracks: [RipLogTrack(trackNumber: 1, copyCrc: 'AAAA')],
      );
      const b = RipLog(
        logFormat: RipLogFormat.eac,
        tracks: [RipLogTrack(trackNumber: 1, copyCrc: 'BBBB')],
      );
      final diff = compareRipLogs(a, b);
      expect(diff.entries, hasLength(1));
      expect(diff.entries.first.path, 'tracks[1].copyCrc');
      expect(diff.entries.first.kind, RipLogDiffKind.changed);
      expect(diff.entries.first.left, 'AAAA');
      expect(diff.entries.first.right, 'BBBB');
    });

    test('track on only one side → trackAdded / trackRemoved', () {
      const a = RipLog(
          logFormat: RipLogFormat.eac, tracks: [RipLogTrack(trackNumber: 1)]);
      const b = RipLog(
        logFormat: RipLogFormat.eac,
        tracks: [RipLogTrack(trackNumber: 1), RipLogTrack(trackNumber: 2)],
      );
      final diff = compareRipLogs(a, b);
      expect(diff.entries, hasLength(1));
      expect(diff.entries.first.path, 'tracks[2]');
      expect(diff.entries.first.kind, RipLogDiffKind.trackAdded);
    });

    test('error-count change reported', () {
      const a = RipLog(
        logFormat: RipLogFormat.eac,
        tracks: [
          RipLogTrack(trackNumber: 1, errors: TrackErrors(readErrors: 0)),
        ],
      );
      const b = RipLog(
        logFormat: RipLogFormat.eac,
        tracks: [
          RipLogTrack(trackNumber: 1, errors: TrackErrors(readErrors: 3)),
        ],
      );
      final diff = compareRipLogs(a, b);
      expect(diff.entries, hasLength(1));
      expect(diff.entries.first.path, 'tracks[1].errors.readErrors');
      expect(diff.entries.first.left, 0);
      expect(diff.entries.first.right, 3);
    });

    test('parser warnings in RipLog.errors are ignored', () {
      const a = RipLog(logFormat: RipLogFormat.eac, errors: ['warning A']);
      const b = RipLog(logFormat: RipLogFormat.eac, errors: ['warning B']);
      expect(compareRipLogs(a, b).isEmpty, isTrue);
    });
  });
}
