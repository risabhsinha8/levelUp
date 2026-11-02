import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../domain/rpg_engine.dart';
import '../models/rpg_models.dart';
import '../providers/rpg_store_provider.dart';
import '../theme/rpg_theme.dart';
import 'empty_prompt.dart';

/// Opens the guided Mid-Month Campfire for the current month.
Future<void> showCampfireSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: RpgColors.slateRaised,
  builder: (_) => const CampfireSheet(),
);

/// Glowing Today's Focus banner shown on the 14th–16th of the month.
class CampfireBanner extends ConsumerWidget {
  const CampfireBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final styles = RpgStyles.of(context);
    final state = ref.watch(rpgStateProvider);
    final today = ref.watch(todayProvider);
    final struggling = RpgEngine.findStrugglingHabits(
      state.activeHabits,
      state.logs,
      today,
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RpgColors.ember.withValues(alpha: 0.8)),
        gradient: LinearGradient(
          colors: [RpgColors.ember.withValues(alpha: 0.2), RpgColors.slate],
        ),
        boxShadow: [
          BoxShadow(
            color: RpgColors.ember.withValues(alpha: 0.35),
            blurRadius: 18,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => showCampfireSheet(context),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(LucideIcons.flame, color: RpgColors.ember, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mid-Month Campfire Reflection',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: RpgColors.parchment,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        struggling.isEmpty
                            ? 'Half 1 is nearly done. Rest by the fire and '
                                  'note what worked.'
                            : '${struggling.length} habit'
                                  '${struggling.length == 1 ? '' : 's'} '
                                  'struggled in Days 1–15. Pivot for Half 2?',
                        style: styles.stat,
                      ),
                    ],
                  ),
                ),
                const Icon(LucideIcons.chevronRight, color: RpgColors.ember),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The guided reflection: struggling Half 1 habits with a one-tap pivot,
/// plus notes saved to the season's `mid_month_notes`.
class CampfireSheet extends ConsumerStatefulWidget {
  const CampfireSheet({super.key});

  @override
  ConsumerState<CampfireSheet> createState() => _CampfireSheetState();
}

class _CampfireSheetState extends ConsumerState<CampfireSheet> {
  late final RpgStore _store;
  late final DateTime _month;
  late final TextEditingController _notes;
  late String _savedNotes;

  @override
  void initState() {
    super.initState();
    _store = ref.read(rpgStoreProvider.notifier);
    final today = ref.read(todayProvider);
    _month = DateTime(today.year, today.month);
    _savedNotes = ref.read(rpgStateProvider).reflectionFor(_month).notes;
    _notes = TextEditingController(text: _savedNotes);
  }

  @override
  void dispose() {
    // Swiping the sheet away still keeps what was written.
    if (_notes.text != _savedNotes) {
      _store.updateReflectionNotes(_month, _notes.text).catchError((_) {});
    }
    _notes.dispose();
    super.dispose();
  }

  String get _halfTwoLabel =>
      'Days ${ActiveHalfMonth.firstHalfLastDay + 1}–'
      '${DateUtils.getDaysInMonth(_month.year, _month.month)}';

  Future<void> _pivot(Habit habit) async {
    final messenger = ScaffoldMessenger.of(context);
    final replacement = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _ReplacementDialog(
        habit: habit,
        branchName: ref.read(rpgStateProvider).nameOf(habit.branch),
        halfTwoLabel: _halfTwoLabel,
      ),
    );
    if (replacement == null || !mounted) return;
    final (title, target) = replacement;
    final newId = await _store.pivotHabit(
      oldHabitId: habit.id,
      newTitle: title,
      newTargetCriteria: target,
      month: _month,
    );
    if (newId == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${habit.title} → $title for $_halfTwoLabel. '
          'Branch points from Days 1–15 are kept.',
        ),
      ),
    );
  }

  Future<void> _saveAndClose() async {
    final navigator = Navigator.of(context);
    await _store.updateReflectionNotes(_month, _notes.text);
    _savedNotes = _notes.text;
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = RpgStyles.of(context);
    final state = ref.watch(rpgStateProvider);
    final today = ref.watch(todayProvider);
    final struggling = RpgEngine.findStrugglingHabits(
      state.activeHabits,
      state.logs,
      today,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.flame, color: RpgColors.ember),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Mid-Month Campfire',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Look back at Days 1–15. Habits done on fewer than 25% of '
              'days can be swapped for $_halfTwoLabel without losing a '
              'single branch point.',
              style: styles.stat,
            ),
            const SizedBox(height: 16),
            Text(
              'STRUGGLING HABITS',
              style: styles.stat.copyWith(
                fontSize: 10,
                letterSpacing: 1.2,
                color: RpgColors.goldDim,
              ),
            ),
            const SizedBox(height: 8),
            if (struggling.isEmpty)
              const EmptyPrompt(
                compact: true,
                icon: LucideIcons.flame,
                title: 'No struggling habits',
                message:
                    'Every Half 1 habit is above 25%. Keep the fire going.',
              )
            else
              for (final s in struggling)
                _StrugglingTile(
                  struggling: s,
                  branchName: state.nameOf(s.habit.branch),
                  halfTwoLabel: _halfTwoLabel,
                  onPivot: () => _pivot(s.habit),
                ),
            const SizedBox(height: 16),
            TextField(
              controller: _notes,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Campfire notes',
                hintText: 'What worked? What felt like burnout?',
                hintStyle: styles.stat,
                filled: true,
                fillColor: RpgColors.obsidian,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saveAndClose,
                icon: const Icon(LucideIcons.feather, size: 16),
                label: const Text('Save Reflection'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StrugglingTile extends StatelessWidget {
  const _StrugglingTile({
    required this.struggling,
    required this.branchName,
    required this.halfTwoLabel,
    required this.onPivot,
  });

  final StrugglingHabit struggling;
  final String branchName;
  final String halfTwoLabel;
  final VoidCallback onPivot;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    final habit = struggling.habit;
    final color = habit.branch.color;
    final percent = (struggling.completionRate * 100).round();

    final Widget action;
    if (habit.isKeystone) {
      action = Text(
        '★ Keystone · stays non-negotiable',
        style: styles.stat.copyWith(color: RpgColors.gold, fontSize: 11),
      );
    } else if (habit.activeHalfMonth == ActiveHalfMonth.firstHalf) {
      action = Row(
        children: [
          const Icon(LucideIcons.check, size: 14, color: RpgColors.gold),
          const SizedBox(width: 4),
          Text(
            'Pivoted for $halfTwoLabel',
            style: styles.stat.copyWith(color: RpgColors.gold, fontSize: 11),
          ),
        ],
      );
    } else {
      action = SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onPivot,
          icon: const Icon(LucideIcons.repeat, size: 16),
          label: Text('Pivot Habit for $halfTwoLabel'),
          style: OutlinedButton.styleFrom(
            foregroundColor: RpgColors.gold,
            side: const BorderSide(color: RpgColors.goldDim),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: RpgColors.slate,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  habit.title,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              Text(
                '${struggling.completedDays}/${struggling.elapsedDays} days '
                '· $percent%',
                style: styles.stat.copyWith(color: color),
              ),
            ],
          ),
          Text(branchName, style: styles.stat),
          const SizedBox(height: 8),
          action,
        ],
      ),
    );
  }
}

/// Asks for the Half 2 replacement's title and target.
class _ReplacementDialog extends StatefulWidget {
  const _ReplacementDialog({
    required this.habit,
    required this.branchName,
    required this.halfTwoLabel,
  });

  final Habit habit;
  final String branchName;
  final String halfTwoLabel;

  @override
  State<_ReplacementDialog> createState() => _ReplacementDialogState();
}

class _ReplacementDialogState extends State<_ReplacementDialog> {
  final _title = TextEditingController();
  final _target = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    final title = _title.text.trim();
    return AlertDialog(
      title: Text('Replace ${widget.habit.title}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.habit.title} stays in Days 1–15 with its points. '
              'The new ${widget.branchName} habit runs '
              '${widget.halfTwoLabel}.',
              style: styles.stat,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'New habit'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _target,
              decoration: const InputDecoration(
                labelText: 'Target',
                hintText: 'e.g. 1 page daily',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: title.isEmpty
              ? null
              : () => Navigator.pop(context, (title, _target.text.trim())),
          child: const Text('Pivot'),
        ),
      ],
    );
  }
}
