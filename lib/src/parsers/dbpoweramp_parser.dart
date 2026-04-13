import '../models.dart';

final _reVersion = RegExp(r'dBpoweramp.*?(?:Release|Reference)?\s*([\d.]+)',
    caseSensitive: false);

/// Parse a dBpoweramp log. Currently a stub: identifies the format and extracts
/// the tool version, but does not yet parse tracks. Full parser pending a
/// real sample log.
RipLog parseDbPoweramp(String content) {
  final version = _reVersion.firstMatch(content)?.group(1);
  return RipLog(
    logFormat: RipLogFormat.dbPoweramp,
    toolVersion: version,
    errors: const ['dBpoweramp parser not yet implemented'],
  );
}
