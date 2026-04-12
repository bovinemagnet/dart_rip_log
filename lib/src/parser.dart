import 'models.dart';
import 'parsers/eac_parser.dart';
import 'parsers/xld_parser.dart';

/// Detect which tool generated [content] without performing a full parse.
///
/// Returns [RipLogFormat.unknown] if the format cannot be identified.
RipLogFormat detectLogFormat(String content) {
  if (content.contains('Exact Audio Copy')) return RipLogFormat.eac;
  if (content.contains('X Lossless Decoder')) return RipLogFormat.xld;
  if (content.contains('CUERipper')) return RipLogFormat.cueRipper;
  if (content.contains('whipper')) return RipLogFormat.whipper;
  if (content.contains('dBpoweramp')) return RipLogFormat.dbPoweramp;
  return RipLogFormat.unknown;
}

/// Parse a rip log from its string [content].
///
/// Auto-detects the log format from content signatures and dispatches to
/// the appropriate parser. Returns a [RipLog] with [RipLogFormat.unknown]
/// if the format could not be determined.
RipLog parseRipLog(String content) {
  final format = detectLogFormat(content);
  switch (format) {
    case RipLogFormat.eac:
      return parseEac(content);
    case RipLogFormat.xld:
      return parseXld(content);
    default:
      return RipLog(
        logFormat: RipLogFormat.unknown,
        errors: ['Unrecognised log format'],
      );
  }
}
