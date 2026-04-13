import 'dart:convert';
import 'dart:io';

import 'package:dart_rip_log/dart_rip_log.dart';

/// Minimal example: parse a rip log file and print a quality summary.
///
/// Run with:
///
/// ```
/// dart run example/dart_rip_log_example.dart path/to/rip.log
/// ```
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart_rip_log_example <path-to-log>');
    exitCode = 2;
    return;
  }

  final RipLog log = await parseRipLogFile(args.first);

  print('Format:   ${log.logFormat.name}');
  print('Tool:     ${log.toolVersion ?? "(unknown)"}');
  print('Date:     ${log.extractionDate?.toIso8601String() ?? "(unknown)"}');
  print('Drive:    ${log.drive?.name ?? "(unknown)"}');
  print('Tracks:   ${log.tracks.length}');
  print('Verified: ${isFullyVerified(log)}');
  print('');

  for (final track in log.tracks) {
    final ar = track.accurateRipStatus.name;
    final peak = track.peakLevel != null
        ? (track.peakLevel! * 100).toStringAsFixed(1)
        : '-';
    print('Track ${track.trackNumber.toString().padLeft(2)}: '
        'AR=$ar  peak=$peak%  CRC=${track.copyCrc ?? "-"}');
  }

  final mismatched = tracksWithArMismatch(log);
  if (mismatched.isNotEmpty) {
    print('');
    print('AccurateRip mismatches:');
    for (final t in mismatched) {
      print('  Track ${t.trackNumber}');
    }
  }

  // Full JSON dump:
  print('');
  print('--- JSON ---');
  print(const JsonEncoder.withIndent('  ').convert(toJson(log)));
}
