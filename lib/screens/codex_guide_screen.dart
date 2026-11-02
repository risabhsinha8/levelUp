import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../domain/character_sheet.dart';
import '../domain/rpg_engine.dart';
import '../models/rpg_models.dart';
import '../models/rpg_state.dart';
import '../providers/rpg_store_provider.dart';
import '../theme/rpg_theme.dart';

/// Opens the Adventurer's Codex from anywhere under [HomeShell].
Future<void> openCodex(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const CodexGuideScreen()));

/// The Adventurer's Codex: the scoring rules as four illustrated cards,
/// with a live leveling preview from the current character.
class CodexGuideScreen extends ConsumerWidget {
  const CodexGuideScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(rpgStoreProvider).value;
    final sheet = ref.watch(characterSheetProvider).value;

    return Scaffold(
      backgroundColor: RpgColors.obsidian,
      appBar: AppBar(
        backgroundColor: RpgColors.obsidian,
        surfaceTintColor: Colors.transparent,
        title: const Text("Adventurer's Codex"),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'How every point, node and key is earned.',
            style: RpgStyles.of(context).stat,
          ),
          const SizedBox(height: 12),
          const _GoldenRuleCard(),
          _SkillTreeCard(sheet: sheet),
          _FormulaCard(state: state, sheet: sheet),
          _LootCard(sheet: sheet),
        ],
      ),
    );
  }
}

/// Shared frame for a numbered codex page.
class _CodexCard extends StatelessWidget {
  const _CodexCard({
    required this.chapter,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String chapter;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = RpgStyles.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: RpgColors.goldDim),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: RpgColors.gold.withValues(alpha: 0.12),
                    border: Border.all(color: RpgColors.goldDim),
                  ),
                  child: Icon(icon, size: 18, color: RpgColors.gold),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chapter.toUpperCase(),
                        style: styles.stat.copyWith(
                          fontSize: 10,
                          letterSpacing: 1.2,
                          color: RpgColors.goldDim,
                        ),
                      ),
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: RpgColors.gold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(subtitle, style: styles.stat),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// a. The Golden Rule
// ---------------------------------------------------------------------------

class _GoldenRuleCard extends StatefulWidget {
  const _GoldenRuleCard();

  @override
  State<_GoldenRuleCard> createState() => _GoldenRuleCardState();
}

class _GoldenRuleCardState extends State<_GoldenRuleCard> {
  int _habits = 1;

  static const _bodyHabits = ['★ Exercise', 'Water', 'Sleep'];

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    final body = BranchType.body.color;
    return _CodexCard(
      chapter: 'Chapter I',
      icon: LucideIcons.sparkles,
      title: 'The Golden Rule',
      subtitle: '1 point per branch per day, however many habits you finish.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: body.withValues(alpha: 0.16),
                selectedForegroundColor: body,
                foregroundColor: RpgColors.ink,
                side: const BorderSide(color: RpgColors.outline),
                textStyle: styles.stat.copyWith(fontSize: 12),
              ),
              segments: const [
                ButtonSegment(value: 1, label: Text('1 habit (★ only)')),
                ButtonSegment(value: 3, label: Text('3 habits')),
              ],
              selected: {_habits},
              onSelectionChanged: (s) => setState(() => _habits = s.single),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < _bodyHabits.length; i++)
                      _MiniCheck(
                        label: _bodyHabits[i],
                        done: i < _habits,
                        color: body,
                      ),
                  ],
                ),
              ),
              const Icon(LucideIcons.arrowRight, color: RpgColors.goldDim),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: body.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: body),
                  boxShadow: [
                    BoxShadow(
                      color: body.withValues(alpha: 0.3),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      '+1',
                      style: styles.statLarge.copyWith(
                        color: body,
                        fontSize: 26,
                      ),
                    ),
                    Text(
                      'Active Day',
                      style: styles.stat.copyWith(color: body, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _habits == 1
                ? 'Your ★ keystone alone secures the full point.'
                : 'Extra habits are great for you, but Body still earns +1.',
            style: styles.stat.copyWith(color: RpgColors.parchment),
          ),
          const Divider(height: 24),
          const _MissedDayStrip(),
        ],
      ),
    );
  }
}

class _MiniCheck extends StatelessWidget {
  const _MiniCheck({
    required this.label,
    required this.done,
    required this.color,
  });

  final String label;
  final bool done;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: done ? color : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: done ? color : RpgColors.ink),
            ),
            child: done
                ? const Icon(
                    LucideIcons.check,
                    size: 12,
                    color: RpgColors.obsidian,
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: styles.stat.copyWith(
                color: done ? RpgColors.parchment : RpgColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A week with one missed day: the tally keeps climbing.
class _MissedDayStrip extends StatelessWidget {
  const _MissedDayStrip();

  static const _week = [true, true, true, false, true, true, true];

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    var tally = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final (i, done) in _week.indexed)
              Expanded(
                child: Column(
                  children: [
                    Text('D${i + 1}', style: styles.stat.copyWith(fontSize: 9)),
                    const SizedBox(height: 4),
                    Icon(
                      done ? LucideIcons.check : LucideIcons.calendarX,
                      size: 16,
                      color: done ? RpgColors.gold : RpgColors.ink,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${done ? ++tally : tally}',
                      style: styles.stat.copyWith(
                        fontSize: 11,
                        color: done ? RpgColors.parchment : RpgColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Missed a day? Nothing resets. Active days only ever add up.',
          style: styles.stat.copyWith(color: RpgColors.parchment),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// b. The Season Skill Tree
// ---------------------------------------------------------------------------

class _SkillTreeCard extends StatefulWidget {
  const _SkillTreeCard({required this.sheet});

  final CharacterSheet? sheet;

  @override
  State<_SkillTreeCard> createState() => _SkillTreeCardState();
}

class _SkillTreeCardState extends State<_SkillTreeCard> {
  /// Days picked on the slider, or null to show the best branch's days.
  int? _picked;

  int get _seasonLength => widget.sheet?.seasonLength ?? 90;

  int get _bestBranchDays =>
      widget.sheet?.branches.values.fold<int>(
        0,
        (best, b) => b.activeDays > best ? b.activeDays : best,
      ) ??
      0;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    final days = (_picked ?? _bestBranchDays).clamp(0, _seasonLength);
    final nodes = RpgEngine.calculateUnlockedNodes(days);
    final next = nodes < RpgEngine.maxNodesPerBranch
        ? RpgEngine.nodeThresholds[nodes]
        : null;

    return _CodexCard(
      chapter: 'Chapter II',
      icon: LucideIcons.network,
      title: 'The 90-Day Skill Tree',
      subtitle:
          'Each season is a calendar quarter (3 months, 90–92 days). Every '
          'branch has 5 nodes that unlock at cumulative active days.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NodeBar(days: days, seasonLength: _seasonLength),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final month in ['Month 1', 'Month 2', 'Month 3'])
                Expanded(
                  child: Text(
                    month,
                    textAlign: TextAlign.center,
                    style: styles.stat.copyWith(fontSize: 10),
                  ),
                ),
            ],
          ),
          Slider(
            value: days.toDouble(),
            max: _seasonLength.toDouble(),
            divisions: _seasonLength,
            label: '$days days',
            semanticFormatterCallback: (v) => '${v.round()} active days',
            onChanged: (v) => setState(() => _picked = v.round()),
          ),
          Text(
            '$days active day${days == 1 ? '' : 's'} → '
            '$nodes of 5 nodes unlocked',
            style: styles.stat.copyWith(color: RpgColors.parchment),
          ),
          Text(
            next == null
                ? 'Branch mastered: an Epic Key is yours.'
                : '${next - days} more day${next - days == 1 ? '' : 's'} to '
                      'the next node (at $next).',
            style: styles.stat,
          ),
        ],
      ),
    );
  }
}

class _NodeBar extends StatelessWidget {
  const _NodeBar({required this.days, required this.seasonLength});

  final int days;
  final int seasonLength;

  static const double _node = 18;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        double x(int day) => width * day / seasonLength;
        return SizedBox(
          height: 44,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: _node / 2 - 3,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: RpgColors.outline,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 150),
                left: 0,
                width: x(days),
                top: _node / 2 - 3,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: RpgColors.gold,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              for (final threshold in RpgEngine.nodeThresholds) ...[
                Positioned(
                  left: x(threshold) - _node / 2,
                  top: 0,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: _node,
                    height: _node,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: days >= threshold
                          ? RpgColors.gold
                          : RpgColors.slate,
                      border: Border.all(
                        color: days >= threshold
                            ? RpgColors.gold
                            : RpgColors.ink,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: x(threshold) - 14,
                  width: 28,
                  top: _node + 6,
                  child: Text(
                    '$threshold',
                    textAlign: TextAlign.center,
                    style: styles.stat.copyWith(
                      fontSize: 11,
                      color: days >= threshold ? RpgColors.gold : RpgColors.ink,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// c. The Leveling Formula
// ---------------------------------------------------------------------------

class _FormulaCard extends StatelessWidget {
  const _FormulaCard({required this.state, required this.sheet});

  final RpgState? state;
  final CharacterSheet? sheet;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    final state = this.state;
    final sheet = this.sheet;
    return _CodexCard(
      chapter: 'Chapter III',
      icon: LucideIcons.sigma,
      title: 'The Leveling Formula',
      subtitle: 'Levels are calculated, never lost. Old seasons carry over.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Equation(
            result: 'Branch Level',
            terms: [
              'Carry-Over Base Level',
              'Forged Nodes (0–5)',
              'Completed Feats',
            ],
          ),
          const SizedBox(height: 10),
          const _Equation(
            result: 'Character Level',
            terms: ['Sum of your active Branch Levels'],
          ),
          if (state != null && sheet != null) ...[
            const Divider(height: 28),
            Text(
              'YOUR SHEET RIGHT NOW',
              style: styles.stat.copyWith(
                fontSize: 10,
                letterSpacing: 1.2,
                color: RpgColors.goldDim,
              ),
            ),
            const SizedBox(height: 8),
            for (final branch in sheet.activeBranches)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(
                        state.nameOf(branch),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: styles.stat.copyWith(color: branch.color),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${state.configFor(branch).baseLevel} + '
                        '${sheet.branches[branch]!.forgedNodes} + '
                        '${sheet.branches[branch]!.completedFeats} = '
                        '${sheet.branches[branch]!.level}',
                        textAlign: TextAlign.right,
                        style: styles.stat.copyWith(
                          color: RpgColors.parchment,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: RpgColors.gold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: RpgColors.goldDim),
              ),
              child: Text(
                '${[for (final b in sheet.activeBranches) sheet.branches[b]!.level].join(' + ')}'
                ' = Character Level ${sheet.totalLevel}',
                textAlign: TextAlign.center,
                style: styles.stat.copyWith(
                  color: RpgColors.gold,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `result = term + term + term` as chips that wrap on narrow screens.
class _Equation extends StatelessWidget {
  const _Equation({required this.result, required this.terms});

  final String result;
  final List<String> terms;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    Widget chip(String text, {bool highlight = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlight
            ? RpgColors.gold.withValues(alpha: 0.16)
            : RpgColors.obsidian,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlight ? RpgColors.gold : RpgColors.outline,
        ),
      ),
      child: Text(
        text,
        style: styles.stat.copyWith(
          fontSize: 12,
          color: highlight ? RpgColors.gold : RpgColors.parchment,
        ),
      ),
    );
    Widget op(String symbol) => Text(
      symbol,
      style: styles.statLarge.copyWith(fontSize: 18, color: RpgColors.goldDim),
    );

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        chip(result, highlight: true),
        op('='),
        for (final (i, term) in terms.indexed) ...[
          if (i > 0) op('+'),
          chip(term),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// d. The 4-Tier Loot Economy
// ---------------------------------------------------------------------------

class _LootCard extends StatelessWidget {
  const _LootCard({required this.sheet});

  final CharacterSheet? sheet;

  static const _howEarned = {
    LootTier.common: 'Every 7-day unbroken streak on a ★ Keystone Habit.',
    LootTier.rare: 'Unlocking any Skill Tree node.',
    LootTier.epic: 'Hitting 80 Active Days in a single branch.',
    LootTier.legendary:
        'Completing every node across the entire Skill Tree (25 with five '
        'pillars).',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = RpgStyles.of(context);
    return _CodexCard(
      chapter: 'Chapter IV',
      icon: LucideIcons.key,
      title: 'The 4-Tier Loot Economy',
      subtitle:
          'Keys open the rewards you stocked in your loot vault. Keystone '
          'streaks are a bonus only: breaking one costs nothing.',
      child: Column(
        children: [
          for (final tier in LootTier.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tier.color.withValues(alpha: 0.14),
                      border: Border.all(color: tier.color, width: 1.5),
                    ),
                    child: Icon(LucideIcons.key, size: 18, color: tier.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tier.label,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: tier.color,
                          ),
                        ),
                        Text(_howEarned[tier]!, style: styles.stat),
                      ],
                    ),
                  ),
                  if (sheet case final sheet?) ...[
                    const SizedBox(width: 8),
                    Semantics(
                      label:
                          '${sheet.lootKeys[tier]!.available} '
                          '${tier.label} keys ready',
                      child: ExcludeSemantics(
                        child: Text(
                          '${sheet.lootKeys[tier]!.available}',
                          style: styles.statLarge.copyWith(
                            fontSize: 20,
                            color: tier.color,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
