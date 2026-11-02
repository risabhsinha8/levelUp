/// Pure planning of the app's local notifications. The schedule is rebuilt
/// from the stored state whenever it changes, so a reminder never nags about
/// something already done: checking off today's keystones drops today's
/// reminder. No Flutter, Riverpod or I/O.
library;

import '../models/rpg_models.dart';
import '../models/rpg_state.dart';
import 'character_sheet.dart';
import 'rpg_engine.dart';

/// One local notification to show at [at] (local time).
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
  });

  /// Stable per slot (see [ReminderPlanner]), so a re-plan replaces it.
  final int id;
  final DateTime at;
  final String title;
  final String body;

  @override
  bool operator ==(Object other) =>
      other is PlannedReminder &&
      other.id == id &&
      other.at == at &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode => Object.hash(id, at, title, body);

  @override
  String toString() => 'PlannedReminder($id @ $at: $title — $body)';
}

/// Every reminder pending at one moment, soonest first.
class ReminderPlan {
  ReminderPlan(List<PlannedReminder> reminders)
    : reminders = List.unmodifiable(reminders);

  static final empty = ReminderPlan(const []);

  final List<PlannedReminder> reminders;

  @override
  bool operator ==(Object other) {
    if (other is! ReminderPlan || other.reminders.length != reminders.length) {
      return false;
    }
    for (var i = 0; i < reminders.length; i++) {
      if (other.reminders[i] != reminders[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(reminders);
}

abstract final class ReminderPlanner {
  /// Days of keystone reminders scheduled ahead (today included). The plan
  /// is rebuilt each time the app runs, so this only covers time away.
  static const int dailyDaysAhead = 7;

  /// Notification ids: daily reminders use [dailyBaseId] + days from today.
  static const int dailyBaseId = 100;
  static const int campfireId = 200;
  static const int seasonFinalStretchId = 300;
  static const int seasonOverId = 301;

  /// 10:00 am, when campfire and season notices arrive.
  static const int noticeMinutes = 10 * 60;

  /// Days before the season's last day that the final-stretch notice comes.
  static const int finalStretchDays = 2;

  /// What to schedule at [now] for [state]. Empty when reminders are off.
  ///
  /// - A daily keystone reminder at the character's reminder time for the
  ///   next [dailyDaysAhead] days. Today's names the keystones still open
  ///   and is left out once they are all done.
  /// - The next Mid-Month Campfire (the 14th) at 10 am.
  /// - "Final stretch" 3 days before the season ends, and "season complete"
  ///   the morning after, when the header offers the level-up.
  static ReminderPlan plan(RpgState state, DateTime now) {
    final minutes = state.character.reminderMinutes;
    if (minutes == null) return ReminderPlan.empty;
    final today = DateTime(now.year, now.month, now.day);
    final reminders =
        <PlannedReminder>[
            for (var i = 0; i < dailyDaysAhead; i++)
              ?_daily(state, today, i, minutes),
            _campfire(now),
            ..._seasonNotices(state, today),
          ].where((r) => r.at.isAfter(now)).toList()
          ..sort((a, b) => a.at.compareTo(b.at));
    return ReminderPlan(reminders);
  }

  static DateTime _at(DateTime date, int minutes) =>
      DateTime(date.year, date.month, date.day, minutes ~/ 60, minutes % 60);

  static PlannedReminder? _daily(
    RpgState state,
    DateTime today,
    int daysAhead,
    int minutes,
  ) {
    final date = DateTime(today.year, today.month, today.day + daysAhead);
    final keystones = [
      for (final branch in state.activeBranches)
        if (state.keystoneFor(branch) case final keystone?)
          if (keystone.isActiveOn(date)) keystone,
    ];
    final done = state.completedOn(date);
    final open = [
      for (final k in keystones)
        if (!done.contains(k.id)) k,
    ];
    if (daysAhead == 0 && keystones.isNotEmpty && open.isEmpty) return null;

    // A keystone 6 days into a run earns a Common Key with today's check-in.
    final keyNear = open
        .where(
          (k) =>
              (keystoneRunBefore(k, state.logs, date) + 1) %
                  RpgEngine.keystoneDaysPerCommonKey ==
              0,
        )
        .firstOrNull;
    final keyLine = keyNear == null
        ? null
        : 'One more day of ${keyNear.title} earns a Common Key.';

    final String title;
    final String body;
    if (daysAhead == 0 && open.isNotEmpty) {
      title = open.length == 1
          ? '1 keystone still open'
          : '${open.length} keystones still open';
      final forgeLine = _hasNodeToForge(state, today)
          ? 'A skill node is ready to forge.'
          : null;
      body = [
        '★ ${open.map((k) => k.title).join(' · ')}',
        ?keyLine,
        ?forgeLine,
      ].join('\n');
    } else {
      title = 'Keystone check-in';
      body =
          keyLine ?? 'Check off your ★ keystones to keep your pillars growing.';
    }
    return PlannedReminder(
      id: dailyBaseId + daysAhead,
      at: _at(date, minutes),
      title: title,
      body: body,
    );
  }

  /// Consecutive days [keystone] was done as the keystone, ending the day
  /// before [date].
  static int keystoneRunBefore(
    Habit keystone,
    List<DailyLog> logs,
    DateTime date,
  ) {
    final days = {
      for (final log in logs)
        if (log.completedHabitIds.contains(keystone.id) &&
            keystone.wasKeystoneOn(log.dateString))
          log.dateString,
    };
    var run = 0;
    var day = DateTime(date.year, date.month, date.day - 1);
    while (days.contains(toDateString(day))) {
      run++;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return run;
  }

  static bool _hasNodeToForge(RpgState state, DateTime today) =>
      CharacterSheet.fromState(
        state,
        today,
      ).branches.values.any((b) => b.readyToForge > 0);

  /// The next campfire notice after [now] (this month's, or next month's
  /// once it has gone by).
  static PlannedReminder _campfire(DateTime now) {
    final day = RpgEngine.campfireDays.reduce((a, b) => a < b ? a : b);
    var at = _at(DateTime(now.year, now.month, day), noticeMinutes);
    if (!at.isAfter(now)) {
      at = _at(DateTime(now.year, now.month + 1, day), noticeMinutes);
    }
    return PlannedReminder(
      id: campfireId,
      at: at,
      title: 'The Mid-Month Campfire is lit',
      body:
          'Look back on Half 1 and swap any habit that isn’t sticking. '
          'Your earned points stay.',
    );
  }

  static List<PlannedReminder> _seasonNotices(RpgState state, DateTime today) {
    final season = state.currentSeason;
    if (RpgEngine.isSeasonOver(season, today)) return const [];
    final end = season.endDate;
    return [
      PlannedReminder(
        id: seasonFinalStretchId,
        at: _at(
          DateTime(end.year, end.month, end.day - finalStretchDays),
          noticeMinutes,
        ),
        title: 'Final stretch: ${finalStretchDays + 1} days left',
        body:
            'Every check-in still counts toward ${season.name}’s skill nodes.',
      ),
      PlannedReminder(
        id: seasonOverId,
        at: _at(DateTime(end.year, end.month, end.day + 1), noticeMinutes),
        title: '${season.name} is complete',
        body: 'Open levelUp to bake your levels and begin the next season.',
      ),
    ];
  }
}
