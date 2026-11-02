import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../domain/history.dart';
import '../models/rpg_models.dart';
import '../models/rpg_state.dart';
import '../providers/rpg_store_provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/empty_prompt.dart';
import '../widgets/stat_tiles.dart';

/// Opens the list of every habit, active and archived.
Future<void> openHabitHistory(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const HabitHistoryScreen()));

/// Opens one habit's lifetime history.
Future<void> openHabitDetail(BuildContext context, String habitId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HabitDetailScreen(habitId: habitId),
      ),
    );

/// Archives [habit] and offers Undo.
Future<void> archiveHabitWithUndo(
  BuildContext context,
  WidgetRef ref,
  Habit habit,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final store = ref.read(rpgStoreProvider.notifier);
  HapticFeedback.mediumImpact();
  await store.archiveHabit(habit.id);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('Archived "${habit.title}".'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => store.restoreHabit(habit.id),
        ),
      ),
    );
}

/// Restores [habit] to the daily list.
Future<void> restoreHabitWithMessage(
  BuildContext context,
  WidgetRef ref,
  Habit habit,
) async {
  final messenger = ScaffoldMessenger.of(context);
  HapticFeedback.selectionClick();
  await ref.read(rpgStoreProvider.notifier).restoreHabit(habit.id);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text('Restored "${habit.title}" to your daily list.')),
    );
}

/// Every habit with its lifetime days: active ones by pillar, then the
/// archive (with Restore).
class HabitHistoryScreen extends ConsumerWidget {
  const HabitHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(rpgStateProvider);
    final active = state.activeHabits;
    final archived = [
      for (final h in state.habits)
        if (!active.contains(h)) h,
    ];

    return Scaffold(
      backgroundColor: RpgColors.obsidian,
      appBar: AppBar(
        backgroundColor: RpgColors.obsidian,
        surfaceTintColor: Colors.transparent,
        title: const Text('Habit History'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          StatSection(
            title: 'Active',
            subtitle: 'Lifetime days done',
            child: active.isEmpty
                ? const EmptyPrompt(
                    icon: LucideIcons.sprout,
                    title: 'No active habits',
                    message: "Add one from Today's Focus.",
                    compact: true,
                  )
                : Column(
                    children: [
                      for (final branch in state.activeBranches)
                        for (final habit in active)
                          if (habit.branch == branch)
                            _HabitRow(state: state, habit: habit),
                    ],
                  ),
          ),
          StatSection(
            title: 'Archived',
            subtitle: 'Their check-ins still count toward your pillars',
            child: archived.isEmpty
                ? const EmptyPrompt(
                    icon: LucideIcons.archive,
                    title: 'Nothing archived',
                    message:
                        'Archive a habit from its editor to retire it '
                        'without losing its history.',
                    compact: true,
                  )
                : Column(
                    children: [
                      for (final habit in archived)
                        _HabitRow(state: state, habit: habit),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _HabitRow extends ConsumerWidget {
  const _HabitRow({required this.state, required this.habit});

  final RpgState state;
  final Habit habit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final styles = RpgStyles.of(context);
    final history = HabitHistory.of(state, habit);
    final resting = !state.configFor(habit.branch).isEnabled;
    final last = history.lastDate == null
        ? 'never done'
        : 'last ${DateFormat.MMMd().format(parseDateString(history.lastDate!))}';
    return ListTile(
      key: ValueKey('habit-history-${habit.id}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        habit.isKeystone ? Icons.star_rounded : Icons.circle,
        size: habit.isKeystone ? 20 : 10,
        color: habit.isKeystone ? RpgColors.gold : habit.branch.color,
      ),
      title: Text(habit.title),
      subtitle: Text(
        '${state.nameOf(habit.branch)}${resting ? ' (resting)' : ''} · '
        '${history.totalDays}d · $last',
        style: styles.stat.copyWith(fontSize: 11),
      ),
      trailing: habit.isArchived
          ? TextButton(
              key: ValueKey('restore-${habit.id}'),
              onPressed: resting
                  ? null
                  : () => restoreHabitWithMessage(context, ref, habit),
              child: const Text('Restore'),
            )
          : const Icon(LucideIcons.chevronRight, size: 18),
      onTap: () => openHabitDetail(context, habit.id),
    );
  }
}

/// One habit across its whole life: totals, best run, seasons, keystone
/// stretches and a calendar of every month since its first check-in.
class HabitDetailScreen extends ConsumerWidget {
  const HabitDetailScreen({super.key, required this.habitId});

  final String habitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(rpgStateProvider);
    final today = ref.watch(todayProvider);
    final habit = state.habits.where((h) => h.id == habitId).firstOrNull;
    final styles = RpgStyles.of(context);
    if (habit == null) {
      // Deleted while open.
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }
    final history = HabitHistory.of(state, habit);
    final shortDate = DateFormat.yMMMd();
    String format(String? date) =>
        date == null ? '—' : shortDate.format(parseDateString(date));
    final resting = !state.configFor(habit.branch).isEnabled;
    final done = history.doneDates.toSet();

    return Scaffold(
      backgroundColor: RpgColors.obsidian,
      appBar: AppBar(
        backgroundColor: RpgColors.obsidian,
        surfaceTintColor: Colors.transparent,
        title: Text(habit.title),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Chip(
                icon: habit.branch.icon,
                label: state.nameOf(habit.branch),
                color: habit.branch.color,
              ),
              if (habit.isKeystone)
                const _Chip(
                  icon: Icons.star_rounded,
                  label: 'Keystone',
                  color: RpgColors.gold,
                ),
              if (habit.isArchived)
                const _Chip(
                  icon: LucideIcons.archive,
                  label: 'Archived',
                  color: RpgColors.ink,
                ),
              if (habit.targetCriteria.isNotEmpty)
                Text(habit.targetCriteria, style: styles.stat),
            ],
          ),
          const SizedBox(height: 12),
          StatTileGrid(
            columns: 2,
            tiles: [
              StatTile(
                icon: LucideIcons.checkCircle2,
                value: '${history.totalDays}',
                label: 'Days done',
              ),
              StatTile(
                icon: LucideIcons.footprints,
                value: '${history.bestRun}',
                label: 'Best run (days)',
              ),
              StatTile(
                icon: LucideIcons.flag,
                value: format(history.firstDate),
                label: 'First done',
              ),
              StatTile(
                icon: LucideIcons.history,
                value: format(history.lastDate),
                label: 'Last done',
              ),
            ],
          ),
          if (habit.keystonePeriods.isNotEmpty)
            StatSection(
              title: 'Keystone Stretches',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final p in habit.keystonePeriods)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        '★ ${p.from == null ? 'From the start' : format(p.from)}'
                        ' – ${p.to == null ? 'now' : format(p.to)}',
                        style: styles.stat.copyWith(color: RpgColors.parchment),
                      ),
                    ),
                ],
              ),
            ),
          StatSection(
            title: 'By Season',
            child: history.perSeason.isEmpty
                ? const EmptyPrompt(
                    icon: LucideIcons.calendarX,
                    title: 'Not done yet',
                    message: 'Seasons appear here once it is checked off.',
                    compact: true,
                  )
                : Column(
                    children: [
                      for (final entry in history.perSeason)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  entry.season.name,
                                  style: styles.stat.copyWith(
                                    color: RpgColors.parchment,
                                  ),
                                ),
                              ),
                              Text('${entry.days}d', style: styles.stat),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          StatSection(
            title: 'Lifetime Calendar',
            child: Column(
              children: [
                for (final month in history.months(today))
                  _MonthCalendar(
                    month: month,
                    done: done,
                    today: today,
                    color: habit.branch.color,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (habit.isArchived)
            FilledButton.icon(
              key: const ValueKey('detail-restore'),
              onPressed: resting
                  ? null
                  : () => restoreHabitWithMessage(context, ref, habit),
              icon: const Icon(LucideIcons.archiveRestore, size: 18),
              label: Text(
                resting
                    ? 'Restore (pillar is resting)'
                    : 'Restore to Daily List',
              ),
            )
          else
            OutlinedButton.icon(
              key: const ValueKey('detail-archive'),
              onPressed: () => archiveHabitWithUndo(context, ref, habit),
              icon: const Icon(LucideIcons.archive, size: 18),
              label: const Text('Archive Habit'),
              style: OutlinedButton.styleFrom(
                foregroundColor: RpgColors.ink,
                side: const BorderSide(color: RpgColors.outline),
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: RpgStyles.of(
              context,
            ).stat.copyWith(fontSize: 11, color: RpgColors.parchment),
          ),
        ],
      ),
    );
  }
}

/// A Monday-first month grid; done days filled in the pillar's color.
class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.done,
    required this.today,
    required this.color,
  });

  final DateTime month;
  final Set<String> done;
  final DateTime today;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final lead = DateTime.utc(month.year, month.month).weekday - 1;
    final todayString = toDateString(today);
    String dateOf(int day) =>
        toDateString(DateTime.utc(month.year, month.month, day));
    final count = [
      for (var d = 1; d <= days; d++)
        if (done.contains(dateOf(d))) d,
    ].length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${DateFormat.yMMMM().format(month)} · ${count}d',
            style: styles.stat.copyWith(color: RpgColors.parchment),
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 3.0;
              // Floored so seven cells always fit one row.
              final cell = ((constraints.maxWidth - gap * 6) / 7)
                  .clamp(0.0, 28.0)
                  .floorToDouble();
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (var i = 0; i < lead; i++)
                    SizedBox.square(dimension: cell),
                  for (var d = 1; d <= days; d++)
                    Tooltip(
                      message:
                          '${DateFormat.MMMd().format(DateTime(month.year, month.month, d))}'
                          '${done.contains(dateOf(d)) ? ' · done' : ''}',
                      child: Container(
                        width: cell,
                        height: cell,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: done.contains(dateOf(d))
                              ? color
                              : dateOf(d).compareTo(todayString) > 0
                              ? Colors.transparent
                              : RpgColors.outline.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(4),
                          border: dateOf(d) == todayString
                              ? Border.all(color: RpgColors.gold)
                              : null,
                        ),
                        child: Text(
                          '$d',
                          style: styles.stat.copyWith(
                            fontSize: 9,
                            color: done.contains(dateOf(d))
                                ? RpgColors.obsidian
                                : RpgColors.ink,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
