import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../providers/rpg_store_provider.dart';
import '../screens/codex_guide_screen.dart';
import '../theme/rpg_theme.dart';

/// Asks for confirmation, then wipes SQLite and returns to onboarding.
Future<void> confirmWipeAndRestart(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Wipe character & restart?'),
      content: const Text(
        'This permanently deletes your character, habits, logs, quests and '
        'loot from this device and returns to Session Zero. Export a backup '
        'first if you want to keep them.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: RpgColors.danger),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Wipe & Restart'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await ref.read(rpgStoreProvider.notifier).wipeDatabaseAndRestart();
  }
}

/// Character editing, JSON backup export/import, and wipe & restart.
class SettingsSection extends ConsumerWidget {
  const SettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final character = ref.watch(rpgStateProvider).character;
    final store = ref.read(rpgStoreProvider.notifier);

    return Card(
      child: Column(
        children: [
          _SettingsTile(
            icon: LucideIcons.bookOpen,
            title: "Adventurer's Codex",
            subtitle: 'How points, nodes, levels and keys work',
            onTap: () => openCodex(context),
          ),
          const Divider(height: 1),
          _SettingsTile(
            icon: LucideIcons.userCog,
            title: 'Edit Name & Class',
            subtitle: '${character.name} · ${character.classTitle}',
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => _EditCharacterDialog(
                name: character.name,
                classTitle: character.classTitle,
                onSave: (name, title) =>
                    store.updateCharacter(name: name, classTitle: title),
              ),
            ),
          ),
          const Divider(height: 1),
          _SettingsTile(
            icon: LucideIcons.download,
            title: 'Export Backup JSON',
            subtitle: 'Copies your full save to the clipboard',
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final json = await store.exportBackup();
              await Clipboard.setData(ClipboardData(text: json));
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    'Backup copied to clipboard '
                    '(${(json.length / 1024).toStringAsFixed(1)} KB).',
                  ),
                ),
              );
            },
          ),
          const Divider(height: 1),
          _SettingsTile(
            icon: LucideIcons.upload,
            title: 'Import Backup JSON',
            subtitle: 'Restore from a backup you exported',
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => const ImportBackupDialog(),
            ),
          ),
          const Divider(height: 1),
          _SettingsTile(
            icon: LucideIcons.rotateCcw,
            title: 'Wipe Character & Restart Onboarding',
            subtitle: 'Deletes everything and returns to Session Zero',
            destructive: true,
            onTap: () => confirmWipeAndRestart(context, ref),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: destructive ? RpgColors.danger : RpgColors.gold,
        size: 20,
      ),
      title: Text(
        title,
        style: destructive ? const TextStyle(color: RpgColors.danger) : null,
      ),
      subtitle: Text(
        subtitle,
        style: RpgStyles.of(context).stat.copyWith(fontSize: 11),
      ),
      trailing: const Icon(
        LucideIcons.chevronRight,
        size: 16,
        color: RpgColors.ink,
      ),
      onTap: onTap,
    );
  }
}

class _EditCharacterDialog extends StatefulWidget {
  const _EditCharacterDialog({
    required this.name,
    required this.classTitle,
    required this.onSave,
  });

  final String name;
  final String classTitle;
  final Future<void> Function(String name, String classTitle) onSave;

  @override
  State<_EditCharacterDialog> createState() => _EditCharacterDialogState();
}

class _EditCharacterDialogState extends State<_EditCharacterDialog> {
  late final _name = TextEditingController(text: widget.name);
  late final _class = TextEditingController(text: widget.classTitle);

  @override
  void dispose() {
    _name.dispose();
    _class.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty && _class.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Character'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _class,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Class title',
              hintText: 'e.g. Recovering Couch Potato',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid
              ? () async {
                  final navigator = Navigator.of(context);
                  await widget.onSave(_name.text.trim(), _class.text.trim());
                  navigator.pop();
                }
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Paste-and-restore dialog for a JSON backup. Used from Settings and from
/// onboarding.
class ImportBackupDialog extends ConsumerStatefulWidget {
  const ImportBackupDialog({super.key});

  @override
  ConsumerState<ImportBackupDialog> createState() => _ImportBackupDialogState();
}

class _ImportBackupDialogState extends ConsumerState<ImportBackupDialog> {
  final _json = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _json.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) setState(() => _json.text = data!.text!);
  }

  Future<void> _restore() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(rpgStoreProvider.notifier).importBackup(_json.text);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    } catch (e) {
      setState(() => _error = 'Could not restore this backup: $e');
      return;
    }
    navigator.pop();
    messenger.showSnackBar(const SnackBar(content: Text('Backup restored.')));
  }

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    return AlertDialog(
      title: const Text('Import Backup'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paste a backup exported from levelUp. This replaces all '
              'current data.',
              style: styles.stat,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _json,
              minLines: 4,
              maxLines: 8,
              style: styles.stat.copyWith(color: RpgColors.parchment),
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                hintText: '{ "schemaVersion": 1, … }',
                errorText: _error,
                errorMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _paste,
                icon: const Icon(LucideIcons.clipboardPaste, size: 16),
                label: const Text('Paste'),
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
          onPressed: _json.text.trim().isEmpty ? null : _restore,
          child: const Text('Restore'),
        ),
      ],
    );
  }
}
