import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_up/domain/history.dart';
import 'package:level_up/domain/rpg_engine.dart';
import 'package:level_up/domain/season_rollover.dart';
import 'package:level_up/models/rpg_models.dart';
import 'package:level_up/models/rpg_state.dart';
import 'package:level_up/providers/rpg_store_provider.dart';
import 'package:level_up/screens/habit_history_screen.dart';
import 'package:level_up/screens/season_detail_screen.dart';

import 'support/fixtures.dart';

final today = DateTime(2026, 10, 24, 9);

/// After the demo season's quarter has ended.
final afterSeason = DateTime(2027, 1, 2, 9);

Habit habitOf(RpgState state, String id) =>
    state.habits.firstWhere((h) => h.id == id);

/// The demo character with Season 1 completed and Season 2 underway.
RpgState rolledOver() => SeasonRollover.apply(
  buildDemoState(today),
  afterSeason,
  newSeasonId: 'season-2',
).state;

ProviderContainer makeContainer(InMemoryRepository repo) {
  final container = ProviderContainer(
    overrides: [
      clockProvider.overrideWithValue(() => today),
      rpgRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('the longest run counts consecutive days only', () {
    expect(RpgEngine.calculateLongestRun(const []), 0);
    expect(
      RpgEngine.calculateLongestRun(const [
        '2026-10-03',
        '2026-10-01',
        '2026-10-02',
        '2026-10-02',
        '2026-10-05',
      ]),
      3,
    );
  });

  group('HabitHistory', () {
    final demo = buildDemoState(today);

    test('totals, best run and dates across the habit\'s life', () {
      final history = HabitHistory.of(demo, habitOf(demo, 'habit-exercise'));
      expect(history.totalDays, 13);
      expect(history.bestRun, 7);
      expect(history.firstDate, '2026-10-07');
      expect(history.lastDate, '2026-10-22');
      expect(history.perSeason.single.days, 13);
    });

    test('per season, newest first', () {
      final state = rolledOver().copyWith(
        logs: [
          ...demo.logs,
          DailyLog(
            dateString: '2027-01-02',
            completedHabitIds: ['habit-exercise'],
          ),
        ],
      );
      final history = HabitHistory.of(state, habitOf(state, 'habit-exercise'));
      expect(history.perSeason.map((s) => (s.season.id, s.days)), [
        ('season-2', 1),
        ('season-1', 13),
      ]);
      expect(history.months(afterSeason).map((m) => m.month), [1, 12, 11, 10]);
    });

    test('a habit never done has no dates and just this month', () {
      const habit = Habit(id: 'new', branch: BranchType.mind, title: 'New');
      final history = HabitHistory.of(demo, habit);
      expect(history.totalDays, 0);
      expect(history.firstDate, isNull);
      expect(history.months(today), [DateTime.utc(2026, 10)]);
    });
  });

  test('SeasonRecord keeps a completed season\'s quests and habits', () {
    final state = rolledOver();
    final record = SeasonRecord.of(state, state.archivedSeasons.single);
    expect(record.quests, hasLength(buildDemoState(today).quests.length));
    expect(record.quests.first.isMainQuest, isTrue);
    expect(
      record.habits.first.days,
      greaterThanOrEqualTo(record.habits.last.days),
    );
    expect(record.habits.map((h) => h.habit.id), contains('habit-water'));

    final current = SeasonRecord.of(state, state.currentSeason);
    expect(current.quests, isEmpty);
    expect(current.habits, isEmpty);
  });

  group('archive and restore', () {
    test(
      'archiving keeps a habit with no check-ins; restore brings it back',
      () async {
        final repo = InMemoryRepository(buildDemoState(today));
        final container = makeContainer(repo);
        final store = container.read(rpgStoreProvider.notifier);
        await container.read(rpgStoreProvider.future);
        final id = await store.addOrUpdateHabit(
          branch: BranchType.body,
          title: 'Stretch',
        );

        await store.archiveHabit(id);
        expect(habitOf(repo.saved!, id).isArchived, isTrue);
        expect(repo.saved!.activeHabits.map((h) => h.id), isNot(contains(id)));

        await store.restoreHabit(id);
        expect(habitOf(repo.saved!, id).isArchived, isFalse);
      },
    );

    test('an archived keystone loses its star but keeps its history', () async {
      final repo = InMemoryRepository(buildDemoState(today));
      final container = makeContainer(repo);
      final store = container.read(rpgStoreProvider.notifier);
      await container.read(rpgStoreProvider.future);
      final keysBefore = container
          .read(characterSheetProvider)
          .value!
          .lootKeys[LootTier.common]!
          .earned;

      await store.archiveHabit('habit-exercise');
      final archived = habitOf(repo.saved!, 'habit-exercise');
      expect(archived.isKeystone, isFalse);
      expect(archived.hasKeystoneHistory, isTrue);
      expect(
        container
            .read(characterSheetProvider)
            .value!
            .lootKeys[LootTier.common]!
            .earned,
        keysBefore,
      );

      await store.restoreHabit('habit-exercise');
      expect(habitOf(repo.saved!, 'habit-exercise').isKeystone, isFalse);
    });

    test('a habit cannot be restored into a resting pillar', () async {
      final demo = buildDemoState(today);
      final state = demo.copyWith(
        habits: [
          for (final h in demo.habits)
            h.id == 'habit-call' ? h.copyWith(isArchived: true) : h,
        ],
        branchConfigs: [
          for (final b in BranchType.values)
            demo
                .configFor(b)
                .copyWith(isEnabled: b == BranchType.bond ? false : null),
        ],
      );
      final repo = InMemoryRepository(state);
      final container = makeContainer(repo);
      await container.read(rpgStoreProvider.future);
      await expectLater(
        container.read(rpgStoreProvider.notifier).restoreHabit('habit-call'),
        throwsArgumentError,
      );
    });
  });

  group('screens', () {
    testWidgets('a past season opens its full record', (tester) async {
      await pumpLevelUp(
        tester,
        now: afterSeason,
        state: rolledOver(),
        size: const Size(800, 3000),
      );
      await tester.tap(find.text('Season Tally').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Season 1'));
      await tester.pumpAndSettle();

      expect(find.byType(SeasonDetailScreen), findsOneWidget);
      expect(find.text('2→9'), findsOneWidget); // Character level.
      expect(find.text('Lv 1 → 3'), findsNWidgets(2)); // Mind and Body.
      expect(find.text('Run a 5K without stopping'), findsOneWidget);
      expect(find.text('Loot Claimed'), findsOneWidget);
    });

    testWidgets('Hall of Seasons invites the first season', (tester) async {
      await pumpLevelUp(
        tester,
        now: today,
        state: buildDemoState(today),
        size: const Size(800, 3000),
      );
      await tester.tap(find.text('Season Tally').last);
      await tester.pumpAndSettle();
      expect(find.text('Your first season is underway'), findsOneWidget);
    });

    testWidgets('habit history: lifetime page and restoring from the archive', (
      tester,
    ) async {
      final demo = buildDemoState(today);
      final repo = await pumpLevelUp(
        tester,
        now: today,
        state: demo.copyWith(
          habits: [
            for (final h in demo.habits)
              h.id == 'habit-water' ? h.copyWith(isArchived: true) : h,
          ],
        ),
        size: const Size(800, 3000),
      );
      await tester.tap(find.byKey(const ValueKey('header-avatar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-habit-history')));
      await tester.pumpAndSettle();
      expect(find.byType(HabitHistoryScreen), findsOneWidget);

      await tester.tap(find.text('Exercise'));
      await tester.pumpAndSettle();
      expect(find.byType(HabitDetailScreen), findsOneWidget);
      expect(find.text('October 2026 · 13d'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('restore-habit-water')));
      await tester.pumpAndSettle();
      expect(habitOf(repo.saved!, 'habit-water').isArchived, isFalse);
      expect(find.text('Restored "Water" to your daily list.'), findsOneWidget);
    });

    testWidgets('archiving from the habit page offers Undo', (tester) async {
      final repo = await pumpLevelUp(
        tester,
        now: today,
        state: buildDemoState(today),
        size: const Size(800, 3000),
      );
      await tester.tap(find.byTooltip('Edit Water'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('detail-archive')));
      await tester.pumpAndSettle();
      expect(habitOf(repo.saved!, 'habit-water').isArchived, isTrue);
      expect(find.text('Archived'), findsOneWidget);
      expect(find.byKey(const ValueKey('detail-restore')), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(habitOf(repo.saved!, 'habit-water').isArchived, isFalse);
    });

    testWidgets('history pages fit a 320pt-wide phone', (tester) async {
      await pumpLevelUp(
        tester,
        now: afterSeason,
        state: rolledOver(),
        size: const Size(320, 3000),
      );
      await tester.tap(find.byKey(const ValueKey('header-avatar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-habit-history')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Water'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Season 1'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
