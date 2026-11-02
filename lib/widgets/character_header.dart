import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/rpg_models.dart';
import '../providers/rpg_store_provider.dart';
import '../screens/character_screen.dart';
import '../screens/codex_guide_screen.dart';
import '../theme/rpg_theme.dart';
import 'character_share_card.dart';
import 'level_badge.dart';
import 'pixel_avatar.dart';
import 'settings_section.dart';

/// Persistent top bar: avatar with level, name, class title and season day
/// counter. Tapping the avatar opens the Character page.
class CharacterHeader extends ConsumerWidget implements PreferredSizeWidget {
  const CharacterHeader({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(104);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(rpgStoreProvider);
    final sheet = ref.watch(characterSheetProvider);
    final theme = Theme.of(context);
    final styles = RpgStyles.of(context);

    final character = store.value?.character;
    final season = store.value?.currentSeason;
    final sheetValue = sheet.value;

    return Material(
      color: RpgColors.obsidian,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: preferredSize.height,
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: RpgColors.outline)),
          ),
          child: Row(
            children: [
              _AvatarButton(
                avatar: character?.avatarOrDefault,
                level: sheetValue?.totalLevel ?? 0,
                onTap: character == null
                    ? null
                    : () => openCharacterPage(context),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      character?.name ?? '…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: RpgColors.parchment,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      character?.classTitle ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: RpgColors.gold,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (sheetValue != null && season != null)
                      _SeasonCounter(
                        label: sheetValue.isSeasonOver
                            ? '${season.name} complete • Level up in Tally'
                            : '${season.name} • Day ${sheetValue.seasonDay}/${sheetValue.seasonLength}',
                        progress:
                            sheetValue.seasonDay / sheetValue.seasonLength,
                        style: styles.stat,
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: "Adventurer's Codex",
                icon: const Icon(LucideIcons.bookOpen, color: RpgColors.gold),
                onPressed: () => openCodex(context),
              ),
              IconButton(
                tooltip: 'Share Character Card',
                icon: const Icon(LucideIcons.share2, color: RpgColors.gold),
                onPressed: sheetValue == null
                    ? null
                    : () => showCharacterShareSheet(context),
              ),
              PopupMenuButton<String>(
                tooltip: 'Character options',
                icon: const Icon(
                  LucideIcons.moreVertical,
                  color: RpgColors.ink,
                ),
                onSelected: (_) => confirmWipeAndRestart(context, ref),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'wipe',
                    child: Text('Wipe character & restart'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarButton extends StatelessWidget {
  const _AvatarButton({
    required this.avatar,
    required this.level,
    required this.onTap,
  });

  final AvatarSpec? avatar;
  final int level;
  final VoidCallback? onTap;

  static const double _size = 60;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Tooltip(
          message: 'Character page',
          child: Semantics(
            button: true,
            label: 'Character page',
            excludeSemantics: true,
            child: GestureDetector(
              key: const ValueKey('header-avatar'),
              onTap: onTap,
              child: avatar != null
                  ? PixelAvatar(spec: avatar!, size: _size)
                  : const SizedBox.square(dimension: _size),
            ),
          ),
        ),
        // A sibling, not a child, so "Level N" stays its own label.
        Positioned(
          right: -10,
          bottom: -8,
          child: GestureDetector(
            onTap: onTap,
            child: LevelBadge(level: level, size: 30),
          ),
        ),
      ],
    );
  }
}

class _SeasonCounter extends StatelessWidget {
  const _SeasonCounter({
    required this.label,
    required this.progress,
    required this.style,
  });

  final String label;
  final double progress;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 56,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress.clamp(0, 1),
              minHeight: 3,
              color: RpgColors.gold,
              backgroundColor: RpgColors.outline,
            ),
          ),
        ),
      ],
    );
  }
}
