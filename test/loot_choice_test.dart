import 'package:flutter_test/flutter_test.dart';
import 'package:level_up/models/rpg_models.dart';
import 'package:level_up/models/rpg_state.dart';

import 'support/fixtures.dart';

final today = DateTime(2026, 10, 24, 9);

/// A fresh character whose Mind keystone ("Read", `habit-0`) was done on
/// the 6 days before today, so checking it today earns a Common Key.
RpgState sixKeystoneDays({List<LootItem> loot = const []}) {
  final fresh = buildFreshState(today);
  return fresh.copyWith(
    logs: [
      for (var day = 18; day <= 23; day++)
        DailyLog(dateString: '2026-10-$day', completedHabitIds: ['habit-0']),
    ],
    loot: loot,
  );
}

void main() {
  testWidgets('a 7th keystone day offers a choice of Common rewards', (
    tester,
  ) async {
    final repo = await pumpLevelUp(
      tester,
      now: today,
      state: sixKeystoneDays(
        loot: const [
          LootItem(id: 'coffee', tier: LootTier.common, title: 'Fancy coffee'),
          LootItem(id: 'movie', tier: LootTier.common, title: 'Movie night'),
        ],
      ),
    );

    await tester.tap(find.text('Read'));
    await tester.pumpAndSettle();
    expect(find.text('COMMON KEY EARNED!'), findsOneWidget);

    await tester.tap(find.text('Choose a Common reward'));
    await tester.pumpAndSettle();
    expect(find.text('Pick a Common Reward'), findsOneWidget);
    await tester.tap(find.text('Movie night'));
    await tester.pumpAndSettle();

    expect(find.text('LOOT UNLOCKED!'), findsOneWidget);
    final claim = repo.saved!.loot.singleWhere((l) => l.isClaimed);
    expect(claim.title, 'Movie night');
  });

  testWidgets('with no Common rewards the key is saved for later', (
    tester,
  ) async {
    final repo = await pumpLevelUp(
      tester,
      now: today,
      state: sixKeystoneDays(),
    );

    await tester.tap(find.text('Read'));
    await tester.pumpAndSettle();
    expect(find.text('COMMON KEY EARNED!'), findsOneWidget);
    expect(find.text('Choose a Common reward'), findsNothing);
    await tester.tap(find.text('Onward'));
    await tester.pumpAndSettle();
    expect(find.text('COMMON KEY EARNED!'), findsNothing);
    expect(repo.saved!.loot, isEmpty);
  });

  testWidgets('other check-ins earn no key and show nothing', (tester) async {
    await pumpLevelUp(tester, now: today, state: sixKeystoneDays());
    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();
    expect(find.text('COMMON KEY EARNED!'), findsNothing);
  });
}
