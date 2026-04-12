/// A pure Dart library that parses CD rip log files from EAC and XLD into
/// structured quality data.
///
/// ## Quick start
///
/// ```dart
/// import 'package:dart_rip_log/dart_rip_log.dart';
///
/// void main() {
///   final log = parseRipLog(myLogFileContent);
///   print(log.logFormat);          // RipLogFormat.eac
///   print(log.tracks.length);      // number of tracks
///   print(isFullyVerified(log));   // true / false
/// }
/// ```
library dart_rip_log;

export 'src/models.dart';
export 'src/parser.dart' show parseRipLog, detectLogFormat;
export 'src/file_reader.dart' show parseRipLogFile;
export 'src/convenience.dart' show isFullyVerified, tracksWithErrors, tracksWithArMismatch, toJson;
