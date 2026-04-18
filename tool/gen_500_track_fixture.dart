// Regenerates test/fixtures/eac_500_track.log.
//
// Run from the package root:
//
//   dart run tool/gen_500_track_fixture.dart
//
// The output is a synthetic 500-track EAC log used by both the
// benchmark harness and the <1 s performance smoke test. Keep the
// content in sync with the shape parseEac() expects; changes here
// affect the smoke test's timing floor.

import 'dart:io';

void main() {
  final buf = StringBuffer()
    ..writeln('Exact Audio Copy V1.6 from 23. October 2019')
    ..writeln('')
    ..writeln('EAC extraction logfile from 15. March 2026')
    ..writeln('')
    ..writeln('Used drive : Some Drive')
    ..writeln('');
  for (var i = 1; i <= 500; i++) {
    final crc = i.toRadixString(16).padLeft(8, '0').toUpperCase();
    buf
      ..writeln('Track  $i')
      ..writeln('')
      ..writeln('     Filename C:\\track_$i.flac')
      ..writeln('     Peak level 90.0 %')
      ..writeln('     Track quality 99.9 %')
      ..writeln('     Copy CRC $crc')
      ..writeln('     Accurately ripped (confidence 1)  [AAAAAAAA]')
      ..writeln('     Copy OK')
      ..writeln('');
  }
  buf.writeln('All tracks accurately ripped');

  final out = File('test/fixtures/eac_500_track.log');
  out.writeAsStringSync(buf.toString());
  stdout.writeln('Wrote ${out.path} (${buf.length} bytes)');
}
