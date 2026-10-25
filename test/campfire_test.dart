import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_up/domain/rpg_engine.dart';
import 'package:level_up/models/rpg_models.dart';
import 'package:level_up/providers/rpg_store_provider.dart';

import 'support/fixtures.dart';

/// The demo character's check-ins run Oct 7–23.
final demoDay = DateTime(2026, 10, 24);

/// A campfire day; Half 1 so far is Oct 7–15 (9 days).
final campfireDay = DateTime(2026, 10, 16, 9);

const reading = Habit(id: 'read', branch: BranchType.mind, title: 'Read');
const journal = Habit(id: 'journal', branch: BranchType.mind, title: 'Journal');

/// One log per day of October in [days], completing [ids].
List<DailyLog> octoberLogs(Iterable<int> days, List<String> ids) => [
  for (final d in days)
    DailyLog(
      dateString: toDateString(DateTime(2026, 10, d)),
      completedHabitIds: ids,
    ),
];

List<String> ids(List<StrugglingHabit> s) => [for (final x in s) x.habit.id];

void main() {
  group('RpgEngine.findStrugglingHabits', () {
    test('flags Half 1 habits under 25%, worst first', () {
      final demo = buildDemoState(demoDay);
      final struggling = RpgEngine.findStrugglingHabits(
        demo.habits,
        demo.logs,
        campfireDay,
      );
      // French practice: 2 of Oct 7–15. Side project: 1 of 9.
      expect(ids(struggling), ['habit-side-project', 'habit-french']);
      expect(struggling.first.completedDays, 1);
      expect(struggling.first.elapsedDays, 9);
      expect(struggling.last.completionRate, closeTo(2 / 9, 1e-9));
    });

    test('counts elapsed days through yesterday, capped at day 15', () {
      final logs = [
        ...octoberLogs([1], ['journal']),
        ...octoberLogs([1, 2, 3], ['read']),
      ];
      final habits = [reading, journal];
      // Oct 5: days 1–4 elapsed. Journal 1/4 = 25% is not struggling.
      expect(
        ids(
          RpgEngine.findStrugglingHabits(habits, logs, DateTime(2026, 10, 5)),
        ),
        isEmpty,
      );
      // Oct 6: days 1–5. Journal 1/5 = 20% is.
      expect(
        ids(
          RpgEngine.findStrugglingHabits(habits, logs, DateTime(2026, 10, 6)),
        ),
        ['journal'],
      );
      // Late in the month only days 1–15 count: Read 3/15 = 20%.
      final late = RpgEngine.findStrugglingHabits(
        habits,
        logs,
        DateTime(2026, 10, 28),
      );
      expect(ids(late), ['journal', 'read']);
      expect(late.last.elapsedDays, 15);
    });

    test('days before the first check-in are not misses', () {
      // Started on Oct 10; checked off Read on 2 of Oct 10–15.
      final logs = octoberLogs([10, 12], ['read']);
      final struggling = RpgEngine.findStrugglingHabits(
        [reading],
        logs,
        campfireDay,
      );
      expect(struggling, isEmpty); // 2/6 = 33%

      // A character from an earlier month is measured from day 1.
      final older = [
        DailyLog(dateString: '2026-09-20', completedHabitIds: ['read']),
        ...logs,
      ];
      final result = RpgEngine.findStrugglingHabits(
        [reading],
        older,
        campfireDay,
      );
      expect(result.single.completedDays, 2);
      expect(result.single.elapsedDays, 15);
    });

    test('skips archived and Half 2 habits, keeps pivoted Half 1 ones', () {
      final habits = [
        reading.copyWith(activeHalfMonth: ActiveHalfMonth.firstHalf),
        journal.copyWith(activeHalfMonth: ActiveHalfMonth.secondHalf),
        const Habit(
          id: 'old',
          branch: BranchType.mind,
          title: 'Old',
          isArchived: true,
        ),
      ];
      final logs = octoberLogs([1], ['other']);
      expect(ids(RpgEngine.findStrugglingHabits(habits, logs, campfireDay)), [
        'read',
      ]);
    });

    test('nothing is struggling on day 1 or with no check-ins', () {
      final logs = octoberLogs([1], ['other']);
      expect(
        RpgEngine.findStrugglingHabits([reading], logs, DateTime(2026, 10, 1)),
        isEmpty,
      );
      expect(
        RpgEngine.findStrugglingHabits([reading], const [], campfireDay),
        isEmpty,
      );
    });

    test('the campfire is offered on the 14th, 15th and 16th', () {
      bool on(int day) => RpgEngine.isCampfireDay(DateTime(2026, 10, day));
      expect(
        [for (var d = 12; d <= 18; d++) on(d)],
        [false, false, true, true, true, false, false],
      );
    });
  });

  test('pivoting a struggling habit keeps its Half 1 branch days', () async {
    final repo = InMemoryRepository(buildDemoState(demoDay));
    final container = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(() => campfireDay),
        rpgRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    final store = container.read(rpgStoreProvider.notifier);
    await container.read(rpgStoreProvider.future);

    final firstHalf = Season(
      id: 'h1',
      name: 'Half 1',
      startDate: DateTime.utc(2026, 10, 1),
      endDate: DateTime.utc(2026, 10, 15),
    );
    int craftHalf1Days() => RpgEngine.calculateBranchActiveDays(
      BranchType.craft,
      repo.saved!.habits,
      repo.saved!.logs,
      season: firstHalf,
    );
    final before = craftHalf1Days();

    final newId = await store.pivotHabit(
      oldHabitId: 'habit-french',
      newTitle: 'Duolingo',
      month: campfireDay,
    );
    final state = repo.saved!;
    final old = state.habits.firstWhere((h) => h.id == 'habit-french');
    final replacement = state.habits.firstWhere((h) => h.id == newId);
    expect(old.activeHalfMonth, ActiveHalfMonth.firstHalf);
    expect(replacement.activeHalfMonth, ActiveHalfMonth.secondHalf);
    expect(replacement.branch, BranchType.craft);
    expect(craftHalf1Days(), before);
    expect(state.hasCheckIns('habit-french'), isTrue);

    // Half 1 shows French practice; Half 2 shows Duolingo instead.
    List<String> shownOn(int day) => [
      for (final h in state.habitsShownOn(DateTime(2026, 10, day)))
        if (h.branch == BranchType.craft) h.title,
    ];
    expect(shownOn(10), ['Sketching', 'French practice']);
    expect(shownOn(30), ['Sketching', 'Duolingo']);

    // Still listed in the campfire, now as already pivoted.
    final struggling = RpgEngine.findStrugglingHabits(
      state.habits,
      state.logs,
      campfireDay,
    );
    expect(ids(struggling), contains('habit-french'));
  });

  group('Mid-Month Campfire UI', () {
    testWidgets('no banner outside the 14th–16th', (tester) async {
      await pumpLevelUp(tester, now: demoDay, state: buildDemoState(demoDay));
      expect(find.text('Mid-Month Campfire Reflection'), findsNothing);
    });

    testWidgets('the banner glows on campfire days', (tester) async {
      await pumpLevelUp(
        tester,
        now: campfireDay,
        state: buildDemoState(demoDay),
      );
      expect(find.text('Mid-Month Campfire Reflection'), findsOneWidget);
      expect(
        find.text('2 habits struggled in Days 1–15. Pivot for Half 2?'),
        findsOneWidget,
      );
    });

    testWidgets('pivot a struggling habit and save notes from the sheet', (
      tester,
    ) async {
      final repo = await pumpLevelUp(
        tester,
        now: campfireDay,
        state: buildDemoState(demoDay),
      );
      await tester.tap(find.text('Mid-Month Campfire Reflection'));
      await tester.pumpAndSettle();

      expect(find.text('Mid-Month Campfire'), findsOneWidget);
      expect(find.text('French practice'), findsWidgets);
      expect(find.text('2/9 days · 22%'), findsOneWidget);
      expect(find.text('★ Keystone · stays non-negotiable'), findsOneWidget);

      // Only French practice can be pivoted (the side project is a keystone).
      await tester.tap(find.text('Pivot Habit for Days 16–31'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'New habit'),
        'Duolingo',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Pivot'));
      await tester.pumpAndSettle();

      expect(find.text('Pivoted for Days 16–31'), findsOneWidget);
      final saved = repo.saved!;
      expect(
        saved.habits.firstWhere((h) => h.id == 'habit-french').activeHalfMonth,
        ActiveHalfMonth.firstHalf,
      );
      final duolingo = saved.habits.firstWhere((h) => h.title == 'Duolingo');
      expect(duolingo.activeHalfMonth, ActiveHalfMonth.secondHalf);
      expect(saved.reflectionFor(campfireDay).pivots, [
        'French practice → Duolingo',
      ]);

      await tester.enterText(
        find.widgetWithText(TextField, 'Campfire notes'),
        'Mornings work, evenings do not.',
      );
      await tester.tap(find.text('Save Reflection'));
      await tester.pumpAndSettle();
      expect(find.text('Mid-Month Campfire'), findsNothing);
      expect(
        repo.saved!.reflectionFor(campfireDay).notes,
        'Mornings work, evenings do not.',
      );
    });

    testWidgets('the matrix opens the campfire on any day', (tester) async {
      await pumpLevelUp(tester, now: demoDay, state: buildDemoState(demoDay));
      await tester.tap(find.text('Monthly Matrix'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Mid-Month Campfire'));
      await tester.pumpAndSettle();

      expect(find.text('Mid-Month Campfire'), findsOneWidget);
      expect(find.text('Work on side project'), findsWidgets);
    });

    testWidgets('notes are kept when the sheet is swiped away', (tester) async {
      final repo = await pumpLevelUp(
        tester,
        now: campfireDay,
        state: buildDemoState(demoDay),
      );
      await tester.tap(find.text('Mid-Month Campfire Reflection'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Campfire notes'),
        'Too tired after work.',
      );
      // Dismiss by tapping the barrier above the sheet.
      await tester.tapAt(const Offset(400, 10));
      await tester.pumpAndSettle();

      expect(find.text('Mid-Month Campfire'), findsNothing);
      expect(
        repo.saved!.reflectionFor(campfireDay).notes,
        'Too tired after work.',
      );
    });
  });
}
