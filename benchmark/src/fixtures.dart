import 'dart:io';

/// The three fixture inputs the benchmark harness measures against.
///
/// Paths are resolved relative to the package root, which is the working
/// directory when the harness is invoked as `dart run benchmark/main.dart`.
class Fixtures {
  Fixtures._(this.eacSmall, this.xldSmall, this.eac500Track);

  /// Human-readable fixture names, stable and in table order.
  static const List<String> names = [
    'eac_sample',
    'xld_sample',
    'eac_500_track'
  ];

  /// Track count of the 500-track fixture. Used for the per-track column.
  static const int eac500TrackCount = 500;

  final String eacSmall;
  final String xldSmall;
  final String eac500Track;

  /// Load all three fixtures from disk. Runs once, before any benchmark
  /// case starts, so the measured loops never touch the filesystem.
  factory Fixtures.load() {
    return Fixtures._(
      File('test/fixtures/eac_sample.log').readAsStringSync(),
      File('test/fixtures/xld_sample.log').readAsStringSync(),
      File('test/fixtures/eac_500_track.log').readAsStringSync(),
    );
  }

  /// Content indexed by fixture name. Order matches [names].
  Map<String, String> asMap() => {
        'eac_sample': eacSmall,
        'xld_sample': xldSmall,
        'eac_500_track': eac500Track,
      };
}
