import 'package:flutter_test/flutter_test.dart';
import 'package:universal_notebook/services/sync_planner.dart';

void main() {
  final DateTime t1 = DateTime.utc(2026, 9, 27, 10);
  final DateTime t2 = DateTime.utc(2026, 9, 27, 11);

  LocalEntityState synced(DateTime at) =>
      LocalEntityState(updatedAt: at, synced: true);
  LocalEntityState unsynced(DateTime at) =>
      LocalEntityState(updatedAt: at, synced: false);

  group('SyncPlanner', () {
    test('downloads rows this device has never seen', () {
      final SyncPlan plan = SyncPlanner.plan(
        local: <String, LocalEntityState>{},
        remote: <String, DateTime>{'a': t1},
        pending: <String>{},
      );
      expect(plan.fetch, <String>['a']);
      expect(plan.deleteLocal, isEmpty);
    });

    test('downloads rows changed on another device', () {
      final SyncPlan plan = SyncPlanner.plan(
        local: <String, LocalEntityState>{'a': synced(t1)},
        remote: <String, DateTime>{'a': t2},
        pending: <String>{},
      );
      expect(plan.fetch, <String>['a']);
    });

    test('skips rows that are already up to date', () {
      final SyncPlan plan = SyncPlanner.plan(
        local: <String, LocalEntityState>{'a': synced(t1)},
        remote: <String, DateTime>{'a': t1},
        pending: <String>{},
      );
      expect(plan.isEmpty, isTrue);
    });

    test('ignores sub-millisecond differences (web precision)', () {
      final SyncPlan plan = SyncPlanner.plan(
        local: <String, LocalEntityState>{
          'a': synced(DateTime.utc(2026, 9, 27, 10, 0, 0, 123)),
        },
        remote: <String, DateTime>{
          'a': DateTime.utc(2026, 9, 27, 10, 0, 0, 123, 456),
        },
        pending: <String>{},
      );
      expect(plan.fetch, isEmpty);
    });

    test('never overwrites a record with unsynced local edits', () {
      final SyncPlan plan = SyncPlanner.plan(
        local: <String, LocalEntityState>{'a': unsynced(t2)},
        remote: <String, DateTime>{'a': t1},
        pending: <String>{'a'},
      );
      expect(plan.fetch, isEmpty);
      expect(plan.deleteLocal, isEmpty);
    });

    test('removes synced records deleted on another device', () {
      final SyncPlan plan = SyncPlanner.plan(
        local: <String, LocalEntityState>{
          'keep': synced(t1),
          'gone': synced(t1),
        },
        remote: <String, DateTime>{'keep': t1},
        pending: <String>{},
      );
      expect(plan.deleteLocal, <String>['gone']);
    });

    test('keeps and re-queues local records that never reached the cloud', () {
      final SyncPlan plan = SyncPlanner.plan(
        local: <String, LocalEntityState>{'draft': unsynced(t1)},
        remote: <String, DateTime>{},
        pending: <String>{},
      );
      expect(plan.deleteLocal, isEmpty);
      expect(plan.reupload, <String>['draft']);
    });

    test('an empty cloud does not wipe a populated device', () {
      final SyncPlan plan = SyncPlanner.plan(
        local: <String, LocalEntityState>{
          for (int i = 0; i < 10; i++) 'n$i': synced(t1),
        },
        remote: <String, DateTime>{},
        pending: <String>{},
      );
      expect(plan.deleteLocal, isEmpty);
      expect(plan.skippedMassDelete, isTrue);
    });

    test('a pending delete is not re-downloaded', () {
      final SyncPlan plan = SyncPlanner.plan(
        local: <String, LocalEntityState>{},
        remote: <String, DateTime>{'a': t1},
        pending: <String>{'a'},
      );
      expect(plan.fetch, isEmpty);
    });
  });
}
