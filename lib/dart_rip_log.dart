/// A pure Dart library that parses CD rip log files from EAC, XLD, and other
/// rippers into structured, JSON-serialisable quality data.
///
/// Entry points:
///
/// - [parseRipLog] — parse from a [String].
/// - [parseRipLogFile] — parse from a file path (async).
/// - [detectLogFormat] — identify the format without a full parse.
/// - [isFullyVerified], [tracksWithErrors], [tracksWithArMismatch] —
///   convenience queries over a parsed [RipLog].
/// - [toJson] — JSON-compatible `Map<String, dynamic>` for any [RipLog].
///
/// ## Quick start
///
/// ```dart
/// import 'package:dart_rip_log/dart_rip_log.dart';
///
/// void main() async {
///   final log = await parseRipLogFile('my_rip.log');
///   print(log.logFormat);          // RipLogFormat.eac
///   print(log.tracks.length);      // number of tracks
///   print(isFullyVerified(log));   // true / false
/// }
/// ```
///
/// See the package README for the full JSON shape, the `riplog` CLI, and
/// supported log-format details.
library dart_rip_log;

export 'src/models.dart';
export 'src/parser.dart' show parseRipLog, detectLogFormat;
export 'src/file_reader.dart' show parseRipLogFile;
export 'src/convenience.dart'
    show isFullyVerified, tracksWithErrors, tracksWithArMismatch, toJson;
export 'src/diff.dart'
    show compareRipLogs, RipLogDiff, RipLogDiffEntry, RipLogDiffKind;
