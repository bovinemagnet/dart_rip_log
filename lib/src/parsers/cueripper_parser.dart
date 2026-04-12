import '../models.dart';

final _reVersion = RegExp(r'CUERipper\s+v?([\d.]+)', caseSensitive: false);

/// Parse a CUERipper log. Currently a stub: identifies the format and extracts
/// the tool version, but does not yet parse tracks. Full parser pending a
/// real sample log.
RipLog parseCueRipper(String content) {
  final version = _reVersion.firstMatch(content)?.group(1);
  return RipLog(
    logFormat: RipLogFormat.cueRipper,
    toolVersion: version,
    errors: const ['CUERipper parser not yet implemented'],
  );
}
