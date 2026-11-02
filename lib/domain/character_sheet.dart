import '../models/rpg_models.dart';
import '../models/rpg_state.dart';
import 'rpg_engine.dart';

/// Derived stats for one branch in the current season.
class BranchStats {
  const BranchStats({
    required this.branch,
    required this.name,
    required this.activeDays,
    required this.unlockedNodes,
    required this.forgedNodes,
    required this.completedFeats,
    required this.level,
  });

  final BranchType branch;

  /// The character's name for the pillar ([RpgState.nameOf]).
  final String name;
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
    required this.activeBranches,
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
    final activeBranches = state.activeBranches;
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
            name: config.name,
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
      activeBranches: activeBranches,
      branches: branches,
      totalLevel: RpgEngine.calculateTotalCharacterLevel({
        for (final branch in activeBranches) branch: branches[branch]!.level,
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
        branches: activeBranches,
      ),
      seasonDay: RpgEngine.calculateSeasonDay(season, today),
      seasonLength: RpgEngine.calculateSeasonLength(season),
      isSeasonOver: RpgEngine.isSeasonOver(season, today),
    );
  }

  /// The pillars in play, in branch order ([RpgState.activeBranches]).
  final List<BranchType> activeBranches;

  /// Stats for every branch, resting ones included (their level is their
  /// banked base level).
  final Map<BranchType, BranchStats> branches;

  /// Sum of the active pillars' levels.
  final int totalLevel;
  final Map<LootTier, LootKeyBalance> lootKeys;
  final int seasonDay;
  final int seasonLength;

  /// Whether the current season's quarter has ended and it is waiting to be
  /// completed.
  final bool isSeasonOver;
}
