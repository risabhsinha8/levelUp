import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/rpg_models.dart';

/// "Tactile Dark Folio" palette.
abstract final class RpgColors {
  static const obsidian = Color(0xFF121316);
  static const slate = Color(0xFF1A1C21);
  static const slateRaised = Color(0xFF23262C);
  static const outline = Color(0xFF34373F);
  static const gold = Color(0xFFD4AF37);
  static const goldDim = Color(0xFF8C7424);
  static const parchment = Color(0xFFEDE4CF);
  static const ink = Color(0xFF9C978B);
  static const danger = Color(0xFFE5484D);

  /// Campfire glow for the mid-month reflection.
  static const ember = Color(0xFFFF8A3D);
}

extension BranchColor on BranchType {
  Color get color => Color(colorValue);

  IconData get icon => switch (this) {
    BranchType.mind => LucideIcons.brain,
    BranchType.body => LucideIcons.dumbbell,
    BranchType.craft => LucideIcons.hammer,
    BranchType.bond => LucideIcons.heartHandshake,
    BranchType.empire => LucideIcons.castle,
  };
}

/// Extra text styles the stock [TextTheme] has no slot for.
@immutable
class RpgStyles extends ThemeExtension<RpgStyles> {
  const RpgStyles({required this.stat, required this.statLarge});

  /// Monospace style for numbers, counters and stat labels.
  final TextStyle stat;
  final TextStyle statLarge;

  static RpgStyles of(BuildContext context) =>
      Theme.of(context).extension<RpgStyles>()!;

  @override
  RpgStyles copyWith({TextStyle? stat, TextStyle? statLarge}) => RpgStyles(
    stat: stat ?? this.stat,
    statLarge: statLarge ?? this.statLarge,
  );

  @override
  RpgStyles lerp(RpgStyles? other, double t) {
    if (other == null) return this;
    return RpgStyles(
      stat: TextStyle.lerp(stat, other.stat, t)!,
      statLarge: TextStyle.lerp(statLarge, other.statLarge, t)!,
    );
  }
}

abstract final class RpgTheme {
  /// The app theme. Pass `useGoogleFonts: false` in tests, where fonts
  /// can't be fetched over the network.
  static ThemeData dark({bool useGoogleFonts = true}) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: RpgColors.gold,
          brightness: Brightness.dark,
        ).copyWith(
          primary: RpgColors.gold,
          onPrimary: RpgColors.obsidian,
          secondary: RpgColors.parchment,
          surface: RpgColors.slate,
          onSurface: RpgColors.parchment,
          onSurfaceVariant: RpgColors.ink,
          surfaceContainerLowest: RpgColors.obsidian,
          surfaceContainerLow: RpgColors.slate,
          surfaceContainer: RpgColors.slate,
          surfaceContainerHigh: RpgColors.slateRaised,
          surfaceContainerHighest: RpgColors.slateRaised,
          outline: RpgColors.outline,
          outlineVariant: RpgColors.outline,
          error: RpgColors.danger,
        );

    final base =
        ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: colorScheme,
        ).textTheme.apply(
          bodyColor: RpgColors.parchment,
          displayColor: RpgColors.parchment,
        );

    TextStyle serif(TextStyle? style) =>
        useGoogleFonts ? GoogleFonts.cinzel(textStyle: style) : style!;
    TextStyle mono(TextStyle style) =>
        useGoogleFonts ? GoogleFonts.jetBrainsMono(textStyle: style) : style;

    final textTheme = base.copyWith(
      displayLarge: serif(base.displayLarge),
      displayMedium: serif(base.displayMedium),
      displaySmall: serif(base.displaySmall),
      headlineLarge: serif(base.headlineLarge),
      headlineMedium: serif(base.headlineMedium),
      headlineSmall: serif(base.headlineSmall),
      titleLarge: serif(base.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      titleMedium: serif(
        base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );

    final styles = RpgStyles(
      stat: mono(
        const TextStyle(
          fontSize: 12,
          letterSpacing: 0.4,
          color: RpgColors.ink,
          fontWeight: FontWeight.w500,
        ),
      ),
      statLarge: mono(
        const TextStyle(
          fontSize: 20,
          color: RpgColors.parchment,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: RpgColors.obsidian,
      textTheme: textTheme,
      extensions: [styles],
      dividerTheme: const DividerThemeData(
        color: RpgColors.outline,
        thickness: 1,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: RpgColors.obsidian,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: RpgColors.slate,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: RpgColors.outline),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: RpgColors.slate,
        surfaceTintColor: Colors.transparent,
        indicatorColor: RpgColors.gold.withValues(alpha: 0.16),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? RpgColors.gold
                : RpgColors.ink,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => styles.stat.copyWith(
            fontSize: 11,
            color: states.contains(WidgetState.selected)
                ? RpgColors.gold
                : RpgColors.ink,
          ),
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: RpgColors.slateRaised,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: RpgColors.slateRaised,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}

extension LootTierStyle on LootTier {
  String get label => switch (this) {
    LootTier.common => 'Common',
    LootTier.rare => 'Rare',
    LootTier.epic => 'Epic',
    LootTier.legendary => 'Legendary',
  };

  Color get color => switch (this) {
    LootTier.common => const Color(0xFFAEB6C2),
    LootTier.rare => const Color(0xFF4F9DFF),
    LootTier.epic => const Color(0xFFC77DFF),
    LootTier.legendary => const Color(0xFFFFB020),
  };

  /// How keys of this tier are earned.
  String get keySource => switch (this) {
    LootTier.common => 'Every 7-day keystone streak',
    LootTier.rare => 'Every skill node unlocked',
    LootTier.epic => '80 days in a branch',
    LootTier.legendary => 'The entire skill tree',
  };
}
