/// Pure reconciliation logic for pulling cloud state into the local store.
///
/// Kept free of Supabase and Hive so it can be unit tested. The rules rely on
/// one invariant maintained by the app: every local edit enqueues a sync
/// mutation, and a record is only marked synced once its latest edit has been
/// pushed. So when an entity has no pending mutation, the local copy *is* the
/// last state this device saw in the cloud, and any difference from the cloud
/// means another device changed it. That avoids comparing clocks across
/// devices entirely.
library;

/// What the planner needs to know about one local record.
class LocalEntityState {
  const LocalEntityState({
    required this.updatedAt,
    required this.synced,
  });

  /// The record's `updatedAt`, which equals the cloud row's `updated_at` for
  /// anything that has been pushed or pulled.
  final DateTime updatedAt;

  /// True once the record has reached the cloud (i.e. `localOnly == false`).
  final bool synced;
}

class SyncPlan {
  const SyncPlan({
    required this.fetch,
    required this.deleteLocal,
    required this.reupload,
    required this.skippedMassDelete,
  });

  /// Cloud rows that are new or changed and must be downloaded.
  final List<String> fetch;

  /// Local records that were synced before but no longer exist in the cloud
  /// (permanently deleted on another device).
  final List<String> deleteLocal;

  /// Local records that never reached the cloud and have no pending mutation
  /// (e.g. a queue lost to an older app version). They get re-queued.
  final List<String> reupload;

  /// True when deletions were suppressed by the empty-cloud safety guard.
  final bool skippedMassDelete;

  bool get isEmpty => fetch.isEmpty && deleteLocal.isEmpty && reupload.isEmpty;
}

class SyncPlanner {
  const SyncPlanner._();

  /// If the cloud reports zero rows while this device holds more than this many
  /// synced records, treat it as an anomaly (auth hiccup, wrong project) rather
  /// than a real mass deletion, and keep the local data.
  static const int emptyCloudGuardThreshold = 3;

  static SyncPlan plan({
    required Map<String, LocalEntityState> local,
    required Map<String, DateTime> remote,
    required Set<String> pending,
  }) {
    final List<String> fetch = <String>[];
    final List<String> deleteLocal = <String>[];
    final List<String> reupload = <String>[];

    remote.forEach((String id, DateTime remoteUpdatedAt) {
      if (pending.contains(id)) {
        return; // our unsynced edit wins; it will be pushed next
      }
      final LocalEntityState? mine = local[id];
      if (mine == null || !_sameInstant(mine.updatedAt, remoteUpdatedAt)) {
        fetch.add(id);
      }
    });

    local.forEach((String id, LocalEntityState mine) {
      if (remote.containsKey(id) || pending.contains(id)) {
        return;
      }
      if (mine.synced) {
        deleteLocal.add(id);
      } else {
        reupload.add(id);
      }
    });

    final int syncedLocalCount =
        local.values.where((LocalEntityState s) => s.synced).length;
    final bool guard =
        remote.isEmpty && syncedLocalCount > emptyCloudGuardThreshold;

    return SyncPlan(
      fetch: fetch,
      deleteLocal: guard ? const <String>[] : deleteLocal,
      reupload: reupload,
      skippedMassDelete: guard && deleteLocal.isNotEmpty,
    );
  }

  /// Compared at millisecond precision: web builds (JavaScript numbers) cannot
  /// represent the microseconds Postgres and native Dart keep.
  static bool _sameInstant(DateTime a, DateTime b) =>
      a.millisecondsSinceEpoch == b.millisecondsSinceEpoch;
}
