import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../domain/character_sheet.dart';
import '../domain/character_stats.dart';
import '../domain/rpg_engine.dart';
import '../models/rpg_models.dart';
import '../models/rpg_state.dart';
import '../providers/rpg_store_provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/empty_prompt.dart';
import '../widgets/pixel_avatar.dart';
import '../widgets/stat_tiles.dart';
import 'habit_history_screen.dart';
import 'season_detail_screen.dart';

/// Opens the Character page (from the header avatar).
Future<void> openCharacterPage(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const CharacterScreen()));

/// The character's avatar (editable) with season and lifetime stats.
class CharacterScreen extends ConsumerWidget {
  const CharacterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(rpgStateProvider);
    final sheet = ref.watch(characterSheetProvider).requireValue;
    final stats = CharacterStats.fromState(state, ref.watch(todayProvider));

    return Scaffold(
      backgroundColor: RpgColors.obsidian,
      appBar: AppBar(
        backgroundColor: RpgColors.obsidian,
        surfaceTintColor: Colors.transparent,
        title: const Text('Character'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _HeroCard(state: state, sheet: sheet),
          StatSection(
            title: 'This Season',
            child: _SeasonTiles(state: state, sheet: sheet, stats: stats),
          ),
          StatSection(
            title: 'Lifetime',
            child: StatTileGrid(
              columns: 3,
              tiles: [
                StatTile(
                  icon: LucideIcons.calendarDays,
                  value: '${stats.daysLogged}',
                  label: 'Days logged',
                  info:
                      'Calendar days with at least one habit checked off, across '
                      'all seasons.',
                ),
                StatTile(
                  icon: LucideIcons.checkCircle2,
                  value: '${stats.totalCheckIns}',
                  label: 'Check-ins',
                  info:
                      'Every habit you have checked off, across all seasons. '
                      'Each habit counts once per day.',
                ),
                StatTile(
                  icon: LucideIcons.footprints,
                  value: '${stats.bestRun}',
                  label: 'Best run (days)',
                  info:
                      'Your longest stretch of back-to-back days with at least '
                      'one check-in. It is a record, not a streak: missing a '
                      'day never lowers it.',
                ),
                StatTile(
                  icon: LucideIcons.trophy,
                  value: '${stats.seasonsCompleted}',
                  label: 'Seasons done',
                  info:
                      'Seasons you have completed and rolled over into the '
                      'next. Each one is listed under History.',
                ),
                StatTile(
                  icon: LucideIcons.swords,
                  value: '${stats.questsCompleted}',
                  label: 'Quests done',
                  info: 'Quests completed across all seasons and pillars.',
                ),
                StatTile(
                  icon: LucideIcons.gem,
                  value: '${stats.lootClaimed}',
                  label: 'Loot claimed',
                  info:
                      'Rewards you have claimed by spending a loot key, across '
                      'all seasons.',
                ),
              ],
            ),
          ),
          StatSection(
            title: 'Pillars',
            subtitle: 'Active days per pillar, all seasons',
            info:
                'The bars are measured in Branch Active Days: a pillar gets 1 '
                'for each calendar day at least one of its habits was checked '
                'off, and never more than 1 a day, however many of its habits '
                'you finish. This counts every season, not just this one.\n\n'
                'The scale under the bars runs from 0 to your most active '
                'pillar, so its bar is always full and the others show how '
                'close they are to it. Your favorite pillar is that top one.'
                '\n\n'
                'On the right of each bar: its active days, and the pillar\'s '
                'level now (carry-over from past seasons + nodes forged + '
                'feats this season).',
            child: _PillarBars(state: state, sheet: sheet, stats: stats),
          ),
          StatSection(
            title: 'History',
            info:
                'Habit History lists every habit: active ones are on your '
                'daily list, archived ones are retired but the points they '
                'earned still count.\n\n'
                'Each past season shows your character level when it began → '
                'when it ended. Tap one for its full results.',
            child: Column(
              children: [
                ListTile(
                  key: const ValueKey('open-habit-history'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    LucideIcons.listChecks,
                    color: RpgColors.gold,
                  ),
                  title: const Text('Habit History'),
                  subtitle: Text(
                    '${state.activeHabits.length} active · '
                    '${state.habits.length - state.activeHabits.length} '
                    'archived',
                    style: RpgStyles.of(context).stat.copyWith(fontSize: 11),
                  ),
                  trailing: const Icon(LucideIcons.chevronRight, size: 18),
                  onTap: () => openHabitHistory(context),
                ),
                for (final season in state.archivedSeasons)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      LucideIcons.award,
                      color: RpgColors.gold,
                    ),
                    title: Text(season.name),
                    subtitle: season.summary == null
                        ? null
                        : Text(
                            'Lv ${season.summary!.startLevel} → '
                            '${season.summary!.endLevel}',
                            style: RpgStyles.of(
                              context,
                            ).stat.copyWith(fontSize: 11),
                          ),
                    trailing: const Icon(LucideIcons.chevronRight, size: 18),
                    onTap: () => openSeasonDetail(context, season.id),
                  ),
              ],
            ),
          ),
          StatSection(
            title: 'Rhythm',
            subtitle: 'Check-ins by day of the week',
            info:
                'Total check-ins on each day of the week, across all seasons, '
                'Monday first. The labeled bar is your best day: the one you '
                'show up most.',
            child: stats.totalCheckIns == 0
                ? const EmptyPrompt(
                    icon: LucideIcons.activity,
                    title: 'No check-ins yet',
                    message: 'Your weekly rhythm appears after a few days.',
                    compact: true,
                  )
                : _WeekdayBars(stats: stats),
          ),
          StatSection(
            title: 'Last 12 Weeks',
            subtitle: 'Check-ins per day',
            info:
                'One square per day for the last 12 weeks: each column is a '
                'week (oldest on the left, Monday at the top). The deeper the '
                'gold, the more habits you checked off that day, compared '
                'with your busiest day in these 12 weeks. Dark squares are '
                'days with no check-ins.',
            child: _Heatmap(stats: stats, today: ref.watch(todayProvider)),
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.state, required this.sheet});

  final RpgState state;
  final CharacterSheet sheet;

  String _info() {
    final season = state.currentSeason;
    final format = DateFormat.MMMd();
    final pillars = sheet.activeBranches.length;
    return 'Level ${sheet.totalLevel} is the sum of your $pillars active '
        'pillars\' levels. Each pillar\'s level is its carry-over from past '
        'seasons + nodes forged this season + feats (quests completed) this '
        'season.\n\n'
        '${season.name} runs ${format.format(season.startDate)} – '
        '${format.format(season.endDate)}, one calendar quarter. Day '
        '${sheet.seasonDay} of ${sheet.seasonLength} is how far in you are. '
        'When it ends you level up: pillar levels carry over and a new '
        'season starts.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = RpgStyles.of(context);
    final character = state.character;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            PixelAvatar(spec: character.avatarOrDefault, size: 112),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    character.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: RpgColors.parchment,
                    ),
                  ),
                  Text(
                    character.classTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: RpgColors.gold,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Lv ${sheet.totalLevel} · ${state.currentSeason.name} '
                          '· Day ${sheet.seasonDay}/${sheet.seasonLength}',
                          style: styles.stat,
                        ),
                      ),
                      StatInfoButton(title: 'Level & Season', body: _info()),
                    ],
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const ValueKey('edit-avatar'),
                    onPressed: () => showAvatarEditor(context),
                    icon: const Icon(LucideIcons.palette, size: 16),
                    label: const Text('Edit Avatar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: RpgColors.gold,
                      side: const BorderSide(color: RpgColors.goldDim),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeasonTiles extends StatelessWidget {
  const _SeasonTiles({
    required this.state,
    required this.sheet,
    required this.stats,
  });

  final RpgState state;
  final CharacterSheet sheet;
  final CharacterStats stats;

  @override
  Widget build(BuildContext context) {
    final active = [for (final b in sheet.activeBranches) sheet.branches[b]!];
    final forged = active.fold(0, (sum, b) => sum + b.forgedNodes);
    final rate = stats.seasonPointRate;
    final ready = active.fold(
      0,
      (sum, b) => sum + b.unlockedNodes - b.forgedNodes,
    );
    final earned = {
      for (final MapEntry(:key, :value) in sheet.lootKeys.entries)
        key: value.earned,
    };
    final keys = earned.values.fold(0, (sum, k) => sum + k);
    final thresholds = RpgEngine.nodeThresholds.join(', ');
    final pointsLine = stats.seasonPointsPossible == 0
        ? 'Possible points start counting from your first check-in this '
              'season.'
        : 'You have ${stats.seasonPoints} of ${stats.seasonPointsPossible} '
              'possible: ${active.length} pillars × '
              '${stats.seasonPointsPossible ~/ active.length} days since your '
              'first check-in this season, today included.';
    return StatTileGrid(
      columns: 2,
      tiles: [
        StatTile(
          icon: LucideIcons.sparkles,
          value: '${stats.seasonPoints}/${stats.seasonPointsPossible}',
          label: rate == null
              ? 'Branch points'
              : 'Branch points · ${(rate * 100).round()}%',
          info:
              'Each active pillar earns at most 1 point (a Branch Active Day) '
              'per calendar day, however many of its habits you check off.'
              '\n\n'
              '$pointsLine\n\n'
              'Points earn skill nodes. Missing a day never takes any away.',
        ),
        StatTile(
          icon: LucideIcons.network,
          value: '$forged/${RpgEngine.maxNodesPerBranch * active.length}',
          label: 'Nodes forged',
          info:
              'Every pillar has ${RpgEngine.maxNodesPerBranch} skill nodes '
              'per season, earned at $thresholds Branch Active Days. An '
              'earned node glows gold on the Skill Tree until you hold it to '
              'forge it.\n\n'
              'Each forged node adds 1 level to its pillar and a Rare key.'
              '${ready > 0 ? '\n\n$ready ready to forge now.' : ''}',
        ),
        StatTile(
          icon: LucideIcons.crown,
          value: '${active.fold(0, (sum, b) => sum + b.completedFeats)}',
          label: 'Feats',
          info:
              'Quests completed this season in your active pillars. Each '
              'feat adds 1 level to its quest\'s pillar.',
        ),
        StatTile(
          icon: LucideIcons.key,
          value: '$keys',
          label: 'Loot keys earned',
          info:
              'Keys earned this season, spent on rewards in the Loot Table.'
              '\n\n'
              'Common (${earned[LootTier.common]}): every 7 days in a row of '
              'checking off a keystone habit.\n'
              'Rare (${earned[LootTier.rare]}): each node forged.\n'
              'Epic (${earned[LootTier.epic]}): all '
              '${RpgEngine.maxNodesPerBranch} nodes forged in one pillar.\n'
              'Legendary (${earned[LootTier.legendary]}): every node forged '
              'in every active pillar.',
        ),
      ],
    );
  }
}

/// One bar per active pillar, in the pillar's color, measured in Branch
/// Active Days against a 0 → most-active-pillar scale.
class _PillarBars extends StatelessWidget {
  const _PillarBars({
    required this.state,
    required this.sheet,
    required this.stats,
  });

  final RpgState state;
  final CharacterSheet sheet;
  final CharacterStats stats;

  static const _nameWidth = 84.0;
  static const _leadWidth = 16 + 8 + _nameWidth;
  static const _valueWidth = 64.0;
  static const _valueGap = 10.0;

  static String _days(int days) => '$days ${days == 1 ? 'day' : 'days'}';

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    final top = math.max(1, stats.lifetimeActiveDays.values.fold(0, math.max));
    final favorite = stats.favoritePillar;
    final scaleStyle = styles.stat.copyWith(fontSize: 10);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final branch in sheet.activeBranches)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Icon(branch.icon, size: 16, color: branch.color),
                const SizedBox(width: 8),
                SizedBox(
                  width: _nameWidth,
                  child: Text(
                    state.nameOf(branch),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: styles.stat.copyWith(color: RpgColors.parchment),
                  ),
                ),
                Expanded(
                  child: Tooltip(
                    message:
                        '${state.nameOf(branch)}: '
                        '${_days(stats.lifetimeActiveDays[branch]!)} active',
                    child: Container(
                      height: 10,
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: RpgColors.outline.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: FractionallySizedBox(
                        widthFactor: stats.lifetimeActiveDays[branch]! / top,
                        child: Container(
                          decoration: BoxDecoration(
                            color: branch.color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: _valueGap),
                SizedBox(
                  width: _valueWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _days(stats.lifetimeActiveDays[branch]!),
                          maxLines: 1,
                          style: styles.stat.copyWith(
                            fontSize: 11,
                            color: RpgColors.parchment,
                          ),
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Lv ${sheet.branches[branch]!.level}',
                          maxLines: 1,
                          style: styles.stat.copyWith(
                            fontSize: 10,
                            color: RpgColors.gold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        // The scale under the bars: empty is 0, full is the top pillar.
        Row(
          children: [
            const SizedBox(width: _leadWidth),
            Text('0', style: scaleStyle),
            const SizedBox(width: 4),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_days(top), style: scaleStyle),
                ),
              ),
            ),
            const SizedBox(width: _valueGap + _valueWidth),
          ],
        ),
        if (favorite != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.star_rounded, size: 16, color: RpgColors.gold),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Favorite pillar: ${state.nameOf(favorite)}',
                  style: styles.stat,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Seven gold bars, Monday first; only the best day is labeled.
class _WeekdayBars extends StatelessWidget {
  const _WeekdayBars({required this.stats});

  final CharacterStats stats;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    final counts = stats.checkInsByWeekday;
    final top = math.max(1, counts.reduce(math.max));
    final best = stats.bestWeekday;
    final weekday = DateFormat.EEEE();
    // Jan 5, 2026 was a Monday.
    String dayName(int day) => weekday.format(DateTime(2026, 1, 4 + day));
    const chartHeight = 96.0;

    return Column(
      children: [
        SizedBox(
          height: chartHeight + 18,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Tooltip(
                    message: '${dayName(i + 1)}s: ${counts[i]} check-ins',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (best == i + 1)
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '${counts[i]}',
                                maxLines: 1,
                                style: styles.stat.copyWith(
                                  fontSize: 11,
                                  color: RpgColors.parchment,
                                ),
                              ),
                            ),
                          const SizedBox(height: 2),
                          Container(
                            height: math.max(2, chartHeight * counts[i] / top),
                            decoration: BoxDecoration(
                              color: best == i + 1
                                  ? RpgColors.gold
                                  : RpgColors.gold.withValues(alpha: 0.55),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final letter in _letters)
              Expanded(
                child: Text(
                  letter,
                  textAlign: TextAlign.center,
                  style: styles.stat.copyWith(fontSize: 10),
                ),
              ),
          ],
        ),
        if (best != null) ...[
          const SizedBox(height: 8),
          Text('Best day: ${dayName(best)}', style: styles.stat),
        ],
      ],
    );
  }
}

/// 12 columns of weeks × 7 weekday rows, shaded in gold by check-ins.
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.stats, required this.today});

  final CharacterStats stats;
  final DateTime today;

  static const _gap = 3.0;

  /// Gold for [count] out of [top]: an empty cell, then four steps.
  static Color _shade(int count, int top) {
    if (count == 0) return RpgColors.outline.withValues(alpha: 0.6);
    final step = (count / top * 4).ceil().clamp(1, 4);
    return RpgColors.gold.withValues(
      alpha: const [0.3, 0.5, 0.75, 1.0][step - 1],
    );
  }

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    final days = stats.recentWeeks;
    final top = math.max(1, days.whereType<int>().fold(0, math.max));
    final todayDate = DateUtils.dateOnly(today);
    final first = todayDate.subtract(
      Duration(
        days: todayDate.weekday - 1 + (CharacterStats.recentWeekCount - 1) * 7,
      ),
    );
    final format = DateFormat.MMMd();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const weeks = CharacterStats.recentWeekCount;
            final cell = math.min(
              22.0,
              (constraints.maxWidth - _gap * (weeks - 1)) / weeks,
            );
            return Row(
              children: [
                for (var week = 0; week < weeks; week++)
                  Padding(
                    padding: EdgeInsets.only(
                      right: week < weeks - 1 ? _gap : 0,
                    ),
                    child: Column(
                      children: [
                        for (var day = 0; day < 7; day++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: _gap),
                            child: () {
                              final count = days[week * 7 + day];
                              final date = DateTime(
                                first.year,
                                first.month,
                                first.day + week * 7 + day,
                              );
                              if (count == null) {
                                return SizedBox.square(dimension: cell);
                              }
                              return Tooltip(
                                message:
                                    '${format.format(date)}: $count check-in'
                                    '${count == 1 ? '' : 's'}',
                                child: Container(
                                  width: cell,
                                  height: cell,
                                  decoration: BoxDecoration(
                                    color: _shade(count, top),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              );
                            }(),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Less', style: styles.stat.copyWith(fontSize: 10)),
            const SizedBox(width: 4),
            for (final count in [0, 1, 2, 3, 4])
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _shade(count, 4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            const SizedBox(width: 4),
            Text('More', style: styles.stat.copyWith(fontSize: 10)),
          ],
        ),
      ],
    );
  }
}
