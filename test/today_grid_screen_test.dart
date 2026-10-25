import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_up/models/rpg_models.dart';

import 'support/fixtures.dart';

final today = DateTime(2026, 10, 24);

Future<void> pumpApp(WidgetTester tester) async {
  await pumpLevelUp(
    tester,
    now: today,
    state: buildDemoState(today),
    size: const Size(800, 2600),
  );
}

Future<void> openMatrix(WidgetTester tester) async {
  await tester.tap(find.text('Monthly Matrix'));
  await tester.pumpAndSettle();
}

void main() {
  group("Today's Focus", () {
    testWidgets('checking a habit secures the branch point and keystone', (
      tester,
    ) async {
      await pumpApp(tester);

      expect(find.text('Keystone Priority'), findsOneWidget);
      expect(find.text('0/5'), findsOneWidget);
      expect(find.text('13 cups daily'), findsOneWidget);
      expect(find.text('+1 Branch Point Secured'), findsNothing);
      expect(find.text('No point yet'), findsNWidgets(5));

      await tester.tap(find.text('Exercise'));
      await tester.pumpAndSettle();
      expect(find.text('+1 Branch Point Secured'), findsOneWidget);
      expect(find.text('1/5'), findsOneWidget);
      expect(readState(tester).completedOn(today), {'habit-exercise'});

      // A second Body habit doesn't add another point.
      await tester.tap(find.text('Water'));
      await tester.pumpAndSettle();
      expect(find.text('+1 Branch Point Secured'), findsOneWidget);

      await tester.tap(find.text('Reading'));
      await tester.pumpAndSettle();
      expect(find.text('+1 Branch Point Secured'), findsNWidgets(2));
      expect(find.text('2/5'), findsOneWidget);
    });

    testWidgets('week strip selects a past day and blocks future days', (
      tester,
    ) async {
      await pumpApp(tester);

      // Oct 23 (Fri): demo logs have Exercise done.
      await tester.tap(find.bySemanticsLabel('Fri, Oct 23'));
      await tester.pumpAndSettle();
      expect(find.text('Exercise'), findsOneWidget);
      expect(find.text('+1 Branch Point Secured'), findsWidgets);

      // Oct 25 (Sun) is in the future: tapping does nothing.
      await tester.tap(find.bySemanticsLabel('Sun, Oct 25'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sleep'));
      await tester.pumpAndSettle();
      expect(readState(tester).completedOn(DateTime(2026, 10, 25)), isEmpty);
    });
  });

  group('Monthly Matrix', () {
    testWidgets('shows both halves with the reflection card between', (
      tester,
    ) async {
      await pumpApp(tester);
      await openMatrix(tester);

      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('Days 1–15'), findsOneWidget);
      expect(find.text('Days 16–31'), findsOneWidget);
      expect(find.text('Mid-Month Reflection & Pivot'), findsOneWidget);

      final half1 = tester.getTopLeft(find.text('Half 1')).dy;
      final reflection = tester
          .getTopLeft(find.text('Mid-Month Reflection & Pivot'))
          .dy;
      final half2 = tester.getTopLeft(find.text('Half 2')).dy;
      expect(half1 < reflection && reflection < half2, isTrue);
    });

    testWidgets('tapping a cell toggles that day', (tester) async {
      await pumpApp(tester);
      await openMatrix(tester);

      final cell = find.bySemanticsLabel('Sleep, Oct 24');
      await tester.ensureVisible(cell);
      await tester.tap(cell);
      await tester.pumpAndSettle();
      expect(readState(tester).completedOn(today), contains('habit-sleep'));

      await tester.tap(cell);
      await tester.pumpAndSettle();
      expect(
        readState(tester).completedOn(today),
        isNot(contains('habit-sleep')),
      );
    });

    testWidgets('reflection notes autosave', (tester) async {
      await pumpApp(tester);
      await openMatrix(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'What worked? What felt like burnout?'),
        'Mornings worked. Evening meditation felt like a chore.',
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(
        readState(tester).reflectionFor(today).notes,
        'Mornings worked. Evening meditation felt like a chore.',
      );
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('pivot swaps Meditation for a new Half 2 habit', (
      tester,
    ) async {
      await pumpApp(tester);
      await openMatrix(tester);

      await tester.tap(find.text('Pivot Habit for Days 16–31'));
      await tester.pumpAndSettle();
      expect(find.text('Pivot a Habit'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<Habit>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Meditation (Mind)').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'New habit'),
        'Journaling',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Target'),
        '1 page',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Pivot'));
      await tester.pumpAndSettle();

      final state = readState(tester);
      final journaling = state.habits.firstWhere(
        (h) => h.title == 'Journaling',
      );
      expect(journaling.activeHalfMonth, ActiveHalfMonth.secondHalf);
      expect(
        state.habits
            .firstWhere((h) => h.id == 'habit-meditation')
            .activeHalfMonth,
        ActiveHalfMonth.firstHalf,
      );
      expect(find.text('Meditation → Journaling'), findsOneWidget);
      // Journaling gets a Half 2 row (plus the pivot note above).
      expect(find.bySemanticsLabel('Journaling, Oct 24'), findsOneWidget);
      expect(find.bySemanticsLabel('Journaling, Oct 1'), findsNothing);

      // Let the confirmation snackbar time out.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });
}
