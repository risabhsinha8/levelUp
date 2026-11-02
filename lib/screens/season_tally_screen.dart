import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../domain/character_sheet.dart';
import '../models/rpg_models.dart';
import '../models/rpg_state.dart';
import '../providers/rpg_store_provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/character_share_card.dart';
import '../widgets/empty_prompt.dart';
import '../widgets/pillar_roster.dart';
import '../widgets/season_complete_dialog.dart';
import '../widgets/season_ledger.dart';
import '../widgets/settings_section.dart';
import 'season_detail_screen.dart';

/// Tab 4: the automated ledger, season rollover, past seasons and settings.
class SeasonTallyScreen extends ConsumerWidget {
  const SeasonTallyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(rpgStateProvider);
    final sheet = ref.watch(characterSheetProvider).requireValue;
    final today = ref.watch(todayProvider);
    final archived = state.archivedSeasons;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _Header(
          title: 'Season Tally',
          trailing:
              '${state.currentSeason.name} · Day ${sheet.seasonDay}/${sheet.seasonLength}',
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: OutlinedButton.icon(
            onPressed: () => showCharacterShareSheet(context),
            icon: const Icon(LucideIcons.share2, size: 16),
            label: const Text('Share Character Card'),
            style: OutlinedButton.styleFrom(
              foregroundColor: RpgColors.gold,
              side: const BorderSide(color: RpgColors.goldDim),
              minimumSize: const Size.fromHeight(44),
            ),
          ),
        ),
        MathLedgerCard(state: state, sheet: sheet),
        MonthBreakdownCard(state: state, sheet: sheet, today: today),
        _PrestigeCard(state: state, sheet: sheet),
        const SizedBox(height: 20),
        const _Header(title: 'Hall of Seasons'),
        if (archived.isEmpty)
          const EmptyPrompt(
            icon: LucideIcons.award,
            title: 'Your first season is underway',
            message: 'Completed seasons land here, each with its full record.',
            compact: true,
          ),
        for (final season in archived) _ArchivedSeasonTile(season: season),
        const SizedBox(height: 20),
        const _Header(title: 'Settings & Data'),
        const SettingsSection(),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: RpgStyles.of(context).stat.copyWith(color: RpgColors.gold),
            ),
        ],
      ),
    );
  }
}

/// "End Season & Prestige": previews the level carry-over and rolls over.
class _PrestigeCard extends ConsumerWidget {
  const _PrestigeCard({required this.state, required this.sheet});

  final RpgState state;
  final CharacterSheet sheet;

  Future<void> _complete(BuildContext context, WidgetRef ref) async {
    final pillars = await showDialog<Set<BranchType>>(
      context: context,
      builder: (context) => _CompleteSeasonDialog(state: state, sheet: sheet),
    );
    if (pillars == null || !context.mounted) return;

    HapticFeedback.heavyImpact();
    final result = await ref
        .read(rpgStoreProvider.notifier)
        .completeSeason(activeBranches: pillars);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SeasonCompleteDialog(result: result),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final styles = RpgStyles.of(context);
    final startLevel = sheet.activeBranches.fold(
      0,
      (sum, b) => sum + state.configFor(b).baseLevel,
    );
    final remaining = sheet.seasonLength - sheet.seasonDay;
    final ready = sheet.activeBranches.fold(
      0,
      (sum, b) => sum + sheet.branches[b]!.readyToForge,
    );
    final nextStart = parseDateString(
      toDateString(state.currentSeason.endDate),
    ).add(const Duration(days: 1));

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RpgColors.goldDim),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [RpgColors.gold.withValues(alpha: 0.14), RpgColors.slate],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.crown, color: RpgColors.gold, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'End Season & Prestige',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: RpgColors.gold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Lv $startLevel',
                style: styles.statLarge.copyWith(color: RpgColors.ink),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Icon(
                  LucideIcons.arrowRight,
                  size: 18,
                  color: RpgColors.gold,
                ),
              ),
              Text(
                // Rollover forges any ready nodes automatically.
                'Lv ${sheet.totalLevel + ready}',
                style: styles.statLarge.copyWith(
                  color: RpgColors.gold,
                  fontSize: 26,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'season start → locked in',
                  style: styles.stat.copyWith(fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final line in [
            'Season nodes + feats bake into each base level',
            if (ready > 0)
              '$ready unforged node${ready == 1 ? ' is' : 's are'} forged '
                  'for you',
            'Skill tree nodes reset to 0 for the new season',
            'Logs, quests and loot history are archived',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.check,
                    size: 14,
                    color: RpgColors.goldDim,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(line, style: styles.stat)),
                ],
              ),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              // Seasons follow calendar quarters, so they end on a fixed date.
              onPressed: sheet.isSeasonOver
                  ? () => _complete(context, ref)
                  : null,
              icon: const Icon(LucideIcons.trophy, size: 18),
              label: Text('Complete ${state.currentSeason.name} & Level Up'),
            ),
          ),
          if (!sheet.isSeasonOver) ...[
            const SizedBox(height: 6),
            Center(
              child: Text(
                '${remaining + 1} day${remaining == 0 ? '' : 's'} left · '
                'unlocks ${DateFormat.MMMd().format(nextStart)}',
                style: styles.stat.copyWith(fontSize: 10),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ArchivedSeasonTile extends StatelessWidget {
  const _ArchivedSeasonTile({required this.season});

  final Season season;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    final summary = season.summary;
    final dates = DateFormat.yMMMd();
    final activeDays = summary == null
        ? 0
        : summary.branches.values.fold(0, (sum, b) => sum + b.activeDays);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(LucideIcons.award, color: RpgColors.gold),
        title: Text(season.name),
        subtitle: Text(
          '${dates.format(season.startDate)} – ${dates.format(season.endDate)}'
          ' · $activeDays branch days',
          style: styles.stat.copyWith(fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (summary != null)
              Text(
                'Lv ${summary.startLevel} → ${summary.endLevel}',
                style: styles.stat.copyWith(color: RpgColors.gold),
              ),
            const Icon(LucideIcons.chevronRight, size: 18),
          ],
        ),
        onTap: () => openSeasonDetail(context, season.id),
      ),
    );
  }
}

/// Confirms the rollover and picks the pillars for the next season. Pops
/// the chosen pillars, or null for "Not yet".
class _CompleteSeasonDialog extends StatefulWidget {
  const _CompleteSeasonDialog({required this.state, required this.sheet});

  final RpgState state;
  final CharacterSheet sheet;

  @override
  State<_CompleteSeasonDialog> createState() => _CompleteSeasonDialogState();
}

class _CompleteSeasonDialogState extends State<_CompleteSeasonDialog> {
  late final _pillars = widget.state.activeBranches.toSet();

  /// [branch]'s level once rolled over (ready nodes are forged for free).
  int _endLevel(BranchType branch) {
    final stats = widget.sheet.branches[branch]!;
    return widget.state.configFor(branch).baseLevel +
        stats.unlockedNodes +
        stats.completedFeats;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final resting = [
      for (final b in BranchType.values)
        if (!_pillars.contains(b) && state.configFor(b).isEnabled) b,
    ];
    return AlertDialog(
      title: Text('Complete ${state.currentSeason.name}?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your nodes and feats will be baked into your base levels and '
              'the skill tree resets to 0 for the next quarter. Check-ins '
              'since the season ended count toward the new season.',
            ),
            const SizedBox(height: 16),
            Text(
              'Pillars next season',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            PillarRoster(
              enabled: _pillars,
              onToggle: (b) => setState(
                () =>
                    _pillars.contains(b) ? _pillars.remove(b) : _pillars.add(b),
              ),
              names: {for (final b in BranchType.values) b: state.nameOf(b)},
              details: {
                for (final b in BranchType.values)
                  b: state.configFor(b).isEnabled
                      ? 'Lv ${_endLevel(b)}'
                      : 'Resting · Lv ${state.configFor(b).baseLevel}',
              },
            ),
            if (resting.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Resting: ${resting.map(state.nameOf).join(', ')}. Resting '
                  'pillars keep their level and habits for when they return, '
                  "but don't count toward your character level.",
                  style: RpgStyles.of(
                    context,
                  ).stat.copyWith(fontSize: 11, color: RpgColors.ember),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Not yet'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, {..._pillars}),
          child: const Text('Level Up'),
        ),
      ],
    );
  }
}
