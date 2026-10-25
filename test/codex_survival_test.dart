import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_up/providers/rpg_store_provider.dart';
import 'package:level_up/screens/codex_guide_screen.dart';

import 'support/fixtures.dart';

final today = DateTime(2026, 10, 24, 9);

void main() {
  group("Adventurer's Codex", () {
    testWidgets('opens from the header with all four chapters', (tester) async {
      await pumpLevelUp(
        tester,
        now: today,
        state: buildDemoState(today),
        size: const Size(800, 3200),
      );
      await tester.tap(find.byTooltip("Adventurer's Codex"));
      await tester.pumpAndSettle();

      expect(find.byType(CodexGuideScreen), findsOneWidget);
      for (final title in [
        'The Golden Rule',
        'The 90-Day Skill Tree',
        'The Leveling Formula',
        'The 4-Tier Loot Economy',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      expect(
        find.text('Every 7-day unbroken streak on a ★ Keystone Habit.'),
        findsOneWidget,
      );
      expect(
        find.text('Completing all 25 nodes across the entire Skill Tree.'),
        findsOneWidget,
      );
    });

    testWidgets('previews the formula with the live character', (tester) async {
      await pumpLevelUp(
        tester,
        now: today,
        state: buildDemoState(today),
        size: const Size(800, 3200),
      );
      await tester.tap(find.byTooltip("Adventurer's Codex"));
      await tester.pumpAndSettle();

      // Mind: base 1 + 2 nodes + 0 feats. Craft: 0 + 1 + 1.
      expect(find.text('1 + 2 + 0 = 3'), findsNWidgets(2)); // Mind, Body
      expect(find.text('0 + 1 + 1 = 2'), findsOneWidget);
      expect(
        find.text('3 + 3 + 2 + 1 + 0 = Character Level 9'),
        findsOneWidget,
      );
      // 2 Common keys; 6 Rare earned with 1 claimed.
      Finder keys(String label) => find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == label,
      );
      expect(keys('2 Common keys ready'), findsOneWidget);
      expect(keys('5 Rare keys ready'), findsOneWidget);
    });

    testWidgets('the golden rule and node bar are interactive', (tester) async {
      await pumpLevelUp(
        tester,
        now: today,
        state: buildDemoState(today),
        size: const Size(800, 3200),
      );
      await tester.tap(find.byTooltip("Adventurer's Codex"));
      await tester.pumpAndSettle();

      expect(
        find.text('Your ★ keystone alone secures the full point.'),
        findsOneWidget,
      );
      await tester.tap(find.text('3 habits'));
      await tester.pumpAndSettle();
      expect(
        find.text('Extra habits are great for you, but Body still earns +1.'),
        findsOneWidget,
      );
      expect(find.text('+1'), findsOneWidget);

      // Starts at the best branch (17 days), drag to the end of the season.
      expect(
        find.text('17 active days → 2 of 5 nodes unlocked'),
        findsOneWidget,
      );
      await tester.drag(find.byType(Slider), const Offset(2000, 0));
      await tester.pumpAndSettle();
      expect(
        find.text('86 active days → 5 of 5 nodes unlocked'),
        findsOneWidget,
      );
      expect(
        find.text('Branch mastered: an Epic Key is yours.'),
        findsOneWidget,
      );
    });

    testWidgets('opens from Settings too', (tester) async {
      await pumpLevelUp(
        tester,
        now: today,
        state: buildDemoState(today),
        size: const Size(800, 3200),
      );
      await tester.tap(find.text('Season Tally').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, "Adventurer's Codex"));
      await tester.pumpAndSettle();
      expect(find.byType(CodexGuideScreen), findsOneWidget);
    });

    testWidgets('fits a 320pt-wide phone', (tester) async {
      await pumpLevelUp(
        tester,
        now: today,
        state: buildDemoState(today),
        size: const Size(320, 3200),
      );
      await tester.tap(find.byTooltip("Adventurer's Codex"));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Survival Mode', () {
    testWidgets('shows only keystones with a reassuring banner', (
      tester,
    ) async {
      await pumpLevelUp(tester, now: today, state: buildDemoState(today));
      expect(find.text('Water'), findsOneWidget);
      expect(find.textContaining('Survival Mode Active'), findsNothing);

      await tester.tap(find.text('Survival Mode (Low Energy)'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Survival Mode Active: Just secure your ★ Keystones today. '
          '1 Keystone = +1 Full Branch Active Day.',
        ),
        findsOneWidget,
      );
      for (final secondary in [
        'Water',
        'Sleep',
        'Meditation',
        'French practice',
      ]) {
        expect(find.text(secondary), findsNothing, reason: secondary);
      }
      for (final keystone in [
        'Exercise',
        'Reading',
        'Sketching',
        'Call family/friends',
        'Work on side project',
      ]) {
        expect(find.text(keystone), findsOneWidget, reason: keystone);
      }

      // One keystone secures the branch's full point.
      await tester.tap(find.text('Exercise'));
      await tester.pumpAndSettle();
      expect(find.text('+1 Branch Point Secured'), findsOneWidget);

      await tester.tap(find.text('Survival Mode (Low Energy)'));
      await tester.pumpAndSettle();
      expect(find.text('Water'), findsOneWidget);
      expect(find.textContaining('Survival Mode Active'), findsNothing);
    });

    test('lasts for the day it was switched on', () async {
      var now = DateTime(2026, 10, 24, 21);
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          rpgRepositoryProvider.overrideWithValue(
            InMemoryRepository(buildDemoState(today)),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(survivalModeProvider), isFalse);
      container.read(survivalModeDateProvider.notifier).set(on: true);
      expect(container.read(survivalModeProvider), isTrue);

      now = DateTime(2026, 10, 25, 7);
      container.read(todayProvider.notifier).refresh();
      expect(container.read(survivalModeProvider), isFalse);
    });
  });
}
