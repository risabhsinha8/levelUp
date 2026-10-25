import '../models/rpg_models.dart';
import '../models/rpg_state.dart';
import 'rpg_engine.dart';

/// Derived stats for one branch in the current season.
class BranchStats {
  const BranchStats({
    required this.branch,
    required this.activeDays,
    required this.unlockedNodes,
    required this.forgedNodes,
    required this.completedFeats,
    required this.level,
  });

  final BranchType branch;
  final int activeDays;

  /// Nodes earned by [activeDays] (0–5).
  final int unlockedNodes;

  /// Earned nodes the user has forged (0 to [unlockedNodes]). These, not
  /// [unlockedNodes], count toward [level].
  final int forgedNodes;
  final int completedFeats;
  final int level;

  /// Earned nodes waiting to be forged on the Skill Tree.
  int get readyToForge => unlockedNodes - forgedNodes;

  /// Active days needed for the next node, or null when all 5 are unlocked.
  int? get nextNodeThreshold => unlockedNodes < RpgEngine.maxNodesPerBranch
      ? RpgEngine.nodeThresholds[unlockedNodes]
      : null;
}

/// Everything the UI shows that is computed rather than stored.
class CharacterSheet {
  const CharacterSheet({
    required this.branches,
    required this.totalLevel,
    required this.lootKeys,
    required this.seasonDay,
    required this.seasonLength,
    required this.isSeasonOver,
  });

  /// Builds the sheet for the current season of [state] as of [today].
  factory CharacterSheet.fromState(RpgState state, DateTime today) {
    final season = state.currentSeason;
    final activeDays = RpgEngine.calculateAllBranchActiveDays(
      state.habits,
      state.logs,
      season: season,
    );

    final branches = {
      for (final branch in BranchType.values)
        branch: () {
          final days = activeDays[branch]!;
          final config = state.configFor(branch);
          final nodes = RpgEngine.calculateUnlockedNodes(days);
          final forged = RpgEngine.calculateForgedNodes(
            nodes,
            config.forgedNodeCount,
          );
          final feats = RpgEngine.calculateCompletedFeats(
            branch,
            state.currentQuests,
          );
          return BranchStats(
            branch: branch,
            activeDays: days,
            unlockedNodes: nodes,
            forgedNodes: forged,
            completedFeats: feats,
            level: RpgEngine.calculateBranchLevel(
              config.baseLevel,
              forged,
              feats,
            ),
          );
        }(),
    };

    return CharacterSheet(
      branches: branches,
      totalLevel: RpgEngine.calculateTotalCharacterLevel({
        for (final entry in branches.entries) entry.key: entry.value.level,
      }),
      lootKeys: RpgEngine.calculateAvailableLootKeys(
        habits: state.habits,
        logs: state.logs,
        claimedLoot: state.loot,
        forgedNodeCounts: {
          for (final branch in BranchType.values)
            branch: state.configFor(branch).forgedNodeCount,
        },
        season: season,
      ),
      seasonDay: RpgEngine.calculateSeasonDay(season, today),
      seasonLength: RpgEngine.calculateSeasonLength(season),
      isSeasonOver: RpgEngine.isSeasonOver(season, today),
    );
  }

  final Map<BranchType, BranchStats> branches;
  final int totalLevel;
  final Map<LootTier, LootKeyBalance> lootKeys;
  final int seasonDay;
  final int seasonLength;

  /// Whether the current season's quarter has ended and it is waiting to be
  /// completed.
  final bool isSeasonOver;
}
