import '../models.dart';

final _reVersion = RegExp(r'whipper\s+([\d.]+)', caseSensitive: false);

/// Parse a whipper log. Currently a stub: identifies the format and extracts
/// the tool version, but does not yet parse tracks. Full parser pending a
/// real sample log.
RipLog parseWhipper(String content) {
  final version = _reVersion.firstMatch(content)?.group(1);
  return RipLog(
    logFormat: RipLogFormat.whipper,
    toolVersion: version,
    errors: const ['whipper parser not yet implemented'],
  );
}
