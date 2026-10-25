import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_up/models/rpg_models.dart';

import 'support/fixtures.dart';

final now = DateTime(2026, 10, 24, 15, 42);

Future<void> pumpQuests(WidgetTester tester) async {
  await pumpLevelUp(
    tester,
    now: now,
    state: buildDemoState(now),
    size: const Size(800, 2400),
  );
  await tester.tap(find.text('Quests & Loot'));
  await tester.pumpAndSettle();
}

Future<void> openLoot(WidgetTester tester) async {
  await tester.tap(find.text('Loot Table'));
  await tester.pumpAndSettle();
}

/// Lets snackbars time out so no timers are left pending.
Future<void> flushSnackBars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  group('Quest Log', () {
    testWidgets('main quest hero card completes for +1 skill point', (
      tester,
    ) async {
      await pumpQuests(tester);

      expect(find.text('MONTH 1 MAIN QUEST'), findsOneWidget);
      expect(find.text('Finish one non-fiction book'), findsOneWidget);
      expect(find.text('A new hardcover of my choice'), findsOneWidget);
      expect(find.bySemanticsLabel('Difficulty 3 of 5'), findsWidgets);
      expect(find.text('Month 1 · now'), findsOneWidget);
      expect(find.bySemanticsLabel('Level 9'), findsOneWidget);

      await tester.tap(find.text('Complete Main Quest (+1 Skill Point)'));
      await tester.pumpAndSettle();
      expect(
        readState(
          tester,
        ).quests.firstWhere((q) => q.id == 'quest-book').isCompleted,
        isTrue,
      );
      expect(find.text('Quest Complete · Tap to undo'), findsOneWidget);
      expect(
        find.text('Main Quest complete! +1 Feat · Mind Lv 3 → 4'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Level 10'), findsOneWidget);
      await flushSnackBars(tester);
    });

    testWidgets('checking a side quest adds a feat; unchecking removes it', (
      tester,
    ) async {
      await pumpQuests(tester);

      expect(find.text('Master 50 French words'), findsOneWidget);
      expect(find.text('Read 10 chapters in one sitting'), findsOneWidget);
      expect(find.text('1/3 feats'), findsOneWidget);

      await tester.tap(find.text('Master 50 French words'));
      await tester.pumpAndSettle();
      expect(find.text('2/3 feats'), findsOneWidget);
      expect(find.bySemanticsLabel('Level 10'), findsOneWidget);

      await tester.tap(find.text('Master 50 French words'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Level 9'), findsOneWidget);
    });

    testWidgets('month chips switch quests; empty month offers a main quest', (
      tester,
    ) async {
      await pumpQuests(tester);

      await tester.tap(find.text('Month 2'));
      await tester.pumpAndSettle();
      expect(find.text('No Main Quest for Month 2'), findsOneWidget);
      expect(find.text('Host a dinner for friends'), findsOneWidget);

      await tester.tap(find.text('Month 3'));
      await tester.pumpAndSettle();
      expect(find.text('MONTH 3 MAIN QUEST'), findsOneWidget);
    });

    testWidgets('FAB adds a side quest to the selected month', (tester) async {
      await pumpQuests(tester);

      await tester.tap(find.text('New Quest'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Side Quest'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Quest'),
        'Sketch 30 hands',
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Craft'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Side Quest'));
      await tester.pumpAndSettle();

      final quest = readState(
        tester,
      ).quests.firstWhere((q) => q.title == 'Sketch 30 hands');
      expect(quest.isMainQuest, isFalse);
      expect(quest.branch, BranchType.craft);
      expect(quest.monthIndex, 1);
      expect(find.text('Sketch 30 hands'), findsOneWidget);
    });

    testWidgets('FAB is hidden on the Loot Table tab', (tester) async {
      await pumpQuests(tester);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      await openLoot(tester);
      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });

  group('Loot Table', () {
    testWidgets('wallet shows available keys per tier', (tester) async {
      await pumpQuests(tester);
      await openLoot(tester);

      expect(find.text('Loot Keys Wallet'), findsOneWidget);
      expect(find.bySemanticsLabel('2 Common keys available'), findsOneWidget);
      // 6 Rare earned, 1 already spent on the sketchbook.
      expect(find.bySemanticsLabel('5 Rare keys available'), findsOneWidget);
      expect(find.bySemanticsLabel('0 Epic keys available'), findsOneWidget);
      expect(
        find.bySemanticsLabel('0 Legendary keys available'),
        findsOneWidget,
      );
      expect(find.text('Ice cream party'), findsOneWidget);
      expect(find.text('Binge TV night'), findsOneWidget);
      expect(find.text('New guitar gear'), findsOneWidget);
    });

    testWidgets('claiming spends a key and logs a timestamped history entry', (
      tester,
    ) async {
      await pumpQuests(tester);
      await openLoot(tester);

      Finder claimButtonFor(String title) => find.descendant(
        of: find.ancestor(of: find.text(title), matching: find.byType(Card)),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      );

      // Epic: no keys, so the button is disabled.
      expect(
        tester
            .widget<FilledButton>(claimButtonFor('New guitar gear'))
            .onPressed,
        isNull,
      );

      await tester.tap(claimButtonFor('Ice cream party'));
      await tester.pumpAndSettle();
      expect(find.text('LOOT UNLOCKED!'), findsOneWidget);
      await tester.tap(find.text('Onward'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('1 Common keys available'), findsOneWidget);
      expect(find.text('Common · Oct 24, 2026 · 3:42 PM'), findsOneWidget);
      // The reward stays in the table for next time.
      expect(find.text('Ice cream party'), findsNWidgets(2));
      // Older seeded claim is listed too.
      expect(find.text('Fancy new sketchbook'), findsOneWidget);
      await flushSnackBars(tester);
    });

    testWidgets('adding a custom reward to a tier', (tester) async {
      await pumpQuests(tester);
      await openLoot(tester);

      await tester.tap(find.text('Add Legendary reward'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Trip to Japan');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('Trip to Japan'), findsOneWidget);
      expect(
        readState(
          tester,
        ).loot.firstWhere((l) => l.title == 'Trip to Japan').tier,
        LootTier.legendary,
      );
    });
  });

  testWidgets('lays out without overflow on a 320pt-wide phone', (
    tester,
  ) async {
    await pumpQuests(tester);
    tester.view.physicalSize = const Size(320, 2400);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await openLoot(tester);
    expect(tester.takeException(), isNull);
  });
}
