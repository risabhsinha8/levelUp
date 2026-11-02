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
import 'mid_month_reflection_card.dart';
import 'empty_prompt.dart';

/// "The Folio Spread": the month split into Half 1 and Half 2 habit grids
/// with the mid-month reflection between them.
class HabitMatrixView extends ConsumerStatefulWidget {
  const HabitMatrixView({super.key});

  @override
  ConsumerState<HabitMatrixView> createState() => _HabitMatrixViewState();
}

class _HabitMatrixViewState extends ConsumerState<HabitMatrixView> {
  /// The month being viewed, or null to follow the current month.
  DateTime? _pickedMonth;

  DateTime get _today => ref.read(todayProvider);

  DateTime get _month => _pickedMonth ?? _firstOfMonth(_today);

  set _month(DateTime month) =>
      _pickedMonth = month == _firstOfMonth(_today) ? null : month;

  static DateTime _firstOfMonth(DateTime date) =>
      DateTime(date.year, date.month);

  @override
  Widget build(BuildContext context) {
    ref.watch(todayProvider); // rebuild when the date rolls over
    final state = ref.watch(rpgStateProvider);
    final today = _today;
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    const split = ActiveHalfMonth.firstHalfLastDay;
    final isCurrentMonth = _month == _firstOfMonth(today);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              icon: const Icon(LucideIcons.chevronLeft, size: 18),
              onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month - 1),
              ),
            ),
            Expanded(
              child: Text(
                DateFormat.yMMMM().format(_month),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              icon: const Icon(LucideIcons.chevronRight, size: 18),
              onPressed: isCurrentMonth
                  ? null
                  : () => setState(
                      () => _month = DateTime(_month.year, _month.month + 1),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _HalfMatrixCard(
          title: 'Half 1',
          subtitle: 'Days 1–$split',
          state: state,
          month: _month,
          firstDay: 1,
          lastDay: split,
          today: today,
        ),
        if (isCurrentMonth)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton.icon(
              onPressed: () => showCampfireSheet(context),
              icon: const Icon(LucideIcons.flame, size: 16),
              label: const Text('Open Mid-Month Campfire'),
              style: OutlinedButton.styleFrom(
                foregroundColor: RpgColors.ember,
                side: BorderSide(color: RpgColors.ember.withValues(alpha: 0.6)),
                minimumSize: const Size.fromHeight(44),
              ),
            ),
          ),
        MidMonthReflectionCard(
          key: ValueKey(MonthReflection.keyFor(_month)),
          month: _month,
          daysInMonth: daysInMonth,
        ),
        _HalfMatrixCard(
          title: 'Half 2',
          subtitle: 'Days ${split + 1}–$daysInMonth',
          state: state,
          month: _month,
          firstDay: split + 1,
          lastDay: daysInMonth,
          today: today,
        ),
      ],
    );
  }
}

class _HalfMatrixCard extends ConsumerWidget {
  const _HalfMatrixCard({
    required this.title,
    required this.subtitle,
    required this.state,
    required this.month,
    required this.firstDay,
    required this.lastDay,
    required this.today,
  });

  final String title;
  final String subtitle;
  final RpgState state;
  final DateTime month;
  final int firstDay;
  final int lastDay;
  final DateTime today;

  static const double _nameWidth = 128;
  static const double _cell = 28;
  static const double _gap = 4;
  static const double _rowHeight = 36;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final styles = RpgStyles.of(context);
    final days = [
      for (var d = firstDay; d <= lastDay; d++)
        DateTime(month.year, month.month, d),
    ];
    final completedByDay = {for (final d in days) d: state.completedOn(d)};

    // Habits scheduled for this half, plus any with completions in it so no
    // logged history is ever hidden (e.g. after a pivot).
    final rows = [
      for (final branch in state.activeBranches)
        for (final h in state.habits)
          if (h.branch == branch &&
              ((!h.isArchived && h.activeHalfMonth.includes(days.first)) ||
                  completedByDay.values.any((ids) => ids.contains(h.id))))
            h,
    ];

    final halfRange = Season(
      id: 'half',
      name: title,
      startDate: days.first,
      endDate: days.last,
    );
    final branchDays = RpgEngine.calculateAllBranchActiveDays(
      state.habits,
      state.logs,
      season: halfRange,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(width: 8),
                Text(subtitle, style: styles.stat),
              ],
            ),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              const EmptyPrompt(
                icon: LucideIcons.layoutGrid,
                title: 'No habits scheduled for this half',
                message: "Add habits from Today's Focus to fill this spread.",
                compact: true,
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _nameWidth,
                    child: Column(
                      children: [
                        const SizedBox(height: _rowHeight),
                        for (final habit in rows) _HabitNameCell(habit: habit),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              for (final day in days)
                                _DayHeaderCell(
                                  day: day,
                                  isToday: DateUtils.isSameDay(day, today),
                                ),
                            ],
                          ),
                          for (final habit in rows)
                            Row(
                              children: [
                                for (final day in days)
                                  _MatrixCell(
                                    habit: habit,
                                    day: day,
                                    done: completedByDay[day]!.contains(
                                      habit.id,
                                    ),
                                    scheduled: habit.activeHalfMonth.includes(
                                      day,
                                    ),
                                    isToday: DateUtils.isSameDay(day, today),
                                    isFuture: day.isAfter(today),
                                    onTap: () async {
                                      HapticFeedback.lightImpact();
                                      await ref
                                          .read(rpgStoreProvider.notifier)
                                          .toggleHabitForDate(habit.id, day);
                                    },
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            Text(
              'Branch points this half',
              style: styles.stat.copyWith(fontSize: 10),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final branch in state.activeBranches)
                  _BranchTally(
                    branch: branch,
                    name: state.nameOf(branch),
                    days: branchDays[branch]!,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HabitNameCell extends StatelessWidget {
  const _HabitNameCell({required this.habit});

  final Habit habit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _HalfMatrixCard._rowHeight,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: habit.branch.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              habit.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: RpgColors.parchment),
            ),
          ),
          if (habit.isKeystone)
            const Padding(
              padding: EdgeInsets.only(left: 2),
              child: Icon(Icons.star_rounded, size: 14, color: RpgColors.gold),
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _DayHeaderCell extends StatelessWidget {
  const _DayHeaderCell({required this.day, required this.isToday});

  final DateTime day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final style = RpgStyles.of(context).stat;
    final color = isToday ? RpgColors.gold : RpgColors.ink;
    return SizedBox(
      width: _HalfMatrixCard._cell + _HalfMatrixCard._gap,
      height: _HalfMatrixCard._rowHeight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            DateFormat.E().format(day).substring(0, 1),
            style: style.copyWith(fontSize: 9, color: color),
          ),
          Text(
            '${day.day}',
            style: style.copyWith(
              fontSize: 11,
              color: color,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _MatrixCell extends StatelessWidget {
  const _MatrixCell({
    required this.habit,
    required this.day,
    required this.done,
    required this.scheduled,
    required this.isToday,
    required this.isFuture,
    required this.onTap,
  });

  final Habit habit;
  final DateTime day;
  final bool done;
  final bool scheduled;
  final bool isToday;
  final bool isFuture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = habit.branch.color;
    final border = isToday
        ? RpgColors.gold
        : done
        ? color
        : scheduled && !isFuture
        ? RpgColors.outline
        : RpgColors.outline.withValues(alpha: 0.35);
    return SizedBox(
      width: _HalfMatrixCard._cell + _HalfMatrixCard._gap,
      height: _HalfMatrixCard._rowHeight,
      child: Center(
        child: Semantics(
          button: true,
          checked: done,
          enabled: !isFuture,
          label: '${habit.title}, ${DateFormat.MMMd().format(day)}',
          child: InkWell(
            onTap: isFuture ? null : onTap,
            borderRadius: BorderRadius.circular(6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _HalfMatrixCard._cell,
              height: _HalfMatrixCard._cell,
              decoration: BoxDecoration(
                color: done ? color : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: border, width: isToday ? 1.5 : 1),
              ),
              child: done
                  ? const Icon(
                      LucideIcons.check,
                      size: 14,
                      color: RpgColors.obsidian,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _BranchTally extends StatelessWidget {
  const _BranchTally({
    required this.branch,
    required this.name,
    required this.days,
  });

  final BranchType branch;
  final String name;
  final int days;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: branch.color.withValues(alpha: 0.6)),
      ),
      child: Text(
        '$name $days',
        style: RpgStyles.of(
          context,
        ).stat.copyWith(fontSize: 10, color: branch.color),
      ),
    );
  }
}
