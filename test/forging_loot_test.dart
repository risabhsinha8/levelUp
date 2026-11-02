import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_up/data/database_helper.dart';
import 'package:level_up/data/rpg_sqlite_repository.dart';
import 'package:level_up/domain/character_sheet.dart';
import 'package:level_up/domain/rpg_engine.dart';
import 'package:level_up/domain/season_rollover.dart';
import 'package:level_up/models/rpg_models.dart';
import 'package:level_up/models/rpg_state.dart';
import 'package:level_up/providers/rpg_store_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fixtures.dart';

final today = DateTime(2026, 10, 24, 9);

/// Always rolls index [value] (mod the number of choices).
class FixedRandom implements math.Random {
  FixedRandom(this.value);

  final int value;

  @override
  int nextInt(int max) => value % max;

  @override
  double nextDouble() => 0;

  @override
  bool nextBool() => false;
}

/// The demo character with Mind's two earned nodes not yet forged (Lv 7).
RpgState demoWithReadyMind() =>
    _withForged(buildDemoState(today), {BranchType.mind: 0});

RpgState _withForged(RpgState state, Map<BranchType, int> forged) =>
    state.copyWith(
      branchConfigs: [
        for (final b in BranchType.values)
          state
              .configFor(b)
              .copyWith(
                forgedNodeCount:
                    forged[b] ?? state.configFor(b).forgedNodeCount,
              ),
      ],
    );

/// A fresh Oct–Dec character whose keystones in [branches] were done on 80
/// days (all 5 nodes earned), on Dec 31.
RpgState masteredState(Set<BranchType> branches) {
  final state = buildFreshState(DateTime(2026, 12, 31));
  final ids = [
    for (final h in state.habits)
      if (branches.contains(h.branch)) h.id,
  ];
  return state.copyWith(
    logs: [
      for (var i = 0; i < 80; i++)
        DailyLog(
          dateString: toDateString(DateTime.utc(2026, 10, 1 + i)),
          completedHabitIds: ids,
        ),
    ],
  );
}

ProviderContainer containerFor(InMemoryRepository repo, {DateTime? at}) {
  final container = ProviderContainer(
    overrides: [
      clockProvider.overrideWithValue(() => at ?? today),
      rpgRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

RpgSqliteRepository openRepo([DatabaseHelper? helper]) {
  final repo = RpgSqliteRepository(
    helper ??
        DatabaseHelper(
          factory: databaseFactoryFfi,
          path: DatabaseHelper.inMemoryPath,
        ),
  );
  addTearDown(repo.close);
  return repo;
}

List<int> forgedCounts(RpgState state) => [
  for (final b in BranchType.defaults) state.configFor(b).forgedNodeCount,
];

void main() {
  setUpAll(sqfliteFfiInit);

  group('forged nodes in the rules', () {
    test('earned nodes add levels and keys only once forged', () {
      final sheet = CharacterSheet.fromState(demoWithReadyMind(), today);
      final mind = sheet.branches[BranchType.mind]!;
      expect(mind.activeDays, 17);
      expect(mind.unlockedNodes, 2);
      expect(mind.forgedNodes, 0);
      expect(mind.readyToForge, 2);
      expect(mind.level, 1); // base only
      expect(sheet.totalLevel, 7);
      expect(sheet.lootKeys[LootTier.rare]!.earned, 4);
    });

    test('a forged count above the earned nodes is capped', () {
      expect(RpgEngine.calculateForgedNodes(2, 5), 2);
      expect(RpgEngine.calculateForgedNodes(3, 1), 1);
      expect(RpgEngine.calculateForgedNodes(0, -1), 0);
    });

    test('backups from before forging count every earned node', () {
      final legacy = BranchConfig.fromJson({'branch': 'mind', 'baseLevel': 1});
      expect(legacy.forgedNodeCount, 5);
      final config = demoWithReadyMind().configFor(BranchType.mind);
      expect(BranchConfig.fromJson(config.toJson()), config);
    });

    test('rollover forges ready nodes automatically and resets', () {
      final result = SeasonRollover.apply(
        demoWithReadyMind(),
        DateTime(2027, 1, 2),
        newSeasonId: 's2',
      );
      final mind = result.state.configFor(BranchType.mind);
      expect(mind.baseLevel, 3); // 1 + 2 nodes + 0 feats
      expect(forgedCounts(result.state), [0, 0, 0, 0, 0]);
      expect(result.summary.endLevel, 9);
    });
  });

  group('RpgStore.forgeNode', () {
    test('forges one node: +1 level and a Rare Key', () async {
      final repo = InMemoryRepository(demoWithReadyMind());
      final container = containerFor(repo);
      final store = container.read(rpgStoreProvider.notifier);
      await container.read(rpgStoreProvider.future);
      final writes = repo.saveCount;

      final result = (await store.forgeNode(BranchType.mind))!;
      expect(result.nodeIndex, 0);
      expect(result.oldBranchLevel, 1);
      expect(result.newBranchLevel, 2);
      expect(result.oldTotalLevel, 7);
      expect(result.newTotalLevel, 8);
      expect(result.keysEarned, {LootTier.rare: 1});
      expect(repo.saveCount, writes + 1);
      expect(repo.saved!.configFor(BranchType.mind).forgedNodeCount, 1);

      await store.forgeNode(BranchType.mind);
      expect(container.read(characterSheetProvider).value!.totalLevel, 9);
      // Nothing left to forge.
      expect(await store.forgeNode(BranchType.mind), isNull);
      expect(await store.forgeNode(BranchType.empire), isNull);
      expect(repo.saveCount, writes + 2);
    });

    test('the 5th node adds an Epic Key, the 25th the Legendary', () async {
      final at = DateTime(2026, 12, 31, 9);
      final epic = _withForged(masteredState({BranchType.body}), {
        BranchType.body: 4,
      });
      var container = containerFor(InMemoryRepository(epic), at: at);
      await container.read(rpgStoreProvider.future);
      var result = await container
          .read(rpgStoreProvider.notifier)
          .forgeNode(BranchType.body);
      expect(result!.keysEarned, {LootTier.rare: 1, LootTier.epic: 1});

      final legendary = _withForged(masteredState(BranchType.values.toSet()), {
        for (final b in BranchType.values) b: b == BranchType.bond ? 4 : 5,
      });
      container = containerFor(InMemoryRepository(legendary), at: at);
      await container.read(rpgStoreProvider.future);
      result = await container
          .read(rpgStoreProvider.notifier)
          .forgeNode(BranchType.bond);
      expect(result!.keysEarned, {
        LootTier.rare: 1,
        LootTier.epic: 1,
        LootTier.legendary: 1,
      });
    });

    test('rollLoot claims a random reward of the tier', () async {
      final repo = InMemoryRepository(buildDemoState(today));
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => today),
          rpgRepositoryProvider.overrideWithValue(repo),
          randomProvider.overrideWithValue(FixedRandom(1)),
        ],
      );
      addTearDown(container.dispose);
      final store = container.read(rpgStoreProvider.notifier);
      await container.read(rpgStoreProvider.future);

      final reward = await store.rollLoot(LootTier.common);
      expect(reward!.id, 'loot-ice-cream');
      final claims = repo.saved!.loot.where(
        (l) => l.isClaimed && l.tier == LootTier.common,
      );
      expect(claims.single.title, 'Ice cream party');

      expect(await store.rollLoot(LootTier.epic), isNull); // no Epic keys
      await store.rollLoot(LootTier.common);
      expect(await store.rollLoot(LootTier.common), isNull); // keys spent
    });
  });

  group('SQLite forged_node_count', () {
    test('updateForgedNodes persists the count', () async {
      final repo = openRepo();
      await repo.replaceAllData(demoWithReadyMind());
      expect(forgedCounts((await repo.loadFullState())!), [0, 2, 1, 1, 0]);

      final config = demoWithReadyMind()
          .configFor(BranchType.mind)
          .copyWith(forgedNodeCount: 1);
      await repo.updateForgedNodes(config);
      final loaded = (await repo.loadFullState())!;
      expect(loaded.configFor(BranchType.mind), config);
    });

    test('upgrading a v3 database forges the nodes already earned', () async {
      final dir = await Directory.systemTemp.createTemp('level_up_v3');
      addTearDown(() => dir.delete(recursive: true));
      final path = p.join(dir.path, DatabaseHelper.fileName);

      // Write the demo with a current helper, then strip it back to v3.
      final setup = DatabaseHelper(factory: databaseFactoryFfi, path: path);
      await RpgSqliteRepository(setup).replaceAllData(
        _withForged(buildDemoState(today), {
          for (final b in BranchType.values) b: 0,
        }),
      );
      final db = await setup.database;
      await db.execute(
        'CREATE TABLE v3 AS SELECT branch, base_level, buff_text, '
        'debuff_text FROM branch_configs',
      );
      await db.execute('DROP TABLE branch_configs');
      await db.execute('ALTER TABLE v3 RENAME TO branch_configs');
      // Characters gained avatar_data in v6.
      await db.execute(
        'CREATE TABLE c5 AS SELECT id, name, class_title, signature_data, '
        'current_season_id, signature_text FROM characters',
      );
      await db.execute('DROP TABLE characters');
      await db.execute('ALTER TABLE c5 RENAME TO characters');
      await db.setVersion(3);
      await setup.close();

      final repo = openRepo(
        DatabaseHelper(factory: databaseFactoryFfi, path: path),
      );
      final loaded = (await repo.loadFullState())!;
      expect(forgedCounts(loaded), [2, 2, 1, 1, 0]);
      expect(CharacterSheet.fromState(loaded, today).totalLevel, 9);
    });
  });

  group('Skill Tree forging', () {
    Future<InMemoryRepository> pumpReadyTree(WidgetTester tester) async {
      final repo = await pumpLevelUp(
        tester,
        now: today,
        state: demoWithReadyMind(),
        size: const Size(800, 3200),
      );
      await tester.tap(find.text('Skill Tree'));
      // Ready nodes pulse forever, so pump frames instead of settling.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1300));
      return repo;
    }

    testWidgets('ready nodes glow with a hold badge', (tester) async {
      await pumpReadyTree(tester);
      expect(
        find.bySemanticsLabel('Mind node 1, ready to forge'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Mind node 2, ready to forge'),
        findsOneWidget,
      );
      expect(find.text('Hold to Forge (+1 Lvl)'), findsOneWidget);
      expect(
        find.text('2 nodes ready! Hold a glowing node to forge it.'),
        findsOneWidget,
      );
      expect(find.text('4/25 nodes'), findsOneWidget);
    });

    testWidgets('a short press does not forge', (tester) async {
      final repo = await pumpReadyTree(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('node-mind-0'))),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repo.saved!.configFor(BranchType.mind).forgedNodeCount, 0);
      expect(find.text('NODE FORGED / LEVEL UP!'), findsNothing);
    });

    testWidgets('holding 1.2s forges the node and celebrates', (tester) async {
      final repo = await pumpReadyTree(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('node-mind-0'))),
      );
      for (var i = 0; i < 13; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(repo.saved!.configFor(BranchType.mind).forgedNodeCount, 1);
      expect(find.text('NODE FORGED / LEVEL UP!'), findsOneWidget);
      expect(find.text('Lv 7 → Lv 8'), findsOneWidget);
      expect(find.text('Mind Lv 1 → Lv 2'), findsOneWidget);
      expect(find.text('+1 Rare Loot Key Earned!'), findsOneWidget);

      await tester.tap(find.text('Onward'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('NODE FORGED / LEVEL UP!'), findsNothing);
      expect(find.bySemanticsLabel('Mind node 1, unlocked'), findsOneWidget);
      // Released after a hold: no details sheet opened.
      expect(find.text('Mind · Node 1'), findsNothing);
    });

    testWidgets('the forged key can be spent on a chosen reward', (
      tester,
    ) async {
      final repo = await pumpReadyTree(tester);
      final claimed = repo.saved!.loot.where((l) => l.isClaimed).length;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('node-mind-0'))),
      );
      for (var i = 0; i < 13; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('Choose a Rare reward'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Pick a Rare Reward'), findsOneWidget);
      expect(find.text('Binge TV night'), findsWidgets);
      await tester.tap(find.text('New video game').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('LOOT UNLOCKED!'), findsOneWidget);
      final claims = repo.saved!.loot.where((l) => l.isClaimed).toList();
      expect(claims, hasLength(claimed + 1));
      expect(claims.last.title, 'New video game');
    });
  });

  testWidgets('ready nodes and chests fit a 320pt-wide phone', (tester) async {
    await pumpLevelUp(
      tester,
      now: today,
      state: demoWithReadyMind(),
      size: const Size(320, 3200),
    );
    await tester.tap(find.text('Skill Tree'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));
    expect(tester.takeException(), isNull);
    expect(find.text('Hold to Forge (+1 Lvl)'), findsOneWidget);

    await tester.tap(find.text('Quests & Loot'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Loot Table'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.text('Common Treasure Chest'), findsOneWidget);
  });

  group('Loot chests', () {
    Future<InMemoryRepository> pumpLoot(
      WidgetTester tester, {
      int roll = 0,
    }) async {
      final repo = await pumpLevelUp(
        tester,
        now: today,
        state: buildDemoState(today),
        size: const Size(800, 3000),
        random: FixedRandom(roll),
      );
      await tester.tap(find.text('Quests & Loot'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Loot Table'));
      await tester.pumpAndSettle();
      return repo;
    }

    Finder inChest(LootTier tier, String text) => find.descendant(
      of: find.byKey(ValueKey('chest-${tier.name}')),
      matching: find.text(text),
    );

    testWidgets('a glowing chest for each tier with unspent keys', (
      tester,
    ) async {
      await pumpLoot(tester);
      expect(find.text('Common Treasure Chest'), findsOneWidget);
      expect(find.text('Rare Treasure Chest'), findsOneWidget);
      expect(find.text('Epic Treasure Chest'), findsNothing);
      expect(find.text('Legendary Treasure Chest'), findsNothing);
      expect(
        find.text('2 keys ready · 2 rewards inside'),
        findsOneWidget,
      ); // Common
    });

    testWidgets('rolling random loot shakes, claims and celebrates', (
      tester,
    ) async {
      final repo = await pumpLoot(tester, roll: 1);
      await tester.tap(inChest(LootTier.common, 'Roll Random Loot'));
      await tester.pumpAndSettle();

      expect(find.text('LOOT UNLOCKED!'), findsOneWidget);
      expect(
        find.text('1 Common Key spent · enjoy it, you earned it'),
        findsOneWidget,
      );
      final claims = repo.saved!.loot.where((l) => l.isClaimed).toList();
      expect(claims.last.title, 'Ice cream party');
      expect(claims.last.claimedAtDate, '2026-10-24');

      await tester.tap(find.text('Onward'));
      await tester.pumpAndSettle();
      expect(find.text('1 key ready · 2 rewards inside'), findsOneWidget);

      // Spending the last Common key removes the chest.
      await tester.tap(inChest(LootTier.common, 'Roll Random Loot'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Onward'));
      await tester.pumpAndSettle();
      expect(find.text('Common Treasure Chest'), findsNothing);
    });

    testWidgets('picking a specific reward', (tester) async {
      final repo = await pumpLoot(tester);
      await tester.tap(inChest(LootTier.rare, 'Pick Reward'));
      await tester.pumpAndSettle();
      expect(find.text('Pick a Rare Reward'), findsOneWidget);

      await tester.tap(find.widgetWithText(ListTile, 'New video game'));
      await tester.pumpAndSettle();
      expect(find.text('LOOT UNLOCKED!'), findsOneWidget);
      await tester.tap(find.text('Onward'));
      await tester.pumpAndSettle();

      final claims = repo.saved!.loot.where(
        (l) => l.isClaimed && l.tier == LootTier.rare,
      );
      expect(claims.map((l) => l.title), contains('New video game'));
      expect(find.text('4 keys ready · 2 rewards inside'), findsOneWidget);
    });
  });
}
