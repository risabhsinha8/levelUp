import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../domain/history.dart';
import '../models/rpg_models.dart';
import '../providers/rpg_store_provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/empty_prompt.dart';
import '../widgets/oath_signature_card.dart';
import '../widgets/stat_tiles.dart';
import 'habit_history_screen.dart';

/// Opens the record of a completed season (from the Hall of Seasons).
Future<void> openSeasonDetail(BuildContext context, String seasonId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SeasonDetailScreen(seasonId: seasonId),
      ),
    );

/// A past season (sprint) as it was played: levels, pillars, quests, the
/// habits done, loot claimed, reflections and the signed oath.
class SeasonDetailScreen extends ConsumerWidget {
  const SeasonDetailScreen({super.key, required this.seasonId});

  final String seasonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(rpgStateProvider);
    final season = state.seasons.firstWhere((s) => s.id == seasonId);
    final record = SeasonRecord.of(state, season);
    final summary = season.summary;
    final styles = RpgStyles.of(context);
    final dates = DateFormat.yMMMd();

    return Scaffold(
      backgroundColor: RpgColors.obsidian,
      appBar: AppBar(
        backgroundColor: RpgColors.obsidian,
        surfaceTintColor: Colors.transparent,
        title: Text(season.name),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            '${dates.format(season.startDate)} – '
            '${dates.format(season.endDate)}',
            style: styles.stat,
          ),
          const SizedBox(height: 12),
          StatTileGrid(
            columns: 3,
            tiles: [
              StatTile(
                icon: LucideIcons.trendingUp,
                value: summary == null
                    ? '—'
                    : '${summary.startLevel}→${summary.endLevel}',
                label: 'Character level',
              ),
              StatTile(
                icon: LucideIcons.sparkles,
                value:
                    '${summary?.branches.values.fold(0, (sum, b) => sum + b.activeDays) ?? 0}',
                label: 'Branch days',
              ),
              StatTile(
                icon: LucideIcons.crown,
                value:
                    '${record.quests.where((q) => q.isCompleted).length}'
                    '/${record.quests.length}',
                label: 'Quests done',
              ),
            ],
          ),
          StatSection(
            title: 'Pillars',
            child: summary == null || summary.branches.isEmpty
                ? const EmptyPrompt(
                    icon: LucideIcons.network,
                    title: 'No tally recorded',
                    message: 'This season was completed before tallies.',
                    compact: true,
                  )
                : Column(
                    children: [
                      for (final branch in BranchType.values)
                        if (summary.branches[branch] case final result?)
                          _PillarResultRow(
                            branch: branch,
                            name: state.nameOf(branch),
                            result: result,
                          ),
                    ],
                  ),
          ),
          StatSection(
            title: 'Habits',
            subtitle: 'Days each habit was done',
            child: record.habits.isEmpty
                ? const EmptyPrompt(
                    icon: LucideIcons.calendarX,
                    title: 'No check-ins this season',
                    message: 'Nothing was logged between these dates.',
                    compact: true,
                  )
                : Column(
                    children: [
                      for (final (:habit, :days) in record.habits)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            habit.hasKeystoneHistory
                                ? Icons.star_rounded
                                : Icons.circle,
                            size: habit.hasKeystoneHistory ? 18 : 10,
                            color: habit.branch.color,
                          ),
                          title: Text(
                            habit.isArchived
                                ? '${habit.title} (archived)'
                                : habit.title,
                          ),
                          subtitle: Text(
                            state.nameOf(habit.branch),
                            style: styles.stat.copyWith(fontSize: 10),
                          ),
                          trailing: Text(
                            '${days}d',
                            style: styles.stat.copyWith(
                              color: RpgColors.parchment,
                            ),
                          ),
                          onTap: () => openHabitDetail(context, habit.id),
                        ),
                    ],
                  ),
          ),
          StatSection(
            title: 'Quests',
            child: record.quests.isEmpty
                ? const EmptyPrompt(
                    icon: LucideIcons.swords,
                    title: 'No quests this season',
                    message: 'Quests you set in a season are kept here.',
                    compact: true,
                  )
                : Column(
                    children: [
                      for (final quest in record.quests)
                        _QuestRow(
                          quest: quest,
                          pillar: state.nameOf(quest.branch),
                        ),
                    ],
                  ),
          ),
          StatSection(
            title: 'Loot Claimed',
            child: record.lootClaimed.isEmpty
                ? const EmptyPrompt(
                    icon: LucideIcons.gift,
                    title: 'No loot claimed',
                    message: 'Keys from this season went unspent.',
                    compact: true,
                  )
                : Column(
                    children: [
                      for (final item in record.lootClaimed)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            LucideIcons.gift,
                            size: 18,
                            color: item.tier.color,
                          ),
                          title: Text(item.title),
                          trailing: Text(
                            '${item.tier.label} · '
                            '${DateFormat.MMMd().format(parseDateString(item.claimedAtDate!))}',
                            style: styles.stat.copyWith(fontSize: 11),
                          ),
                        ),
                    ],
                  ),
          ),
          if (record.reflections.isNotEmpty)
            StatSection(
              title: 'Reflections',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final r in record.reflections)
                    _ReflectionBlock(reflection: r),
                ],
              ),
            ),
          if (season.oath case final oath?)
            StatSection(
              title: 'Seasonal Oath',
              subtitle:
                  'Signed ${DateFormat.yMMMd().format(parseDateString(oath.signedAtDate))}',
              child: AspectRatio(
                aspectRatio: 3,
                child: CustomPaint(
                  painter: SignaturePainter(
                    strokes: [
                      for (final stroke in oath.strokes)
                        [
                          for (var i = 0; i + 1 < stroke.length; i += 2)
                            Offset(stroke[i], stroke[i + 1]),
                        ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PillarResultRow extends StatelessWidget {
  const _PillarResultRow({
    required this.branch,
    required this.name,
    required this.result,
  });

  final BranchType branch;
  final String name;
  final BranchSeasonResult result;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(branch.icon, size: 16, color: branch.color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: styles.stat.copyWith(color: RpgColors.parchment),
                ),
                Text(
                  '${result.activeDays}d · ${result.nodes} node'
                  '${result.nodes == 1 ? '' : 's'} · ${result.feats} feat'
                  '${result.feats == 1 ? '' : 's'}',
                  style: styles.stat.copyWith(fontSize: 10),
                ),
              ],
            ),
          ),
          Text(
            'Lv ${result.startLevel} → ${result.endLevel}',
            style: styles.stat.copyWith(color: RpgColors.parchment),
          ),
        ],
      ),
    );
  }
}

class _QuestRow extends StatelessWidget {
  const _QuestRow({required this.quest, required this.pillar});

  final Quest quest;
  final String pillar;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        quest.isCompleted ? LucideIcons.checkCircle2 : LucideIcons.circle,
        size: 18,
        color: quest.isCompleted ? quest.branch.color : RpgColors.ink,
      ),
      title: Text(quest.title),
      subtitle: Text(
        '${quest.isMainQuest ? 'Main quest' : 'Side quest'} · '
        'Month ${quest.monthIndex} · $pillar',
        style: styles.stat.copyWith(fontSize: 10),
      ),
    );
  }
}

class _ReflectionBlock extends StatelessWidget {
  const _ReflectionBlock({required this.reflection});

  final MonthReflection reflection;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    final month = DateFormat.yMMMM().format(
      parseDateString('${reflection.monthKey}-01'),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(month, style: styles.stat.copyWith(color: RpgColors.ember)),
          if (reflection.notes.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                reflection.notes.trim(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          for (final pivot in reflection.pivots)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Pivot: $pivot', style: styles.stat),
            ),
        ],
      ),
    );
  }
}
