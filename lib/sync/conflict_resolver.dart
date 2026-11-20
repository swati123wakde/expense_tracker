/// Field-level three-way merge between a local pending record and an
/// incoming cloud record.
///
/// For every mergeable field we compare both sides against the common
/// ancestor (`base` — the version both devices last agreed on):
///
/// | local changed | remote changed | result                                |
/// |---------------|----------------|---------------------------------------|
/// | no            | no             | base (== remote)                      |
/// | yes           | no             | local                                 |
/// | no            | yes            | remote                                |
/// | yes           | yes, same val  | that value                            |
/// | yes           | yes, different | Last-Write-Wins on record updated_at  |
///
/// So a note edit on device A and an amount edit on device B both survive;
/// only a genuine same-field conflict falls back to LWW. LWW ties are broken
/// by comparing the values themselves so every device picks the same winner
/// regardless of which side is "local".
///
/// With no base (record created independently on two devices with the same
/// deterministic id, e.g. seeded categories) every differing field is a
/// conflict and is resolved by LWW.
class ConflictResolver {
  ConflictResolver._();

  static MergeOutcome merge({
    required Map<String, Object?>? base,
    required Map<String, Object?> local,
    required Map<String, Object?> remote,
    required List<String> fields,
  }) {
    final localUpdated = _ms(local['updated_at']);
    final remoteUpdated = _ms(remote['updated_at']);

    final merged = <String, Object?>{...remote};
    final conflicts = <String>[];
    final fromLocal = <String>[];

    for (final f in fields) {
      final l = local[f];
      final r = remote[f];
      if (_eq(l, r)) {
        merged[f] = r;
        continue;
      }
      final localChanged = base == null || !_eq(l, base[f]);
      final remoteChanged = base == null || !_eq(r, base[f]);

      if (localChanged && !remoteChanged) {
        merged[f] = l;
        fromLocal.add(f);
      } else if (!localChanged && remoteChanged) {
        merged[f] = r;
      } else {
        // Both sides changed the same field to different values.
        conflicts.add(f);
        final localWins = localUpdated > remoteUpdated ||
            (localUpdated == remoteUpdated && _tieBreak(l, r));
        merged[f] = localWins ? l : r;
        if (localWins) fromLocal.add(f);
      }
    }

    merged['id'] = remote['id'] ?? local['id'];
    merged['user_id'] = remote['user_id'] ?? local['user_id'];
    merged['created_at'] = _min(local['created_at'], remote['created_at']);
    merged['updated_at'] = localUpdated > remoteUpdated ? localUpdated : remoteUpdated;

    return MergeOutcome(
      merged: merged,
      conflictedFields: conflicts,
      localFields: fromLocal,
    );
  }

  static int _ms(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  static Object? _min(Object? a, Object? b) {
    if (a == null) return b;
    if (b == null) return a;
    return _ms(a) <= _ms(b) ? a : b;
  }

  static bool _eq(Object? a, Object? b) {
    if (a is num && b is num) return a == b;
    return a == b;
  }

  /// Deterministic, perspective-independent tie break: higher string value wins.
  static bool _tieBreak(Object? local, Object? remote) =>
      '${local ?? ''}'.compareTo('${remote ?? ''}') > 0;
}

class MergeOutcome {
  const MergeOutcome({
    required this.merged,
    required this.conflictedFields,
    required this.localFields,
  });

  /// The merged record (content columns).
  final Map<String, Object?> merged;

  /// Fields edited on both sides with different values (resolved by LWW).
  final List<String> conflictedFields;

  /// Fields whose merged value came from the local side. If non-empty the
  /// merged record differs from the cloud and must be uploaded.
  final List<String> localFields;

  bool get needsUpload => localFields.isNotEmpty;
}
