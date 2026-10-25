import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/rpg_repository.dart';
import '../data/rpg_sqlite_repository.dart';
import '../domain/character_sheet.dart';
import '../domain/new_character.dart';
import '../domain/season_rollover.dart';
import '../models/rpg_models.dart';
import '../models/rpg_state.dart';

/// Current time source. Override in tests for deterministic dates.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Random source for "Roll Random Loot". Override in tests with a seeded one.
final randomProvider = Provider<math.Random>((ref) => math.Random());

/// Today's date (midnight, local). Unlike reading [clockProvider] once, it
/// moves forward at midnight and when [TodayNotifier.refresh] is called (the
/// app calls it on resume), so a long-open or backgrounded app never logs
/// check-ins against yesterday.
final todayProvider = NotifierProvider<TodayNotifier, DateTime>(
  TodayNotifier.new,
);

class TodayNotifier extends Notifier<DateTime> {
  Timer? _midnight;

  static DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

  @override
  DateTime build() {
    ref.onDispose(() => _midnight?.cancel());
    final now = ref.watch(clockProvider)();
    _scheduleMidnight(now);
    return _dateOnly(now);
  }

  /// Re-reads the clock; updates listeners only if the date changed.
  void refresh() {
    final now = ref.read(clockProvider)();
    final today = _dateOnly(now);
    if (today != state) state = today;
    _scheduleMidnight(now);
  }

  void _scheduleMidnight(DateTime now) {
    _midnight?.cancel();
    final next = DateTime(now.year, now.month, now.day + 1);
    // A second past midnight, so the clock has certainly rolled over.
    _midnight = Timer(
      next.difference(now) + const Duration(seconds: 1),
      refresh,
    );
  }
}

/// The date Survival Mode (Low Energy) was switched on, or null. Read
/// [survivalModeProvider] to know whether it is on today.
final survivalModeDateProvider =
    NotifierProvider<SurvivalModeNotifier, DateTime?>(SurvivalModeNotifier.new);

class SurvivalModeNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  /// Switches Survival Mode on or off for today.
  void set({required bool on}) => state = on ? ref.read(todayProvider) : null;
}

/// Whether Today's Focus shows only the ★ keystones. Lasts for the day it
/// was switched on, so it is off again after midnight.
final survivalModeProvider = Provider<bool>(
  (ref) => ref.watch(survivalModeDateProvider) == ref.watch(todayProvider),
);

final rpgRepositoryProvider = Provider<RpgRepository>(
  (ref) => RpgSqliteRepository(),
);

/// The app state, or null while no character exists (onboarding needed).
final rpgStoreProvider = AsyncNotifierProvider<RpgStore, RpgState?>(
  RpgStore.new,
);

/// The loaded state, for widgets that only exist once a character does
/// (everything under `HomeShell`).
final rpgStateProvider = NotifierProvider<_CurrentState, RpgState>(
  _CurrentState.new,
);

class _CurrentState extends Notifier<RpgState> {
  @override
  RpgState build() {
    final state = ref.watch(rpgStoreProvider).value;
    if (state != null) return state;
    // After "start over", keep the last state for the frame in which
    // HomeShell is still mounted, before the root gate swaps to onboarding.
    final previous = stateOrNull;
    if (previous != null) return previous;
    throw StateError('No character yet; onboarding first.');
  }
}

/// Derived stats (levels, nodes, keys, season day) for the current state.
/// Stays loading while there is no character.
/// Whether a character exists in SQLite. False on first install and after
/// [RpgStore.wipeDatabaseAndRestart], until onboarding is completed.
final isOnboardedProvider = Provider<bool>(
  (ref) => ref.watch(rpgStoreProvider).value != null,
);

final characterSheetProvider = Provider<AsyncValue<CharacterSheet>>((ref) {
  final now = ref.watch(todayProvider);
  final store = ref.watch(rpgStoreProvider);
  final state = store.value;
  if (store.hasError) return AsyncError(store.error!, store.stackTrace!);
  if (state == null) return const AsyncLoading();
  return AsyncData(CharacterSheet.fromState(state, now));
});

/// What forging a skill node changed, for the celebration overlay.
class NodeForgeResult {
  const NodeForgeResult({
    required this.branch,
    required this.nodeIndex,
    required this.oldBranchLevel,
    required this.newBranchLevel,
    required this.oldTotalLevel,
    required this.newTotalLevel,
    required this.keysEarned,
  });

  final BranchType branch;

  /// 0-based index of the node just forged.
  final int nodeIndex;
  final int oldBranchLevel;
  final int newBranchLevel;
  final int oldTotalLevel;
  final int newTotalLevel;

  /// New keys per tier (always a Rare one; Epic/Legendary on milestones).
  final Map<LootTier, int> keysEarned;
}

enum HabitRemoval {
  /// Removed completely (it had no check-ins).
  deleted,

  /// Hidden but kept, because its check-ins still count toward the branch.
  archived,
}

/// Owns the app state: loads it from the repository on start (null on first
/// install, which sends the user to onboarding). Each action updates the
/// in-memory state and makes one granular repository write.
class RpgStore extends AsyncNotifier<RpgState?> {
  static const _uuid = Uuid();

  RpgRepository get _repository => ref.read(rpgRepositoryProvider);

  DateTime get _now => ref.read(clockProvider)();

  @override
  Future<RpgState?> build() => _repository.loadFullState();

  /// Finishes Session Zero: creates the character, Season 1 (the current
  /// calendar quarter), keystones, buffs/debuffs, main quest, loot table and
  /// signed oath in one SQLite transaction, then reloads from storage.
  Future<void> completeOnboarding({
    required String name,
    required String classTitle,
    required List<KeystoneChoice> keystones,
    MainQuestChoice? mainQuest,
    List<LootChoice> loot = const [],
    List<ModifierChoice> modifiers = const [],
    List<List<double>> oathStrokes = const [],
  }) async {
    final initial = buildNewCharacterState(
      name: name,
      classTitle: classTitle,
      keystones: keystones,
      mainQuest: mainQuest,
      loot: loot,
      modifiers: modifiers,
      oathStrokes: oathStrokes,
      today: _now,
      seasonId: _uuid.v4(),
      newId: _uuid.v4,
    );
    // Stored first, then re-read, so the UI shows exactly what's saved.
    await _repository.initializeFromOnboarding(initial);
    state = AsyncData(await _repository.loadFullState());
  }

  /// Marks [habitId] done on [date], or undoes it if already done.
  Future<void> toggleHabitForDate(String habitId, DateTime date) {
    final dateString = toDateString(date);
    return _update((state) {
      final logs = [...state.logs];
      final index = logs.indexWhere((l) => l.dateString == dateString);
      if (index == -1) {
        logs.add(
          DailyLog(dateString: dateString, completedHabitIds: [habitId]),
        );
      } else {
        final ids = [...logs[index].completedHabitIds];
        if (!ids.remove(habitId)) ids.add(habitId);
        if (ids.isEmpty) {
          logs.removeAt(index);
        } else {
          logs[index] = logs[index].copyWith(completedHabitIds: ids);
        }
      }
      return state.copyWith(logs: logs);
    }, (repo) => repo.toggleHabitForDate(habitId, dateString));
  }

  /// Creates a habit (when [id] is null) or updates the one with [id].
  ///
  /// Starring a habit unstars the branch's previous active keystone; both
  /// changes are recorded from today on, so Common Keys already earned stay.
  /// A habit with check-ins can't change branch (that would move its past
  /// points); doing so throws an [ArgumentError]. Returns the habit's id.
  Future<String> addOrUpdateHabit({
    String? id,
    required BranchType branch,
    required String title,
    String targetCriteria = '',
    bool isKeystone = false,
    ActiveHalfMonth activeHalfMonth = ActiveHalfMonth.both,
  }) async {
    final today = toDateString(_now);
    final habitId = id ?? _uuid.v4();
    final changed = <Habit>[];
    await _update((state) {
      final existing = state.habits.where((h) => h.id == habitId).firstOrNull;
      if (existing != null &&
          existing.branch != branch &&
          state.hasCheckIns(existing.id)) {
        throw ArgumentError.value(
          branch,
          'branch',
          '"${existing.title}" has check-ins counted toward '
              '${existing.branch.displayName}',
        );
      }
      final habit =
          (existing ?? Habit(id: habitId, branch: branch, title: title))
              .copyWith(
                branch: branch,
                title: title,
                targetCriteria: targetCriteria,
                activeHalfMonth: activeHalfMonth,
              )
              .withKeystone(isKeystone, today);
      changed.add(habit);
      final habits = [
        for (final h in state.habits)
          if (h.id == habit.id)
            habit
          else if (habit.isKeystone &&
              h.branch == branch &&
              h.isKeystone &&
              !h.isArchived)
            () {
              final unstarred = h.withKeystone(false, today);
              changed.add(unstarred);
              return unstarred;
            }()
          else
            h,
        if (existing == null) habit,
      ];
      return state.copyWith(habits: habits);
    }, (repo) => repo.upsertHabits(changed));
    return habitId;
  }

  /// Stars or unstars [habitId] as its branch's keystone.
  Future<void> setKeystone(String habitId, {required bool isKeystone}) async {
    final habit = state.value?.habits.where((h) => h.id == habitId).firstOrNull;
    if (habit == null || habit.isArchived) return;
    await addOrUpdateHabit(
      id: habit.id,
      branch: habit.branch,
      title: habit.title,
      targetCriteria: habit.targetCriteria,
      isKeystone: isKeystone,
      activeHalfMonth: habit.activeHalfMonth,
    );
  }

  /// Removes [habitId]. A habit with logged check-ins is archived instead,
  /// so the branch points it earned are kept; one never checked off is
  /// deleted outright. Returns the outcome, or null if the habit is unknown.
  Future<HabitRemoval?> deleteHabit(String habitId) async {
    HabitRemoval? outcome;
    Habit? archived;
    await _update(
      (state) {
        final habit = state.habits.where((h) => h.id == habitId).firstOrNull;
        if (habit == null || habit.isArchived) return state;
        final hasHistory = state.hasCheckIns(habitId);
        outcome = hasHistory ? HabitRemoval.archived : HabitRemoval.deleted;
        // Archived keystones lose the star from today; the days they were
        // the keystone (and the Common Keys earned) are kept.
        if (hasHistory) {
          archived = habit
              .withKeystone(false, toDateString(_now))
              .copyWith(isArchived: true);
        }
        return state.copyWith(
          habits: [
            for (final h in state.habits)
              if (h.id != habitId) h else if (hasHistory) archived!,
          ],
        );
      },
      (repo) => archived != null
          ? repo.upsertHabit(archived!)
          : repo.deleteHabit(habitId),
    );
    return outcome;
  }

  Future<void> completeQuest(String questId) =>
      setQuestCompleted(questId, completed: true);

  /// Checks or unchecks a quest. Each completed quest is +1 Feat (and +1
  /// level) for its branch.
  Future<void> setQuestCompleted(String questId, {required bool completed}) {
    return _update(
      (state) => state.copyWith(
        quests: [
          for (final q in state.quests)
            q.id == questId ? q.copyWith(isCompleted: completed) : q,
        ],
      ),
      (repo) => repo.completeQuest(questId, completed: completed),
    );
  }

  /// Adds a quest and returns its id. A new main quest replaces the month's
  /// existing one, which becomes a side quest (one main quest per month).
  Future<String> addQuest({
    required String title,
    required BranchType branch,
    bool isMainQuest = false,
    int difficulty = 1,
    int monthIndex = 1,
    String rewardText = '',
  }) async {
    late Quest quest;
    await _update((state) {
      quest = Quest(
        id: _uuid.v4(),
        title: title,
        isMainQuest: isMainQuest,
        branch: branch,
        difficulty: difficulty,
        monthIndex: monthIndex,
        rewardText: rewardText,
        seasonId: state.character.currentSeasonId,
      );
      final current = state.currentQuests.toSet();
      return state.copyWith(
        quests: [
          for (final q in state.quests)
            isMainQuest &&
                    current.contains(q) &&
                    q.isMainQuest &&
                    q.monthIndex == monthIndex
                ? q.copyWith(isMainQuest: false)
                : q,
          quest,
        ],
      );
    }, (repo) => repo.upsertQuest(quest));
    return quest.id;
  }

  /// Adds a reusable real-life reward to the loot table.
  Future<String> addLootItem(LootTier tier, String title) async {
    final item = LootItem(id: _uuid.v4(), tier: tier, title: title);
    await _update(
      (state) => state.copyWith(loot: [...state.loot, item]),
      (repo) => repo.upsertLootItem(item),
    );
    return item.id;
  }

  /// Spends one key of the reward's tier and logs the claim in the history.
  /// Rewards stay in the table so they can be claimed again. Returns false if
  /// the reward is unknown or no key of its tier is available.
  Future<bool> claimLoot(String lootId) async {
    LootItem? claim;
    await _update((state) {
      final item = state.loot.where((l) => l.id == lootId).firstOrNull;
      if (item == null || item.isClaimed) return state;
      final sheet = CharacterSheet.fromState(state, _now);
      if (sheet.lootKeys[item.tier]!.available <= 0) return state;
      final now = _now;
      claim = item.copyWith(
        id: _uuid.v4(),
        claimedAtDate: toDateString(now),
        claimedAt: now,
      );
      return state.copyWith(loot: [...state.loot, claim!]);
    }, (repo) => repo.claimLootItem(claim!));
    return claim != null;
  }

  /// Spends a [tier] key on a random reward from that tier's loot table.
  /// Returns the reward rolled, or null with no key or no reward to roll.
  Future<LootItem?> rollLoot(LootTier tier) async {
    await future;
    final rewards = [
      for (final l in state.requireValue?.loot ?? const <LootItem>[])
        if (l.tier == tier && !l.isClaimed) l,
    ];
    if (rewards.isEmpty) return null;
    final reward = rewards[ref.read(randomProvider).nextInt(rewards.length)];
    return await claimLoot(reward.id) ? reward : null;
  }

  /// Forges the next earned-but-unforged node of [branch]: +1 level and a
  /// Rare Key (plus an Epic Key for a branch's 5th node and the Legendary
  /// Key for the 25th). Returns null when no node is ready to forge.
  Future<NodeForgeResult?> forgeNode(BranchType branch) async {
    NodeForgeResult? result;
    late BranchConfig config;
    await _update((state) {
      final before = CharacterSheet.fromState(state, _now);
      final stats = before.branches[branch]!;
      if (stats.readyToForge <= 0) return state;
      config = state
          .configFor(branch)
          .copyWith(forgedNodeCount: stats.forgedNodes + 1);
      final next = state.copyWith(
        branchConfigs: [
          for (final c in state.branchConfigs)
            if (c.branch != branch) c,
          config,
        ]..sort((a, b) => a.branch.index.compareTo(b.branch.index)),
      );
      final after = CharacterSheet.fromState(next, _now);
      int earned(CharacterSheet sheet, LootTier tier) =>
          sheet.lootKeys[tier]!.earned;
      result = NodeForgeResult(
        branch: branch,
        nodeIndex: stats.forgedNodes,
        oldBranchLevel: stats.level,
        newBranchLevel: after.branches[branch]!.level,
        oldTotalLevel: before.totalLevel,
        newTotalLevel: after.totalLevel,
        keysEarned: {
          for (final tier in LootTier.values)
            if (earned(after, tier) > earned(before, tier))
              tier: earned(after, tier) - earned(before, tier),
        },
      );
      return next;
    }, (repo) => repo.updateForgedNodes(config));
    return result;
  }

  /// Saves the mid-month reflection notes for the month of [month].
  Future<void> updateReflectionNotes(DateTime month, String notes) {
    late MonthReflection reflection;
    return _update((state) {
      final current = state.reflectionFor(month);
      if (current.notes == notes) return state;
      reflection = current.copyWith(notes: notes);
      return _withReflection(state, reflection);
    }, (repo) => repo.saveReflection(reflection));
  }

  /// Swaps [oldHabitId] for a new habit in the same branch from Half 2 on.
  ///
  /// The old habit is kept (limited to Half 1) so the branch points already
  /// earned from its logs stay intact. Only non-keystone habits active in
  /// both halves can be pivoted. Returns the new habit's id, or null if the
  /// habit can't be pivoted.
  Future<String?> pivotHabit({
    required String oldHabitId,
    required String newTitle,
    String newTargetCriteria = '',
    required DateTime month,
  }) async {
    Habit? limited;
    late Habit replacement;
    late MonthReflection reflection;
    await _update(
      (state) {
        final old = state.habits.where((h) => h.id == oldHabitId).firstOrNull;
        if (old == null ||
            old.isKeystone ||
            old.isArchived ||
            old.activeHalfMonth != ActiveHalfMonth.both) {
          return state;
        }
        limited = old.copyWith(activeHalfMonth: ActiveHalfMonth.firstHalf);
        replacement = Habit(
          id: _uuid.v4(),
          branch: old.branch,
          title: newTitle,
          targetCriteria: newTargetCriteria,
          activeHalfMonth: ActiveHalfMonth.secondHalf,
        );
        final current = state.reflectionFor(month);
        reflection = current.copyWith(
          pivots: [...current.pivots, '${old.title} → $newTitle'],
        );
        return _withReflection(
          state.copyWith(
            habits: [
              for (final h in state.habits)
                if (h.id == old.id) limited! else h,
              replacement,
            ],
          ),
          reflection,
        );
      },
      (repo) => repo.pivotHabit(
        old: limited!,
        replacement: replacement,
        reflection: reflection,
      ),
    );
    return limited == null ? null : replacement.id;
  }

  RpgState _withReflection(RpgState state, MonthReflection reflection) {
    return state.copyWith(
      reflections: [
        for (final r in state.reflections)
          if (r.monthKey != reflection.monthKey) r,
        reflection,
      ],
    );
  }

  /// Replaces the buff and/or debuff chips for [branch].
  Future<void> updateBranchModifiers(
    BranchType branch, {
    List<String>? buffs,
    List<String>? debuffs,
  }) {
    late BranchConfig config;
    return _update((state) {
      config = state.configFor(branch).copyWith(buffs: buffs, debuffs: debuffs);
      return state.copyWith(
        branchConfigs: [
          for (final c in state.branchConfigs)
            if (c.branch != branch) c,
          config,
        ]..sort((a, b) => a.branch.index.compareTo(b.branch.index)),
      );
    }, (repo) => repo.updateBranchBuffDebuff(config));
  }

  /// Seals the current season's oath with the drawn [strokes].
  Future<void> signSeasonOath(List<List<double>> strokes) =>
      _setOath(SeasonOath(strokes: strokes, signedAtDate: toDateString(_now)));

  Future<void> clearSeasonOath() => _setOath(null);

  Future<void> _setOath(SeasonOath? oath) {
    late String seasonId;
    return _update((state) {
      seasonId = state.character.currentSeasonId;
      return state.copyWith(
        seasons: [
          for (final s in state.seasons)
            s.id == seasonId
                ? (oath == null
                      ? s.copyWith(clearOath: true)
                      : s.copyWith(oath: oath))
                : s,
        ],
      );
    }, (repo) => repo.saveSignature(seasonId, oath));
  }

  /// Ends the current season, bakes its points into each branch's base
  /// level and starts the next quarter's season.
  /// Throws a [StateError] while the season's quarter is still running.
  Future<SeasonRolloverResult> completeSeason() async {
    late SeasonRolloverResult result;
    await _update(
      (state) {
        result = SeasonRollover.apply(state, _now, newSeasonId: _uuid.v4());
        return result.state;
      },
      (repo) => repo.prestigeSeason(
        completed: result.completedSeason,
        next: result.state,
      ),
    );
    return result;
  }

  Future<void> updateCharacter({String? name, String? classTitle}) {
    late Character character;
    return _update((state) {
      character = state.character.copyWith(name: name, classTitle: classTitle);
      return state.copyWith(character: character);
    }, (repo) => repo.updateCharacter(character));
  }

  Future<void> updateSignature(String signatureText) {
    late Character character;
    return _update((state) {
      character = state.character.copyWith(signatureText: signatureText);
      return state.copyWith(character: character);
    }, (repo) => repo.updateCharacter(character));
  }

  /// The full app state as pretty-printed backup JSON.
  Future<String> exportBackup() async {
    final current = await future;
    if (current == null) throw StateError('Nothing to export yet.');
    return const JsonEncoder.withIndent('  ').convert(current);
  }

  /// Replaces all data with a backup from [exportBackup]. Throws a
  /// [FormatException] (and changes nothing) if [json] isn't a valid backup.
  Future<void> importBackup(String json) async {
    final RpgState restored;
    try {
      restored = RpgState.fromJson(jsonDecode(json) as Map<String, dynamic>);
      restored.currentSeason; // Must reference an existing season.
      _checkUniqueIds(restored);
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Not a valid levelUp backup: $e');
    }
    await _repository.replaceAllData(restored);
    state = AsyncData(restored);
  }

  /// Rejects backups whose ids collide, which the database would refuse
  /// part-way through restoring.
  static void _checkUniqueIds(RpgState state) {
    void unique(String kind, Iterable<String> ids) {
      final seen = <String>{};
      for (final id in ids) {
        if (!seen.add(id)) {
          throw FormatException(
            'Not a valid levelUp backup: duplicate $kind "$id"',
          );
        }
      }
    }

    unique('habit', state.habits.map((h) => h.id));
    unique('quest', state.quests.map((q) => q.id));
    unique('loot item', state.loot.map((l) => l.id));
    unique('season', state.seasons.map((s) => s.id));
    unique('branch', state.branchConfigs.map((c) => c.branch.name));
  }

  /// Deletes everything in SQLite and returns to onboarding (Session Zero).
  Future<void> wipeDatabaseAndRestart() async {
    await _repository.wipeAllData();
    state = const AsyncData(null);
  }

  /// Applies [change] in memory, then [persist]s it with one repository
  /// write. If the write fails, the state is reloaded from the database so
  /// memory never drifts from what's stored.
  Future<void> _update(
    RpgState Function(RpgState state) change,
    Future<void> Function(RpgRepository repo) persist,
  ) async {
    await future;
    // Read the latest value after awaiting so concurrent actions don't
    // overwrite each other with stale state.
    final current = state.requireValue;
    if (current == null) throw StateError('No character yet.');
    final next = change(current);
    if (identical(next, current)) return;
    state = AsyncData(next);
    try {
      await persist(_repository);
    } catch (_) {
      state = AsyncData(await _repository.loadFullState());
      rethrow;
    }
  }
}
