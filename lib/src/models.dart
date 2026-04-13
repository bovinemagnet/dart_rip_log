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

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is! String) return fallback;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
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

  /// Reconstruct a [DriveInfo] from its JSON form (as produced by [toJson]).
  factory DriveInfo.fromJson(Map<String, dynamic> json) => DriveInfo(
        name: json['name'] as String,
        readOffset: json['readOffset'] as int?,
        adapter: json['adapter'] as String?,
      );

  /// Convert to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'name': name,
        if (readOffset != null) 'readOffset': readOffset,
        if (adapter != null) 'adapter': adapter,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DriveInfo &&
          other.name == name &&
          other.readOffset == readOffset &&
          other.adapter == adapter);

  @override
  int get hashCode => Object.hash(name, readOffset, adapter);
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

  /// Reconstruct a [TrackErrors] from its JSON form. Missing fields default
  /// to `0` so partial payloads are tolerated.
  factory TrackErrors.fromJson(Map<String, dynamic> json) => TrackErrors(
        readErrors: (json['readErrors'] as int?) ?? 0,
        skipErrors: (json['skipErrors'] as int?) ?? 0,
        jitterErrors: (json['jitterErrors'] as int?) ?? 0,
        edgeJitterErrors: (json['edgeJitterErrors'] as int?) ?? 0,
        atomJitterErrors: (json['atomJitterErrors'] as int?) ?? 0,
        driftErrors: (json['driftErrors'] as int?) ?? 0,
        droppedBytes: (json['droppedBytes'] as int?) ?? 0,
        duplicatedBytes: (json['duplicatedBytes'] as int?) ?? 0,
        inconsistentErrorSectors:
            (json['inconsistentErrorSectors'] as int?) ?? 0,
        damagedSectors: (json['damagedSectors'] as int?) ?? 0,
      );

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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrackErrors &&
          other.readErrors == readErrors &&
          other.skipErrors == skipErrors &&
          other.jitterErrors == jitterErrors &&
          other.edgeJitterErrors == edgeJitterErrors &&
          other.atomJitterErrors == atomJitterErrors &&
          other.driftErrors == driftErrors &&
          other.droppedBytes == droppedBytes &&
          other.duplicatedBytes == duplicatedBytes &&
          other.inconsistentErrorSectors == inconsistentErrorSectors &&
          other.damagedSectors == damagedSectors);

  @override
  int get hashCode => Object.hash(
        readErrors,
        skipErrors,
        jitterErrors,
        edgeJitterErrors,
        atomJitterErrors,
        driftErrors,
        droppedBytes,
        duplicatedBytes,
        inconsistentErrorSectors,
        damagedSectors,
      );
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

  /// Reconstruct a [RipLogTrack] from its JSON form.
  factory RipLogTrack.fromJson(Map<String, dynamic> json) => RipLogTrack(
        trackNumber: json['trackNumber'] as int,
        filename: json['filename'] as String?,
        peakLevel: (json['peakLevel'] as num?)?.toDouble(),
        trackQuality: (json['trackQuality'] as num?)?.toDouble(),
        copyCrc: json['copyCrc'] as String?,
        testCrc: json['testCrc'] as String?,
        accurateRipStatus: _enumByName(AccurateRipStatus.values,
            json['accurateRipStatus'], AccurateRipStatus.notChecked),
        accurateRipCrcV1: json['accurateRipCrcV1'] as String?,
        accurateRipCrcV2: json['accurateRipCrcV2'] as String?,
        accurateRipConfidence: json['accurateRipConfidence'] as int?,
        copyOk: (json['copyOk'] as bool?) ?? false,
        errors: json['errors'] is Map<String, dynamic>
            ? TrackErrors.fromJson(json['errors'] as Map<String, dynamic>)
            : const TrackErrors(),
        logFormat: _enumByName(
            RipLogFormat.values, json['logFormat'], RipLogFormat.unknown),
      );

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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RipLogTrack &&
          other.trackNumber == trackNumber &&
          other.filename == filename &&
          other.peakLevel == peakLevel &&
          other.trackQuality == trackQuality &&
          other.copyCrc == copyCrc &&
          other.testCrc == testCrc &&
          other.accurateRipStatus == accurateRipStatus &&
          other.accurateRipCrcV1 == accurateRipCrcV1 &&
          other.accurateRipCrcV2 == accurateRipCrcV2 &&
          other.accurateRipConfidence == accurateRipConfidence &&
          other.copyOk == copyOk &&
          other.errors == errors &&
          other.logFormat == logFormat);

  @override
  int get hashCode => Object.hash(
        trackNumber,
        filename,
        peakLevel,
        trackQuality,
        copyCrc,
        testCrc,
        accurateRipStatus,
        accurateRipCrcV1,
        accurateRipCrcV2,
        accurateRipConfidence,
        copyOk,
        errors,
        logFormat,
      );
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

  /// Whether the rip was performed in "test and copy" mode (both a test
  /// pass and a copy pass). `null` when the log does not indicate a mode.
  ///
  /// For EAC, derived from the presence of per-track `Test CRC` lines.
  final bool? testAndCopy;

  /// AccurateRip disc identifier, when the log includes one (e.g. XLD).
  final String? accurateRipDiscId;

  /// Total AccurateRip submissions recorded for this disc, when present.
  final int? accurateRipTotalSubmissions;

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
    this.testAndCopy,
    this.accurateRipDiscId,
    this.accurateRipTotalSubmissions,
  })  : tracks = tracks ?? const [],
        errors = errors ?? const [];

  /// Reconstruct a [RipLog] from its JSON form (as produced by [toJson]).
  ///
  /// Unknown enum values degrade to [RipLogFormat.unknown] /
  /// [AccurateRipStatus.notChecked] rather than throwing, so round-tripping
  /// a log produced by a newer library version is safe for consumers on
  /// older versions.
  factory RipLog.fromJson(Map<String, dynamic> json) => RipLog(
        logFormat: _enumByName(
            RipLogFormat.values, json['logFormat'], RipLogFormat.unknown),
        toolVersion: json['toolVersion'] as String?,
        extractionDate: json['extractionDate'] is String
            ? DateTime.tryParse(json['extractionDate'] as String)
            : null,
        drive: json['drive'] is Map<String, dynamic>
            ? DriveInfo.fromJson(json['drive'] as Map<String, dynamic>)
            : null,
        readMode: json['readMode'] as String?,
        readOffset: json['readOffset'] as int?,
        overread: json['overread'] as bool?,
        gapHandling: json['gapHandling'] as String?,
        mediaType: json['mediaType'] as String?,
        tracks: (json['tracks'] as List?)
                ?.cast<Map<String, dynamic>>()
                .map(RipLogTrack.fromJson)
                .toList() ??
            const [],
        accurateRipSummary: json['accurateRipSummary'] as String?,
        integrityHash: json['integrityHash'] as String?,
        errors: (json['errors'] as List?)?.cast<String>() ?? const [],
        testAndCopy: json['testAndCopy'] as bool?,
        accurateRipDiscId: json['accurateRipDiscId'] as String?,
        accurateRipTotalSubmissions:
            json['accurateRipTotalSubmissions'] as int?,
      );

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
        if (testAndCopy != null) 'testAndCopy': testAndCopy,
        if (accurateRipDiscId != null) 'accurateRipDiscId': accurateRipDiscId,
        if (accurateRipTotalSubmissions != null)
          'accurateRipTotalSubmissions': accurateRipTotalSubmissions,
        'errors': errors,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RipLog &&
          other.logFormat == logFormat &&
          other.toolVersion == toolVersion &&
          other.extractionDate == extractionDate &&
          other.drive == drive &&
          other.readMode == readMode &&
          other.readOffset == readOffset &&
          other.overread == overread &&
          other.gapHandling == gapHandling &&
          other.mediaType == mediaType &&
          _listEquals(other.tracks, tracks) &&
          other.accurateRipSummary == accurateRipSummary &&
          other.integrityHash == integrityHash &&
          other.testAndCopy == testAndCopy &&
          other.accurateRipDiscId == accurateRipDiscId &&
          other.accurateRipTotalSubmissions == accurateRipTotalSubmissions &&
          _listEquals(other.errors, errors));

  @override
  int get hashCode => Object.hash(
        logFormat,
        toolVersion,
        extractionDate,
        drive,
        readMode,
        readOffset,
        overread,
        gapHandling,
        mediaType,
        Object.hashAll(tracks),
        accurateRipSummary,
        integrityHash,
        testAndCopy,
        accurateRipDiscId,
        accurateRipTotalSubmissions,
        Object.hashAll(errors),
      );
}
