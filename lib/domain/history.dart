/// Read-only views over past data: one habit across its whole life, and one
/// season (sprint) as it was played. Pure Dart, derived from stored logs.
library;

import '../models/rpg_models.dart';
import '../models/rpg_state.dart';
import 'rpg_engine.dart';

/// Days a habit was done within one season.
class SeasonHabitCount {
  const SeasonHabitCount({required this.season, required this.days});

  final Season season;
  final int days;
}

/// Everything recorded for one habit, across every season.
class HabitHistory {
  const HabitHistory({
    required this.habit,
    required this.doneDates,
    required this.bestRun,
    required this.perSeason,
  });

  factory HabitHistory.of(RpgState state, Habit habit) {
    final done = {
      for (final log in state.logs)
        if (log.completedHabitIds.contains(habit.id)) log.dateString,
    }.toList()..sort();
    return HabitHistory(
      habit: habit,
      doneDates: done,
      bestRun: RpgEngine.calculateLongestRun(done),
      perSeason: [
        for (final season in state.seasons.reversed)
          if (done.where(season.containsDate).length case final days
              when days > 0)
            SeasonHabitCount(season: season, days: days),
      ],
    );
  }

  final Habit habit;

  /// Dates (`YYYY-MM-DD`) the habit was checked off, oldest first.
  final List<String> doneDates;

  /// Longest run of consecutive days done.
  final int bestRun;

  /// Seasons the habit was done in, newest first.
  final List<SeasonHabitCount> perSeason;

  int get totalDays => doneDates.length;
  String? get firstDate => doneDates.firstOrNull;
  String? get lastDate => doneDates.lastOrNull;

  /// First day of every month from the first check-in through [today]'s
  /// month, newest first; just [today]'s month before any check-in.
  List<DateTime> months(DateTime today) {
    final last = DateTime.utc(today.year, today.month);
    final first = firstDate == null
        ? last
        : DateTime.utc(
            parseDateString(firstDate!).year,
            parseDateString(firstDate!).month,
          );
    return [
      for (
        var m = last;
        !m.isBefore(first);
        m = DateTime.utc(m.year, m.month - 1)
      )
        m,
    ];
  }
}

/// A season as it was played: its quests, claimed loot, reflections and the
/// habits done in it.
class SeasonRecord {
  const SeasonRecord({
    required this.season,
    required this.quests,
    required this.lootClaimed,
    required this.reflections,
    required this.habits,
  });

  factory SeasonRecord.of(RpgState state, Season season) {
    final isCurrent = season.id == state.character.currentSeasonId;
    final start = toDateString(season.startDate);
    final end = toDateString(season.endDate);
    bool overlaps(MonthReflection r) =>
        '${r.monthKey}-31'.compareTo(start) >= 0 &&
        '${r.monthKey}-01'.compareTo(end) <= 0;

    return SeasonRecord(
      season: season,
      quests:
          [
            for (final q in state.quests)
              if (q.seasonId == season.id || (q.seasonId == null && isCurrent))
                q,
          ]..sort((a, b) {
            final byMonth = a.monthIndex.compareTo(b.monthIndex);
            if (byMonth != 0) return byMonth;
            return (b.isMainQuest ? 1 : 0).compareTo(a.isMainQuest ? 1 : 0);
          }),
      lootClaimed: [
        for (final l in state.loot)
          if (l.claimedAtDate != null && season.containsDate(l.claimedAtDate!))
            l,
      ],
      reflections: [
        for (final r in state.reflections)
          if (overlaps(r) && (r.notes.trim().isNotEmpty || r.pivots.isNotEmpty))
            r,
      ]..sort((a, b) => a.monthKey.compareTo(b.monthKey)),
      habits: [
        for (final h in state.habits)
          if (RpgEngine.calculateHabitActiveDays(
                h.id,
                state.logs,
                season: season,
              )
              case final days when days > 0)
            (habit: h, days: days),
      ]..sort((a, b) => b.days.compareTo(a.days)),
    );
  }

  final Season season;

  /// The season's quests by month, main quest first.
  final List<Quest> quests;

  /// Rewards claimed during the season.
  final List<LootItem> lootClaimed;

  /// Month reflections with notes or pivots, oldest first.
  final List<MonthReflection> reflections;

  /// Habits done during the season, most days first.
  final List<({Habit habit, int days})> habits;
}
