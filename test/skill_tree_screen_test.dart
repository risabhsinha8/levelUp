import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_up/models/rpg_models.dart';
import 'package:level_up/widgets/oath_signature_card.dart';

import 'support/fixtures.dart';

final today = DateTime(2026, 10, 24);

Future<void> pumpSkillTree(WidgetTester tester) async {
  await pumpLevelUp(
    tester,
    now: today,
    state: buildDemoState(today),
    size: const Size(800, 3200),
  );
  await tester.tap(find.text('Skill Tree'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('nodes show unlocked, in-progress and locked states', (
    tester,
  ) async {
    await pumpSkillTree(tester);

    expect(find.text('6/25 nodes'), findsOneWidget);
    // Mind has 17 active days: nodes 5 and 15 unlocked, 30 in progress.
    expect(find.bySemanticsLabel('Mind node 1, unlocked'), findsOneWidget);
    expect(find.bySemanticsLabel('Mind node 2, unlocked'), findsOneWidget);
    expect(find.bySemanticsLabel('Mind node 3, 17 of 30 days'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Mind node 4, locked, unlocks at 50 days'),
      findsOneWidget,
    );
    // Empire has 4 days: first node in progress.
    expect(find.bySemanticsLabel('Empire node 1, 4 of 5 days'), findsOneWidget);
    expect(find.text('17/30'), findsNWidgets(2)); // Mind and Body rings
    expect(find.text('80'), findsNWidgets(5)); // every final node locked
  });

  testWidgets('tapping a node opens its details sheet', (tester) async {
    await pumpSkillTree(tester);

    await tester.tap(find.byKey(const ValueKey('node-craft-1')));
    await tester.pumpAndSettle();

    expect(find.text('Craft · Node 2'), findsOneWidget);
    expect(find.text('4 more active days to unlock'), findsOneWidget);
    expect(find.text('11/15 Craft active days this season'), findsOneWidget);
    expect(find.text('Reward: Rare Key'), findsOneWidget);
    expect(find.text('Contributing habits'), findsOneWidget);
    // Sketching: 8 days; French: 3 days (the union is 11 branch days).
    expect(find.text('8d'), findsOneWidget);
    expect(find.text('3d'), findsOneWidget);
  });

  testWidgets('final node sheet mentions the Epic Key; unlocked says so', (
    tester,
  ) async {
    await pumpSkillTree(tester);

    await tester.tap(find.byKey(const ValueKey('node-body-4')));
    await tester.pumpAndSettle();
    expect(find.text('63 more active days to unlock'), findsOneWidget);
    expect(
      find.text('Reward: Rare Key + Epic Key (branch mastered)'),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(400, 20)); // dismiss
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('node-body-0')));
    await tester.pumpAndSettle();
    expect(find.text('Forged'), findsOneWidget);
  });

  testWidgets('attribute card shows the level formula and edits chips', (
    tester,
  ) async {
    await pumpSkillTree(tester);

    expect(
      find.text('Base 1 + Nodes 2 + Feats 0 = 3', findRichText: true),
      findsNWidgets(2), // Mind and Body
    );
    expect(
      find.text('Base 0 + Nodes 1 + Feats 1 = 2', findRichText: true),
      findsOneWidget, // Craft
    );

    await tester.tap(find.text('Body').last);
    await tester.pumpAndSettle();
    expect(find.text('Leave gym clothes out the night before'), findsOneWidget);
    expect(find.text('Phone in bed past 11 PM'), findsOneWidget);

    await tester.tap(find.text('+ Buff'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Shoes by the door');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Shoes by the door'), findsOneWidget);
    expect(readState(tester).configFor(BranchType.body).buffs, [
      'Leave gym clothes out the night before',
      'Water bottle on the desk',
      'Shoes by the door',
    ]);

    await tester.tap(find.text('− Debuff'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Snooze button');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(
      readState(tester).configFor(BranchType.body).debuffs,
      contains('Snooze button'),
    );

    // Remove the first Body buff.
    final removeButtons = find.byTooltip('Remove');
    await tester.tap(removeButtons.first);
    await tester.pumpAndSettle();
    expect(
      readState(tester).configFor(BranchType.body).buffs,
      isNot(contains('Leave gym clothes out the night before')),
    );
  });

  testWidgets('signing, sealing and re-signing the seasonal oath', (
    tester,
  ) async {
    await pumpSkillTree(tester);

    expect(find.text('Sign Your Seasonal Oath'), findsOneWidget);
    expect(find.textContaining('I, Rowan, swear'), findsOneWidget);
    // FilledButton.icon builds a private subclass, so match by `is`.
    final seal = find.ancestor(
      of: find.text('Seal Oath'),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    );
    expect(tester.widget<FilledButton>(seal).onPressed, isNull);

    final pad = find.byType(SignaturePad);
    await tester.ensureVisible(pad);
    await tester.drag(pad, const Offset(220, 30));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(seal).onPressed, isNotNull);

    await tester.tap(seal);
    await tester.pumpAndSettle();
    final oath = readState(tester).currentSeason.oath;
    expect(oath, isNotNull);
    expect(oath!.signedAtDate, '2026-10-24');
    expect(oath.strokes.single.length, greaterThan(4));
    expect(oath.strokes.single.every((v) => v >= 0 && v <= 1), isTrue);
    expect(find.text('SEALED · Oct 24'), findsOneWidget);
    expect(find.text('Seal Oath'), findsNothing);

    await tester.tap(find.text('Clear / Re-sign'));
    await tester.pumpAndSettle();
    expect(readState(tester).currentSeason.oath, isNull);
    expect(find.text('Seal Oath'), findsOneWidget);
  });

  testWidgets('lays out without overflow on a 320pt-wide phone', (
    tester,
  ) async {
    await pumpSkillTree(tester);
    tester.view.physicalSize = const Size(320, 3200);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Empire node 1, 4 of 5 days'), findsOneWidget);
  });
}
