import 'dart:math' as math;

import '../models/rpg_models.dart';
import '../models/rpg_state.dart';
import 'rpg_engine.dart';

/// Lifetime and current-season numbers for the Character page. Everything
/// is derived from stored logs, quests, loot and seasons.
class CharacterStats {
  const CharacterStats({
    required this.daysLogged,
    required this.totalCheckIns,
    required this.bestRun,
    required this.seasonsCompleted,
    required this.questsCompleted,
    required this.lootClaimed,
    required this.seasonPoints,
    required this.seasonPointsPossible,
    required this.lifetimeActiveDays,
    required this.checkInsByWeekday,
    required this.recentWeeks,
  });

  /// Weeks shown in [recentWeeks].
  static const int recentWeekCount = 12;

  /// Builds the stats for [state] as of [today].
  factory CharacterStats.fromState(RpgState state, DateTime today) {
    final todayString = toDateString(today);
    final todayDate = parseDateString(todayString);

    // Check-ins per date, counting each habit once per date.
    final perDate = <String, Set<String>>{};
    for (final log in state.logs) {
      if (log.dateString.compareTo(todayString) > 0) continue;
      perDate
          .putIfAbsent(log.dateString, () => {})
          .addAll(log.completedHabitIds);
    }
    perDate.removeWhere((_, ids) => ids.isEmpty);
    final dates = perDate.keys.map(parseDateString).toList()..sort();
    final bestRun = RpgEngine.calculateLongestRun(perDate.keys);

    final byWeekday = List.filled(7, 0);
    for (final MapEntry(:key, :value) in perDate.entries) {
      byWeekday[parseDateString(key).weekday - 1] += value.length;
    }

    // Branch points this season: active days over every pillar, out of one
    // per pillar per day since the character's first check-in this season.
    final season = state.currentSeason;
    final branches = state.activeBranches;
    final seasonDays = RpgEngine.calculateAllBranchActiveDays(
      state.habits,
      state.logs,
      season: season,
    );
    final seasonStart = parseDateString(toDateString(season.startDate));
    final firstInSeason = dates
        .where((d) => !d.isBefore(seasonStart))
        .firstOrNull;
    final elapsed = firstInSeason == null
        ? 0
        : todayDate.difference(firstInSeason).inDays + 1;

    final firstWeek = todayDate.subtract(
      Duration(days: todayDate.weekday - 1 + (recentWeekCount - 1) * 7),
    );

    return CharacterStats(
      daysLogged: perDate.length,
      totalCheckIns: perDate.values.fold(0, (sum, ids) => sum + ids.length),
      bestRun: bestRun,
      seasonsCompleted: state.archivedSeasons.length,
      questsCompleted: state.quests.where((q) => q.isCompleted).length,
      lootClaimed: state.loot.where((l) => l.isClaimed).length,
      seasonPoints: branches.fold(0, (sum, b) => sum + seasonDays[b]!),
      seasonPointsPossible: elapsed * branches.length,
      lifetimeActiveDays: {
        for (final branch in branches)
          branch: RpgEngine.calculateBranchActiveDays(branch, state.habits, [
            for (final MapEntry(:key, :value) in perDate.entries)
              DailyLog(dateString: key, completedHabitIds: value.toList()),
          ]),
      },
      checkInsByWeekday: byWeekday,
      recentWeeks: [
        for (var day = 0; day < recentWeekCount * 7; day++)
          () {
            final date = firstWeek.add(Duration(days: day));
            if (date.isAfter(todayDate)) return null;
            return perDate[toDateString(date)]?.length ?? 0;
          }(),
      ],
    );
  }

  /// Distinct dates with at least one check-in.
  final int daysLogged;

  /// Habit check-ins, each habit counted once per date.
  final int totalCheckIns;

  /// Longest run of consecutive days with a check-in. A best, never a
  /// streak to lose.
  final int bestRun;
  final int seasonsCompleted;

  /// Completed quests across all seasons.
  final int questsCompleted;

  /// Rewards claimed with loot keys, across all seasons.
  final int lootClaimed;

  /// Branch Active Days earned this season across the active pillars.
  final int seasonPoints;

  /// One point per active pillar per day, from the first check-in this
  /// season through today.
  final int seasonPointsPossible;

  /// Branch Active Days across all seasons, per active pillar.
  final Map<BranchType, int> lifetimeActiveDays;

  /// Check-ins per weekday, Monday first.
  final List<int> checkInsByWeekday;

  /// Check-ins per day for the last [recentWeekCount] weeks, Monday first
  /// and oldest week first; null for days after today.
  final List<int?> recentWeeks;

  /// Share of possible branch points earned this season, or null before the
  /// first check-in.
  double? get seasonPointRate =>
      seasonPointsPossible == 0 ? null : seasonPoints / seasonPointsPossible;

  /// The pillar with the most lifetime active days (the first on a tie), or
  /// null with no check-ins.
  BranchType? get favoritePillar {
    BranchType? best;
    for (final MapEntry(:key, :value) in lifetimeActiveDays.entries) {
      if (value > 0 && (best == null || value > lifetimeActiveDays[best]!)) {
        best = key;
      }
    }
    return best;
  }

  /// Weekday (1 = Monday) with the most check-ins, or null with none.
  int? get bestWeekday {
    final top = checkInsByWeekday.reduce(math.max);
    return top == 0 ? null : checkInsByWeekday.indexOf(top) + 1;
  }
}
