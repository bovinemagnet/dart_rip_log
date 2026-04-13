/// Which CD-ripping tool generated the log.
enum RipLogFormat {
  eac,
  xld,
  cueRipper,
  whipper,
  dbPoweramp,
  unknown,
}

/// AccurateRip verification result for a single track.
enum AccurateRipStatus {
  verified,
  mismatch,
  notInDatabase,
  notChecked,
}

/// Drive information extracted from the log header.
class DriveInfo {
  /// Drive model name (e.g. "ASUS BW-16D1HT").
  final String name;

  /// Drive read-offset correction in samples, if present.
  final int? readOffset;

  /// Adapter/interface description (e.g. "ATAPI"), if present.
  final String? adapter;

  const DriveInfo({
    required this.name,
    this.readOffset,
    this.adapter,
  });

  /// Convert to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'name': name,
        if (readOffset != null) 'readOffset': readOffset,
        if (adapter != null) 'adapter': adapter,
      };
}

/// Per-track error statistics reported by the ripper.
class TrackErrors {
  final int readErrors;
  final int skipErrors;
  final int jitterErrors;
  final int edgeJitterErrors;
  final int atomJitterErrors;
  final int driftErrors;
  final int droppedBytes;
  final int duplicatedBytes;
  final int inconsistentErrorSectors;
  final int damagedSectors;

  const TrackErrors({
    this.readErrors = 0,
    this.skipErrors = 0,
    this.jitterErrors = 0,
    this.edgeJitterErrors = 0,
    this.atomJitterErrors = 0,
    this.driftErrors = 0,
    this.droppedBytes = 0,
    this.duplicatedBytes = 0,
    this.inconsistentErrorSectors = 0,
    this.damagedSectors = 0,
  });

  /// Returns `true` if any error count is greater than zero.
  bool get hasErrors =>
      readErrors > 0 ||
      skipErrors > 0 ||
      jitterErrors > 0 ||
      edgeJitterErrors > 0 ||
      atomJitterErrors > 0 ||
      driftErrors > 0 ||
      droppedBytes > 0 ||
      duplicatedBytes > 0 ||
      inconsistentErrorSectors > 0 ||
      damagedSectors > 0;

  /// Convert to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'readErrors': readErrors,
        'skipErrors': skipErrors,
        'jitterErrors': jitterErrors,
        'edgeJitterErrors': edgeJitterErrors,
        'atomJitterErrors': atomJitterErrors,
        'driftErrors': driftErrors,
        'droppedBytes': droppedBytes,
        'duplicatedBytes': duplicatedBytes,
        'inconsistentErrorSectors': inconsistentErrorSectors,
        'damagedSectors': damagedSectors,
        'hasErrors': hasErrors,
      };
}

/// Per-track quality data — unified across all log formats.
class RipLogTrack {
  /// 1-based track number.
  final int trackNumber;

  /// Output filename (may include a path).
  final String? filename;

  /// Peak level as a fraction in the range 0.0 to 1.0.
  final double? peakLevel;

  /// Track extraction quality as a fraction in the range 0.0 to 1.0.
  final double? trackQuality;

  /// Copy CRC-32 hex string (e.g. "882B01BE").
  final String? copyCrc;

  /// Test CRC-32 hex string (EAC test+copy mode only).
  final String? testCrc;

  /// AccurateRip verification result.
  final AccurateRipStatus accurateRipStatus;

  /// AccurateRip v1 CRC hex string.
  final String? accurateRipCrcV1;

  /// AccurateRip v2 CRC hex string.
  final String? accurateRipCrcV2;

  /// AccurateRip confidence value (number of matching submissions).
  final int? accurateRipConfidence;

  /// Whether the ripper reported a successful copy.
  final bool copyOk;

  /// Per-track error statistics.
  final TrackErrors errors;

  /// Which tool produced this track entry.
  final RipLogFormat logFormat;

  const RipLogTrack({
    required this.trackNumber,
    this.filename,
    this.peakLevel,
    this.trackQuality,
    this.copyCrc,
    this.testCrc,
    this.accurateRipStatus = AccurateRipStatus.notChecked,
    this.accurateRipCrcV1,
    this.accurateRipCrcV2,
    this.accurateRipConfidence,
    this.copyOk = false,
    TrackErrors? errors,
    this.logFormat = RipLogFormat.unknown,
  }) : errors = errors ?? const TrackErrors();

  /// Convert to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'trackNumber': trackNumber,
        if (filename != null) 'filename': filename,
        if (peakLevel != null) 'peakLevel': peakLevel,
        if (trackQuality != null) 'trackQuality': trackQuality,
        if (copyCrc != null) 'copyCrc': copyCrc,
        if (testCrc != null) 'testCrc': testCrc,
        'accurateRipStatus': accurateRipStatus.name,
        if (accurateRipCrcV1 != null) 'accurateRipCrcV1': accurateRipCrcV1,
        if (accurateRipCrcV2 != null) 'accurateRipCrcV2': accurateRipCrcV2,
        if (accurateRipConfidence != null)
          'accurateRipConfidence': accurateRipConfidence,
        'copyOk': copyOk,
        'errors': errors.toJson(),
        'logFormat': logFormat.name,
      };
}

/// Top-level result from parsing a complete log file.
class RipLog {
  /// Which tool generated this log.
  final RipLogFormat logFormat;

  /// Tool version string (e.g. "V1.6" for EAC, "20230916 (153.8)" for XLD).
  final String? toolVersion;

  /// Date and time the extraction was performed.
  final DateTime? extractionDate;

  /// Drive information.
  final DriveInfo? drive;

  /// Read / rip mode (e.g. "Secure", "Paranoid", "Burst").
  final String? readMode;

  /// Read-offset correction in samples.
  final int? readOffset;

  /// Whether overread into lead-in / lead-out was enabled.
  final bool? overread;

  /// Gap handling description.
  final String? gapHandling;

  /// Media type description (e.g. "Pressed CD").
  final String? mediaType;

  /// Parsed per-track data, in track order.
  final List<RipLogTrack> tracks;

  /// AccurateRip summary line from the log footer.
  final String? accurateRipSummary;

  /// Integrity / checksum hash embedded in the log (EAC/XLD log signature).
  final String? integrityHash;

  /// Any parsing warnings accumulated during parsing.
  final List<String> errors;

  const RipLog({
    required this.logFormat,
    this.toolVersion,
    this.extractionDate,
    this.drive,
    this.readMode,
    this.readOffset,
    this.overread,
    this.gapHandling,
    this.mediaType,
    List<RipLogTrack>? tracks,
    this.accurateRipSummary,
    this.integrityHash,
    List<String>? errors,
  })  : tracks = tracks ?? const [],
        errors = errors ?? const [];

  /// Convert to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'logFormat': logFormat.name,
        if (toolVersion != null) 'toolVersion': toolVersion,
        if (extractionDate != null)
          'extractionDate': extractionDate!.toIso8601String(),
        if (drive != null) 'drive': drive!.toJson(),
        if (readMode != null) 'readMode': readMode,
        if (readOffset != null) 'readOffset': readOffset,
        if (overread != null) 'overread': overread,
        if (gapHandling != null) 'gapHandling': gapHandling,
        if (mediaType != null) 'mediaType': mediaType,
        'tracks': tracks.map((t) => t.toJson()).toList(),
        if (accurateRipSummary != null)
          'accurateRipSummary': accurateRipSummary,
        if (integrityHash != null) 'integrityHash': integrityHash,
        'errors': errors,
      };
}
