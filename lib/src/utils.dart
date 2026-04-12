library;

/// Converts a percentage string like "96.2 %" to a fraction [0.0, 1.0].
///
/// Returns `null` if [value] is `null` or cannot be parsed.
double? percentToFraction(String? value) {
  if (value == null) return null;
  final cleaned = value.replaceAll('%', '').trim();
  final parsed = double.tryParse(cleaned);
  if (parsed == null) return null;
  return parsed / 100.0;
}

/// Extracts the first capture group from [pattern] applied to [line].
///
/// Returns the trimmed capture or `null` when there is no match.
String? extractGroup(RegExp pattern, String line) {
  final match = pattern.firstMatch(line);
  if (match == null || match.groupCount < 1) return null;
  return match.group(1)?.trim();
}

/// Normalises line endings so the rest of the parsers only see `\n`.
String normaliseLineEndings(String content) =>
    content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
