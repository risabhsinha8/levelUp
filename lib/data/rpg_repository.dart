import '../models/rpg_models.dart';
import '../models/rpg_state.dart';

/// Storage boundary for the app state. The store keeps the state in memory
/// and calls one granular write per user action.
abstract interface class RpgRepository {
  /// Whether a character exists (false on first install → onboarding).
  Future<bool> hasCharacter();

  /// Everything stored, or null when there is no character yet.
  Future<RpgState?> loadFullState();

  /// Writes the character created in onboarding, all in one transaction:
  /// character, Season 1, branch configs, keystones, main quest and loot.
  /// Throws a [StateError] if a character already exists.
  Future<void> initializeFromOnboarding(RpgState initial);

  /// Toggles [habitId] on [dateString]. Returns true if it is now done.
  Future<bool> toggleHabitForDate(String habitId, String dateString);

  /// Inserts or updates [habit]. A keystone unstars the branch's other
  /// active keystone in the same transaction.
  Future<void> upsertHabit(Habit habit);

  /// Inserts or updates several habits in one transaction (e.g. a new
  /// keystone together with the unstarred old one).
  Future<void> upsertHabits(List<Habit> habits);

  /// Removes a habit with no history.
  Future<void> deleteHabit(String habitId);

  Future<void> updateBranchBuffDebuff(BranchConfig config);

  /// Saves [config]'s `forged_node_count` after a node is forged.
  Future<void> updateForgedNodes(BranchConfig config);

  /// Inserts or updates [quest]. A main quest demotes the month's other
  /// main quest of the same season in the same transaction.
  Future<void> upsertQuest(Quest quest);

  Future<void> completeQuest(String questId, {bool completed = true});

  /// Inserts or updates a reward in the loot table.
  Future<void> upsertLootItem(LootItem item);

  /// Logs a claim (a claimed [LootItem] record) in the history.
  Future<void> claimLootItem(LootItem claim);

  /// Stores (or clears, when [oath] is null) the oath for [seasonId].
  Future<void> saveSignature(String seasonId, SeasonOath? oath);

  Future<void> saveReflection(MonthReflection reflection);

  /// Limits [old] to Half 1 and adds [replacement], atomically.
  Future<void> pivotHabit({
    required Habit old,
    required Habit replacement,
    required MonthReflection reflection,
  });

  Future<void> updateCharacter(Character character);

  /// Writes a season rollover: archives [completed], adds [next]'s new
  /// current season, rebased branch levels and stamped quests.
  Future<void> prestigeSeason({
    required Season completed,
    required RpgState next,
  });

  /// Replaces everything (backup import), in one transaction.
  Future<void> replaceAllData(RpgState state);

  /// Deletes everything, returning the app to onboarding.
  Future<void> wipeAllData();
}
