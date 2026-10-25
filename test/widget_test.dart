import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

final today = DateTime(2026, 10, 24);

void main() {
  testWidgets('shell shows the character header and switches tabs', (
    tester,
  ) async {
    await pumpLevelUp(
      tester,
      now: today,
      state: buildDemoState(today),
      size: const Size(800, 600),
    );

    expect(find.text('Rowan'), findsOneWidget);
    expect(find.text('Recovering Couch Potato'), findsOneWidget);
    expect(find.text('Season 1 • Day 18/86'), findsOneWidget);
    expect(find.bySemanticsLabel('Level 9'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);

    expect(find.byType(NavigationDestination), findsNWidgets(4));
    await tester.tap(find.text('Skill Tree'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
  });

  testWidgets('lays out without overflow on a 320pt-wide phone', (
    tester,
  ) async {
    await pumpLevelUp(
      tester,
      now: today,
      state: buildDemoState(today),
      size: const Size(320, 640),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Season 1 • Day 18/86'), findsOneWidget);
  });
}
