import 'dart:convert';
import 'dart:io';

import 'package:dart_rip_log/dart_rip_log.dart';

const String _cliVersion = '0.0.1';

void _printUsage(IOSink sink) {
  sink.writeln('riplog — parse EAC / XLD rip logs.');
  sink.writeln('');
  sink.writeln('Usage:');
  sink.writeln('  riplog [options] <file> [<file>...]');
  sink.writeln('  riplog [options] -            # read from stdin');
  sink.writeln('  cat rip.log | riplog         # read from stdin');
  sink.writeln('');
  sink.writeln('Options:');
  sink.writeln('  -h, --help       Show this help and exit');
  sink.writeln('  --version        Show version and exit');
  sink.writeln('  --format <fmt>   Output format: json (default), text');
  sink.writeln('  --summary        One line per track summary');
  sink.writeln('  -q, --quiet      One machine-readable line per file:');
  sink.writeln('                   <path>\\t<format>\\t<tracks>\\t<verified>\\t<errors>');
  sink.writeln('');
  sink.writeln('Exit codes:');
  sink.writeln('  0  all files parsed, every track verified, no track errors');
  sink.writeln('  1  at least one AR mismatch or track with error counts > 0');
  sink.writeln('  2  bad arguments or file I/O error');
}

Future<void> main(List<String> args) async {
  String format = 'json';
  bool summary = false;
  bool quiet = false;
  final inputs = <String>[];

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '--help':
      case '-h':
        _printUsage(stdout);
        exit(0);
      case '--version':
        stdout.writeln('riplog $_cliVersion');
        exit(0);
      case '--format':
        if (i + 1 >= args.length) {
          stderr.writeln('Missing value for --format');
          exit(2);
        }
        format = args[++i];
        if (format != 'json' && format != 'text') {
          stderr.writeln('Unknown --format value: $format (expected json or text)');
          exit(2);
        }
      case '--summary':
        summary = true;
      case '--quiet':
      case '-q':
        quiet = true;
      case '-':
        inputs.add('-');
      default:
        if (a.startsWith('-')) {
          stderr.writeln('Unknown option: $a');
          _printUsage(stderr);
          exit(2);
        }
        inputs.add(a);
    }
  }

  // If no file given and stdin is piped, default to stdin.
  if (inputs.isEmpty) {
    if (stdin.hasTerminal) {
      _printUsage(stderr);
      exit(2);
    }
    inputs.add('-');
  }

  // Multiple files only make sense with --summary or --quiet (to avoid
  // mashing multiple JSON documents together without a separator).
  final multi = inputs.length > 1;
  if (multi && !(summary || quiet) && format == 'json') {
    // Emit a JSON array of results.
  }

  int overallExit = 0;
  final jsonArray = <Map<String, dynamic>>[];

  for (var idx = 0; idx < inputs.length; idx++) {
    final path = inputs[idx];
    final String content;
    try {
      content = path == '-'
          ? await _readStdin()
          : await File(path).readAsString();
    } on FileSystemException catch (e) {
      stderr.writeln('Cannot read $path: ${e.message}');
      exit(2);
    }

    final log = parseRipLog(content);

    final trackFailed = !isFullyVerified(log) || tracksWithErrors(log).isNotEmpty;
    if (trackFailed) overallExit = 1;

    if (quiet) {
      final verified = isFullyVerified(log);
      final errCount = tracksWithErrors(log).length;
      stdout.writeln(
          '$path\t${log.logFormat.name}\t${log.tracks.length}\t$verified\t$errCount');
      continue;
    }

    if (summary) {
      if (multi) stdout.writeln('# $path');
      _printSummary(log);
      if (multi && idx != inputs.length - 1) stdout.writeln('');
      continue;
    }

    if (format == 'text') {
      if (multi) stdout.writeln('# $path');
      _printText(log);
      if (multi && idx != inputs.length - 1) stdout.writeln('');
    } else {
      if (multi) {
        jsonArray.add(toJson(log));
      } else {
        stdout.writeln(const JsonEncoder.withIndent('  ').convert(toJson(log)));
      }
    }
  }

  if (!quiet && !summary && format == 'json' && multi) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(jsonArray));
  }

  exit(overallExit);
}

Future<String> _readStdin() async {
  final buf = StringBuffer();
  await for (final chunk in stdin.transform(utf8.decoder)) {
    buf.write(chunk);
  }
  return buf.toString();
}

void _printSummary(RipLog log) {
  stdout.writeln('Format : ${log.logFormat.name}');
  if (log.toolVersion != null) stdout.writeln('Version: ${log.toolVersion}');
  stdout.writeln('Tracks : ${log.tracks.length}');
  for (final t in log.tracks) {
    final ar = t.accurateRipStatus.name;
    final quality = t.trackQuality != null
        ? '${(t.trackQuality! * 100).toStringAsFixed(1)}%'
        : 'n/a';
    stdout.writeln(
        '  Track ${t.trackNumber.toString().padLeft(2)} | AR: $ar | Quality: $quality');
  }
}

void _printText(RipLog log) {
  stdout.writeln('Log format  : ${log.logFormat.name}');
  if (log.toolVersion != null) stdout.writeln('Tool version: ${log.toolVersion}');
  if (log.extractionDate != null) {
    stdout.writeln('Date        : ${log.extractionDate}');
  }
  if (log.drive != null) stdout.writeln('Drive       : ${log.drive!.name}');
  if (log.readMode != null) stdout.writeln('Read mode   : ${log.readMode}');
  if (log.readOffset != null) stdout.writeln('Read offset : ${log.readOffset}');
  stdout.writeln('');
  for (final t in log.tracks) {
    stdout.writeln('Track ${t.trackNumber}');
    if (t.filename != null) stdout.writeln('  File   : ${t.filename}');
    stdout.writeln('  AR     : ${t.accurateRipStatus.name}');
    if (t.accurateRipConfidence != null) {
      stdout.writeln('  AR conf: ${t.accurateRipConfidence}');
    }
    if (t.copyCrc != null) stdout.writeln('  CRC    : ${t.copyCrc}');
    if (t.peakLevel != null) {
      stdout.writeln('  Peak   : ${(t.peakLevel! * 100).toStringAsFixed(1)}%');
    }
    if (t.trackQuality != null) {
      stdout.writeln('  Quality: ${(t.trackQuality! * 100).toStringAsFixed(1)}%');
    }
    if (t.errors.hasErrors) {
      stdout.writeln('  ERRORS :');
      if (t.errors.readErrors > 0) {
        stdout.writeln('    read: ${t.errors.readErrors}');
      }
      if (t.errors.jitterErrors > 0) {
        stdout.writeln('    jitter: ${t.errors.jitterErrors}');
      }
      if (t.errors.damagedSectors > 0) {
        stdout.writeln('    damaged sectors: ${t.errors.damagedSectors}');
      }
    }
  }
  if (log.accurateRipSummary != null) {
    stdout.writeln('');
    stdout.writeln(log.accurateRipSummary);
  }
}
