import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_up/models/rpg_models.dart';
import 'package:level_up/models/rpg_state.dart';
import 'package:level_up/screens/home_shell.dart';
import 'package:level_up/screens/onboarding/onboarding_screen.dart';
import 'package:level_up/screens/onboarding/onboarding_steps.dart';
import 'package:level_up/screens/root_gate.dart';
import 'package:level_up/widgets/oath_signature_card.dart';

import 'support/fixtures.dart';

final today = DateTime(2026, 10, 24);

Finder button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

bool enabled(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(button(label)).onPressed != null;

Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Repository whose first load waits until [finishLoading] is called.
class SlowRepository extends InMemoryRepository {
  SlowRepository([super.saved]);

  final _loaded = Completer<void>();

  void finishLoading() => _loaded.complete();

  @override
  Future<RpgState?> loadFullState() async {
    await _loaded.future;
    return super.loadFullState();
  }
}

/// Fills every step with quick-fill chips, stopping before "Begin Season 1".
Future<void> fillWizard(WidgetTester tester) async {
  // Step 1: Roll Your Character.
  await tester.enterText(
    find.widgetWithText(TextField, 'Character Name'),
    'Ari',
  );
  await tapAndSettle(tester, find.text('Caffeine Paladin'));
  await tapAndSettle(tester, find.text('Next'));

  // Step 2: one keystone chip per branch.
  for (final chip in [
    'Read · 10 pages',
    'Drink water · 13 cups daily',
    'Sketch · 1 rough thumbnail',
    'Call someone · 1 real conversation',
    'Side project · 30 focused min',
  ]) {
    await tapAndSettle(tester, find.text(chip));
  }
  await tapAndSettle(tester, find.text('Next'));

  // Step 3: buff, debuff and main quest.
  await tapAndSettle(tester, find.text('Lay out gym clothes at night'));
  await tapAndSettle(tester, find.text('Phone in bed after 11 PM'));
  await tester.enterText(
    find.widgetWithText(TextField, 'Main quest'),
    'Run a 5K',
  );
  await tester.enterText(find.widgetWithText(TextField, 'Reward'), 'Shoes');
  await tester.pump();
  await tapAndSettle(tester, find.text('Next'));

  // Step 4: one reward per tier.
  for (final chip in [
    'Ice cream night',
    'Buy a new book',
    'Nice dinner out',
    'Big gear upgrade',
  ]) {
    await tapAndSettle(tester, find.text(chip));
  }
  await tapAndSettle(tester, find.text('Next'));
}

Future<void> sign(WidgetTester tester) async {
  final pad = find.byType(SignaturePad);
  // On short screens the pad starts below the fold, unbuilt.
  await tester.scrollUntilVisible(
    pad,
    200,
    scrollable: find
        .descendant(
          of: find.byType(SignOathStep),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.ensureVisible(pad);
  await tester.pumpAndSettle();
  // Start near the top-left, which is on screen even when the pad's center
  // sits behind the bottom bar.
  await tester.dragFrom(
    tester.getTopLeft(pad) + const Offset(30, 20),
    const Offset(160, 20),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('startup gate', () {
    testWidgets('shows the loading screen, then onboarding', (tester) async {
      final repo = SlowRepository();
      await pumpLevelUp(tester, now: today, repository: repo, settle: false);

      expect(find.byType(StartupLoadingScreen), findsOneWidget);
      expect(find.text('Unrolling your character sheet…'), findsOneWidget);

      repo.finishLoading();
      await tester.pumpAndSettle();
      expect(find.byType(StartupLoadingScreen), findsNothing);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
    });

    testWidgets('an onboarded character goes straight to HomeShell', (
      tester,
    ) async {
      final repo = SlowRepository(buildDemoState(today));
      await pumpLevelUp(tester, now: today, repository: repo, settle: false);
      expect(find.byType(StartupLoadingScreen), findsOneWidget);

      repo.finishLoading();
      await tester.pumpAndSettle();
      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
    });
  });

  group('Session Zero wizard', () {
    testWidgets('step 1 shows the branches and the no-punishment rule', (
      tester,
    ) async {
      await pumpLevelUp(tester, now: today);
      expect(find.text('Roll Your Character'), findsOneWidget);
      expect(find.text('Step 1 of 5 · Roll Your Character'), findsOneWidget);
      for (final branch in BranchType.values) {
        expect(find.text(branch.displayName), findsWidgets);
      }
      expect(
        find.text(
          'Cumulative active days over a quarterly Season '
          '(Jan, Apr, Jul, Oct)—no streak-break punishment.',
        ),
        findsOneWidget,
      );
      // Next needs a name and a class.
      expect(enabled(tester, 'Next'), isFalse);
      await tester.enterText(
        find.widgetWithText(TextField, 'Character Name'),
        'Ari',
      );
      await tester.pump();
      expect(enabled(tester, 'Next'), isFalse);
      await tester.tap(find.text('Shadow Monk'));
      await tester.pump();
      expect(enabled(tester, 'Next'), isTrue);
      expect(find.text('Shadow Monk'), findsWidgets); // filled the field
    });

    testWidgets(
      'completing all 5 steps writes the character and opens HomeShell',
      (tester) async {
        final repo = await pumpLevelUp(tester, now: today);
        await fillWizard(tester);

        // Step 5: preview, then sign.
        expect(find.text('Sign the Seasonal Oath'), findsOneWidget);
        expect(find.text('Lv 0'), findsOneWidget);
        expect(
          find.textContaining('Season 1 · Day 24 of 92 · Oct 1 – Dec 31'),
          findsOneWidget,
        );
        expect(find.text('Month 1: Run a 5K'), findsOneWidget);
        expect(find.text('4 rewards in the loot vault'), findsOneWidget);
        expect(enabled(tester, 'Begin Season 1'), isFalse);

        await sign(tester);
        expect(enabled(tester, 'Begin Season 1'), isTrue);
        await tapAndSettle(tester, find.text('Begin Season 1'));

        // Transitioned straight into HomeShell.
        expect(find.byType(OnboardingScreen), findsNothing);
        expect(find.byType(HomeShell), findsOneWidget);
        expect(find.text('Ari'), findsOneWidget);
        expect(find.text('Caffeine Paladin'), findsOneWidget);
        expect(find.text('Season 1 • Day 24/92'), findsOneWidget);
        expect(find.bySemanticsLabel('Level 0'), findsOneWidget);
        expect(find.text('0/5'), findsOneWidget);

        // Everything was written in one transaction.
        expect(repo.saveCount, 1);
        final saved = repo.saved!;
        expect(saved.habits.map((h) => h.title), [
          'Read',
          'Drink water',
          'Sketch',
          'Call someone',
          'Side project',
        ]);
        expect(saved.habits.every((h) => h.isKeystone), isTrue);
        expect(
          saved.keystoneFor(BranchType.body)!.targetCriteria,
          '13 cups daily',
        );
        final body = saved.configFor(BranchType.body);
        expect(body.buffs, ['Lay out gym clothes at night']);
        expect(body.debuffs, ['Phone in bed after 11 PM']);
        final quest = saved.quests.single;
        expect(quest.title, 'Run a 5K');
        expect(quest.isMainQuest, isTrue);
        expect(quest.monthIndex, 1);
        expect(quest.rewardText, 'Shoes');
        expect(saved.loot.map((l) => (l.tier, l.title)), [
          (LootTier.common, 'Ice cream night'),
          (LootTier.rare, 'Buy a new book'),
          (LootTier.epic, 'Nice dinner out'),
          (LootTier.legendary, 'Big gear upgrade'),
        ]);
        final oath = saved.currentSeason.oath!;
        expect(oath.signedAtDate, '2026-10-24');
        expect(oath.strokes.single.length, greaterThan(4));

        // The signed oath shows on the Skill Tree tab.
        await tapAndSettle(tester, find.text('Skill Tree'));
        expect(find.text('SEALED · Oct 24'), findsOneWidget);
      },
    );

    testWidgets('loot vault needs a reward for every tier', (tester) async {
      await pumpLevelUp(tester, now: today);
      await tester.enterText(
        find.widgetWithText(TextField, 'Character Name'),
        'Ari',
      );
      await tapAndSettle(tester, find.text('Code Ranger'));
      await tapAndSettle(tester, find.text('Next'));
      await tapAndSettle(tester, find.text('Read · 10 pages'));
      await tapAndSettle(tester, find.text('Next'));
      // Step 3 is optional.
      expect(enabled(tester, 'Next'), isTrue);
      await tapAndSettle(tester, find.text('Next'));

      expect(find.text('Stock Your Loot Vault'), findsOneWidget);
      expect(enabled(tester, 'Next'), isFalse);
      expect(find.text('Add a reward for every tier.'), findsOneWidget);
      for (final chip in ['Fancy coffee', 'Binge TV night', 'Spa day']) {
        await tapAndSettle(tester, find.text(chip));
      }
      expect(enabled(tester, 'Next'), isFalse);
      await tapAndSettle(tester, find.text('Weekend trip away'));
      expect(enabled(tester, 'Next'), isTrue);
    });

    testWidgets('keystones: needs one; Back keeps earlier answers', (
      tester,
    ) async {
      await pumpLevelUp(tester, now: today);
      await tester.enterText(
        find.widgetWithText(TextField, 'Character Name'),
        'Ari',
      );
      await tapAndSettle(tester, find.text('Shadow Monk'));
      await tapAndSettle(tester, find.text('Next'));

      expect(find.text('Forge Your 5 Keystone Habits'), findsOneWidget);
      expect(enabled(tester, 'Next'), isFalse);
      await tester.enterText(
        find.byKey(const ValueKey('keystone-title-craft')),
        'Paint',
      );
      await tester.pump();
      expect(enabled(tester, 'Next'), isTrue);

      await tapAndSettle(tester, find.text('Back'));
      expect(find.text('Roll Your Character'), findsOneWidget);
      expect(find.text('Ari'), findsOneWidget);
    });

    testWidgets('clearing the signature disables Begin again', (tester) async {
      await pumpLevelUp(tester, now: today);
      await fillWizard(tester);
      await sign(tester);
      expect(enabled(tester, 'Begin Season 1'), isTrue);
      await tapAndSettle(tester, find.text('Clear / Re-sign'));
      expect(enabled(tester, 'Begin Season 1'), isFalse);
      expect(find.text('Sign the oath to begin.'), findsOneWidget);
    });

    testWidgets('header wipe & restart returns to Session Zero', (
      tester,
    ) async {
      final repo = await pumpLevelUp(
        tester,
        now: today,
        state: buildDemoState(today),
      );
      await tapAndSettle(tester, find.byTooltip('Character options'));
      await tapAndSettle(tester, find.text('Wipe character & restart'));
      await tapAndSettle(tester, find.text('Wipe & Restart'));

      expect(repo.saved, isNull);
      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    testWidgets('every step fits a 320pt-wide phone', (tester) async {
      await pumpLevelUp(tester, now: today, size: const Size(320, 640));
      expect(tester.takeException(), isNull);
      await fillWizard(tester);
      expect(tester.takeException(), isNull);
      await sign(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Step 5 of 5 · Seasonal Oath'), findsOneWidget);
      expect(enabled(tester, 'Begin Season 1'), isTrue);
    });
  });
}
