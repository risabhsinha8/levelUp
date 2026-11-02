import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_up/data/database_helper.dart';
import 'package:level_up/data/rpg_sqlite_repository.dart';
import 'package:level_up/domain/character_sheet.dart';
import 'package:level_up/domain/new_character.dart';
import 'package:level_up/domain/rpg_engine.dart';
import 'package:level_up/domain/season_rollover.dart';
import 'package:level_up/models/rpg_models.dart';
import 'package:level_up/models/rpg_state.dart';
import 'package:level_up/providers/rpg_store_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fixtures.dart';

final today = DateTime(2026, 10, 24, 9);

/// After the demo season's quarter (Oct 7 – Dec 31) has ended.
final afterSeason = DateTime(2027, 1, 1, 9);

/// Mind, Body and a renamed Spirit ("Faith"); Body's name is unchanged.
RpgState threePillarState() {
  var next = 0;
  return buildNewCharacterState(
    name: 'Ari',
    classTitle: 'Novice',
    activeBranches: const [BranchType.mind, BranchType.body, BranchType.spirit],
    branchNames: const {BranchType.spirit: ' Faith ', BranchType.body: 'Body'},
    keystones: const [
      KeystoneChoice(branch: BranchType.mind, title: 'Read'),
      KeystoneChoice(branch: BranchType.craft, title: 'Sketch'),
      KeystoneChoice(branch: BranchType.spirit, title: 'Pray'),
    ],
    mainQuest: const MainQuestChoice(title: 'Ship', branch: BranchType.empire),
    today: today,
    seasonId: 'season-1',
    newId: () => 'id-${next++}',
  );
}

/// [state] with [branch] switched on or off.
RpgState withEnabled(RpgState state, BranchType branch, bool enabled) =>
    state.copyWith(
      branchConfigs: [
        for (final b in BranchType.values)
          state.configFor(b).copyWith(isEnabled: b == branch ? enabled : null),
      ],
    );

ProviderContainer makeContainer(InMemoryRepository repo) {
  final container = ProviderContainer(
    overrides: [
      clockProvider.overrideWithValue(() => today),
      rpgRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('BranchConfig names and enabled flag', () {
    test('custom names fall back to the default name', () {
      const config = BranchConfig(branch: BranchType.body);
      expect(config.name, 'Body');
      expect(config.copyWith(customName: 'Health').name, 'Health');
      expect(config.copyWith(customName: '   ').name, 'Body');
    });

    test('customNameFor trims, caps and drops the default name', () {
      expect(BranchConfig.customNameFor(BranchType.body, ' Health '), 'Health');
      expect(BranchConfig.customNameFor(BranchType.body, 'Body'), '');
      expect(BranchConfig.customNameFor(BranchType.body, ''), '');
      expect(
        BranchConfig.customNameFor(BranchType.body, 'Relationships & Love'),
        'Relationships',
      );
    });

    test('JSON keeps names and the flag; old backups are enabled', () {
      const config = BranchConfig(
        branch: BranchType.spirit,
        customName: 'Faith',
        isEnabled: false,
      );
      expect(BranchConfig.fromJson(config.toJson()), config);
      final legacy = BranchConfig.fromJson({'branch': 'mind'});
      expect(legacy.isEnabled, isTrue);
      expect(legacy.customName, '');
    });

    test('spare slots without a stored config are resting', () {
      final demo = buildDemoState(today);
      expect(demo.activeBranches, BranchType.defaults);
      expect(demo.configFor(BranchType.wander).isEnabled, isFalse);
      expect(demo.nameOf(BranchType.wander), 'Wander');
    });
  });

  group('Session Zero with custom pillars', () {
    final state = threePillarState();

    test('stores every slot with the chosen ones enabled and named', () {
      expect(state.branchConfigs, hasLength(BranchType.values.length));
      expect(state.activeBranches, [
        BranchType.mind,
        BranchType.body,
        BranchType.spirit,
      ]);
      expect(state.nameOf(BranchType.spirit), 'Faith');
      expect(state.configFor(BranchType.body).customName, '');
    });

    test('skips keystones and main quests of unchosen pillars', () {
      expect(state.habits.map((h) => h.title), ['Read', 'Pray']);
      expect(state.quests, isEmpty);
    });
  });

  group('rules with custom pillars', () {
    final dates = [
      for (var d = 0; d < 80; d++)
        toDateString(DateTime.utc(2027, 1, 1).add(Duration(days: d))),
    ];
    final season = Season(
      id: 's',
      name: 'Season',
      startDate: DateTime.utc(2027, 1, 1),
      endDate: DateTime.utc(2027, 3, 31),
    );
    List<Habit> habits(List<BranchType> branches) => [
      for (final b in branches) Habit(id: b.name, branch: b, title: b.name),
    ];
    List<DailyLog> logsFor(List<Habit> habits) => [
      for (final d in dates)
        DailyLog(
          dateString: d,
          completedHabitIds: [for (final h in habits) h.id],
        ),
    ];

    test('Legendary needs every node of the active pillars only', () {
      const three = [BranchType.mind, BranchType.body, BranchType.spirit];
      final all = habits([...three, BranchType.craft]);
      final keys = RpgEngine.calculateAvailableLootKeys(
        habits: all,
        logs: logsFor(all),
        claimedLoot: const [],
        season: season,
        branches: three,
      );
      expect(keys[LootTier.rare]!.earned, 15); // Craft's nodes don't count.
      expect(keys[LootTier.epic]!.earned, 3);
      expect(keys[LootTier.legendary]!.earned, 1);
    });

    test('resting pillars leave the character level and the sheet', () {
      final demo = buildDemoState(today);
      final rested = withEnabled(demo, BranchType.craft, false);
      final sheet = CharacterSheet.fromState(rested, today);
      expect(sheet.activeBranches, isNot(contains(BranchType.craft)));
      expect(sheet.totalLevel, 9 - 2); // Craft was Lv 2.
      expect(
        rested.habitsShownOn(today).map((h) => h.branch),
        isNot(contains(BranchType.craft)),
      );
      expect(
        rested.activeHabits.where((h) => h.branch == BranchType.craft),
        isEmpty,
      );
    });

    test('rollover puts pillars to rest and brings spares in', () {
      final demo = buildDemoState(today);
      final result = SeasonRollover.apply(
        demo,
        afterSeason,
        newSeasonId: 's2',
        activeBranches: {
          BranchType.mind,
          BranchType.body,
          BranchType.bond,
          BranchType.spirit,
        },
      );
      final next = result.state;
      expect(next.activeBranches, [
        BranchType.mind,
        BranchType.body,
        BranchType.bond,
        BranchType.spirit,
      ]);
      // Craft was active all season, so its level is baked in and banked.
      expect(next.configFor(BranchType.craft).baseLevel, 2);
      expect(next.configFor(BranchType.craft).isEnabled, isFalse);
      expect(result.summary.branches.keys, BranchType.defaults);
      expect(result.summary.endLevel, 9);
      final sheet = CharacterSheet.fromState(next, afterSeason);
      expect(sheet.totalLevel, 3 + 3 + 1 + 0);
    });

    test('rollover keeps the pillars when none are chosen', () {
      final rested = withEnabled(
        buildDemoState(today),
        BranchType.empire,
        false,
      );
      final result = SeasonRollover.apply(
        rested,
        afterSeason,
        newSeasonId: 's2',
      );
      expect(result.state.activeBranches, rested.activeBranches);
      expect(result.summary.branches.keys, rested.activeBranches);
    });

    test('rollover refuses fewer than the minimum pillars', () {
      expect(
        () => SeasonRollover.apply(
          buildDemoState(today),
          afterSeason,
          newSeasonId: 's2',
          activeBranches: {BranchType.mind, BranchType.body},
        ),
        throwsArgumentError,
      );
    });
  });

  group('store', () {
    test('renameBranch saves the name; blank restores the default', () async {
      final repo = InMemoryRepository(buildDemoState(today));
      final container = makeContainer(repo);
      final store = container.read(rpgStoreProvider.notifier);
      await container.read(rpgStoreProvider.future);

      await store.renameBranch(BranchType.body, '  Health ');
      expect(repo.saved!.nameOf(BranchType.body), 'Health');
      expect(repo.saved!.configFor(BranchType.body).baseLevel, 1);
      final writes = repo.saveCount;

      await store.renameBranch(BranchType.body, 'Health');
      expect(repo.saveCount, writes); // Unchanged: no write.

      await store.renameBranch(BranchType.body, '');
      expect(repo.saved!.nameOf(BranchType.body), 'Body');
    });

    test('habits and quests cannot join a resting pillar', () async {
      final repo = InMemoryRepository(buildDemoState(today));
      final container = makeContainer(repo);
      final store = container.read(rpgStoreProvider.notifier);
      await container.read(rpgStoreProvider.future);

      await expectLater(
        store.addOrUpdateHabit(branch: BranchType.wander, title: 'Hike'),
        throwsArgumentError,
      );
      await expectLater(
        store.addQuest(title: 'Trip', branch: BranchType.wander),
        throwsArgumentError,
      );
    });

    test('completeSeason applies the chosen pillars', () async {
      final repo = InMemoryRepository(buildDemoState(today));
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => afterSeason),
          rpgRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      await container.read(rpgStoreProvider.future);

      await container
          .read(rpgStoreProvider.notifier)
          .completeSeason(
            activeBranches: {...BranchType.defaults, BranchType.wander},
          );
      expect(repo.saved!.activeBranches, [
        ...BranchType.defaults,
        BranchType.wander,
      ]);
    });
  });

  group('SQLite', () {
    setUpAll(sqfliteFfiInit);

    test('names and enabled pillars round-trip', () async {
      final repo = RpgSqliteRepository(
        DatabaseHelper(
          factory: databaseFactoryFfi,
          path: DatabaseHelper.inMemoryPath,
        ),
      );
      addTearDown(repo.close);
      await repo.initializeFromOnboarding(threePillarState());
      var loaded = (await repo.loadFullState())!;
      expect(loaded.activeBranches, [
        BranchType.mind,
        BranchType.body,
        BranchType.spirit,
      ]);
      expect(loaded.nameOf(BranchType.spirit), 'Faith');

      await repo.renameBranch(
        loaded.configFor(BranchType.mind).copyWith(customName: 'Lore'),
      );
      loaded = (await repo.loadFullState())!;
      expect(loaded.nameOf(BranchType.mind), 'Lore');
      expect(
        loaded.branchConfigs,
        threePillarState().branchConfigs.map(
          (c) =>
              c.branch == BranchType.mind ? c.copyWith(customName: 'Lore') : c,
        ),
      );
    });

    test('upgrading a v4 database keeps the five pillars enabled', () async {
      final dir = await Directory.systemTemp.createTemp('level_up_v4');
      addTearDown(() => dir.delete(recursive: true));
      final path = p.join(dir.path, DatabaseHelper.fileName);

      // Write the demo with a current helper, then strip it back to v4.
      final setup = DatabaseHelper(factory: databaseFactoryFfi, path: path);
      await RpgSqliteRepository(setup).replaceAllData(buildDemoState(today));
      final db = await setup.database;
      await db.execute(
        'CREATE TABLE v4 AS SELECT branch, base_level, buff_text, '
        'debuff_text, forged_node_count FROM branch_configs',
      );
      await db.execute('DROP TABLE branch_configs');
      await db.execute('ALTER TABLE v4 RENAME TO branch_configs');
      // Characters gained avatar_data in v6.
      await db.execute(
        'CREATE TABLE c5 AS SELECT id, name, class_title, signature_data, '
        'current_season_id, signature_text FROM characters',
      );
      await db.execute('DROP TABLE characters');
      await db.execute('ALTER TABLE c5 RENAME TO characters');
      await db.setVersion(4);
      await setup.close();

      final repo = RpgSqliteRepository(
        DatabaseHelper(factory: databaseFactoryFfi, path: path),
      );
      addTearDown(repo.close);
      final loaded = (await repo.loadFullState())!;
      expect(loaded.activeBranches, BranchType.defaults);
      expect(loaded.nameOf(BranchType.mind), 'Mind');
      expect(CharacterSheet.fromState(loaded, today).totalLevel, 9);
    });
  });

  group('screens', () {
    testWidgets('renaming a pillar in Settings shows on the Skill Tree', (
      tester,
    ) async {
      final repo = await pumpLevelUp(
        tester,
        now: today,
        state: buildDemoState(today),
        size: const Size(800, 3000),
      );
      await tester.tap(find.text('Season Tally').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Rename Pillars'));
      await tester.tap(find.text('Rename Pillars'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('rename-body')),
        'Health',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.saved!.nameOf(BranchType.body), 'Health');

      await tester.tap(find.text('Skill Tree'));
      await tester.pumpAndSettle();
      expect(find.text('HEALTH'), findsOneWidget);
      expect(find.bySemanticsLabel('Health node 1, unlocked'), findsOneWidget);
    });

    testWidgets('the rollover dialog picks next season\'s pillars', (
      tester,
    ) async {
      final repo = await pumpLevelUp(
        tester,
        now: afterSeason,
        state: buildDemoState(today),
        size: const Size(800, 3000),
      );
      await tester.tap(find.text('Season Tally').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Complete Season 1 & Level Up'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('pillar-toggle-empire')));
      await tester.tap(find.byKey(const ValueKey('pillar-toggle-spirit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Resting: Empire.'), findsOneWidget);
      await tester.tap(find.text('Level Up'));
      await tester.pumpAndSettle();

      expect(find.text('Season 1 Complete!'), findsOneWidget);
      expect(repo.saved!.activeBranches, [
        BranchType.mind,
        BranchType.body,
        BranchType.craft,
        BranchType.bond,
        BranchType.spirit,
      ]);
    });

    testWidgets('the minimum pillars cannot be unchecked', (tester) async {
      await pumpLevelUp(
        tester,
        now: afterSeason,
        state: buildDemoState(today),
        size: const Size(800, 3000),
      );
      await tester.tap(find.text('Season Tally').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Complete Season 1 & Level Up'));
      await tester.pumpAndSettle();

      for (final b in [BranchType.craft, BranchType.bond]) {
        await tester.tap(find.byKey(ValueKey('pillar-toggle-${b.name}')));
        await tester.pumpAndSettle();
      }
      Checkbox box(BranchType b) =>
          tester.widget(find.byKey(ValueKey('pillar-toggle-${b.name}')));
      expect(box(BranchType.mind).onChanged, isNull);
      expect(box(BranchType.wander).onChanged, isNotNull);
    });

    testWidgets('seven pillars fit a 320pt-wide Skill Tree', (tester) async {
      var state = buildDemoState(today);
      for (final b in [BranchType.spirit, BranchType.wander]) {
        state = withEnabled(state, b, true);
      }
      await pumpLevelUp(
        tester,
        now: today,
        state: state,
        size: const Size(320, 3000),
      );
      await tester.tap(find.text('Skill Tree'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('6/35 nodes'), findsOneWidget);
      expect(find.text('WANDER'), findsOneWidget);
    });
  });
}
