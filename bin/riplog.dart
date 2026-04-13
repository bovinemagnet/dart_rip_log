import 'dart:convert';
import 'dart:io';

import 'package:dart_rip_log/dart_rip_log.dart';

const String _cliVersion = '0.0.5';

enum _Filter { all, mismatch, errors, problems }

enum _FailOn { any, mismatch, errors, never }

enum _ColorMode { auto, always, never }

class _Style {
  final bool enabled;
  const _Style(this.enabled);

  String green(String s) => enabled ? '\x1B[32m$s\x1B[0m' : s;
  String red(String s) => enabled ? '\x1B[31m$s\x1B[0m' : s;
  String yellow(String s) => enabled ? '\x1B[33m$s\x1B[0m' : s;
  String dim(String s) => enabled ? '\x1B[2m$s\x1B[0m' : s;

  String colourAr(AccurateRipStatus s) {
    final name = s.name;
    switch (s) {
      case AccurateRipStatus.verified:
        return green(name);
      case AccurateRipStatus.mismatch:
        return red(name);
      case AccurateRipStatus.notInDatabase:
        return yellow(name);
      case AccurateRipStatus.notChecked:
        return dim(name);
    }
  }
}

void _printUsage(IOSink sink) {
  sink.writeln('riplog — parse EAC / XLD rip logs.');
  sink.writeln('');
  sink.writeln('Usage:');
  sink.writeln('  riplog [options] <file-or-dir> [<file-or-dir>...]');
  sink.writeln('  riplog [options] -            # read from stdin');
  sink.writeln('  cat rip.log | riplog         # read from stdin');
  sink.writeln('');
  sink.writeln('Options:');
  sink.writeln('  -h, --help       Show this help and exit');
  sink.writeln('  --version        Show version and exit');
  sink.writeln('  --format <fmt>   Output: json (default), text, ndjson');
  sink.writeln('  --summary        One line per track summary');
  sink.writeln('  -q, --quiet      Machine-readable tab-separated line per');
  sink.writeln(
      '                   file: <path>\\t<format>\\t<tracks>\\t<verified>\\t<errors>');
  sink.writeln('  --filter <f>     Filter shown tracks (text/summary only):');
  sink.writeln('                   all (default), mismatch, errors, problems');
  sink.writeln('  --fail-on <p>    Exit-code policy:');
  sink.writeln('                   any (default), mismatch, errors, never');
  sink.writeln('  -r, --recursive  Walk directories for *.log files');
  sink.writeln('  --color <mode>   auto (default) | always | never');
  sink.writeln('');
  sink.writeln('Exit codes:');
  sink.writeln('  0  --fail-on policy not triggered');
  sink.writeln('  1  --fail-on policy triggered (default: any AR mismatch or');
  sink.writeln('     track with error counts > 0)');
  sink.writeln('  2  bad arguments or file I/O error');
}

Future<void> main(List<String> args) async {
  String format = 'json';
  bool summary = false;
  bool quiet = false;
  bool recursive = false;
  _Filter filter = _Filter.all;
  _FailOn failOn = _FailOn.any;
  _ColorMode colorMode = _ColorMode.auto;
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
        if (i + 1 >= args.length) _die('Missing value for --format');
        format = args[++i];
        if (format != 'json' && format != 'text' && format != 'ndjson') {
          _die('Unknown --format value: $format (expected json, text, ndjson)');
        }
      case '--summary':
        summary = true;
      case '--quiet':
      case '-q':
        quiet = true;
      case '--filter':
        if (i + 1 >= args.length) _die('Missing value for --filter');
        filter = _parseFilter(args[++i]);
      case '--fail-on':
        if (i + 1 >= args.length) _die('Missing value for --fail-on');
        failOn = _parseFailOn(args[++i]);
      case '--recursive':
      case '-r':
        recursive = true;
      case '--color':
      case '--colour':
        if (i + 1 >= args.length) _die('Missing value for --color');
        colorMode = _parseColorMode(args[++i]);
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

  // Expand directories into files if --recursive.
  final expanded = <String>[];
  for (final input in inputs) {
    if (input == '-') {
      expanded.add(input);
      continue;
    }
    if (FileSystemEntity.isDirectorySync(input)) {
      if (!recursive) {
        _die('$input is a directory (use --recursive to walk it)');
      }
      final logs = Directory(input)
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.log'))
          .map((f) => f.path)
          .toList()
        ..sort();
      expanded.addAll(logs);
    } else {
      expanded.add(input);
    }
  }

  if (expanded.isEmpty) {
    if (stdin.hasTerminal) {
      _printUsage(stderr);
      exit(2);
    }
    expanded.add('-');
  }

  final style = _Style(_colorEnabled(colorMode));
  final multi = expanded.length > 1;
  final jsonArray = <Map<String, dynamic>>[];
  int overallExit = 0;

  for (var idx = 0; idx < expanded.length; idx++) {
    final path = expanded[idx];
    final String content;
    try {
      content =
          path == '-' ? await _readStdin() : await File(path).readAsString();
    } on FileSystemException catch (e) {
      stderr.writeln('Cannot read $path: ${e.message}');
      exit(2);
    }

    final log = parseRipLog(content);

    if (_failOnHit(failOn, log)) overallExit = 1;

    if (quiet) {
      stdout.writeln(
          '$path\t${log.logFormat.name}\t${log.tracks.length}\t${isFullyVerified(log)}\t${tracksWithErrors(log).length}');
      continue;
    }

    if (summary) {
      if (multi) stdout.writeln('# $path');
      _printSummary(log, filter, style);
      if (multi && idx != expanded.length - 1) stdout.writeln('');
      continue;
    }

    switch (format) {
      case 'ndjson':
        stdout.writeln(jsonEncode(toJson(log)));
      case 'text':
        if (multi) stdout.writeln('# $path');
        _printText(log, filter, style);
        if (multi && idx != expanded.length - 1) stdout.writeln('');
      case 'json':
      default:
        if (multi) {
          jsonArray.add(toJson(log));
        } else {
          stdout
              .writeln(const JsonEncoder.withIndent('  ').convert(toJson(log)));
        }
    }
  }

  if (!quiet && !summary && format == 'json' && multi) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(jsonArray));
  }

  exit(overallExit);
}

Never _die(String message) {
  stderr.writeln(message);
  exit(2);
}

_Filter _parseFilter(String s) {
  switch (s) {
    case 'all':
      return _Filter.all;
    case 'mismatch':
      return _Filter.mismatch;
    case 'errors':
      return _Filter.errors;
    case 'problems':
      return _Filter.problems;
    default:
      _die(
          'Unknown --filter value: $s (expected all, mismatch, errors, problems)');
  }
}

_FailOn _parseFailOn(String s) {
  switch (s) {
    case 'any':
      return _FailOn.any;
    case 'mismatch':
      return _FailOn.mismatch;
    case 'errors':
      return _FailOn.errors;
    case 'never':
      return _FailOn.never;
    default:
      _die(
          'Unknown --fail-on value: $s (expected any, mismatch, errors, never)');
  }
}

_ColorMode _parseColorMode(String s) {
  switch (s) {
    case 'auto':
      return _ColorMode.auto;
    case 'always':
      return _ColorMode.always;
    case 'never':
      return _ColorMode.never;
    default:
      _die('Unknown --color value: $s (expected auto, always, never)');
  }
}

bool _colorEnabled(_ColorMode mode) {
  switch (mode) {
    case _ColorMode.always:
      return true;
    case _ColorMode.never:
      return false;
    case _ColorMode.auto:
      if (Platform.environment['NO_COLOR']?.isNotEmpty ?? false) return false;
      return stdout.hasTerminal;
  }
}

bool _failOnHit(_FailOn policy, RipLog log) {
  final hasMismatch = tracksWithArMismatch(log).isNotEmpty;
  final hasErrors = tracksWithErrors(log).isNotEmpty;
  switch (policy) {
    case _FailOn.never:
      return false;
    case _FailOn.mismatch:
      return hasMismatch;
    case _FailOn.errors:
      return hasErrors;
    case _FailOn.any:
      return hasMismatch || hasErrors || !isFullyVerified(log);
  }
}

bool _keepTrack(RipLogTrack t, _Filter filter) {
  switch (filter) {
    case _Filter.all:
      return true;
    case _Filter.mismatch:
      return t.accurateRipStatus == AccurateRipStatus.mismatch;
    case _Filter.errors:
      return t.errors.hasErrors;
    case _Filter.problems:
      return t.accurateRipStatus == AccurateRipStatus.mismatch ||
          t.errors.hasErrors;
  }
}

Future<String> _readStdin() async {
  final buf = StringBuffer();
  await for (final chunk in stdin.transform(utf8.decoder)) {
    buf.write(chunk);
  }
  return buf.toString();
}

void _printSummary(RipLog log, _Filter filter, _Style style) {
  stdout.writeln('Format : ${log.logFormat.name}');
  if (log.toolVersion != null) stdout.writeln('Version: ${log.toolVersion}');
  stdout.writeln('Tracks : ${log.tracks.length}');
  for (final t in log.tracks.where((x) => _keepTrack(x, filter))) {
    final ar = style.colourAr(t.accurateRipStatus);
    final quality = t.trackQuality != null
        ? '${(t.trackQuality! * 100).toStringAsFixed(1)}%'
        : 'n/a';
    stdout.writeln(
        '  Track ${t.trackNumber.toString().padLeft(2)} | AR: $ar | Quality: $quality');
  }
}

void _printText(RipLog log, _Filter filter, _Style style) {
  stdout.writeln('Log format  : ${log.logFormat.name}');
  if (log.toolVersion != null) {
    stdout.writeln('Tool version: ${log.toolVersion}');
  }
  if (log.extractionDate != null) {
    stdout.writeln('Date        : ${log.extractionDate}');
  }
  if (log.drive != null) stdout.writeln('Drive       : ${log.drive!.name}');
  if (log.readMode != null) stdout.writeln('Read mode   : ${log.readMode}');
  if (log.readOffset != null) stdout.writeln('Read offset : ${log.readOffset}');
  stdout.writeln('');
  for (final t in log.tracks.where((x) => _keepTrack(x, filter))) {
    stdout.writeln('Track ${t.trackNumber}');
    if (t.filename != null) stdout.writeln('  File   : ${t.filename}');
    stdout.writeln('  AR     : ${style.colourAr(t.accurateRipStatus)}');
    if (t.accurateRipConfidence != null) {
      stdout.writeln('  AR conf: ${t.accurateRipConfidence}');
    }
    if (t.copyCrc != null) stdout.writeln('  CRC    : ${t.copyCrc}');
    if (t.peakLevel != null) {
      stdout.writeln('  Peak   : ${(t.peakLevel! * 100).toStringAsFixed(1)}%');
    }
    if (t.trackQuality != null) {
      stdout
          .writeln('  Quality: ${(t.trackQuality! * 100).toStringAsFixed(1)}%');
    }
    if (t.errors.hasErrors) {
      stdout.writeln('  ${style.red("ERRORS")} :');
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
