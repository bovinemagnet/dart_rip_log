import 'dart:convert';

import 'models.dart';
import 'parsers/cueripper_parser.dart';
import 'parsers/dbpoweramp_parser.dart';
import 'parsers/eac_parser.dart';
import 'parsers/whipper_parser.dart';
import 'parsers/xld_parser.dart';

/// Number of leading lines inspected for a tool signature.
///
/// Every supported tool writes its signature on the first line of the log;
/// a small window of tolerance is kept for stray blank lines or BOMs.
const _signatureWindow = 10;

/// Detect which tool generated [content] without performing a full parse.
///
/// Signatures are anchored to the start of the first few lines of the log
/// (where the tools actually write them), so rival tool names appearing in
/// track titles or file paths cannot misroute detection.
///
/// Returns [RipLogFormat.unknown] if the format cannot be identified.
RipLogFormat detectLogFormat(String content) {
  var head = content;
  if (head.startsWith('\uFEFF')) head = head.substring(1);
  for (final line in LineSplitter.split(head).take(_signatureWindow)) {
    final l = line.trim();
    if (l.startsWith('Exact Audio Copy V') ||
        l.startsWith('EAC extraction logfile')) {
      return RipLogFormat.eac;
    }
    if (l.startsWith('X Lossless Decoder version') ||
        l.startsWith('XLD extraction logfile')) {
      return RipLogFormat.xld;
    }
    if (l.startsWith('CUERipper v')) return RipLogFormat.cueRipper;
    if (l.startsWith('Log created by: whipper')) return RipLogFormat.whipper;
    if (l.startsWith('dBpoweramp')) return RipLogFormat.dbPoweramp;
  }
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
    case RipLogFormat.cueRipper:
      return parseCueRipper(content);
    case RipLogFormat.whipper:
      return parseWhipper(content);
    case RipLogFormat.dbPoweramp:
      return parseDbPoweramp(content);
    default:
      return RipLog(
        logFormat: RipLogFormat.unknown,
        errors: ['Unrecognised log format'],
      );
  }
}
