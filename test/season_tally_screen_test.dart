import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_up/models/rpg_models.dart';

import 'support/fixtures.dart';

final now = DateTime(2026, 10, 24, 9);

/// Fake system clipboard for export/import.
String? clipboard;

Future<InMemoryRepository> pumpTally(
  WidgetTester tester, {
  double width = 800,
  DateTime? at,
}) async {
  clipboard = null;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String?;
      } else if (call.method == 'Clipboard.getData') {
        return {'text': clipboard};
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  final repo = await pumpLevelUp(
    tester,
    now: at ?? now,
    state: buildDemoState(now),
    size: Size(width, 3000),
  );
  await tester.tap(find.text('Season Tally').last);
  await tester.pumpAndSettle();
  return repo;
}

Future<void> flushSnackBars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ledger and month breakdown are calculated automatically', (
    tester,
  ) async {
    await pumpTally(tester);

    expect(find.text('The Math Ledger'), findsOneWidget);
    expect(find.text('Season 1 · Day 18/86'), findsOneWidget);
    // Character row: base 2 + 6 nodes + 1 feat = 9.
    final characterRow = find.ancestor(
      of: find.text('Character'),
      matching: find.byType(Table),
    );
    expect(
      find.descendant(of: characterRow, matching: find.text('+6')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: characterRow, matching: find.text('+1')),
      findsWidgets,
    );

    expect(find.text('Active Days by Month'), findsOneWidget);
    expect(find.text('M1'), findsOneWidget);
    expect(find.text('Oct 7–Oct 31'), findsOneWidget);
    // Months 2 and 3 haven't started: 5 branches × 2 dashes.
    expect(find.text('—'), findsNWidgets(10));
    expect(find.text('Lv 2'), findsOneWidget); // prestige preview: start
  });

  testWidgets('completing the season shows the celebration and resets nodes', (
    tester,
  ) async {
    // The demo season (Oct 7 – Dec 31) ended yesterday.
    await pumpTally(tester, at: DateTime(2027, 1, 1, 9));
    expect(find.text('Season 1 complete • Level up in Tally'), findsOneWidget);

    await tester.tap(find.text('Complete Season 1 & Level Up'));
    await tester.pumpAndSettle();
    expect(find.text('Complete Season 1?'), findsOneWidget);
    await tester.tap(find.text('Level Up'));
    await tester.pumpAndSettle();

    expect(find.text('Season 1 Complete!'), findsOneWidget);
    expect(find.text('+7 levels this season'), findsOneWidget);
    expect(find.text('Lv 1 → 3'), findsNWidgets(2)); // Mind and Body
    await tester.tap(find.text('Begin Season 2'));
    await tester.pumpAndSettle();

    final state = readState(tester);
    expect(state.currentSeason.name, 'Season 2');
    expect(state.configFor(BranchType.mind).baseLevel, 3);
    expect(find.text('Season 2 • Day 1/90'), findsOneWidget); // Jan 1–Mar 31
    expect(find.bySemanticsLabel('Level 9'), findsOneWidget);
    expect(find.text('Hall of Seasons'), findsOneWidget);
    expect(find.text('Lv 2 → 9'), findsOneWidget);
  });

  testWidgets('settings: edit name and class', (tester) async {
    await pumpTally(tester);

    await tester.tap(find.text('Edit Name & Class'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Ari');
    await tester.enterText(
      find.widgetWithText(TextField, 'Class title'),
      'Weekend Warrior',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(readState(tester).character.name, 'Ari');
    expect(find.text('Ari'), findsOneWidget); // header
    expect(find.text('Weekend Warrior'), findsOneWidget);
  });

  testWidgets('settings: export to clipboard and import it back', (
    tester,
  ) async {
    await pumpTally(tester);

    await tester.tap(find.text('Export Backup JSON'));
    await tester.pumpAndSettle();
    expect(clipboard, contains('"name": "Rowan"'));
    await flushSnackBars(tester);

    await tester.tap(find.text('Wipe Character & Restart Onboarding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wipe & Restart'));
    await tester.pumpAndSettle();
    expect(find.text('Roll Your Character'), findsOneWidget);

    // Restore the backup from onboarding.
    await tester.tap(find.text('Restore a backup instead'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(readState(tester).character.name, 'Rowan');
    expect(find.bySemanticsLabel('Level 9'), findsOneWidget);
    await flushSnackBars(tester);
  });

  testWidgets('settings: an invalid backup shows an error', (tester) async {
    await pumpTally(tester);

    await tester.tap(find.text('Import Backup JSON'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '{"oops": true}');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Not a valid levelUp backup'), findsOneWidget);
    expect(find.text('Import Backup'), findsOneWidget); // dialog stays open
    expect(readState(tester).character.name, 'Rowan');
  });

  testWidgets('settings: wipe character & restart returns to Session Zero', (
    tester,
  ) async {
    final repo = await pumpTally(tester);

    await tester.tap(find.text('Wipe Character & Restart Onboarding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.saved, isNotNull);

    await tester.tap(find.text('Wipe Character & Restart Onboarding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wipe & Restart'));
    await tester.pumpAndSettle();
    expect(repo.saved, isNull);
    expect(find.text('Roll Your Character'), findsOneWidget);
    expect(find.text('Load Demo Data (Level 9)'), findsNothing);
  });

  testWidgets('lays out without overflow on a 320pt-wide phone', (
    tester,
  ) async {
    await pumpTally(tester, width: 320);
    expect(tester.takeException(), isNull);
    expect(find.text('The Math Ledger'), findsOneWidget);
  });
}
