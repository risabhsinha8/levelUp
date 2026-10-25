import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_up/domain/character_sheet.dart';
import 'package:level_up/domain/new_character.dart';
import 'package:level_up/domain/rpg_engine.dart';
import 'package:level_up/models/rpg_models.dart';
import 'package:level_up/models/rpg_state.dart';
import 'package:level_up/providers/rpg_store_provider.dart';

import 'support/fixtures.dart';

final now = DateTime(2026, 10, 24, 9, 30);

/// After the demo season's quarter (Oct 7 – Dec 31) has ended.
final afterSeason = DateTime(2027, 1, 2, 9, 30);

ProviderContainer makeContainer(InMemoryRepository repo, {DateTime? at}) {
  final container = ProviderContainer(
    overrides: [
      clockProvider.overrideWithValue(() => at ?? now),
      rpgRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('demo seed data', () {
    final demo = buildDemoState(now);
    final sheet = CharacterSheet.fromState(demo, now);

    test('is a Level 9 Recovering Couch Potato on Day 18/86', () {
      expect(demo.character.classTitle, 'Recovering Couch Potato');
      expect(sheet.totalLevel, 9);
      expect(sheet.seasonDay, 18);
      expect(sheet.seasonLength, 86); // Oct 7 – Dec 31
    });

    test('has 17 days of logs ending yesterday', () {
      // 17 days of check-ins; today (day 18) is still open.
      expect(demo.logs, hasLength(17));
      expect(demo.logs.last.dateString, '2026-10-23');
      expect(demo.logs.first.dateString, '2026-10-07');
      expect(
        demo.logs.every((l) => l.dateString.startsWith('2026-10')),
        isTrue,
      );
    });

    test('unlocks the 5- and 15-day nodes on some branches', () {
      final nodes = {
        for (final s in sheet.branches.values) s.branch: s.unlockedNodes,
      };
      expect(nodes, {
        BranchType.mind: 2,
        BranchType.body: 2,
        BranchType.craft: 1,
        BranchType.bond: 1,
        BranchType.empire: 0,
      });
    });

    test('every branch has buffs, debuffs and exactly one keystone', () {
      for (final branch in BranchType.values) {
        final config = demo.configFor(branch);
        expect(config.buffs, isNotEmpty);
        expect(config.debuffs, isNotEmpty);
        expect(demo.habitsFor(branch).where((h) => h.isKeystone), hasLength(1));
      }
      expect(
        demo.habits.firstWhere((h) => h.title == 'Water').targetCriteria,
        '13 cups daily',
      );
    });

    test('keys: 2 Common, 6 Rare earned with 1 Rare already claimed', () {
      expect(sheet.lootKeys[LootTier.common]!.earned, 2);
      expect(sheet.lootKeys[LootTier.rare]!.earned, 6);
      expect(sheet.lootKeys[LootTier.rare]!.claimed, 1);
    });

    test('survives a JSON round-trip', () {
      final restored = RpgState.fromJson(demo.toJson());
      expect(restored.toJson(), demo.toJson());
    });
  });

  group('RpgStore', () {
    test('first launch has no character and saves nothing', () async {
      final repo = InMemoryRepository();
      final container = makeContainer(repo);
      expect(await container.read(rpgStoreProvider.future), isNull);
      expect(repo.saveCount, 0);
      expect(container.read(characterSheetProvider).isLoading, isTrue);
    });

    test('completeOnboarding creates the character and Season 1', () async {
      final repo = InMemoryRepository();
      final container = makeContainer(repo);
      await container.read(rpgStoreProvider.future);

      await container
          .read(rpgStoreProvider.notifier)
          .completeOnboarding(
            name: 'Ari',
            classTitle: 'Weekend Warrior',
            keystones: const [
              KeystoneChoice(
                branch: BranchType.body,
                title: 'Walk',
                targetCriteria: '20 min',
              ),
              KeystoneChoice(branch: BranchType.mind, title: 'Read'),
              KeystoneChoice(branch: BranchType.bond, title: '  '),
            ],
          );

      final state = repo.saved!;
      expect(repo.saveCount, 1);
      expect(state.character.name, 'Ari');
      expect(state.currentSeason.name, 'Season 1');
      // Season 1 is the current quarter; Oct 24 is day 24 of Oct 1–Dec 31.
      expect(toDateString(state.currentSeason.startDate), '2026-10-01');
      expect(toDateString(state.currentSeason.endDate), '2026-12-31');
      // Blank keystones are skipped; habits follow branch order.
      expect(state.habits.map((h) => h.title), ['Read', 'Walk']);
      expect(state.habits.every((h) => h.isKeystone), isTrue);
      expect(state.keystoneFor(BranchType.body)!.targetCriteria, '20 min');
      expect(state.branchConfigs.map((c) => c.baseLevel), [0, 0, 0, 0, 0]);
      final sheet = container.read(characterSheetProvider).value!;
      expect(sheet.totalLevel, 0);
      expect(sheet.seasonDay, 24);
    });

    test('isOnboarded follows the character in storage', () async {
      final repo = InMemoryRepository();
      final container = makeContainer(repo);
      await container.read(rpgStoreProvider.future);
      expect(container.read(isOnboardedProvider), isFalse);

      final store = container.read(rpgStoreProvider.notifier);
      await store.completeOnboarding(
        name: 'Ari',
        classTitle: 'Novice',
        keystones: const [
          KeystoneChoice(branch: BranchType.mind, title: 'Read'),
        ],
      );
      expect(container.read(isOnboardedProvider), isTrue);
      // The state is re-read from storage after onboarding.
      expect(identical(container.read(rpgStateProvider), repo.saved), isTrue);

      await store.wipeDatabaseAndRestart();
      expect(container.read(isOnboardedProvider), isFalse);
    });

    test(
      'wipeDatabaseAndRestart erases everything and returns to onboarding',
      () async {
        final repo = InMemoryRepository(buildDemoState(now));
        final container = makeContainer(repo);
        await container.read(rpgStoreProvider.future);

        await container
            .read(rpgStoreProvider.notifier)
            .wipeDatabaseAndRestart();
        expect(repo.saved, isNull);
        expect(container.read(rpgStoreProvider).value, isNull);
        expect(container.read(characterSheetProvider).isLoading, isTrue);
      },
    );

    test('actions need a character', () async {
      final container = makeContainer(InMemoryRepository());
      await container.read(rpgStoreProvider.future);
      final store = container.read(rpgStoreProvider.notifier);
      await expectLater(store.toggleHabitForDate('x', now), throwsStateError);
      await expectLater(store.exportBackup(), throwsStateError);
    });

    test('loads the saved state', () async {
      final repo = InMemoryRepository(buildFreshState(now));
      final container = makeContainer(repo);
      final state = await container.read(rpgStoreProvider.future);
      expect(state!.character.classTitle, 'Novice');
      expect(repo.saveCount, 0);
    });

    test('toggleHabitForDate adds, removes and persists completions', () async {
      final repo = InMemoryRepository(buildFreshState(now));
      final container = makeContainer(repo);
      final store = container.read(rpgStoreProvider.notifier);
      await container.read(rpgStoreProvider.future);

      final id = await store.addOrUpdateHabit(
        branch: BranchType.body,
        title: 'Walk',
      );
      await store.toggleHabitForDate(id, now);
      expect(repo.saved!.logs.single.completedHabitIds, [id]);
      expect(repo.saved!.logs.single.dateString, '2026-10-24');

      await store.toggleHabitForDate(id, now);
      expect(repo.saved!.logs, isEmpty);
    });

    test('concurrent toggles do not drop updates', () async {
      final repo = InMemoryRepository(buildFreshState(now));
      final container = makeContainer(repo);
      final store = container.read(rpgStoreProvider.notifier);
      await container.read(rpgStoreProvider.future);

      await Future.wait([
        store.toggleHabitForDate('a', now),
        store.toggleHabitForDate('b', now),
      ]);
      expect(repo.saved!.logs.single.completedHabitIds, ['a', 'b']);
    });

    test(
      'a new keystone unstars the old keystone in that branch only',
      () async {
        final repo = InMemoryRepository(buildDemoState(now));
        final container = makeContainer(repo);
        final store = container.read(rpgStoreProvider.notifier);
        await container.read(rpgStoreProvider.future);

        await store.addOrUpdateHabit(
          id: 'habit-water',
          branch: BranchType.body,
          title: 'Water',
          targetCriteria: '13 cups daily',
          isKeystone: true,
        );
        final habits = repo.saved!.habits;
        final bodyKeystones = habits
            .where((h) => h.branch == BranchType.body && h.isKeystone)
            .map((h) => h.id);
        expect(bodyKeystones, ['habit-water']);
        expect(
          habits.firstWhere((h) => h.id == 'habit-reading').isKeystone,
          isTrue,
        );
        // Updating keeps the habit in place rather than appending it.
        expect(habits.indexWhere((h) => h.id == 'habit-water'), 1);
      },
    );

    test('completeQuest adds a feat and raises the level', () async {
      final container = makeContainer(InMemoryRepository(buildDemoState(now)));
      await container.read(rpgStoreProvider.future);
      expect(container.read(characterSheetProvider).value!.totalLevel, 9);

      await container
          .read(rpgStoreProvider.notifier)
          .completeQuest('quest-book');
      final sheet = container.read(characterSheetProvider).value!;
      expect(sheet.branches[BranchType.mind]!.completedFeats, 1);
      expect(sheet.totalLevel, 10);
    });

    test('claimLoot spends one key per claim and logs history', () async {
      final container = makeContainer(InMemoryRepository(buildDemoState(now)));
      final store = container.read(rpgStoreProvider.notifier);
      await container.read(rpgStoreProvider.future);
      int commonAvailable() => container
          .read(characterSheetProvider)
          .value!
          .lootKeys[LootTier.common]!
          .available;
      expect(commonAvailable(), 2);

      // Rewards are reusable: the same reward can be claimed per key.
      expect(await store.claimLoot('loot-coffee'), isTrue);
      expect(await store.claimLoot('loot-coffee'), isTrue);
      expect(await store.claimLoot('loot-coffee'), isFalse);
      expect(commonAvailable(), 0);

      final loot = container.read(rpgStoreProvider).value!.loot;
      final catalogItem = loot.firstWhere((l) => l.id == 'loot-coffee');
      expect(catalogItem.isClaimed, isFalse);
      final claims = loot.where(
        (l) => l.title == 'Fancy coffee' && l.isClaimed,
      );
      expect(claims, hasLength(2));
      expect(claims.first.claimedAtDate, '2026-10-24');
      expect(claims.first.claimedAt, now);
      expect(claims.first.id, isNot('loot-coffee'));
    });

    test('claimLoot refuses when no key of that tier is available', () async {
      final container = makeContainer(InMemoryRepository(buildDemoState(now)));
      final store = container.read(rpgStoreProvider.notifier);
      await container.read(rpgStoreProvider.future);

      expect(await store.claimLoot('loot-concert'), isFalse); // Epic: 0 keys
      expect(await store.claimLoot('missing'), isFalse);
    });

    test('updateSignature saves the signature text', () async {
      final repo = InMemoryRepository(buildDemoState(now));
      final container = makeContainer(repo);
      await container.read(rpgStoreProvider.future);

      await container.read(rpgStoreProvider.notifier).updateSignature('Onward');
      expect(repo.saved!.character.signatureText, 'Onward');
    });
  });

  group('half-month scheduling and reflections', () {
    test('Half 1 is days 1–15, Half 2 is 16 to month end', () {
      expect(
        ActiveHalfMonth.of(DateTime(2026, 2, 15)),
        ActiveHalfMonth.firstHalf,
      );
      expect(
        ActiveHalfMonth.of(DateTime(2026, 2, 16)),
        ActiveHalfMonth.secondHalf,
      );
      const habit = Habit(
        id: 'h',
        branch: BranchType.mind,
        title: 'H',
        activeHalfMonth: ActiveHalfMonth.secondHalf,
      );
      expect(habit.isActiveOn(DateTime(2026, 10, 15)), isFalse);
      expect(habit.isActiveOn(DateTime(2026, 10, 31)), isTrue);
      expect(ActiveHalfMonth.both.includes(DateTime(2026, 10, 1)), isTrue);
    });

    test('habitsShownOn hides off-half habits unless completed that day', () {
      final state = buildDemoState(now).copyWith(
        habits: const [
          Habit(
            id: 'early',
            branch: BranchType.mind,
            title: 'Early',
            activeHalfMonth: ActiveHalfMonth.firstHalf,
          ),
          Habit(id: 'always', branch: BranchType.body, title: 'Always'),
        ],
        logs: [
          DailyLog(dateString: '2026-10-20', completedHabitIds: ['early']),
        ],
      );
      expect(state.habitsShownOn(DateTime(2026, 10, 24)).map((h) => h.id), [
        'always',
      ]);
      // Mind sorts before Body; logged history is never hidden.
      expect(state.habitsShownOn(DateTime(2026, 10, 20)).map((h) => h.id), [
        'early',
        'always',
      ]);
    });

    test('reflections round-trip through JSON', () {
      final state = buildFreshState(now).copyWith(
        reflections: [
          MonthReflection(
            monthKey: '2026-10',
            notes: 'Mornings worked',
            pivots: ['Meditation → Journaling'],
          ),
        ],
      );
      final restored = RpgState.fromJson(state.toJson());
      expect(restored.reflections, state.reflections);
      expect(
        restored.reflectionFor(DateTime(2026, 10, 2)).notes,
        'Mornings worked',
      );
      expect(restored.reflectionFor(DateTime(2026, 11, 2)).notes, isEmpty);
    });

    test('state saved before reflections existed still loads', () {
      final json = buildFreshState(now).toJson()..remove('reflections');
      expect(RpgState.fromJson(json).reflections, isEmpty);
    });

    test('updateReflectionNotes saves per month', () async {
      final repo = InMemoryRepository(buildDemoState(now));
      final container = makeContainer(repo);
      final store = container.read(rpgStoreProvider.notifier);
      await container.read(rpgStoreProvider.future);

      await store.updateReflectionNotes(DateTime(2026, 10), 'Sleep slipped');
      await store.updateReflectionNotes(DateTime(2026, 9), 'Older');
      await store.updateReflectionNotes(DateTime(2026, 10), 'Sleep fixed');
      expect(
        repo.saved!.reflectionFor(DateTime(2026, 10)).notes,
        'Sleep fixed',
      );
      expect(repo.saved!.reflectionFor(DateTime(2026, 9)).notes, 'Older');
      expect(repo.saved!.reflections, hasLength(2));
    });

    test('pivotHabit swaps Half 2 without losing earned points', () async {
      final repo = InMemoryRepository(buildDemoState(now));
      final container = makeContainer(repo);
      final store = container.read(rpgStoreProvider.notifier);
      await container.read(rpgStoreProvider.future);
      final before = container.read(characterSheetProvider).value!;

      final newId = await store.pivotHabit(
        oldHabitId: 'habit-meditation',
        newTitle: 'Journaling',
        newTargetCriteria: '1 page',
        month: now,
      );
      expect(newId, isNotNull);

      final state = repo.saved!;
      final old = state.habits.firstWhere((h) => h.id == 'habit-meditation');
      final replacement = state.habits.firstWhere((h) => h.id == newId);
      expect(old.activeHalfMonth, ActiveHalfMonth.firstHalf);
      expect(replacement.activeHalfMonth, ActiveHalfMonth.secondHalf);
      expect(replacement.branch, BranchType.mind);
      expect(replacement.targetCriteria, '1 page');
      expect(state.reflectionFor(now).pivots, ['Meditation → Journaling']);

      final after = container.read(characterSheetProvider).value!;
      expect(
        after.branches[BranchType.mind]!.activeDays,
        before.branches[BranchType.mind]!.activeDays,
      );
      expect(after.totalLevel, before.totalLevel);

      // Half 2 now shows Journaling instead of Meditation.
      final shown = state.habitsShownOn(now).map((h) => h.title);
      expect(shown, contains('Journaling'));
      expect(shown, isNot(contains('Meditation')));
    });

    test('pivotHabit refuses keystones and already-pivoted habits', () async {
      final repo = InMemoryRepository(buildDemoState(now));
      final container = makeContainer(repo);
      final store = container.read(rpgStoreProvider.notifier);
      await container.read(rpgStoreProvider.future);

      expect(
        await store.pivotHabit(
          oldHabitId: 'habit-reading',
          newTitle: 'X',
          month: now,
        ),
        isNull,
      );
      await store.pivotHabit(
        oldHabitId: 'habit-meditation',
        newTitle: 'Journaling',
        month: now,
      );
      expect(
        await store.pivotHabit(
          oldHabitId: 'habit-meditation',
          newTitle: 'Again',
          month: now,
        ),
        isNull,
      );
      expect(repo.saved!.reflectionFor(now).pivots, hasLength(1));
    });
  });

  group('character sheet edits', () {
    test('legacy single buff/debuff text loads as one chip', () {
      final config = BranchConfig.fromJson({
        'branch': 'body',
        'baseLevel': 2,
        'buffText': 'Gym clothes out',
        'debuffText': '',
      });
      expect(config.buffs, ['Gym clothes out']);
      expect(config.debuffs, isEmpty);
    });

    test('updateBranchModifiers edits one branch and keeps order', () async {
      final repo = InMemoryRepository(buildDemoState(now));
      final container = makeContainer(repo);
      final store = container.read(rpgStoreProvider.notifier);
      await container.read(rpgStoreProvider.future);

      await store.updateBranchModifiers(
        BranchType.craft,
        buffs: ['Desk cleared'],
      );
      final configs = repo.saved!.branchConfigs;
      expect(configs.map((c) => c.branch), BranchType.values);
      expect(repo.saved!.configFor(BranchType.craft).buffs, ['Desk cleared']);
      expect(repo.saved!.configFor(BranchType.craft).debuffs, [
        'Waiting for the "perfect" idea',
      ]);
    });

    test('sign and clear the season oath, persisted as JSON', () async {
      final repo = InMemoryRepository(buildDemoState(now));
      final container = makeContainer(repo);
      final store = container.read(rpgStoreProvider.notifier);
      await container.read(rpgStoreProvider.future);

      await store.signSeasonOath([
        [0.1, 0.5, 0.2, 0.6, 0.3, 0.55],
        [0.5, 0.5],
      ]);
      final oath = repo.saved!.currentSeason.oath!;
      expect(oath.signedAtDate, '2026-10-24');
      expect(oath.strokes, hasLength(2));

      final restored = RpgState.fromJson(repo.saved!.toJson());
      expect(restored.currentSeason.oath, oath);

      await store.clearSeasonOath();
      expect(repo.saved!.currentSeason.oath, isNull);
    });

    test('habit contribution counts distinct dates per habit', () {
      final demo = buildDemoState(now);
      int days(String id) => RpgEngine.calculateHabitActiveDays(
        id,
        demo.logs,
        season: demo.currentSeason,
      );
      expect(days('habit-sketching'), 8);
      expect(days('habit-french'), 3);
      expect(days('missing'), 0);
    });
  });

  group('quests and loot table', () {
    test('season month index follows the calendar months', () {
      final season = buildDemoState(now).currentSeason; // Oct 7 – Dec 31
      int month(DateTime d) => RpgEngine.calculateSeasonMonthIndex(season, d);
      expect(month(DateTime(2026, 9, 20)), 1); // before the season
      expect(month(DateTime(2026, 10, 7)), 1);
      expect(month(DateTime(2026, 10, 31)), 1);
      expect(month(DateTime(2026, 11, 1)), 2);
      expect(month(DateTime(2026, 12, 1)), 3);
      expect(month(DateTime(2027, 6, 1)), 3); // after the season
    });

    test('a new main quest demotes the month\'s old one', () async {
      final repo = InMemoryRepository(buildDemoState(now));
      final container = makeContainer(repo);
      final store = container.read(rpgStoreProvider.notifier);
      await container.read(rpgStoreProvider.future);

      final id = await store.addQuest(
        title: 'Run a 10K',
        branch: BranchType.body,
        isMainQuest: true,
        difficulty: 5,
        monthIndex: 1,
        rewardText: 'Massage',
      );
      final quests = repo.saved!.quests;
      final mains = quests.where((q) => q.isMainQuest && q.monthIndex == 1);
      expect(mains.map((q) => q.id), [id]);
      expect(
        quests.firstWhere((q) => q.id == 'quest-book').isMainQuest,
        isFalse,
      );
      // Other months keep their main quests.
      expect(
        quests.where((q) => q.isMainQuest && q.monthIndex == 3),
        hasLength(2),
      );
    });

    test('side quest toggling adds and removes a feat', () async {
      final container = makeContainer(InMemoryRepository(buildDemoState(now)));
      final store = container.read(rpgStoreProvider.notifier);
      await container.read(rpgStoreProvider.future);
      int craftLevel() => container
          .read(characterSheetProvider)
          .value!
          .branches[BranchType.craft]!
          .level;
      expect(craftLevel(), 2);

      await store.setQuestCompleted('quest-french-words', completed: true);
      expect(craftLevel(), 3);
      await store.setQuestCompleted('quest-french-words', completed: false);
      expect(craftLevel(), 2);
    });

    test('addLootItem adds an unclaimed reward', () async {
      final repo = InMemoryRepository(buildDemoState(now));
      final container = makeContainer(repo);
      final store = container.read(rpgStoreProvider.notifier);
      await container.read(rpgStoreProvider.future);

      final id = await store.addLootItem(LootTier.epic, 'Standing desk');
      final item = repo.saved!.loot.firstWhere((l) => l.id == id);
      expect(item.tier, LootTier.epic);
      expect(item.isClaimed, isFalse);
    });

    test('claim timestamps round-trip through JSON', () {
      final item = LootItem(
        id: 'x',
        tier: LootTier.rare,
        title: 'Book',
        claimedAtDate: '2026-10-24',
        claimedAt: DateTime(2026, 10, 24, 15, 42),
      );
      expect(LootItem.fromJson(item.toJson()), item);
    });
  });

  group('season tally and settings', () {
    test('completeSeason refuses while the quarter is running', () async {
      final repo = InMemoryRepository(buildDemoState(now));
      final container = makeContainer(repo);
      final store = container.read(rpgStoreProvider.notifier);
      await container.read(rpgStoreProvider.future);

      await expectLater(store.completeSeason(), throwsStateError);
      expect(repo.saved!.currentSeason.name, 'Season 1');
    });

    test('completeSeason persists the rollover', () async {
      final repo = InMemoryRepository(buildDemoState(now));
      final container = makeContainer(repo, at: afterSeason);
      final store = container.read(rpgStoreProvider.notifier);
      await container.read(rpgStoreProvider.future);

      final result = await store.completeSeason();
      expect(result.summary.endLevel, 9);
      expect(repo.saved!.currentSeason.name, 'Season 2');
      expect(repo.saved!.configFor(BranchType.mind).baseLevel, 3);
      final sheet = container.read(characterSheetProvider).value!;
      expect(sheet.totalLevel, 9);
      expect(sheet.seasonDay, 2); // Jan 2 of the Jan–Mar season
    });

    test('new quests belong to the current season', () async {
      final repo = InMemoryRepository(buildDemoState(now));
      final container = makeContainer(repo, at: afterSeason);
      final store = container.read(rpgStoreProvider.notifier);
      await container.read(rpgStoreProvider.future);
      await store.completeSeason();

      await store.addQuest(
        title: 'Fresh start',
        branch: BranchType.bond,
        isMainQuest: true,
      );
      final current = repo.saved!.currentQuests;
      expect(current.single.title, 'Fresh start');
      expect(current.single.seasonId, repo.saved!.character.currentSeasonId);
      // The old season's main quest was not demoted.
      expect(
        repo.saved!.quests.firstWhere((q) => q.id == 'quest-book').isMainQuest,
        isTrue,
      );
    });

    test('updateCharacter edits name and class', () async {
      final repo = InMemoryRepository(buildDemoState(now));
      final container = makeContainer(repo);
      await container.read(rpgStoreProvider.future);
      await container
          .read(rpgStoreProvider.notifier)
          .updateCharacter(name: 'Ari', classTitle: 'Weekend Warrior');
      expect(repo.saved!.character.name, 'Ari');
      expect(repo.saved!.character.classTitle, 'Weekend Warrior');
      expect(repo.saved!.character.currentSeasonId, 'season-1');
    });

    test('export then import restores the same state', () async {
      final repo = InMemoryRepository(buildDemoState(now));
      final container = makeContainer(repo);
      final store = container.read(rpgStoreProvider.notifier);
      await container.read(rpgStoreProvider.future);

      final backup = await store.exportBackup();
      expect(backup, contains('"schemaVersion": 1'));
      await store.wipeDatabaseAndRestart();
      expect(repo.saved, isNull);

      // Restoring works from onboarding (no character) too.
      await store.importBackup(backup);
      expect(repo.saved!.character.name, 'Rowan');
      expect(container.read(characterSheetProvider).value!.totalLevel, 9);
    });

    test('invalid imports throw and change nothing', () async {
      final repo = InMemoryRepository(buildDemoState(now));
      final container = makeContainer(repo);
      final store = container.read(rpgStoreProvider.notifier);
      await container.read(rpgStoreProvider.future);
      final saves = repo.saveCount;

      for (final bad in [
        'not json',
        '[]',
        '{"character": {"name": "X"}}',
        '{"character": {"name": "X", "classTitle": "Y", '
            '"currentSeasonId": "missing"}, "seasons": []}',
      ]) {
        await expectLater(store.importBackup(bad), throwsFormatException);
      }
      expect(repo.saveCount, saves);
      expect(repo.saved!.character.name, 'Rowan');
    });
  });

  group('habit editing', () {
    test('deleting a never-checked habit removes it', () async {
      final repo = InMemoryRepository(buildDemoState(now));
      final container = makeContainer(repo);
      final store = container.read(rpgStoreProvider.notifier);
      await container.read(rpgStoreProvider.future);

      final id = await store.addOrUpdateHabit(
        branch: BranchType.bond,
        title: 'Write a letter',
      );
      expect(await store.deleteHabit(id), HabitRemoval.deleted);
      expect(repo.saved!.habits.where((h) => h.id == id), isEmpty);
      expect(await store.deleteHabit('missing'), isNull);
    });

    test(
      'deleting a habit with history archives it and keeps points',
      () async {
        final repo = InMemoryRepository(buildDemoState(now));
        final container = makeContainer(repo);
        final store = container.read(rpgStoreProvider.notifier);
        await container.read(rpgStoreProvider.future);
        final before = container.read(characterSheetProvider).value!;

        expect(await store.deleteHabit('habit-water'), HabitRemoval.archived);
        final state = repo.saved!;
        expect(
          state.habits.firstWhere((h) => h.id == 'habit-water').isArchived,
          isTrue,
        );
        expect(
          state.activeHabits.map((h) => h.id),
          isNot(contains('habit-water')),
        );
        // Gone from today's list but still shown on a day it was checked off.
        expect(
          state.habitsShownOn(now).map((h) => h.id),
          isNot(contains('habit-water')),
        );
        expect(
          state.habitsShownOn(DateTime(2026, 10, 7)).map((h) => h.id),
          contains('habit-water'),
        );
        final after = container.read(characterSheetProvider).value!;
        expect(
          after.branches[BranchType.body]!.activeDays,
          before.branches[BranchType.body]!.activeDays,
        );
        expect(after.totalLevel, before.totalLevel);
        // Archived habits can't be pivoted or re-deleted.
        expect(
          await store.pivotHabit(
            oldHabitId: 'habit-water',
            newTitle: 'X',
            month: now,
          ),
          isNull,
        );
        expect(await store.deleteHabit('habit-water'), isNull);
      },
    );

    test('archived keystones keep their earned Common Keys', () async {
      final repo = InMemoryRepository(buildDemoState(now));
      final container = makeContainer(repo);
      final store = container.read(rpgStoreProvider.notifier);
      await container.read(rpgStoreProvider.future);
      int commonEarned() => container
          .read(characterSheetProvider)
          .value!
          .lootKeys[LootTier.common]!
          .earned;
      expect(commonEarned(), 2);

      await store.deleteHabit('habit-exercise');
      expect(repo.saved!.keystoneFor(BranchType.body), isNull);
      expect(commonEarned(), 2);

      // The archived habit lost its star but kept its keystone history.
      final exercise = repo.saved!.habits.firstWhere(
        (h) => h.id == 'habit-exercise',
      );
      expect(exercise.isKeystone, isFalse);
      expect(exercise.keystonePeriods, [
        const KeystonePeriod(to: '2026-10-24'),
      ]);

      await store.setKeystone('habit-sleep', isKeystone: true);
      expect(repo.saved!.keystoneFor(BranchType.body)!.id, 'habit-sleep');
      expect(commonEarned(), 2);
    });

    test('setKeystone stars and unstars within a branch', () async {
      final repo = InMemoryRepository(buildDemoState(now));
      final container = makeContainer(repo);
      final store = container.read(rpgStoreProvider.notifier);
      await container.read(rpgStoreProvider.future);

      await store.setKeystone('habit-meditation', isKeystone: true);
      expect(repo.saved!.keystoneFor(BranchType.mind)!.id, 'habit-meditation');
      expect(
        repo.saved!.habits
            .firstWhere((h) => h.id == 'habit-reading')
            .isKeystone,
        isFalse,
      );
      await store.setKeystone('habit-meditation', isKeystone: false);
      expect(repo.saved!.keystoneFor(BranchType.mind), isNull);
    });

    test('archived flag round-trips through JSON', () {
      const habit = Habit(
        id: 'h',
        branch: BranchType.mind,
        title: 'H',
        isArchived: true,
      );
      expect(Habit.fromJson(habit.toJson()), habit);
      expect(habit.isActiveOn(now), isFalse);
      expect(
        Habit.fromJson({'id': 'x', 'branch': 'body', 'title': 'X'}).isArchived,
        isFalse,
      );
    });
  });
}
