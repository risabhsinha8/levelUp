/// Pure, deterministic rule engine for the Skill Tree RPG.
///
/// Implements every domain rule in CLAUDE.md. No Flutter, Riverpod or I/O:
/// all inputs are passed in and nothing is mutated.
library;

import 'dart:math' as math;

import '../models/rpg_models.dart';

/// Earned vs. claimed keys for a single loot tier.
class LootKeyBalance {
  const LootKeyBalance({required this.earned, required this.claimed});

  final int earned;
  final int claimed;

  /// Keys that can still be spent. Never negative.
  int get available => math.max(0, earned - claimed);

  @override
  bool operator ==(Object other) =>
      other is LootKeyBalance &&
      other.earned == earned &&
      other.claimed == claimed;

  @override
  int get hashCode => Object.hash(earned, claimed);

  @override
  String toString() =>
      'LootKeyBalance(earned: $earned, claimed: $claimed, available: $available)';
}

/// A Half 1 habit with too few check-ins, found by
/// [RpgEngine.findStrugglingHabits].
class StrugglingHabit {
  const StrugglingHabit({
    required this.habit,
    required this.completedDays,
    required this.elapsedDays,
  });

  final Habit habit;
  final int completedDays;
  final int elapsedDays;

  /// Share of the elapsed Half 1 days the habit was completed, 0 to 1.
  double get completionRate => completedDays / elapsedDays;

  @override
  bool operator ==(Object other) =>
      other is StrugglingHabit &&
      other.habit == habit &&
      other.completedDays == completedDays &&
      other.elapsedDays == elapsedDays;

  @override
  int get hashCode => Object.hash(habit, completedDays, elapsedDays);

  @override
  String toString() =>
      'StrugglingHabit(${habit.id}: $completedDays/$elapsedDays)';
}

abstract final class RpgEngine {
  /// Cumulative Branch Active Days needed for each of the 5 skill nodes.
  static const List<int> nodeThresholds = [5, 15, 30, 50, 80];

  static int get maxNodesPerBranch => nodeThresholds.length;

  /// Consecutive keystone days needed for one Common Key.
  static const int keystoneDaysPerCommonKey = 7;

  /// Number of distinct dates on which at least one habit of [branch] was
  /// completed (the "1-Point-Per-Branch-Per-Day" rule).
  ///
  /// Completing several habits of the same branch on one date, or having
  /// duplicate logs for a date, still yields a single active day. Completions
  /// of unknown habit ids are ignored. When [season] is given, only dates
  /// inside it count.
  static int calculateBranchActiveDays(
    BranchType branch,
    List<Habit> habits,
    List<DailyLog> logs, {
    Season? season,
  }) {
    final branchHabitIds = {
      for (final habit in habits)
        if (habit.branch == branch) habit.id,
    };
    if (branchHabitIds.isEmpty) return 0;

    final activeDates = <String>{};
    for (final log in logs) {
      if (season != null && !season.containsDate(log.dateString)) continue;
      if (log.completedHabitIds.any(branchHabitIds.contains)) {
        activeDates.add(toDateString(parseDateString(log.dateString)));
      }
    }
    return activeDates.length;
  }

  /// Active days for every branch.
  static Map<BranchType, int> calculateAllBranchActiveDays(
    List<Habit> habits,
    List<DailyLog> logs, {
    Season? season,
  }) {
    return {
      for (final branch in BranchType.values)
        branch: calculateBranchActiveDays(branch, habits, logs, season: season),
    };
  }

  /// Number of distinct dates [habitId] was completed (within [season], if
  /// given). Shows how much a single habit contributes to its branch.
  static int calculateHabitActiveDays(
    String habitId,
    List<DailyLog> logs, {
    Season? season,
  }) {
    return {
      for (final log in logs)
        if ((season == null || season.containsDate(log.dateString)) &&
            log.completedHabitIds.contains(habitId))
          log.dateString,
    }.length;
  }

  /// Longest run of consecutive calendar days among [dateStrings]
  /// (`YYYY-MM-DD`, any order, duplicates ignored). A best to celebrate,
  /// never a streak to lose.
  static int calculateLongestRun(Iterable<String> dateStrings) {
    final dates = dateStrings.toSet().map(parseDateString).toList()..sort();
    var best = 0;
    var run = 0;
    DateTime? previous;
    for (final date in dates) {
      run = previous != null && date.difference(previous).inDays == 1
          ? run + 1
          : 1;
      best = math.max(best, run);
      previous = date;
    }
    return best;
  }

  /// Number of skill nodes (0 to 5) unlocked by [activeDays].
  static int calculateUnlockedNodes(int activeDays) {
    return nodeThresholds.where((threshold) => activeDays >= threshold).length;
  }

  /// Earned nodes the user has forged: [forgedNodeCount] capped to the
  /// [unlockedNodes] the branch's active days have earned. Only these add
  /// levels and keys.
  static int calculateForgedNodes(int unlockedNodes, int forgedNodeCount) =>
      forgedNodeCount.clamp(0, unlockedNodes);

  /// Number of completed quests (feats) in [branch].
  static int calculateCompletedFeats(BranchType branch, List<Quest> quests) {
    return quests.where((q) => q.branch == branch && q.isCompleted).length;
  }

  /// `Base Carry-Over Level + Unlocked Nodes + Completed Feats`.
  static int calculateBranchLevel(
    int baseLevel,
    int unlockedNodesCount,
    int completedFeatsCount,
  ) {
    if (baseLevel < 0) {
      throw ArgumentError.value(baseLevel, 'baseLevel', 'must be >= 0');
    }
    if (unlockedNodesCount < 0 || unlockedNodesCount > maxNodesPerBranch) {
      throw ArgumentError.value(
        unlockedNodesCount,
        'unlockedNodesCount',
        'must be between 0 and $maxNodesPerBranch',
      );
    }
    if (completedFeatsCount < 0) {
      throw ArgumentError.value(
        completedFeatsCount,
        'completedFeatsCount',
        'must be >= 0',
      );
    }
    return baseLevel + unlockedNodesCount + completedFeatsCount;
  }

  /// Sum of all branch levels.
  static int calculateTotalCharacterLevel(Map<BranchType, int> branchLevels) {
    return branchLevels.values.fold(0, (sum, level) => sum + level);
  }

  /// Common Keys earned by [habit] as a keystone: one for every full run of
  /// 7 consecutive completed dates (a 14-day run earns 2). Only days on
  /// which it was the keystone count, so moving the star keeps earned keys.
  static int calculateKeystoneCommonKeys(
    Habit habit,
    List<DailyLog> logs, {
    Season? season,
  }) {
    final dates = <DateTime>{
      for (final log in logs)
        if ((season == null || season.containsDate(log.dateString)) &&
            log.completedHabitIds.contains(habit.id) &&
            habit.wasKeystoneOn(log.dateString))
          parseDateString(log.dateString),
    }.toList()..sort();

    var keys = 0;
    var run = 0;
    DateTime? previous;
    for (final date in dates) {
      final isConsecutive =
          previous != null && date.difference(previous).inDays == 1;
      run = isConsecutive ? run + 1 : 1;
      if (run % keystoneDaysPerCommonKey == 0) keys++;
      previous = date;
    }
    return keys;
  }

  /// Days of the month the Mid-Month Campfire banner is offered.
  static const Set<int> campfireDays = {14, 15, 16};

  /// Whether [today] is a Mid-Month Campfire day (the 14th–16th).
  static bool isCampfireDay(DateTime today) => campfireDays.contains(today.day);

  /// Below this completion rate a Half 1 habit counts as struggling.
  static const double strugglingCompletionRate = 0.25;

  /// Habits scheduled in Half 1 (days 1–15) of [today]'s month that were
  /// completed on less than 25% of the elapsed Half 1 days, worst first.
  ///
  /// Elapsed days run from day 1 through yesterday (today can still be
  /// checked off), capped at day 15. They start no earlier than the first
  /// check-in on record, so days before the character existed don't count
  /// as misses. Archived and Half 2-only habits are skipped; already
  /// pivoted (Half 1-only) habits are included.
  static List<StrugglingHabit> findStrugglingHabits(
    List<Habit> habits,
    List<DailyLog> logs,
    DateTime today,
  ) {
    final todayDate = parseDateString(toDateString(today));
    final monthStart = DateTime.utc(today.year, today.month);
    final lastDay = math.min(today.day - 1, ActiveHalfMonth.firstHalfLastDay);
    final firstLog = logs.isEmpty
        ? null
        : logs
              .map((l) => parseDateString(l.dateString))
              .reduce((a, b) => a.isBefore(b) ? a : b);
    if (firstLog == null) return const [];
    // A character whose first check-in is this month started that day.
    final firstDay = firstLog.isBefore(monthStart) ? 1 : firstLog.day;
    if (firstLog.isAfter(todayDate) || lastDay < firstDay) return const [];

    final window = Season(
      id: 'half-1',
      name: 'Half 1',
      startDate: DateTime.utc(today.year, today.month, firstDay),
      endDate: DateTime.utc(today.year, today.month, lastDay),
    );
    final elapsed = lastDay - firstDay + 1;
    final struggling = [
      for (final habit in habits)
        if (!habit.isArchived &&
            habit.activeHalfMonth != ActiveHalfMonth.secondHalf)
          StrugglingHabit(
            habit: habit,
            completedDays: calculateHabitActiveDays(
              habit.id,
              logs,
              season: window,
            ),
            elapsedDays: elapsed,
          ),
    ].where((s) => s.completionRate < strugglingCompletionRate).toList();
    // Worst first; ties keep the habit order.
    return struggling..sort((a, b) {
      final byRate = a.completionRate.compareTo(b.completionRate);
      return byRate != 0
          ? byRate
          : habits.indexOf(a.habit).compareTo(habits.indexOf(b.habit));
    });
  }

  /// 1-based day of [season] on [today], clamped to the season's length
  /// (e.g. day 32 of 92). Returns 0 before the season starts.
  static int calculateSeasonDay(Season season, DateTime today) {
    final start = parseDateString(toDateString(season.startDate));
    final end = parseDateString(toDateString(season.endDate));
    final date = parseDateString(toDateString(today));
    if (date.isBefore(start)) return 0;
    final length = end.difference(start).inDays + 1;
    return math.min(date.difference(start).inDays + 1, length);
  }

  /// Which season month (1–3) [today] falls in: its calendar month's place
  /// in the season (October, November, December for a season starting
  /// Oct 1). Clamped to 1 before the season and 3 after it.
  static int calculateSeasonMonthIndex(Season season, DateTime today) {
    final start = season.startDate;
    final months = (today.year - start.year) * 12 + today.month - start.month;
    return months.clamp(0, 2) + 1;
  }

  /// The date range of season month [monthIndex] (1–3) as a [Season]
  /// window: the season's three calendar months, clipped to the season.
  static Season seasonMonthWindow(Season season, int monthIndex) {
    final seasonStart = parseDateString(toDateString(season.startDate));
    final seasonEnd = parseDateString(toDateString(season.endDate));
    final monthStart = DateTime.utc(
      seasonStart.year,
      seasonStart.month + monthIndex - 1,
    );
    final start = monthIndex == 1 ? seasonStart : monthStart;
    final end = monthIndex == 3
        ? seasonEnd
        : DateTime.utc(monthStart.year, monthStart.month + 1, 0);
    return Season(
      id: '${season.id}-m$monthIndex',
      name: 'Month $monthIndex',
      startDate: start,
      endDate: end.isAfter(seasonEnd) ? seasonEnd : end,
    );
  }

  /// Whether [season] has ended by [today], so it can be completed.
  static bool isSeasonOver(Season season, DateTime today) {
    final end = parseDateString(toDateString(season.endDate));
    return parseDateString(toDateString(today)).isAfter(end);
  }

  /// Total number of days in [season], inclusive.
  static int calculateSeasonLength(Season season) {
    final start = parseDateString(toDateString(season.startDate));
    final end = parseDateString(toDateString(season.endDate));
    return end.difference(start).inDays + 1;
  }

  /// Earned vs. claimed keys for every loot tier.
  ///
  /// - Common: every 7 consecutive days of each habit while it was the
  ///   keystone.
  /// - Rare: every forged skill node.
  /// - Epic: every branch with all 5 nodes forged.
  /// - Legendary: all nodes forged in every active branch (25 across the
  ///   five core branches).
  ///
  /// Only [branches] count: the character's active pillars, by default
  /// the five core ones ([BranchType.defaults]).
  /// [forgedNodeCounts] holds each branch's forged node count; without it
  /// every unlocked node counts as forged. Claimed counts come from the
  /// claimed items in [claimedLoot] (unclaimed items are ignored); when
  /// [season] is given, only logs and loot claimed inside it count.
  static Map<LootTier, LootKeyBalance> calculateAvailableLootKeys({
    required List<Habit> habits,
    required List<DailyLog> logs,
    required List<LootItem> claimedLoot,
    Map<BranchType, int>? forgedNodeCounts,
    Season? season,
    List<BranchType> branches = BranchType.defaults,
  }) {
    final counted = branches.toSet();
    final commonEarned = habits
        .where((h) => h.hasKeystoneHistory && counted.contains(h.branch))
        .fold(
          0,
          (sum, h) =>
              sum + calculateKeystoneCommonKeys(h, logs, season: season),
        );

    final activeDays = calculateAllBranchActiveDays(
      habits,
      logs,
      season: season,
    );
    final nodesPerBranch = [
      for (final branch in counted)
        if (forgedNodeCounts?[branch] case final forged?)
          calculateForgedNodes(
            calculateUnlockedNodes(activeDays[branch]!),
            forged,
          )
        else
          calculateUnlockedNodes(activeDays[branch]!),
    ];

    final rareEarned = nodesPerBranch.fold(0, (sum, n) => sum + n);
    final epicEarned = nodesPerBranch
        .where((n) => n == maxNodesPerBranch)
        .length;
    final legendaryEarned = counted.isNotEmpty && epicEarned == counted.length
        ? 1
        : 0;

    final earned = {
      LootTier.common: commonEarned,
      LootTier.rare: rareEarned,
      LootTier.epic: epicEarned,
      LootTier.legendary: legendaryEarned,
    };

    final claimed = {for (final tier in LootTier.values) tier: 0};
    for (final item in claimedLoot) {
      final claimedAt = item.claimedAtDate;
      if (claimedAt == null) continue;
      if (season != null && !season.containsDate(claimedAt)) continue;
      claimed[item.tier] = claimed[item.tier]! + 1;
    }

    return {
      for (final tier in LootTier.values)
        tier: LootKeyBalance(earned: earned[tier]!, claimed: claimed[tier]!),
    };
  }
}
