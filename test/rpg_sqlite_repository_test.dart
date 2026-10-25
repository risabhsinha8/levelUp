import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_up/data/database_helper.dart';
import 'package:level_up/data/rpg_sqlite_repository.dart';
import 'package:level_up/domain/new_character.dart';
import 'package:level_up/domain/season_rollover.dart';
import 'package:level_up/models/rpg_models.dart';
import 'package:level_up/models/rpg_state.dart';
import 'package:level_up/providers/rpg_store_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fixtures.dart';

final today = DateTime(2026, 10, 24, 9);

RpgSqliteRepository openRepo([String path = DatabaseHelper.inMemoryPath]) {
  final repo = RpgSqliteRepository(
    DatabaseHelper(factory: databaseFactoryFfi, path: path),
  );
  addTearDown(repo.close);
  return repo;
}

RpgState onboardingState() {
  var next = 0;
  return buildNewCharacterState(
    name: 'Ari',
    classTitle: 'Weekend Warrior',
    keystones: const [
      KeystoneChoice(
        branch: BranchType.mind,
        title: 'Read',
        targetCriteria: '10 pages',
      ),
      KeystoneChoice(
        branch: BranchType.body,
        title: 'Walk',
        targetCriteria: '8,000 steps',
      ),
      KeystoneChoice(branch: BranchType.craft, title: 'Sketch'),
      KeystoneChoice(branch: BranchType.bond, title: 'Call someone'),
      KeystoneChoice(branch: BranchType.empire, title: 'Ship'),
    ],
    mainQuest: const MainQuestChoice(
      title: 'Run a 5K',
      branch: BranchType.body,
      difficulty: 4,
      rewardText: 'New shoes',
    ),
    loot: const [
      LootChoice(tier: LootTier.common, title: 'Fancy coffee'),
      LootChoice(tier: LootTier.rare, title: 'Binge TV night'),
      LootChoice(tier: LootTier.epic, title: 'New guitar gear'),
      LootChoice(tier: LootTier.legendary, title: 'Weekend trip'),
    ],
    today: today,
    seasonId: 'season-1',
    newId: () => 'id-${next++}',
  );
}

/// Compares states via JSON, normalizing the orders the database defines.
Map<String, dynamic> normalized(RpgState state) {
  final json = state.toJson();
  (json['reflections'] as List).sort(
    (a, b) => (a['monthKey'] as String).compareTo(b['monthKey'] as String),
  );
  (json['logs'] as List).sort(
    (a, b) => (a['dateString'] as String).compareTo(b['dateString'] as String),
  );
  return json;
}

Future<int> count(RpgSqliteRepository repo, String table) async {
  final db = await repo.helper.database;
  return Sqflite.firstIntValue(
    await db.rawQuery('SELECT COUNT(*) FROM $table'),
  )!;
}

void main() {
  setUpAll(sqfliteFfiInit);

  group('schema', () {
    test('creates the Phase 7 tables and columns', () async {
      final repo = openRepo();
      final db = await repo.helper.database;
      Future<Set<String>> columns(String table) async => {
        for (final row in await db.rawQuery('PRAGMA table_info($table)'))
          row['name']! as String,
      };

      expect(
        await columns('characters'),
        containsAll([
          'id',
          'name',
          'class_title',
          'signature_data',
          'current_season_id',
        ]),
      );
      expect(
        await columns('seasons'),
        containsAll([
          'id',
          'name',
          'start_date',
          'end_date',
          'is_archived',
          'mid_month_notes',
        ]),
      );
      expect(
        await columns('branch_configs'),
        containsAll(['branch', 'base_level', 'buff_text', 'debuff_text']),
      );
      expect(
        await columns('habits'),
        containsAll([
          'id',
          'branch',
          'title',
          'target_criteria',
          'is_keystone',
          'active_half_month',
        ]),
      );
      expect(
        await columns('daily_logs'),
        containsAll(['date_string', 'habit_id']),
      );
      expect(
        await columns('quests'),
        containsAll([
          'id',
          'title',
          'is_main_quest',
          'branch',
          'difficulty',
          'is_completed',
          'month_index',
          'reward_text',
        ]),
      );
      expect(
        await columns('loot_items'),
        containsAll(['id', 'tier', 'title', 'claimed_at_date']),
      );
    });

    test('an empty database has no character', () async {
      final repo = openRepo();
      expect(await repo.hasCharacter(), isFalse);
      expect(await repo.loadFullState(), isNull);
    });
  });

  group('initializeFromOnboarding', () {
    test('writes every starting record', () async {
      final repo = openRepo();
      await repo.initializeFromOnboarding(onboardingState());

      expect(await repo.hasCharacter(), isTrue);
      final state = (await repo.loadFullState())!;
      expect(state.character.name, 'Ari');
      expect(state.character.classTitle, 'Weekend Warrior');

      final season = state.currentSeason;
      expect(season.name, 'Season 1');
      // The calendar quarter containing the Oct 24 onboarding.
      expect(toDateString(season.startDate), '2026-10-01');
      expect(toDateString(season.endDate), '2026-12-31');

      expect(state.branchConfigs.map((c) => c.branch), BranchType.values);
      expect(state.branchConfigs.every((c) => c.baseLevel == 0), isTrue);

      expect(state.habits, hasLength(5));
      expect(state.habits.every((h) => h.isKeystone), isTrue);
      expect(state.keystoneFor(BranchType.body)!.targetCriteria, '8,000 steps');

      final quest = state.quests.single;
      expect(quest.isMainQuest, isTrue);
      expect(quest.monthIndex, 1);
      expect(quest.seasonId, 'season-1');
      expect(quest.rewardText, 'New shoes');

      expect(state.loot.map((l) => l.tier), LootTier.values);
      expect(state.loot.every((l) => !l.isClaimed), isTrue);
      expect(normalized(state), normalized(onboardingState()));
    });

    test('refuses to run twice and keeps the existing character', () async {
      final repo = openRepo();
      await repo.initializeFromOnboarding(onboardingState());
      await expectLater(
        repo.initializeFromOnboarding(buildFreshState(today)),
        throwsStateError,
      );
      expect((await repo.loadFullState())!.character.name, 'Ari');
    });

    test('is atomic: a failure part-way writes nothing', () async {
      final repo = openRepo();
      final initial = onboardingState();
      // Duplicate habit ids fail on the primary key after earlier inserts.
      final broken = initial.copyWith(
        habits: [...initial.habits, initial.habits.first],
      );
      await expectLater(
        repo.initializeFromOnboarding(broken),
        throwsA(isA<DatabaseException>()),
      );
      expect(await repo.hasCharacter(), isFalse);
      for (final table in DatabaseHelper.tables) {
        expect(await count(repo, table), 0, reason: table);
      }
    });
  });

  group('toggleHabitForDate', () {
    test('adds and removes a check-in', () async {
      final repo = openRepo();
      await repo.initializeFromOnboarding(onboardingState());

      expect(await repo.toggleHabitForDate('id-0', '2026-10-24'), isTrue);
      expect(
        (await repo.loadFullState())!.completedOn(DateTime(2026, 10, 24)),
        {'id-0'},
      );
      expect(await repo.toggleHabitForDate('id-0', '2026-10-24'), isFalse);
      expect(
        (await repo.loadFullState())!.completedOn(DateTime(2026, 10, 24)),
        isEmpty,
      );
      expect(await count(repo, 'daily_logs'), 0);
    });

    test('keeps multiple habits and dates apart, in order', () async {
      final repo = openRepo();
      await repo.initializeFromOnboarding(onboardingState());

      await repo.toggleHabitForDate('id-1', '2026-10-24');
      await repo.toggleHabitForDate('id-0', '2026-10-24');
      await repo.toggleHabitForDate('id-0', '2026-10-25');
      final logs = (await repo.loadFullState())!.logs;
      expect(logs.map((l) => l.dateString), ['2026-10-24', '2026-10-25']);
      expect(logs.first.completedHabitIds, ['id-1', 'id-0']);
      expect(logs.last.completedHabitIds, ['id-0']);
    });

    test('a check-in survives restarting the app', () async {
      final dir = await Directory.systemTemp.createTemp('level_up_db');
      addTearDown(() => dir.delete(recursive: true));
      final path = p.join(dir.path, DatabaseHelper.fileName);

      final first = RpgSqliteRepository(
        DatabaseHelper(factory: databaseFactoryFfi, path: path),
      );
      await first.initializeFromOnboarding(onboardingState());
      await first.toggleHabitForDate('id-2', '2026-10-24');
      await first.close();

      final second = openRepo(path);
      final state = (await second.loadFullState())!;
      expect(state.completedOn(DateTime(2026, 10, 24)), {'id-2'});
      expect(File(path).existsSync(), isTrue);
    });
  });

  group('granular writes', () {
    test('upsertHabit keeps position and one active keystone', () async {
      final repo = openRepo();
      await repo.replaceAllData(buildDemoState(today));

      // Archive the Body keystone, then star Sleep.
      await repo.upsertHabit(
        const Habit(
          id: 'habit-exercise',
          branch: BranchType.body,
          title: 'Exercise',
          targetCriteria: '20 min movement',
          isKeystone: true,
          isArchived: true,
        ),
      );
      await repo.upsertHabit(
        const Habit(
          id: 'habit-sleep',
          branch: BranchType.body,
          title: 'Sleep',
          targetCriteria: '8 hrs',
          isKeystone: true,
        ),
      );
      await repo.upsertHabit(
        const Habit(id: 'habit-new', branch: BranchType.body, title: 'Stretch'),
      );

      final state = (await repo.loadFullState())!;
      expect(state.keystoneFor(BranchType.body)!.id, 'habit-sleep');
      // Archived keystone keeps its star.
      expect(
        state.habits.firstWhere((h) => h.id == 'habit-exercise').isKeystone,
        isTrue,
      );
      expect(state.habits.indexWhere((h) => h.id == 'habit-sleep'), 2);
      expect(state.habits.last.id, 'habit-new');

      await repo.deleteHabit('habit-new');
      expect(
        (await repo.loadFullState())!.habits.map((h) => h.id),
        isNot(contains('habit-new')),
      );
    });

    test('updateBranchBuffDebuff stores chip lists', () async {
      final repo = openRepo();
      await repo.initializeFromOnboarding(onboardingState());
      await repo.updateBranchBuffDebuff(
        const BranchConfig(
          branch: BranchType.body,
          buffs: ['Gym clothes laid out', 'Water by the bed'],
          debuffs: ['Late night scrolling'],
        ),
      );
      final config = (await repo.loadFullState())!.configFor(BranchType.body);
      expect(config.buffs, ['Gym clothes laid out', 'Water by the bed']);
      expect(config.debuffs, ['Late night scrolling']);
      expect(config.baseLevel, 0);
    });

    test('quests: new main quest demotes the old one; completeQuest', () async {
      final repo = openRepo();
      await repo.initializeFromOnboarding(onboardingState());
      await repo.upsertQuest(
        const Quest(
          id: 'q2',
          title: 'Read 3 books',
          isMainQuest: true,
          branch: BranchType.mind,
          seasonId: 'season-1',
        ),
      );
      await repo.completeQuest('q2');

      final quests = (await repo.loadFullState())!.quests;
      expect(quests.where((q) => q.isMainQuest).map((q) => q.id), ['q2']);
      expect(quests.firstWhere((q) => q.id == 'q2').isCompleted, isTrue);

      await repo.completeQuest('q2', completed: false);
      expect((await repo.loadFullState())!.quests.last.isCompleted, isFalse);
    });

    test('loot: add a reward, then claim it', () async {
      final repo = openRepo();
      await repo.initializeFromOnboarding(onboardingState());
      await repo.upsertLootItem(
        const LootItem(id: 'l-new', tier: LootTier.rare, title: 'Board game'),
      );
      final claimedAt = DateTime(2026, 10, 24, 15, 42);
      await repo.claimLootItem(
        LootItem(
          id: 'claim-1',
          tier: LootTier.rare,
          title: 'Board game',
          claimedAtDate: '2026-10-24',
          claimedAt: claimedAt,
        ),
      );
      await expectLater(
        repo.claimLootItem(
          const LootItem(id: 'x', tier: LootTier.rare, title: 'Unclaimed'),
        ),
        throwsArgumentError,
      );

      final loot = (await repo.loadFullState())!.loot;
      expect(loot.map((l) => l.id).skip(4), ['l-new', 'claim-1']);
      expect(loot.last.claimedAt, claimedAt);
      expect(loot.where((l) => l.isClaimed), hasLength(1));
    });

    test('saveSignature stores and clears the current oath', () async {
      final repo = openRepo();
      await repo.initializeFromOnboarding(onboardingState());
      final oath = SeasonOath(
        strokes: [
          [0.1, 0.5, 0.3, 0.6],
        ],
        signedAtDate: '2026-10-24',
      );
      await repo.saveSignature('season-1', oath);
      expect((await repo.loadFullState())!.currentSeason.oath, oath);
      final db = await repo.helper.database;
      expect(
        (await db.query('characters')).single['signature_data'],
        contains('"strokes"'),
      );

      await repo.saveSignature('season-1', null);
      expect((await repo.loadFullState())!.currentSeason.oath, isNull);
    });

    test('reflections and pivots live in seasons.mid_month_notes', () async {
      final repo = openRepo();
      await repo.replaceAllData(buildDemoState(today));
      final meditation = (await repo.loadFullState())!.habits.firstWhere(
        (h) => h.id == 'habit-meditation',
      );
      await repo.pivotHabit(
        old: meditation.copyWith(activeHalfMonth: ActiveHalfMonth.firstHalf),
        replacement: const Habit(
          id: 'habit-journal',
          branch: BranchType.mind,
          title: 'Journal',
          activeHalfMonth: ActiveHalfMonth.secondHalf,
        ),
        reflection: MonthReflection(
          monthKey: '2026-10',
          notes: 'Meditation felt like a chore.',
          pivots: ['Meditation → Journal'],
        ),
      );
      await repo.saveReflection(
        MonthReflection(
          monthKey: '2026-10',
          notes: 'Updated notes',
          pivots: ['Meditation → Journal'],
        ),
      );

      final state = (await repo.loadFullState())!;
      final reflection = state.reflectionFor(DateTime(2026, 10, 1));
      expect(reflection.notes, 'Updated notes');
      expect(reflection.pivots, ['Meditation → Journal']);
      expect(
        state.habits
            .firstWhere((h) => h.id == 'habit-meditation')
            .activeHalfMonth,
        ActiveHalfMonth.firstHalf,
      );
      expect(state.habits.last.id, 'habit-journal');
      final db = await repo.helper.database;
      expect(
        (await db.query('seasons')).single['mid_month_notes'],
        contains('Updated notes'),
      );
    });

    test('updateCharacter edits name and class', () async {
      final repo = openRepo();
      await repo.initializeFromOnboarding(onboardingState());
      final state = (await repo.loadFullState())!;
      await repo.updateCharacter(
        state.character.copyWith(name: 'Rowan', classTitle: 'Late Bloomer'),
      );
      final character = (await repo.loadFullState())!.character;
      expect(character.name, 'Rowan');
      expect(character.classTitle, 'Late Bloomer');
    });

    test('prestigeSeason writes the full rollover', () async {
      final repo = openRepo();
      final demo = buildDemoState(today);
      await repo.replaceAllData(demo);
      final oath = SeasonOath(
        strokes: [
          [0.2, 0.4],
        ],
        signedAtDate: '2026-10-10',
      );
      await repo.saveSignature('season-1', oath);

      final before = (await repo.loadFullState())!;
      final result = SeasonRollover.apply(
        before,
        DateTime(2027, 1, 1),
        newSeasonId: 's2',
      );
      await repo.prestigeSeason(
        completed: result.completedSeason,
        next: result.state,
      );

      final after = (await repo.loadFullState())!;
      expect(normalized(after), normalized(result.state));
      expect(after.currentSeason.id, 's2');
      expect(after.currentSeason.oath, isNull);
      final archived = after.seasons.firstWhere((s) => s.id == 'season-1');
      expect(archived.isArchived, isTrue);
      expect(archived.oath, oath); // kept with the archived season
      expect(archived.summary!.endLevel, 9);
      expect(after.configFor(BranchType.mind).baseLevel, 3);
      expect(after.quests.every((q) => q.seasonId == 'season-1'), isTrue);
    });

    test('replaceAllData round-trips the demo character', () async {
      final repo = openRepo();
      final demo = buildDemoState(today);
      await repo.replaceAllData(demo);
      expect(normalized((await repo.loadFullState())!), normalized(demo));
    });
  });

  group('wipeAllData', () {
    test('empties every table and returns to onboarding', () async {
      final repo = openRepo();
      await repo.replaceAllData(buildDemoState(today));
      await repo.toggleHabitForDate('habit-water', '2026-10-24');
      expect(await repo.hasCharacter(), isTrue);

      await repo.wipeAllData();
      expect(await repo.hasCharacter(), isFalse);
      expect(await repo.loadFullState(), isNull);
      for (final table in DatabaseHelper.tables) {
        expect(await count(repo, table), 0, reason: table);
      }

      // Onboarding works again on the wiped database.
      await repo.initializeFromOnboarding(onboardingState());
      expect(await repo.hasCharacter(), isTrue);
    });
  });

  test('store end-to-end: onboarding and check-ins persist', () async {
    final dir = await Directory.systemTemp.createTemp('level_up_db');
    addTearDown(() => dir.delete(recursive: true));
    final path = p.join(dir.path, DatabaseHelper.fileName);

    ProviderContainer launch() {
      final repo = openRepo(path);
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => today),
          rpgRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    final first = launch();
    expect(await first.read(rpgStoreProvider.future), isNull);
    final store = first.read(rpgStoreProvider.notifier);
    await store.completeOnboarding(
      name: 'Ari',
      classTitle: 'Weekend Warrior',
      keystones: const [KeystoneChoice(branch: BranchType.body, title: 'Walk')],
      mainQuest: const MainQuestChoice(
        title: 'Run a 5K',
        branch: BranchType.body,
      ),
      loot: const [LootChoice(tier: LootTier.common, title: 'Coffee')],
    );
    final walk = first.read(rpgStateProvider).habits.single;
    await store.toggleHabitForDate(walk.id, today);
    await store.completeQuest(first.read(rpgStateProvider).quests.single.id);

    final second = launch();
    final reloaded = (await second.read(rpgStoreProvider.future))!;
    expect(reloaded.character.name, 'Ari');
    expect(reloaded.completedOn(today), {walk.id});
    expect(reloaded.quests.single.isCompleted, isTrue);
    expect(second.read(characterSheetProvider).value!.totalLevel, 1);
  });
}
