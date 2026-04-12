import 'dart:io';
import 'models.dart';
import 'parser.dart';

/// Parse a rip log from a file at [filePath].
///
/// Reads the file as UTF-8 and delegates to [parseRipLog].
///
/// Throws a [FileSystemException] if the file does not exist or cannot be
/// read.
Future<RipLog> parseRipLogFile(String filePath) async {
  final file = File(filePath);
  final content = await file.readAsString();
  return parseRipLog(content);
}
