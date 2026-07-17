import 'dart:io';
import 'encoding.dart';
import 'models.dart';
import 'parser.dart';

/// Parse a rip log from a file at [filePath].
///
/// Reads the file's bytes and decodes them with BOM detection (UTF-16LE,
/// UTF-16BE, UTF-8 with BOM, plain UTF-8, Latin-1 fallback — real EAC
/// logs are UTF-16LE) before delegating to [parseRipLog]. The returned
/// [RipLog] has its [RipLog.source] populated with lineage information
/// (byte size, line count, parser name, parse timestamp).
///
/// Throws a [FileSystemException] if the file does not exist or cannot be
/// read.
Future<RipLog> parseRipLogFile(String filePath) async {
  final file = File(filePath);
  final bytes = await file.readAsBytes();
  final content = decodeLogBytes(bytes);
  final log = parseRipLog(content);
  final source = LogSource(
    byteSize: content.length,
    lineCount: '\n'.allMatches(content).length + 1,
    parserName: log.logFormat.name,
    parsedAt: DateTime.now().toUtc(),
  );
  return log.withSource(source);
}
