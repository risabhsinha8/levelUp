import 'package:flutter/material.dart';

import 'package:lucide_icons/lucide_icons.dart';

import '../theme/rpg_theme.dart';

/// Opens a sheet explaining a stat: its [title], optional current [value]
/// and what it means ([body], paragraphs split by blank lines).
Future<void> showStatInfo(
  BuildContext context, {
  required String title,
  String? value,
  required String body,
}) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: RpgColors.slateRaised,
  builder: (context) {
    final theme = Theme.of(context);
    final styles = RpgStyles.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.info, size: 18, color: RpgColors.gold),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
            ],
          ),
          if (value != null) ...[
            const SizedBox(height: 8),
            Text(
              value,
              style: styles.statLarge.copyWith(color: RpgColors.parchment),
            ),
          ],
          for (final paragraph in body.split('\n\n')) ...[
            const SizedBox(height: 10),
            Text(
              paragraph,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: RpgColors.parchment,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  },
);

/// Small ⓘ button that opens [showStatInfo].
class StatInfoButton extends StatelessWidget {
  const StatInfoButton({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'About $title',
    visualDensity: VisualDensity.compact,
    iconSize: 16,
    color: RpgColors.goldDim,
    icon: const Icon(LucideIcons.info),
    onPressed: () => showStatInfo(context, title: title, body: body),
  );
}

/// A titled card section on the Character and history pages.
class StatSection extends StatelessWidget {
  const StatSection({
    super.key,
    required this.title,
    this.subtitle,
    this.info,
    required this.child,
  });

  final String title;
  final String? subtitle;

  /// What the section shows, behind an ⓘ next to the title.
  final String? info;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (info != null) StatInfoButton(title: title, body: info!),
            ],
          ),
          if (subtitle != null)
            Text(subtitle!, style: styles.stat.copyWith(fontSize: 11)),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(padding: const EdgeInsets.all(14), child: child),
          ),
        ],
      ),
    );
  }
}

/// One headline number with an icon and a label.
class StatTile {
  const StatTile({
    required this.icon,
    required this.value,
    required this.label,
    this.info,
  });

  final IconData icon;
  final String value;
  final String label;

  /// What the number means; when set, tapping the tile explains it.
  final String? info;
}

/// [tiles] in a grid of [columns].
class StatTileGrid extends StatelessWidget {
  const StatTileGrid({super.key, required this.columns, required this.tiles});

  final int columns;
  final List<StatTile> tiles;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    const gap = 8.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles)
              SizedBox(
                width: width,
                child: Material(
                  color: RpgColors.obsidian,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: RpgColors.outline),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: tile.info == null
                        ? null
                        : () => showStatInfo(
                            context,
                            title: tile.label,
                            value: tile.value,
                            body: tile.info!,
                          ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(tile.icon, size: 16, color: RpgColors.gold),
                              const Spacer(),
                              if (tile.info != null)
                                const Icon(
                                  LucideIcons.info,
                                  size: 12,
                                  color: RpgColors.goldDim,
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              tile.value,
                              style: styles.statLarge.copyWith(
                                fontSize: 22,
                                color: RpgColors.parchment,
                              ),
                            ),
                          ),
                          Text(
                            tile.label,
                            maxLines: 2,
                            style: styles.stat.copyWith(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
