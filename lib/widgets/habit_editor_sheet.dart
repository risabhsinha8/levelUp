import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/rpg_models.dart';
import '../providers/rpg_store_provider.dart';
import '../theme/rpg_theme.dart';

/// Opens the habit editor: pass [habit] to edit it, or [branch] to add a new
/// habit to that branch.
Future<void> showHabitEditor(
  BuildContext context, {
  Habit? habit,
  BranchType? branch,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: RpgColors.slateRaised,
    builder: (_) => HabitEditorSheet(
      habit: habit,
      initialBranch: branch ?? habit?.branch ?? BranchType.mind,
    ),
  );
}

class HabitEditorSheet extends ConsumerStatefulWidget {
  const HabitEditorSheet({super.key, this.habit, required this.initialBranch});

  final Habit? habit;
  final BranchType initialBranch;

  @override
  ConsumerState<HabitEditorSheet> createState() => _HabitEditorSheetState();
}

class _HabitEditorSheetState extends ConsumerState<HabitEditorSheet> {
  late final _title = TextEditingController(text: widget.habit?.title);
  late final _target = TextEditingController(
    text: widget.habit?.targetCriteria,
  );
  late BranchType _branch = widget.initialBranch;
  late bool _isKeystone = widget.habit?.isKeystone ?? false;
  late ActiveHalfMonth _schedule =
      widget.habit?.activeHalfMonth ?? ActiveHalfMonth.both;

  bool get _isNew => widget.habit == null;

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    await ref
        .read(rpgStoreProvider.notifier)
        .addOrUpdateHabit(
          id: widget.habit?.id,
          branch: _branch,
          title: _title.text.trim(),
          targetCriteria: _target.text.trim(),
          isKeystone: _isKeystone,
          activeHalfMonth: _schedule,
        );
    navigator.pop();
  }

  Future<void> _delete() async {
    final habit = widget.habit!;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${habit.title}"?'),
        content: const Text(
          'It disappears from your daily list. Days you already checked it '
          'off still count toward your branch points.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: RpgColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    HapticFeedback.mediumImpact();
    await ref.read(rpgStoreProvider.notifier).deleteHabit(habit.id);
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text('Deleted "${habit.title}".')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = RpgStyles.of(context);
    final state = ref.watch(rpgStateProvider);
    final currentKeystone = state.keystoneFor(_branch);
    // Moving a habit with history would move its earned points too.
    final branchLocked =
        widget.habit != null && state.hasCheckIns(widget.habit!.id);
    final replacesKeystone =
        _isKeystone &&
        currentKeystone != null &&
        currentKeystone.id != widget.habit?.id;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isNew ? 'New Habit' : 'Edit Habit',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _title,
              autofocus: _isNew,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Habit',
                hintText: 'e.g. Water',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _target,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Target',
                hintText: 'e.g. 13 cups daily',
              ),
            ),
            const SizedBox(height: 16),
            Text('Branch', style: styles.stat),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final branch in BranchType.values)
                  ChoiceChip(
                    label: Text(branch.displayName),
                    selected: _branch == branch,
                    showCheckmark: false,
                    selectedColor: branch.color.withValues(alpha: 0.25),
                    side: BorderSide(
                      color: _branch == branch
                          ? branch.color
                          : RpgColors.outline,
                    ),
                    labelStyle: TextStyle(
                      color: _branch == branch ? branch.color : RpgColors.ink,
                    ),
                    onSelected: branchLocked
                        ? null
                        : (_) => setState(() => _branch = branch),
                  ),
              ],
            ),
            if (branchLocked) ...[
              const SizedBox(height: 6),
              Text(
                'Branch locked: past check-ins count toward '
                '${_branch.displayName}.',
                style: styles.stat.copyWith(fontSize: 10),
              ),
            ],
            const SizedBox(height: 16),
            Text('Schedule', style: styles.stat),
            const SizedBox(height: 6),
            SegmentedButton<ActiveHalfMonth>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                textStyle: styles.stat.copyWith(fontSize: 12),
              ),
              segments: const [
                ButtonSegment(
                  value: ActiveHalfMonth.both,
                  label: Text('Every day'),
                ),
                ButtonSegment(
                  value: ActiveHalfMonth.firstHalf,
                  label: Text('Days 1–15'),
                ),
                ButtonSegment(
                  value: ActiveHalfMonth.secondHalf,
                  label: Text('Days 16+'),
                ),
              ],
              selected: {_schedule},
              onSelectionChanged: (s) => setState(() => _schedule = s.single),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isKeystone,
              activeColor: RpgColors.gold,
              onChanged: (v) => setState(() => _isKeystone = v),
              secondary: Icon(
                _isKeystone ? Icons.star_rounded : Icons.star_outline_rounded,
                color: _isKeystone ? RpgColors.gold : RpgColors.ink,
              ),
              title: const Text('Keystone habit'),
              subtitle: Text(
                replacesKeystone
                    ? 'Replaces ★ ${currentKeystone.title} as the '
                          '${_branch.displayName} keystone'
                    : 'The daily non-negotiable for this branch',
                style: styles.stat.copyWith(fontSize: 11),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (!_isNew)
                  TextButton.icon(
                    onPressed: _delete,
                    icon: const Icon(LucideIcons.trash2, size: 16),
                    label: const Text('Delete'),
                    style: TextButton.styleFrom(
                      foregroundColor: RpgColors.danger,
                    ),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: _title.text.trim().isEmpty ? null : _save,
                  child: Text(_isNew ? 'Add Habit' : 'Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
