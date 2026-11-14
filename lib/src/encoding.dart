import 'dart:convert';

/// Decode raw rip-log [bytes] into a string, sniffing the byte-order mark.
///
/// Real EAC logs are written as UTF-16LE with a BOM, so a plain UTF-8
/// decode fails on the single most common real-world input. Detection:
///
/// - `FF FE` → UTF-16LE (BOM stripped)
/// - `FE FF` → UTF-16BE (BOM stripped)
/// - `EF BB BF` → UTF-8 (BOM stripped)
/// - no BOM, but `00` bytes on alternate offsets → BOM-less UTF-16LE or
///   UTF-16BE (e.g. a log re-saved by an editor that strips the BOM)
/// - otherwise → UTF-8, falling back to Latin-1 when the bytes are not
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
  final littleEndian = _sniffBomlessUtf16(bytes);
  if (littleEndian != null) {
    return _decodeUtf16(bytes, offset: 0, littleEndian: littleEndian);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

/// Number of leading bytes inspected for a BOM-less UTF-16 pattern.
const _sniffWindow = 512;

/// Detect BOM-less UTF-16 from the byte pattern at the start of [bytes].
///
/// Rip logs open with ASCII text, whose UTF-16 code units have a zero
/// high byte, so `00` dominates one byte parity: odd offsets for
/// little-endian, even offsets for big-endian. UTF-8 and Latin-1 text
/// never contains `00`. Returns `true` for UTF-16LE, `false` for
/// UTF-16BE, or `null` when the pattern is absent.
bool? _sniffBomlessUtf16(List<int> bytes) {
  final n = (bytes.length < _sniffWindow ? bytes.length : _sniffWindow) & ~1;
  if (n < 4) return null;
  var evenZeros = 0;
  var oddZeros = 0;
  for (var i = 0; i < n; i += 2) {
    if (bytes[i] == 0) evenZeros++;
    if (bytes[i + 1] == 0) oddZeros++;
  }
  final pairs = n ~/ 2;
  // At least 75% zeros on one parity and under 10% on the other.
  bool dominant(int zeros) => zeros * 4 >= pairs * 3;
  bool rare(int zeros) => zeros * 10 < pairs;
  if (dominant(oddZeros) && rare(evenZeros)) return true;
  if (dominant(evenZeros) && rare(oddZeros)) return false;
  return null;
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
