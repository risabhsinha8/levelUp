import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/rpg_models.dart';
import '../providers/rpg_store_provider.dart';
import '../theme/rpg_theme.dart';
import 'quest_widgets.dart';

/// Opens the "New Quest" sheet. Returns true if a quest was added.
Future<bool?> showQuestFormSheet(
  BuildContext context, {
  required int monthIndex,
  bool isMainQuest = false,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: RpgColors.slateRaised,
    builder: (context) =>
        QuestFormSheet(monthIndex: monthIndex, isMainQuest: isMainQuest),
  );
}

class QuestFormSheet extends ConsumerStatefulWidget {
  const QuestFormSheet({
    super.key,
    required this.monthIndex,
    this.isMainQuest = false,
  });

  final int monthIndex;
  final bool isMainQuest;

  @override
  ConsumerState<QuestFormSheet> createState() => _QuestFormSheetState();
}

class _QuestFormSheetState extends ConsumerState<QuestFormSheet> {
  late bool _isMain = widget.isMainQuest;
  late int _month = widget.monthIndex;
  BranchType _branch = BranchType.mind;
  int _difficulty = 2;
  final _title = TextEditingController();
  final _reward = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _reward.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    await ref
        .read(rpgStoreProvider.notifier)
        .addQuest(
          title: _title.text.trim(),
          branch: _branch,
          isMainQuest: _isMain,
          difficulty: _difficulty,
          monthIndex: _month,
          rewardText: _reward.text.trim(),
        );
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    final state = ref.watch(rpgStateProvider);
    final replacing = _isMain
        ? state.currentQuests
              .where((q) => q.isMainQuest && q.monthIndex == _month)
              .firstOrNull
        : null;

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
            Text('New Quest', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, label: Text('Main Quest')),
                ButtonSegment(value: false, label: Text('Side Quest')),
              ],
              selected: {_isMain},
              onSelectionChanged: (s) => setState(() => _isMain = s.single),
            ),
            if (replacing != null) ...[
              const SizedBox(height: 6),
              Text(
                'Replaces "${replacing.title}", which becomes a side quest.',
                style: styles.stat.copyWith(fontSize: 10),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _title,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Quest',
                hintText: _isMain
                    ? 'e.g. Run a 5K without stopping'
                    : 'e.g. Master 50 French words',
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
                    onSelected: (_) => setState(() => _branch = branch),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Difficulty', style: styles.stat),
                      const SizedBox(height: 6),
                      DifficultyStars(
                        value: _difficulty,
                        size: 26,
                        onChanged: (v) => setState(() => _difficulty = v),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Month', style: styles.stat),
                    const SizedBox(height: 2),
                    DropdownButton<int>(
                      value: _month,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (var m = 1; m <= 3; m++)
                          DropdownMenuItem(value: m, child: Text('Month $m')),
                      ],
                      onChanged: (m) => setState(() => _month = m!),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reward,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Reward (optional)',
                hintText: 'e.g. New running shoes',
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _title.text.trim().isEmpty ? null : _save,
                child: Text(_isMain ? 'Add Main Quest' : 'Add Side Quest'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
