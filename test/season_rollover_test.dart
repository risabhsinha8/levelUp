import 'package:flutter_test/flutter_test.dart';
import 'support/fixtures.dart';
import 'package:level_up/domain/character_sheet.dart';
import 'package:level_up/domain/rpg_engine.dart';
import 'package:level_up/domain/season_rollover.dart';
import 'package:level_up/models/rpg_models.dart';
import 'package:level_up/models/rpg_state.dart';

final today = DateTime(2026, 10, 24, 9);

/// The demo season (Oct 7 – Dec 31) has ended; completed a few days late.
final rolloverDay = DateTime(2027, 1, 5, 9);

void main() {
  group('calendar quarters', () {
    String quarter(DateTime d) =>
        '${toDateString(Season.quarterStartOf(d))}..'
        '${toDateString(Season.quarterEndOf(d))}';

    test('seasons start on Jan 1, Apr 1, Jul 1 and Oct 1', () {
      expect(quarter(DateTime(2027, 1, 1)), '2027-01-01..2027-03-31');
      expect(quarter(DateTime(2027, 2, 14)), '2027-01-01..2027-03-31');
      expect(quarter(DateTime(2028, 2, 29)), '2028-01-01..2028-03-31');
      expect(quarter(DateTime(2027, 6, 30)), '2027-04-01..2027-06-30');
      expect(quarter(DateTime(2027, 7, 1)), '2027-07-01..2027-09-30');
      expect(quarter(DateTime(2026, 11, 1)), '2026-10-01..2026-12-31');
      expect(quarter(DateTime(2026, 12, 31, 23)), '2026-10-01..2026-12-31');
    });

    test('joining on Nov 1 starts on day 32 of the Oct–Dec season', () {
      final nov1 = DateTime(2026, 11, 1, 8);
      final sheet = CharacterSheet.fromState(buildFreshState(nov1), nov1);
      expect(sheet.seasonDay, 32);
      expect(sheet.seasonLength, 92);
      expect(sheet.isSeasonOver, isFalse);
    });

    test('a season is over the day after its quarter ends', () {
      final season = buildFreshState(today).currentSeason;
      expect(RpgEngine.isSeasonOver(season, DateTime(2026, 12, 31, 23)), false);
      expect(RpgEngine.isSeasonOver(season, DateTime(2027, 1, 1)), isTrue);
    });
  });

  test('a running season cannot be completed', () {
    expect(
      () =>
          SeasonRollover.apply(buildDemoState(today), today, newSeasonId: 's2'),
      throwsStateError,
    );
  });

  group('SeasonRollover.apply (after the quarter ends)', () {
    final demo = buildDemoState(today);
    // A check-in after the season ended, before completing it, belongs to
    // the new season.
    final withLateLog = demo.copyWith(
      logs: [
        ...demo.logs,
        DailyLog(
          dateString: '2027-01-03',
          completedHabitIds: ['habit-exercise'],
        ),
      ],
    );
    final before = CharacterSheet.fromState(withLateLog, rolloverDay);
    final result = SeasonRollover.apply(
      withLateLog,
      rolloverDay,
      newSeasonId: 's2',
    );
    final after = CharacterSheet.fromState(result.state, rolloverDay);

    test('bakes nodes + feats into base levels; level carries over', () {
      final bases = {
        for (final b in BranchType.defaults)
          b: result.state.configFor(b).baseLevel,
      };
      // The Jan 3 log is in Season 2; Body still ends on 17 days (2 nodes).
      expect(bases, {
        BranchType.mind: 3,
        BranchType.body: 3,
        BranchType.craft: 2,
        BranchType.bond: 1,
        BranchType.empire: 0,
      });
      expect(before.totalLevel, 9);
      expect(after.totalLevel, 9);
    });

    test('summary records old vs new character level', () {
      expect(result.summary.startLevel, 2);
      expect(result.summary.endLevel, 9);
      expect(result.summary.branches[BranchType.craft]!.feats, 1);
      expect(result.summary.branches[BranchType.mind]!.activeDays, 17);
    });

    test('resets the skill tree and feats for the new season', () {
      for (final stats in after.branches.values) {
        expect(stats.completedFeats, 0);
      }
      final nodes = after.branches.values.fold(
        0,
        (s, b) => s + b.unlockedNodes,
      );
      expect(nodes, 0);
      expect(after.branches[BranchType.body]!.activeDays, 1); // Jan 3
      expect(after.seasonDay, 5);
      expect(after.seasonLength, 90);
    });

    test('archives the old season as is and starts the next quarter', () {
      final old = result.state.seasons.firstWhere((s) => s.id == 'season-1');
      expect(old.isArchived, isTrue);
      expect(toDateString(old.endDate), '2026-12-31');
      expect(old.summary, result.summary);

      final current = result.state.currentSeason;
      expect(current.id, 's2');
      expect(current.name, 'Season 2');
      expect(toDateString(current.startDate), '2027-01-01');
      expect(toDateString(current.endDate), '2027-03-31');
      expect(current.isArchived, isFalse);
      expect(result.state.archivedSeasons.map((s) => s.id), ['season-1']);
    });

    test('keeps habits and logs; stamps quests with the old season', () {
      expect(result.state.habits, withLateLog.habits);
      expect(result.state.logs, withLateLog.logs);
      expect(
        result.state.quests.every((q) => q.seasonId == 'season-1'),
        isTrue,
      );
      expect(result.state.currentQuests, isEmpty);
    });

    test('loot keys start over for the new season', () {
      for (final balance in after.lootKeys.values) {
        expect(balance.earned, 0);
        expect(balance.claimed, 0);
      }
    });

    test('survives a JSON round-trip', () {
      final restored = RpgState.fromJson(result.state.toJson());
      expect(restored.toJson(), result.state.toJson());
      expect(restored.seasons.first.summary, result.summary);
    });

    test('a second rollover builds on the first', () {
      final later = DateTime(2027, 4, 2);
      final second = SeasonRollover.apply(
        result.state,
        later,
        newSeasonId: 's3',
      );
      expect(second.state.currentSeason.name, 'Season 3');
      expect(second.summary.startLevel, 9);
      final s2 = second.state.seasons.firstWhere((s) => s.id == 's2');
      expect(toDateString(s2.endDate), '2027-03-31');
      expect(toDateString(second.state.currentSeason.startDate), '2027-04-01');
      expect(second.state.archivedSeasons.map((s) => s.id), ['s2', 'season-1']);
    });

    test('a skipped quarter becomes its own season, then the next one', () {
      final july = DateTime(2027, 7, 10);
      final q2 = SeasonRollover.apply(result.state, july, newSeasonId: 's3');
      final s3 = q2.state.currentSeason;
      expect(toDateString(s3.startDate), '2027-04-01');
      expect(toDateString(s3.endDate), '2027-06-30');
      expect(RpgEngine.isSeasonOver(s3, july), isTrue);

      final q3 = SeasonRollover.apply(q2.state, july, newSeasonId: 's4');
      final s4 = q3.state.currentSeason;
      expect(toDateString(s4.startDate), '2027-07-01');
      expect(toDateString(s4.endDate), '2027-09-30');
      expect(CharacterSheet.fromState(q3.state, july).seasonDay, 10);
    });
  });

  test('season months are the calendar months, clipped to the season', () {
    final season = buildDemoState(today).currentSeason; // Oct 7 – Dec 31
    String range(int m) {
      final w = RpgEngine.seasonMonthWindow(season, m);
      return '${toDateString(w.startDate)}..${toDateString(w.endDate)}';
    }

    expect(range(1), '2026-10-07..2026-10-31');
    expect(range(2), '2026-11-01..2026-11-30');
    expect(range(3), '2026-12-01..2026-12-31');
  });

  test('quests saved before season ids still count as current', () {
    final quest = Quest.fromJson({
      'id': 'q',
      'title': 'Old',
      'branch': 'mind',
      'isCompleted': true,
    });
    expect(quest.seasonId, isNull);
    final state = buildFreshState(today).copyWith(quests: [quest]);
    expect(state.currentQuests, [quest]);
  });
}
