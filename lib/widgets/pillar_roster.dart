import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/rpg_models.dart';
import '../providers/rpg_store_provider.dart';
import '../theme/rpg_theme.dart';

/// Every pillar slot with a checkbox to bring it into play, used in Session
/// Zero and at season rollover. With [nameFields] each row is a rename
/// field; otherwise it shows [names]. At least [BranchType.minEnabled]
/// pillars stay checked.
class PillarRoster extends StatelessWidget {
  const PillarRoster({
    super.key,
    required this.enabled,
    required this.onToggle,
    this.nameFields,
    this.names = const {},
    this.details = const {},
    this.onNameChanged,
  });

  final Set<BranchType> enabled;
  final ValueChanged<BranchType> onToggle;
  final Map<BranchType, TextEditingController>? nameFields;

  /// Names shown when there are no [nameFields]; default names otherwise.
  final Map<BranchType, String> names;

  /// Small text under each pillar, e.g. its description or level.
  final Map<BranchType, String> details;
  final VoidCallback? onNameChanged;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${enabled.length} of ${BranchType.values.length} pillars in play · '
          'at least ${BranchType.minEnabled}',
          style: styles.stat.copyWith(fontSize: 10),
        ),
        const SizedBox(height: 4),
        for (final branch in BranchType.values)
          _PillarRow(
            branch: branch,
            checked: enabled.contains(branch),
            locked:
                enabled.contains(branch) &&
                enabled.length <= BranchType.minEnabled,
            onToggle: () => onToggle(branch),
            field: nameFields?[branch],
            name: names[branch] ?? branch.displayName,
            detail: details[branch],
            onNameChanged: onNameChanged,
          ),
      ],
    );
  }
}

class _PillarRow extends StatelessWidget {
  const _PillarRow({
    required this.branch,
    required this.checked,
    required this.locked,
    required this.onToggle,
    required this.field,
    required this.name,
    required this.detail,
    required this.onNameChanged,
  });

  final BranchType branch;
  final bool checked;
  final bool locked;
  final VoidCallback onToggle;
  final TextEditingController? field;
  final String name;
  final String? detail;
  final VoidCallback? onNameChanged;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    final color = checked ? branch.color : RpgColors.ink;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Checkbox(
            key: ValueKey('pillar-toggle-${branch.name}'),
            value: checked,
            activeColor: branch.color,
            onChanged: locked ? null : (_) => onToggle(),
          ),
          Icon(branch.icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: field != null
                ? TextField(
                    key: ValueKey('pillar-name-${branch.name}'),
                    controller: field,
                    enabled: checked,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(
                        BranchConfig.maxNameLength,
                      ),
                    ],
                    onChanged: (_) => onNameChanged?.call(),
                    style: TextStyle(color: color),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: branch.displayName,
                      helperText: detail,
                      helperMaxLines: 2,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: styles.stat.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (detail != null)
                        Text(
                          detail!,
                          style: styles.stat.copyWith(fontSize: 10),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Settings dialog to rename the pillars. Names are display-only, so this
/// works any time; resting pillars can be renamed too.
class RenamePillarsDialog extends ConsumerStatefulWidget {
  const RenamePillarsDialog({super.key});

  @override
  ConsumerState<RenamePillarsDialog> createState() =>
      _RenamePillarsDialogState();
}

class _RenamePillarsDialogState extends ConsumerState<RenamePillarsDialog> {
  late final _fields = {
    for (final branch in BranchType.values)
      branch: TextEditingController(
        text: ref.read(rpgStateProvider).configFor(branch).customName,
      ),
  };

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    final store = ref.read(rpgStoreProvider.notifier);
    for (final MapEntry(key: branch, value: field) in _fields.entries) {
      await store.renameBranch(branch, field.text);
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rpgStateProvider);
    final active = state.activeBranches;
    return AlertDialog(
      title: const Text('Pillar Names'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final branch in [
              ...active,
              for (final b in BranchType.values)
                if (!active.contains(b)) b,
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  key: ValueKey('rename-${branch.name}'),
                  controller: _fields[branch],
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(
                      BranchConfig.maxNameLength,
                    ),
                  ],
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(
                      branch.icon,
                      size: 18,
                      color: branch.color,
                    ),
                    hintText: branch.displayName,
                    helperText: active.contains(branch)
                        ? null
                        : 'Resting · bring it back at season rollover',
                  ),
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
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
