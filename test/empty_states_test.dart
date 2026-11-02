import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_up/domain/new_character.dart';
import 'package:level_up/models/rpg_models.dart';
import 'package:level_up/models/rpg_state.dart';

import 'support/fixtures.dart';

final today = DateTime(2026, 10, 24);

/// Day 1 straight out of onboarding: one keystone, no logs, quests or loot.
RpgState dayOne() => buildNewCharacterState(
  name: 'Ari',
  classTitle: 'Novice',
  keystones: const [KeystoneChoice(branch: BranchType.body, title: 'Walk')],
  today: today,
  seasonId: 'season-1',
  newId: () => 'habit-walk',
);

/// The emptiest possible sheet: no habits and no branch config rows.
RpgState bare() => dayOne().copyWith(habits: const [], branchConfigs: const []);

Future<void> visitEverything(WidgetTester tester) async {
  Future<void> tapAndSettle(Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  // Today & Grid, both views.
  await tapAndSettle(find.text('Monthly Matrix'));
  await tapAndSettle(find.text("Today's Focus"));

  // Skill tree, a node sheet, an attribute card.
  await tapAndSettle(find.text('Skill Tree'));
  await tapAndSettle(find.byKey(const ValueKey('node-mind-0')));
  await tester.tapAt(const Offset(400, 20));
  await tester.pumpAndSettle();
  await tapAndSettle(find.text('Mind').last);

  // Quests & Loot, both tabs.
  await tapAndSettle(find.text('Quests & Loot'));
  await tapAndSettle(find.text('Month 2'));
  await tapAndSettle(find.text('Loot Table'));

  // Season Tally.
  await tapAndSettle(find.text('Season Tally').last);

  // Character page and the avatar editor.
  await tapAndSettle(find.byKey(const ValueKey('header-avatar')));
  await tapAndSettle(find.byKey(const ValueKey('edit-avatar')));
  await tapAndSettle(find.text('Save Avatar'));
  await tapAndSettle(find.byKey(const ValueKey('open-habit-history')));
  await tester.pageBack();
  await tester.pumpAndSettle();
  await tester.pageBack();
  await tester.pumpAndSettle();
}

void main() {
  for (final (name, build) in [('Day 1', dayOne), ('bare', bare)]) {
    testWidgets('$name character: every screen renders without errors', (
      tester,
    ) async {
      await pumpLevelUp(tester, now: today, state: build());
      expect(tester.takeException(), isNull);
      await visitEverything(tester);
    });

    testWidgets('$name character: fits a 320pt-wide phone', (tester) async {
      await pumpLevelUp(
        tester,
        now: today,
        state: build(),
        size: const Size(320, 2400),
      );
      await visitEverything(tester);
    });
  }

  testWidgets('Day 1 shows themed empty prompts', (tester) async {
    await pumpLevelUp(tester, now: today, state: dayOne());

    // Joined on Oct 24: day 24 of the Oct 1 – Dec 31 season.
    expect(find.text('Season 1 • Day 24/92'), findsOneWidget);
    expect(find.bySemanticsLabel('Level 0'), findsOneWidget);
    expect(find.text('0/1'), findsOneWidget); // keystone banner

    await tester.tap(find.text('Quests & Loot'));
    await tester.pumpAndSettle();
    expect(find.text('No Main Quest for Month 1'), findsOneWidget);
    expect(find.text('No side quests yet'), findsOneWidget);

    await tester.tap(find.text('Loot Table'));
    await tester.pumpAndSettle();
    expect(find.text('The loot table is empty'), findsNWidgets(4));
    expect(find.text('No loot claimed yet'), findsOneWidget);
  });

  testWidgets('bare character shows empty prompts with actions', (
    tester,
  ) async {
    await pumpLevelUp(tester, now: today, state: bare());
    expect(find.text('No habits on the sheet yet'), findsOneWidget);
    expect(find.text('Add your first habit'), findsOneWidget);
    expect(find.text('0/0'), findsOneWidget);

    await tester.tap(find.text('Monthly Matrix'));
    await tester.pumpAndSettle();
    expect(find.text('No habits scheduled for this half'), findsNWidgets(2));

    await tester.tap(find.text('Skill Tree'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('node-craft-0')));
    await tester.pumpAndSettle();
    expect(find.text('No Craft habits yet'), findsOneWidget);
  });
}
