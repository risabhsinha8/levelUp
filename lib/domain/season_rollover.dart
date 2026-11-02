import '../models/rpg_models.dart';
import '../models/rpg_state.dart';
import 'character_sheet.dart';
import 'rpg_engine.dart';

class SeasonRolloverResult {
  const SeasonRolloverResult({
    required this.state,
    required this.summary,
    required this.completedSeason,
    required this.newSeason,
  });

  final RpgState state;
  final SeasonSummary summary;
  final Season completedSeason;
  final Season newSeason;
}

/// "End Season & Prestige": closes the current season and starts the next.
abstract final class SeasonRollover {
  /// Completes the current season of [state] on [today], once its quarter
  /// has ended:
  ///
  /// - The season is archived with its original end date.
  /// - Each branch's season nodes + feats are baked into its `baseLevel`.
  ///   Earned nodes still waiting to be forged are forged automatically, so
  ///   no progress is lost; the forged count resets to 0.
  /// - The season's quests are stamped with its id, so their feats stop
  ///   counting toward the new season.
  /// - The next season starts the day after, through the end of that
  ///   calendar quarter, with all skill tree nodes at 0. Check-ins made
  ///   before completing therefore still count toward it. If that quarter
  ///   has ended too, it can be completed straight away.
  ///
  /// - [activeBranches], when given, are the pillars in play next season
  ///   (at least [BranchType.minEnabled]). A pillar put to rest keeps its
  ///   base level and habits for when it returns; the summary covers the
  ///   pillars that were active this season.
  ///
  /// Throws a [StateError] while the season is still running, and an
  /// [ArgumentError] for too few [activeBranches].
  static SeasonRolloverResult apply(
    RpgState state,
    DateTime today, {
    required String newSeasonId,
    Set<BranchType>? activeBranches,
  }) {
    final old = state.currentSeason;
    if (!RpgEngine.isSeasonOver(old, today)) {
      throw StateError('${old.name} runs until ${toDateString(old.endDate)}.');
    }
    if (activeBranches != null &&
        activeBranches.length < BranchType.minEnabled) {
      throw ArgumentError.value(
        activeBranches,
        'activeBranches',
        'needs at least ${BranchType.minEnabled} pillars',
      );
    }
    final sheet = CharacterSheet.fromState(state, today);

    final summary = SeasonSummary(
      branches: {
        for (final branch in sheet.activeBranches)
          branch: BranchSeasonResult(
            startLevel: state.configFor(branch).baseLevel,
            nodes: sheet.branches[branch]!.unlockedNodes,
            feats: sheet.branches[branch]!.completedFeats,
            activeDays: sheet.branches[branch]!.activeDays,
          ),
      },
    );

    final completed = state.currentSeason.copyWith(
      isArchived: true,
      summary: summary,
    );
    final newStart = parseDateString(
      toDateString(old.endDate),
    ).add(const Duration(days: 1));
    final newSeason = Season(
      id: newSeasonId,
      name: 'Season ${state.seasons.length + 1}',
      startDate: newStart,
      endDate: Season.quarterEndOf(newStart),
    );

    final next = state.copyWith(
      seasons: [
        for (final s in state.seasons)
          if (s.id == old.id) completed else s,
        newSeason,
      ],
      branchConfigs: [
        for (final branch in BranchType.values)
          state
              .configFor(branch)
              .copyWith(
                baseLevel: summary.branches[branch]?.endLevel,
                forgedNodeCount: 0,
                isEnabled: activeBranches?.contains(branch),
              ),
      ],
      quests: [
        for (final q in state.quests)
          q.seasonId == null ? q.copyWith(seasonId: old.id) : q,
      ],
      character: state.character.copyWith(currentSeasonId: newSeason.id),
    );

    return SeasonRolloverResult(
      state: next,
      summary: summary,
      completedSeason: completed,
      newSeason: newSeason,
    );
  }
}
