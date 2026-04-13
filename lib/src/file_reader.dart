import 'dart:io';
import 'models.dart';
import 'parser.dart';

/// Parse a rip log from a file at [filePath].
///
/// Reads the file as UTF-8 and delegates to [parseRipLog]. The returned
/// [RipLog] has its [RipLog.source] populated with lineage information
/// (byte size, line count, parser name, parse timestamp).
///
/// Throws a [FileSystemException] if the file does not exist or cannot be
/// read.
Future<RipLog> parseRipLogFile(String filePath) async {
  final file = File(filePath);
  final content = await file.readAsString();
  final log = parseRipLog(content);
  final source = LogSource(
    byteSize: content.length,
    lineCount: '\n'.allMatches(content).length + 1,
    parserName: log.logFormat.name,
    parsedAt: DateTime.now().toUtc(),
  );
  return log.withSource(source);
}
