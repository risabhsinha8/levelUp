import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/rpg_models.dart';
import '../providers/rpg_store_provider.dart';
import '../theme/rpg_theme.dart';

/// Reflection notes for the month plus the "Pivot Habit" action, shown
/// between the Half 1 and Half 2 grids. Key it by month so the notes reset
/// when the month changes.
class MidMonthReflectionCard extends ConsumerStatefulWidget {
  const MidMonthReflectionCard({
    super.key,
    required this.month,
    required this.daysInMonth,
  });

  final DateTime month;
  final int daysInMonth;

  @override
  ConsumerState<MidMonthReflectionCard> createState() =>
      _MidMonthReflectionCardState();
}

class _MidMonthReflectionCardState
    extends ConsumerState<MidMonthReflectionCard> {
  static const _saveDelay = Duration(milliseconds: 700);

  late final TextEditingController _notes;
  // Captured up front: `ref` can't be used in dispose(), where pending notes
  // are flushed.
  late final RpgStore _store;
  Timer? _debounce;
  bool _saved = true;

  @override
  void initState() {
    super.initState();
    _store = ref.read(rpgStoreProvider.notifier);
    _notes = TextEditingController(
      text: ref.read(rpgStateProvider).reflectionFor(widget.month).notes,
    );
  }

  @override
  void dispose() {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      // Best effort: after "wipe & restart" there's no character to save to.
      _save().catchError((_) {});
    }
    _notes.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    setState(() => _saved = false);
    _debounce?.cancel();
    _debounce = Timer(_saveDelay, () async {
      await _save();
      if (mounted) setState(() => _saved = true);
    });
  }

  Future<void> _save() =>
      _store.updateReflectionNotes(widget.month, _notes.text);

  Future<void> _openPivotDialog(List<Habit> candidates) async {
    final result = await showDialog<_PivotRequest>(
      context: context,
      builder: (context) => _PivotDialog(
        candidates: candidates,
        halfTwoLabel:
            'Days ${ActiveHalfMonth.firstHalfLastDay + 1}–'
            '${widget.daysInMonth}',
        nameOf: ref.read(rpgStateProvider).nameOf,
      ),
    );
    if (result == null || !mounted) return;
    final newId = await _store.pivotHabit(
      oldHabitId: result.oldHabit.id,
      newTitle: result.newTitle,
      newTargetCriteria: result.newTarget,
      month: widget.month,
    );
    if (newId == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${result.oldHabit.title} → ${result.newTitle} for Half 2. '
          'Branch points from Days 1–15 are kept.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = RpgStyles.of(context);
    final state = ref.watch(rpgStateProvider);
    final reflection = state.reflectionFor(widget.month);
    // Show notes changed elsewhere (e.g. a restored backup) unless the user
    // is mid-edit, so stale text never overwrites them.
    ref.listen(
      rpgStateProvider.select((s) => s.reflectionFor(widget.month).notes),
      (_, notes) {
        if (!(_debounce?.isActive ?? false) && notes != _notes.text) {
          _notes.text = notes;
        }
      },
    );
    final candidates = [
      for (final branch in state.activeBranches)
        for (final h in state.habits)
          if (h.branch == branch &&
              !h.isKeystone &&
              !h.isArchived &&
              h.activeHalfMonth == ActiveHalfMonth.both)
            h,
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: RpgColors.goldDim),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  LucideIcons.feather,
                  size: 18,
                  color: RpgColors.gold,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Mid-Month Reflection & Pivot',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: RpgColors.gold,
                    ),
                  ),
                ),
                AnimatedOpacity(
                  opacity: _notes.text.isEmpty ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: Text(_saved ? 'Saved' : 'Saving…', style: styles.stat),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              onChanged: _onChanged,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'What worked? What felt like burnout?',
                hintStyle: styles.stat,
                filled: true,
                fillColor: RpgColors.obsidian,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: RpgColors.outline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: RpgColors.outline),
                ),
              ),
            ),
            if (reflection.pivots.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final pivot in reflection.pivots)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.repeat,
                        size: 14,
                        color: RpgColors.ink,
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: Text(pivot, style: styles.stat)),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: candidates.isEmpty
                    ? null
                    : () => _openPivotDialog(candidates),
                icon: const Icon(LucideIcons.repeat, size: 16),
                label: Text(
                  'Pivot Habit for Days '
                  '${ActiveHalfMonth.firstHalfLastDay + 1}–${widget.daysInMonth}',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: RpgColors.gold,
                  side: const BorderSide(color: RpgColors.goldDim),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              candidates.isEmpty
                  ? 'No habits left to pivot. Keystones stay non-negotiable.'
                  : 'Swap a habit that isn\'t working. Points already earned '
                        'stay on the sheet.',
              style: styles.stat.copyWith(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _PivotRequest {
  const _PivotRequest(this.oldHabit, this.newTitle, this.newTarget);

  final Habit oldHabit;
  final String newTitle;
  final String newTarget;
}

class _PivotDialog extends StatefulWidget {
  const _PivotDialog({
    required this.candidates,
    required this.halfTwoLabel,
    required this.nameOf,
  });

  final List<Habit> candidates;
  final String halfTwoLabel;
  final String Function(BranchType) nameOf;

  @override
  State<_PivotDialog> createState() => _PivotDialogState();
}

class _PivotDialogState extends State<_PivotDialog> {
  Habit? _old;
  final _title = TextEditingController();
  final _target = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    super.dispose();
  }

  bool get _canSubmit => _old != null && _title.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    return AlertDialog(
      title: const Text('Pivot a Habit'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The old habit stays in Half 1 so its branch points are kept. '
              'The new one runs ${widget.halfTwoLabel}.',
              style: styles.stat,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<Habit>(
              value: _old,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Replace'),
              items: [
                for (final h in widget.candidates)
                  DropdownMenuItem(
                    value: h,
                    child: Text(
                      '${h.title} (${widget.nameOf(h.branch)})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (h) => setState(() => _old = h),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'New habit',
                helperText: _old == null
                    ? null
                    : 'Joins the ${widget.nameOf(_old!.branch)} branch',
              ),
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
          onPressed: _canSubmit
              ? () => Navigator.pop(
                  context,
                  _PivotRequest(_old!, _title.text.trim(), _target.text.trim()),
                )
              : null,
          child: const Text('Pivot'),
        ),
      ],
    );
  }
}
