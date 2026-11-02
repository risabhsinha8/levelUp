import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/character_sheet.dart';
import '../domain/rpg_engine.dart';
import '../models/rpg_models.dart';
import '../models/rpg_state.dart';
import '../theme/rpg_theme.dart';

/// "Math it out": Base + Nodes + Feats = New Level for every branch.
class MathLedgerCard extends StatelessWidget {
  const MathLedgerCard({super.key, required this.state, required this.sheet});

  final RpgState state;
  final CharacterSheet sheet;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    final rows = [
      for (final branch in sheet.activeBranches)
        (
          branch: branch,
          base: state.configFor(branch).baseLevel,
          stats: sheet.branches[branch]!,
        ),
    ];
    final totalBase = rows.fold(0, (sum, r) => sum + r.base);
    final totalNodes = rows.fold(0, (sum, r) => sum + r.stats.forgedNodes);
    final totalFeats = rows.fold(0, (sum, r) => sum + r.stats.completedFeats);

    TextStyle num([Color color = RpgColors.parchment]) =>
        styles.stat.copyWith(fontSize: 14, color: color);
    Widget cell(String text, TextStyle style) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Text(text, textAlign: TextAlign.center, style: style),
    );

    return _LedgerCard(
      title: 'The Math Ledger',
      subtitle:
          '${state.currentSeason.name} · calculated automatically from your logs',
      child: Table(
        columnWidths: const {0: FlexColumnWidth(2.1)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: RpgColors.outline)),
            ),
            children: [
              cell('', styles.stat),
              for (final h in ['Base', '+Nodes', '+Feats', '=Lv'])
                cell(h, styles.stat.copyWith(fontSize: 10)),
            ],
          ),
          for (final r in rows)
            TableRow(
              children: [
                _BranchLabel(branch: r.branch, name: r.stats.name),
                cell('${r.base}', num(RpgColors.ink)),
                cell('+${r.stats.forgedNodes}', num()),
                cell('+${r.stats.completedFeats}', num()),
                cell(
                  '${r.stats.level}',
                  num(
                    r.branch.color,
                  ).copyWith(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ],
            ),
          TableRow(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: RpgColors.goldDim)),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'Character',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: RpgColors.gold),
                ),
              ),
              cell('$totalBase', num(RpgColors.ink)),
              cell('+$totalNodes', num()),
              cell('+$totalFeats', num()),
              cell(
                '${sheet.totalLevel}',
                num(
                  RpgColors.gold,
                ).copyWith(fontWeight: FontWeight.w700, fontSize: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Active days per branch in season months 1, 2 and 3.
class MonthBreakdownCard extends StatelessWidget {
  const MonthBreakdownCard({
    super.key,
    required this.state,
    required this.sheet,
    required this.today,
  });

  final RpgState state;
  final CharacterSheet sheet;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    final season = state.currentSeason;
    final currentMonth = RpgEngine.calculateSeasonMonthIndex(season, today);
    final windows = [
      for (var m = 1; m <= 3; m++) RpgEngine.seasonMonthWindow(season, m),
    ];
    final days = [
      for (final w in windows)
        RpgEngine.calculateAllBranchActiveDays(
          state.habits,
          state.logs,
          season: w,
        ),
    ];
    final todayDate = DateUtils.dateOnly(today);
    bool started(Season w) =>
        !DateUtils.dateOnly(w.startDate).isAfter(todayDate);
    final range = DateFormat.MMMd();

    TextStyle monthStyle(int m) => styles.stat.copyWith(
      fontSize: 14,
      color: m == currentMonth ? RpgColors.parchment : RpgColors.ink,
      fontWeight: m == currentMonth ? FontWeight.w700 : FontWeight.w500,
    );
    Widget cell(String text, TextStyle style, {bool highlight = false}) =>
        Container(
          color: highlight
              ? RpgColors.gold.withValues(alpha: 0.07)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Text(text, textAlign: TextAlign.center, style: style),
        );

    return _LedgerCard(
      title: 'Active Days by Month',
      subtitle: 'Max 1 point per branch per day',
      child: Table(
        columnWidths: const {0: FlexColumnWidth(2.1)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: RpgColors.outline)),
            ),
            children: [
              const SizedBox.shrink(),
              for (var m = 1; m <= 3; m++)
                Container(
                  color: m == currentMonth
                      ? RpgColors.gold.withValues(alpha: 0.07)
                      : Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      Text(
                        'M$m',
                        style: styles.stat.copyWith(
                          color: m == currentMonth
                              ? RpgColors.gold
                              : RpgColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      FittedBox(
                        child: Text(
                          '${range.format(windows[m - 1].startDate)}–'
                          '${range.format(windows[m - 1].endDate)}',
                          style: styles.stat.copyWith(fontSize: 8),
                        ),
                      ),
                    ],
                  ),
                ),
              cell('Total', styles.stat.copyWith(fontSize: 10)),
            ],
          ),
          for (final branch in sheet.activeBranches)
            TableRow(
              children: [
                _BranchLabel(branch: branch, name: state.nameOf(branch)),
                for (var m = 1; m <= 3; m++)
                  cell(
                    started(windows[m - 1]) ? '${days[m - 1][branch]}' : '—',
                    monthStyle(m),
                    highlight: m == currentMonth,
                  ),
                cell(
                  '${sheet.branches[branch]!.activeDays}',
                  styles.stat.copyWith(
                    fontSize: 14,
                    color: branch.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _BranchLabel extends StatelessWidget {
  const _BranchLabel({required this.branch, required this.name});

  final BranchType branch;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: branch.color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _LedgerCard extends StatelessWidget {
  const _LedgerCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: RpgStyles.of(context).stat.copyWith(fontSize: 10),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
