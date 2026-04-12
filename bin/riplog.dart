import 'dart:convert';
import 'dart:io';

import 'package:dart_rip_log/dart_rip_log.dart';

void _printUsage() {
  stderr.writeln('Usage: riplog [--format json|text] [--summary] <file>');
  stderr.writeln('');
  stderr.writeln('Options:');
  stderr.writeln('  --format json   Output as JSON (default)');
  stderr.writeln('  --format text   Output as human-readable text');
  stderr.writeln('  --summary       One line per track summary');
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _printUsage();
    exit(2);
  }

  String format = 'json';
  bool summary = false;
  String? filePath;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--format':
        if (i + 1 >= args.length) {
          stderr.writeln('Missing value for --format');
          exit(2);
        }
        format = args[++i];
      case '--summary':
        summary = true;
      case '--help':
      case '-h':
        _printUsage();
        exit(0);
      default:
        if (args[i].startsWith('-')) {
          stderr.writeln('Unknown option: ${args[i]}');
          exit(2);
        }
        filePath = args[i];
    }
  }

  if (filePath == null) {
    _printUsage();
    exit(2);
  }

  final file = File(filePath);
  if (!file.existsSync()) {
    stderr.writeln('File not found: $filePath');
    exit(2);
  }

  final log = await parseRipLogFile(filePath);

  if (summary) {
    _printSummary(log);
    return;
  }

  if (format == 'text') {
    _printText(log);
  } else {
    print(const JsonEncoder.withIndent('  ').convert(toJson(log)));
  }
}

void _printSummary(RipLog log) {
  print('Format : ${log.logFormat.name}');
  if (log.toolVersion != null) print('Version: ${log.toolVersion}');
  print('Tracks : ${log.tracks.length}');
  for (final t in log.tracks) {
    final ar = t.accurateRipStatus.name;
    final quality =
        t.trackQuality != null ? '${(t.trackQuality! * 100).toStringAsFixed(1)}%' : 'n/a';
    print('  Track ${t.trackNumber.toString().padLeft(2)} | AR: $ar | Quality: $quality');
  }
}

void _printText(RipLog log) {
  print('Log format  : ${log.logFormat.name}');
  if (log.toolVersion != null) print('Tool version: ${log.toolVersion}');
  if (log.extractionDate != null) {
    print('Date        : ${log.extractionDate}');
  }
  if (log.drive != null) print('Drive       : ${log.drive!.name}');
  if (log.readMode != null) print('Read mode   : ${log.readMode}');
  if (log.readOffset != null) print('Read offset : ${log.readOffset}');
  print('');
  for (final t in log.tracks) {
    print('Track ${t.trackNumber}');
    if (t.filename != null) print('  File   : ${t.filename}');
    print('  AR     : ${t.accurateRipStatus.name}');
    if (t.accurateRipConfidence != null) {
      print('  AR conf: ${t.accurateRipConfidence}');
    }
    if (t.copyCrc != null) print('  CRC    : ${t.copyCrc}');
    if (t.peakLevel != null) {
      print('  Peak   : ${(t.peakLevel! * 100).toStringAsFixed(1)}%');
    }
    if (t.trackQuality != null) {
      print('  Quality: ${(t.trackQuality! * 100).toStringAsFixed(1)}%');
    }
    if (t.errors.hasErrors) {
      print('  ERRORS :');
      if (t.errors.readErrors > 0) print('    read: ${t.errors.readErrors}');
      if (t.errors.jitterErrors > 0) {
        print('    jitter: ${t.errors.jitterErrors}');
      }
      if (t.errors.damagedSectors > 0) {
        print('    damaged sectors: ${t.errors.damagedSectors}');
      }
    }
  }
  if (log.accurateRipSummary != null) {
    print('');
    print(log.accurateRipSummary);
  }
}
