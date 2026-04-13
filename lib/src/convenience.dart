import 'models.dart';

/// Returns `true` if every track in [log] was accurately ripped.
///
/// An empty track list returns `true` (vacuously verified).
bool isFullyVerified(RipLog log) =>
    log.tracks.every((t) => t.accurateRipStatus == AccurateRipStatus.verified);

/// Returns the subset of tracks in [log] that have any non-zero error counts.
List<RipLogTrack> tracksWithErrors(RipLog log) =>
    log.tracks.where((t) => t.errors.hasErrors).toList();

/// Returns the subset of tracks in [log] whose AccurateRip status is
/// [AccurateRipStatus.mismatch].
List<RipLogTrack> tracksWithArMismatch(RipLog log) => log.tracks
    .where((t) => t.accurateRipStatus == AccurateRipStatus.mismatch)
    .toList();

/// Convert [log] to a JSON-compatible map.
Map<String, dynamic> toJson(RipLog log) => log.toJson();
