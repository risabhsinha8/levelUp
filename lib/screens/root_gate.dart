import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../providers/rpg_store_provider.dart';
import '../theme/rpg_theme.dart';
import 'home_shell.dart';
import 'onboarding/onboarding_screen.dart';

/// Root router (`LevelUpApp.home`): a loading screen while SQLite opens,
/// Session Zero while no character exists, otherwise the app.
class RootGate extends ConsumerWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(rpgStoreProvider);
    // Swaps instantly (no cross-fade): screens under HomeShell assume a
    // character exists, so HomeShell must unmount as soon as it's gone.
    if (store.hasError && !store.hasValue) {
      return _LoadError(error: store.error!);
    }
    if (!store.hasValue) return const StartupLoadingScreen();
    return ref.watch(isOnboardedProvider)
        ? const HomeShell()
        : const OnboardingScreen();
  }
}

class _LoadError extends ConsumerWidget {
  const _LoadError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        // Scrolls because the error text can be arbitrarily long (e.g. a
        // SQLite exception that echoes the failing statement and arguments).
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.alertTriangle, color: RpgColors.danger),
              const SizedBox(height: 12),
              Text(
                'Could not open your character sheet.',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: SelectableText(
                  '$error',
                  style: RpgStyles.of(context).stat,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.invalidate(rpgStoreProvider),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown while the SQLite database opens and loads on startup.
class StartupLoadingScreen extends StatelessWidget {
  const StartupLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    return Scaffold(
      backgroundColor: RpgColors.obsidian,
      body: Center(
        child: Semantics(
          label: 'Loading your character sheet',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: RpgColors.gold, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: RpgColors.gold.withValues(alpha: 0.35),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: const Icon(
                  LucideIcons.dice5,
                  size: 36,
                  color: RpgColors.gold,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'levelUp',
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(color: RpgColors.gold),
              ),
              const SizedBox(height: 6),
              Text('Unrolling your character sheet…', style: styles.stat),
              const SizedBox(height: 20),
              const SizedBox(
                width: 140,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: RpgColors.gold,
                  backgroundColor: RpgColors.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
