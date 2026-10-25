import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_up/models/rpg_models.dart';

import 'support/fixtures.dart';

final today = DateTime(2026, 10, 24);

Future<void> pumpToday(WidgetTester tester, {double width = 800}) async {
  await pumpLevelUp(
    tester,
    now: today,
    state: buildDemoState(today),
    size: Size(width, 2600),
  );
}

/// The row for the habit titled [title].
Finder habitRow(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(InkWell)).first;

Future<void> flushSnackBars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('adds a habit to a branch from its card', (tester) async {
    await pumpToday(tester);

    await tester.tap(find.byTooltip('Add Body habit'));
    await tester.pumpAndSettle();
    expect(find.text('New Habit'), findsOneWidget);
    // Branch is preselected; Add is disabled until there's a title.
    final add = find.widgetWithText(FilledButton, 'Add Habit');
    expect(tester.widget<FilledButton>(add).onPressed, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'Habit'), 'Stretch');
    await tester.enterText(find.widgetWithText(TextField, 'Target'), '5 min');
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();

    final habit = readState(
      tester,
    ).habits.firstWhere((h) => h.title == 'Stretch');
    expect(habit.branch, BranchType.body);
    expect(habit.targetCriteria, '5 min');
    expect(habit.isKeystone, isFalse);
    expect(find.text('Stretch'), findsOneWidget);
    expect(find.text('5 min'), findsWidgets);
  });

  testWidgets('a new keystone warns it replaces the old one', (tester) async {
    await pumpToday(tester);

    await tester.tap(find.text('Add Habit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Habit'),
      'Ship one feature',
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Empire'));
    await tester.tap(find.text('Keystone habit'));
    await tester.pumpAndSettle();
    expect(
      find.text('Replaces ★ Work on side project as the Empire keystone'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add Habit'));
    await tester.pumpAndSettle();

    final state = readState(tester);
    expect(state.keystoneFor(BranchType.empire)!.title, 'Ship one feature');
    expect(
      state.habits.firstWhere((h) => h.id == 'habit-side-project').isKeystone,
      isFalse,
    );
  });

  testWidgets('edits a habit\'s title, target and schedule', (tester) async {
    await pumpToday(tester);

    await tester.tap(find.byTooltip('Edit Water'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Habit'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Habit'), 'Hydrate');
    await tester.enterText(
      find.widgetWithText(TextField, 'Target'),
      '3 liters',
    );
    await tester.tap(find.text('Days 16+'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final habit = readState(
      tester,
    ).habits.firstWhere((h) => h.id == 'habit-water');
    expect(habit.title, 'Hydrate');
    expect(habit.targetCriteria, '3 liters');
    expect(habit.activeHalfMonth, ActiveHalfMonth.secondHalf);
    expect(find.text('Hydrate'), findsOneWidget); // Oct 24 is in Half 2
  });

  testWidgets('long-press also opens the editor', (tester) async {
    await pumpToday(tester);
    await tester.longPress(find.text('Sleep'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Habit'), findsOneWidget);
  });

  testWidgets('tapping the star moves the keystone', (tester) async {
    await pumpToday(tester);

    await tester.tap(
      find.descendant(
        of: habitRow('Meditation'),
        matching: find.byTooltip('Make keystone'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('★ Meditation is now the Mind keystone (was Reading).'),
      findsOneWidget,
    );
    expect(readState(tester).keystoneFor(BranchType.mind)!.title, 'Meditation');
    // Reading lost its star; Meditation now offers to remove it.
    expect(
      find.descendant(
        of: habitRow('Reading'),
        matching: find.byTooltip('Make keystone'),
      ),
      findsOneWidget,
    );
    await flushSnackBars(tester);

    await tester.tap(
      find.descendant(
        of: habitRow('Meditation'),
        matching: find.byTooltip('Remove keystone star'),
      ),
    );
    await tester.pumpAndSettle();
    expect(readState(tester).keystoneFor(BranchType.mind), isNull);
    expect(find.text('4/4'), findsNothing);
    expect(find.text('0/4'), findsOneWidget); // banner: 4 keystones left
    await flushSnackBars(tester);
  });

  testWidgets('deleting a habit hides it but keeps its points', (tester) async {
    await pumpToday(tester);
    final levelBefore = find.bySemanticsLabel('Level 9');
    expect(levelBefore, findsOneWidget);

    await tester.tap(find.byTooltip('Edit Water'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete "Water"?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Water'), findsNothing);
    expect(find.text('Deleted "Water".'), findsOneWidget);
    expect(
      readState(
        tester,
      ).habits.firstWhere((h) => h.id == 'habit-water').isArchived,
      isTrue,
    );
    expect(find.bySemanticsLabel('Level 9'), findsOneWidget);

    // On a past day it was checked off, it shows as deleted, read-only.
    await tester.tap(find.bySemanticsLabel('Fri, Oct 23'));
    await tester.pumpAndSettle();
    expect(find.text('Water'), findsOneWidget);
    expect(find.text('Deleted · past check-ins still count'), findsOneWidget);
    expect(find.byTooltip('Edit Water'), findsNothing);
    await flushSnackBars(tester);
  });

  testWidgets('habit rows fit on a 320pt-wide phone', (tester) async {
    await pumpToday(tester, width: 320);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Edit Water'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
