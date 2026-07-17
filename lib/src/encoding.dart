import 'dart:convert';

/// Decode raw rip-log [bytes] into a string, sniffing the byte-order mark.
///
/// Real EAC logs are written as UTF-16LE with a BOM, so a plain UTF-8
/// decode fails on the single most common real-world input. Detection:
///
/// - `FF FE` → UTF-16LE (BOM stripped)
/// - `FE FF` → UTF-16BE (BOM stripped)
/// - `EF BB BF` → UTF-8 (BOM stripped)
/// - no BOM → UTF-8, falling back to Latin-1 when the bytes are not
///   valid UTF-8 (never throws on content).
String decodeLogBytes(List<int> bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes, offset: 2, littleEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes, offset: 2, littleEndian: false);
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3));
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

String _decodeUtf16(List<int> bytes,
    {required int offset, required bool littleEndian}) {
  final codeUnits = <int>[];
  // A trailing odd byte (truncated file) is ignored rather than throwing.
  for (var i = offset; i + 1 < bytes.length; i += 2) {
    codeUnits.add(littleEndian
        ? bytes[i] | (bytes[i + 1] << 8)
        : (bytes[i] << 8) | bytes[i + 1]);
  }
  return String.fromCharCodes(codeUnits);
}
