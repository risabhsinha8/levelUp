import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_up/data/database_helper.dart';
import 'package:level_up/data/rpg_sqlite_repository.dart';
import 'package:level_up/domain/reminder_plan.dart';
import 'package:level_up/models/rpg_models.dart';
import 'package:level_up/models/rpg_state.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fixtures.dart';

final day = DateTime(2026, 11, 10);
final morning = DateTime(2026, 11, 10, 9);

RpgState withLogs(RpgState state, Map<String, List<String>> logs) =>
    state.copyWith(
      logs: [
        for (final MapEntry(:key, :value) in logs.entries)
          DailyLog(dateString: key, completedHabitIds: value),
      ],
    );

PlannedReminder? byId(ReminderPlan plan, int id) =>
    plan.reminders.where((r) => r.id == id).firstOrNull;

/// Read (habit-0) done on each day from [from] through [to] (November).
Map<String, List<String>> readDays(int from, int to) => {
  for (var d = from; d <= to; d++)
    toDateString(DateTime(2026, 11, d)): ['habit-0'],
};

void main() {
  group('ReminderPlanner', () {
    test('plans nothing when reminders are off', () {
      final state = buildFreshState(day);
      final off = state.copyWith(character: state.character.withReminder(null));
      expect(ReminderPlanner.plan(off, morning).reminders, isEmpty);
    });

    test('schedules a week of keystone reminders plus notices', () {
      final plan = ReminderPlanner.plan(buildFreshState(day), morning);

      expect(
        plan.reminders.map((r) => r.id),
        [
          for (var i = 0; i < ReminderPlanner.dailyDaysAhead; i++)
            ReminderPlanner.dailyBaseId + i,
          ReminderPlanner.seasonFinalStretchId,
          ReminderPlanner.seasonOverId,
        ]..insert(4, ReminderPlanner.campfireId),
      );

      final tonight = plan.reminders.first;
      expect(tonight.at, DateTime(2026, 11, 10, 20));
      expect(tonight.title, '5 keystones still open');
      expect(tonight.body, '★ Read · Move · Create · Reach out · Build');
      expect(byId(plan, 101)!.title, 'Keystone check-in');
      expect(
        byId(plan, ReminderPlanner.campfireId)!.at,
        DateTime(2026, 11, 14, 10),
      );
      // Season 1 is Q4: its last day is Dec 31.
      expect(
        byId(plan, ReminderPlanner.seasonFinalStretchId)!.at,
        DateTime(2026, 12, 29, 10),
      );
      expect(
        byId(plan, ReminderPlanner.seasonOverId)!.at,
        DateTime(2027, 1, 1, 10),
      );
    });

    test("names only open keystones and drops today's once all are done", () {
      final fresh = buildFreshState(day);
      final some = withLogs(fresh, {
        '2026-11-10': ['habit-0', 'habit-1', 'habit-2'],
      });
      final tonight = byId(ReminderPlanner.plan(some, morning), 100)!;
      expect(tonight.title, '2 keystones still open');
      expect(tonight.body, '★ Reach out · Build');

      final all = withLogs(fresh, {
        '2026-11-10': ['habit-0', 'habit-1', 'habit-2', 'habit-3', 'habit-4'],
      });
      final plan = ReminderPlanner.plan(all, morning);
      expect(byId(plan, 100), isNull);
      expect(byId(plan, 101), isNotNull);
    });

    test('skips times already passed and uses the chosen time', () {
      final state = buildFreshState(day);
      final late = ReminderPlanner.plan(state, DateTime(2026, 11, 10, 21));
      expect(byId(late, 100), isNull);

      final early = state.copyWith(
        character: state.character.withReminder(7 * 60 + 30),
      );
      final plan = ReminderPlanner.plan(early, DateTime(2026, 11, 10, 8));
      expect(byId(plan, 100), isNull);
      expect(byId(plan, 101)!.at, DateTime(2026, 11, 11, 7, 30));
    });

    test('nudges when one more keystone day earns a Common Key', () {
      final fresh = buildFreshState(day);
      // Nov 4–9 is a 6-day run: today's check-in would be the 7th.
      final sixDays = withLogs(fresh, readDays(4, 9));
      expect(
        byId(ReminderPlanner.plan(sixDays, morning), 100)!.body,
        contains('One more day of Read earns a Common Key.'),
      );

      // Already done today (Nov 5–10): tomorrow's reminder carries it.
      final doneToday = withLogs(fresh, readDays(5, 10));
      final plan = ReminderPlanner.plan(doneToday, morning);
      expect(byId(plan, 101)!.body, 'One more day of Read earns a Common Key.');
      expect(byId(plan, 102)!.body, isNot(contains('Common Key')));
    });

    test('mentions a node waiting to be forged', () {
      // Read on 5 days earns Mind's first node, not yet forged.
      final state = withLogs(buildFreshState(day), readDays(1, 5));
      expect(
        byId(ReminderPlanner.plan(state, morning), 100)!.body,
        contains('A skill node is ready to forge.'),
      );
    });

    test('moves the campfire to next month after the 14th', () {
      final plan = ReminderPlanner.plan(
        buildFreshState(day),
        DateTime(2026, 11, 14, 11),
      );
      expect(
        byId(plan, ReminderPlanner.campfireId)!.at,
        DateTime(2026, 12, 14, 10),
      );
    });

    test('sends no season notices once the season is over', () {
      final plan = ReminderPlanner.plan(
        buildFreshState(day),
        DateTime(2027, 1, 2, 9),
      );
      expect(byId(plan, ReminderPlanner.seasonFinalStretchId), isNull);
      expect(byId(plan, ReminderPlanner.seasonOverId), isNull);
      expect(byId(plan, 100), isNotNull);
    });
  });

  group('reminder time storage', () {
    setUpAll(sqfliteFfiInit);

    test('backups keep "off" and older backups get the default', () {
      const off = Character(
        name: 'Ari',
        classTitle: 'Novice',
        currentSeasonId: 's',
        reminderMinutes: null,
      );
      expect(Character.fromJson(off.toJson()).reminderMinutes, isNull);
      final old = off.toJson()..remove('reminderMinutes');
      expect(
        Character.fromJson(old).reminderMinutes,
        Character.defaultReminderMinutes,
      );
    });

    test(
      'SQLite saves the time, and upgrading from v6 turns them on',
      () async {
        final dir = await Directory.systemTemp.createTemp('level_up_db');
        addTearDown(() => dir.delete(recursive: true));
        final path = p.join(dir.path, DatabaseHelper.fileName);
        RpgSqliteRepository open() => RpgSqliteRepository(
          DatabaseHelper(factory: databaseFactoryFfi, path: path),
        );

        final first = open();
        final state = buildFreshState(day);
        await first.initializeFromOnboarding(state);
        await first.updateCharacter(state.character.withReminder(6 * 60));
        expect(
          (await first.loadFullState())!.character.reminderMinutes,
          6 * 60,
        );
        await first.updateCharacter(state.character.withReminder(null));
        expect(
          (await first.loadFullState())!.character.reminderMinutes,
          isNull,
        );
        await first.close();

        // Roll the file back to v6 (no reminder column) and reopen.
        final raw = await databaseFactoryFfi.openDatabase(path);
        await raw.execute(
          'ALTER TABLE characters DROP COLUMN reminder_minutes',
        );
        await raw.setVersion(6);
        await raw.close();

        final upgraded = open();
        addTearDown(upgraded.close);
        expect(
          (await upgraded.loadFullState())!.character.reminderMinutes,
          Character.defaultReminderMinutes,
        );
      },
    );
  });

  testWidgets('the app schedules the plan and Settings switches it off', (
    tester,
  ) async {
    final reminders = FakeReminderScheduler();
    await pumpLevelUp(
      tester,
      now: morning,
      state: buildFreshState(day),
      reminders: reminders,
    );
    expect(reminders.permissionRequests, 1);
    expect(byId(reminders.scheduled, 100)!.title, '5 keystones still open');

    await tester.tap(find.text('Season Tally').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Reminders'), 300);
    expect(find.textContaining('Keystones at 8:00 PM'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Reminders'),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    expect(readState(tester).character.reminderMinutes, isNull);
    expect(reminders.scheduled.reminders, isEmpty);
    expect(find.text('Off'), findsOneWidget);
  });
}
