import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../domain/rpg_engine.dart';
import '../models/rpg_models.dart';
import '../models/rpg_state.dart';
import '../providers/rpg_store_provider.dart';
import '../theme/rpg_theme.dart';
import 'campfire_sheet.dart';
import 'habit_editor_sheet.dart';
import 'empty_prompt.dart';

/// "Today's Focus": Survival Mode switch, week strip, keystone banner and
/// habits grouped by branch.
class TodayFocusView extends ConsumerStatefulWidget {
  const TodayFocusView({super.key});

  @override
  ConsumerState<TodayFocusView> createState() => _TodayFocusViewState();
}

class _TodayFocusViewState extends ConsumerState<TodayFocusView> {
  /// The day being viewed, or null to follow today (also across midnight).
  DateTime? _picked;

  DateTime get _today => ref.read(todayProvider);

  DateTime get _selected => _picked ?? _today;

  set _selected(DateTime date) =>
      _picked = DateUtils.isSameDay(date, _today) ? null : date;

  Future<void> _toggle(RpgState state, Habit habit) async {
    final completed = state.completedOn(_selected);
    final branchWasSecured = state
        .habitsFor(habit.branch)
        .any((h) => completed.contains(h.id));
    final checking = !completed.contains(habit.id);
    if (checking && !branchWasSecured) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
    await ref
        .read(rpgStoreProvider.notifier)
        .toggleHabitForDate(habit.id, _selected);
  }

  Future<void> _toggleKeystone(RpgState state, Habit habit) async {
    final messenger = ScaffoldMessenger.of(context);
    HapticFeedback.selectionClick();
    final makeKeystone = !habit.isKeystone;
    final previous = state.keystoneFor(habit.branch);
    await ref
        .read(rpgStoreProvider.notifier)
        .setKeystone(habit.id, isKeystone: makeKeystone);
    final branch = habit.branch.displayName;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            makeKeystone
                ? '★ ${habit.title} is now the $branch keystone'
                      '${previous == null ? '' : ' (was ${previous.title})'}.'
                : '${habit.title} is no longer the $branch keystone.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(todayProvider); // rebuild when the date rolls over
    final state = ref.watch(rpgStateProvider);
    final completed = state.completedOn(_selected);
    final habits = state.habitsShownOn(_selected);
    final survival = ref.watch(survivalModeProvider);
    bool shown(Habit h) => !survival || (h.isKeystone && !h.isArchived);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _SurvivalModeSwitch(
          on: survival,
          onChanged: (on) {
            HapticFeedback.selectionClick();
            ref.read(survivalModeDateProvider.notifier).set(on: on);
          },
        ),
        _Collapsible(visible: survival, child: const _SurvivalBanner()),
        if (RpgEngine.isCampfireDay(_today)) ...[
          const SizedBox(height: 12),
          const CampfireBanner(),
        ],
        const SizedBox(height: 12),
        _WeekStrip(
          state: state,
          selected: _selected,
          today: _today,
          onSelected: (date) => setState(() => _selected = date),
        ),
        const SizedBox(height: 12),
        _KeystoneBanner(
          keystones: [
            for (final h in habits)
              if (h.isKeystone && !h.isArchived) h,
          ],
          completed: completed,
          isToday: DateUtils.isSameDay(_selected, _today),
        ),
        const SizedBox(height: 12),
        if (habits.isEmpty)
          const _EmptyHabits()
        else ...[
          for (final branch in BranchType.values)
            if (habits.any((h) => h.branch == branch))
              _Collapsible(
                visible: habits.any((h) => h.branch == branch && shown(h)),
                child: _BranchCard(
                  branch: branch,
                  habits: [
                    for (final h in habits)
                      if (h.branch == branch) h,
                  ],
                  isShown: shown,
                  completed: completed,
                  onToggle: (habit) => _toggle(state, habit),
                  onToggleKeystone: (habit) => _toggleKeystone(state, habit),
                ),
              ),
          OutlinedButton.icon(
            onPressed: () => showHabitEditor(context),
            icon: const Icon(LucideIcons.plus, size: 16),
            label: const Text('Add Habit'),
            style: OutlinedButton.styleFrom(
              foregroundColor: RpgColors.gold,
              side: const BorderSide(color: RpgColors.goldDim),
              minimumSize: const Size.fromHeight(44),
            ),
          ),
        ],
      ],
    );
  }
}

/// Smoothly folds [child] away (fading and shrinking) when not [visible].
class _Collapsible extends StatelessWidget {
  const _Collapsible({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          axisAlignment: -1,
          child: child,
        ),
      ),
      child: visible
          ? KeyedSubtree(key: const ValueKey(true), child: child)
          : const SizedBox(key: ValueKey(false), width: double.infinity),
    );
  }
}

/// "Minimum Viable Day": on low-energy days show only the ★ keystones.
class _SurvivalModeSwitch extends StatelessWidget {
  const _SurvivalModeSwitch({required this.on, required this.onChanged});

  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: on ? RpgColors.gold.withValues(alpha: 0.1) : RpgColors.slate,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: on ? RpgColors.gold : RpgColors.outline),
      ),
      child: SwitchListTile(
        value: on,
        onChanged: onChanged,
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        secondary: Icon(
          LucideIcons.batteryLow,
          color: on ? RpgColors.gold : RpgColors.ink,
        ),
        title: Text(
          'Survival Mode (Low Energy)',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: on ? RpgColors.gold : RpgColors.parchment,
          ),
        ),
        subtitle: Text(
          on ? 'Showing only your ★ keystones' : 'Show only your ★ keystones',
          style: styles.stat.copyWith(fontSize: 11),
        ),
      ),
    );
  }
}

class _SurvivalBanner extends StatelessWidget {
  const _SurvivalBanner();

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RpgColors.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RpgColors.goldDim),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.heartPulse, size: 18, color: RpgColors.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Survival Mode Active: Just secure your ★ Keystones today. '
              '1 Keystone = +1 Full Branch Active Day.',
              style: styles.stat.copyWith(color: RpgColors.parchment),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.state,
    required this.selected,
    required this.today,
    required this.onSelected,
  });

  final RpgState state;
  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onSelected;

  static DateTime _weekStart(DateTime date) =>
      DateTime(date.year, date.month, date.day - (date.weekday - 1));

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    final start = _weekStart(selected);
    final days = [
      for (var i = 0; i < 7; i++)
        DateTime(start.year, start.month, start.day + i),
    ];
    final nextWeek = DateTime(start.year, start.month, start.day + 7);

    return Row(
      children: [
        IconButton(
          tooltip: 'Previous week',
          visualDensity: VisualDensity.compact,
          icon: const Icon(LucideIcons.chevronLeft, size: 18),
          onPressed: () => onSelected(
            DateTime(selected.year, selected.month, selected.day - 7),
          ),
        ),
        for (final day in days)
          Expanded(
            child: _DayChip(
              date: day,
              isSelected: DateUtils.isSameDay(day, selected),
              isToday: DateUtils.isSameDay(day, today),
              isFuture: day.isAfter(today),
              activeBranches: _activeBranches(day),
              style: styles.stat,
              onTap: () => onSelected(day),
            ),
          ),
        IconButton(
          tooltip: 'Next week',
          visualDensity: VisualDensity.compact,
          icon: const Icon(LucideIcons.chevronRight, size: 18),
          onPressed: nextWeek.isAfter(today)
              ? null
              : () {
                  final target = DateTime(
                    selected.year,
                    selected.month,
                    selected.day + 7,
                  );
                  onSelected(target.isAfter(today) ? today : target);
                },
        ),
      ],
    );
  }

  List<BranchType> _activeBranches(DateTime day) {
    final done = state.completedOn(day);
    return [
      for (final branch in BranchType.values)
        if (state.habitsFor(branch).any((h) => done.contains(h.id))) branch,
    ];
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.date,
    required this.isSelected,
    required this.isToday,
    required this.isFuture,
    required this.activeBranches,
    required this.style,
    required this.onTap,
  });

  final DateTime date;
  final bool isSelected;
  final bool isToday;
  final bool isFuture;
  final List<BranchType> activeBranches;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = isFuture
        ? RpgColors.outline
        : isSelected
        ? RpgColors.obsidian
        : RpgColors.parchment;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Semantics(
        button: true,
        selected: isSelected,
        label: DateFormat.MMMEd().format(date),
        child: InkWell(
          onTap: isFuture ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? RpgColors.gold : RpgColors.slate,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isToday && !isSelected
                    ? RpgColors.gold
                    : RpgColors.outline,
              ),
            ),
            child: ExcludeSemantics(
              child: Column(
                children: [
                  Text(
                    DateFormat.E().format(date).substring(0, 2),
                    style: style.copyWith(fontSize: 10, color: foreground),
                  ),
                  Text(
                    '${date.day}',
                    style: style.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: foreground,
                    ),
                  ),
                  const SizedBox(height: 3),
                  SizedBox(
                    height: 4,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final branch in activeBranches)
                          Container(
                            width: 4,
                            height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 0.5),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? RpgColors.obsidian
                                  : branch.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KeystoneBanner extends StatelessWidget {
  const _KeystoneBanner({
    required this.keystones,
    required this.completed,
    required this.isToday,
  });

  final List<Habit> keystones;
  final Set<String> completed;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = RpgStyles.of(context);
    final done = keystones.where((h) => completed.contains(h.id)).length;
    final total = keystones.length;
    final allDone = total > 0 && done == total;

    final message = total == 0
        ? 'Star one habit per branch as its daily non-negotiable.'
        : allDone
        ? 'Every non-negotiable secured. Legendary discipline.'
        : '${total - done} non-negotiable${total - done == 1 ? '' : 's'} '
              'left ${isToday ? 'today' : 'that day'}.';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RpgColors.slate,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: allDone ? RpgColors.gold : RpgColors.goldDim,
          width: allDone ? 1.5 : 1,
        ),
        gradient: LinearGradient(
          colors: [
            RpgColors.gold.withValues(alpha: allDone ? 0.18 : 0.08),
            RpgColors.slate,
          ],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Keystone Priority',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: RpgColors.gold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(message, style: styles.stat),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  children: [
                    for (final h in keystones)
                      Tooltip(
                        message: '${h.branch.displayName}: ${h.title}',
                        child: Icon(
                          Icons.star_rounded,
                          size: 20,
                          color: completed.contains(h.id)
                              ? RpgColors.gold
                              : RpgColors.outline,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            '$done/$total',
            semanticsLabel: '$done of $total keystones done',
            style: styles.statLarge.copyWith(
              fontSize: 28,
              color: allDone ? RpgColors.gold : RpgColors.parchment,
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  const _BranchCard({
    required this.branch,
    required this.habits,
    required this.isShown,
    required this.completed,
    required this.onToggle,
    required this.onToggleKeystone,
  });

  final BranchType branch;
  final List<Habit> habits;

  /// Habits hidden by Survival Mode fold away but still count when done.
  final bool Function(Habit) isShown;
  final Set<String> completed;
  final ValueChanged<Habit> onToggle;
  final ValueChanged<Habit> onToggleKeystone;

  @override
  Widget build(BuildContext context) {
    final secured = habits.any((h) => completed.contains(h.id));
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 4, 2, 4),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: branch.color, width: 3),
                bottom: const BorderSide(color: RpgColors.outline),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    branch.displayName,
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: branch.color),
                  ),
                ),
                _BranchPointPill(color: branch.color, secured: secured),
                IconButton(
                  tooltip: 'Add ${branch.displayName} habit',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(LucideIcons.plus, size: 18, color: branch.color),
                  onPressed: () => showHabitEditor(context, branch: branch),
                ),
              ],
            ),
          ),
          for (final habit in habits)
            _Collapsible(
              visible: isShown(habit),
              child: _HabitTile(
                habit: habit,
                done: completed.contains(habit.id),
                onTap: () => onToggle(habit),
                onToggleKeystone: () => onToggleKeystone(habit),
                onEdit: () => showHabitEditor(context, habit: habit),
              ),
            ),
        ],
      ),
    );
  }
}

class _BranchPointPill extends StatelessWidget {
  const _BranchPointPill({required this.color, required this.secured});

  final Color color;
  final bool secured;

  @override
  Widget build(BuildContext context) {
    final style = RpgStyles.of(context).stat.copyWith(fontSize: 11);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: secured ? color.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: secured ? color : RpgColors.outline),
        boxShadow: secured
            ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10)]
            : const [],
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Text(
          secured ? '+1 Branch Point Secured' : 'No point yet',
          key: ValueKey(secured),
          style: style.copyWith(
            color: secured ? color : RpgColors.ink,
            fontWeight: secured ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _HabitTile extends StatelessWidget {
  const _HabitTile({
    required this.habit,
    required this.done,
    required this.onTap,
    required this.onToggleKeystone,
    required this.onEdit,
  });

  final Habit habit;
  final bool done;
  final VoidCallback onTap;
  final VoidCallback onToggleKeystone;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final color = habit.branch.color;
    return Semantics(
      checked: done,
      child: InkWell(
        onTap: onTap,
        onLongPress: habit.isArchived ? null : onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: done ? color : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: done ? color : RpgColors.ink,
                    width: 1.5,
                  ),
                ),
                child: done
                    ? const Icon(
                        LucideIcons.check,
                        size: 16,
                        color: RpgColors.obsidian,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      habit.title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        decoration: done ? TextDecoration.lineThrough : null,
                        decorationColor: RpgColors.ink,
                        color: done ? RpgColors.ink : RpgColors.parchment,
                      ),
                    ),
                    if (habit.targetCriteria.isNotEmpty || habit.isArchived)
                      Text(
                        habit.isArchived
                            ? 'Deleted · past check-ins still count'
                            : habit.targetCriteria,
                        style: RpgStyles.of(context).stat,
                      ),
                  ],
                ),
              ),
              if (habit.isArchived)
                const SizedBox(width: 8)
              else ...[
                IconButton(
                  tooltip: habit.isKeystone
                      ? 'Remove keystone star'
                      : 'Make keystone',
                  onPressed: onToggleKeystone,
                  icon: Icon(
                    habit.isKeystone
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: habit.isKeystone
                        ? RpgColors.gold
                        : RpgColors.outline,
                    size: 22,
                  ),
                ),
                IconButton(
                  tooltip: 'Edit ${habit.title}',
                  onPressed: onEdit,
                  icon: const Icon(
                    LucideIcons.pencil,
                    size: 16,
                    color: RpgColors.ink,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyHabits extends StatelessWidget {
  const _EmptyHabits();

  @override
  Widget build(BuildContext context) {
    return EmptyPrompt(
      icon: LucideIcons.scrollText,
      title: 'No habits on the sheet yet',
      message:
          'Your character sheet is blank. Add a habit to start earning '
          'branch points.',
      actionLabel: 'Add your first habit',
      onAction: () => showHabitEditor(context),
    );
  }
}
