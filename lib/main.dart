import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/platform/sqlite_setup.dart';
import 'screens/root_gate.dart';
import 'theme/rpg_theme.dart';

void main() {
  configureSqlite();
  runApp(const ProviderScope(child: LevelUpApp()));
}

class LevelUpApp extends StatelessWidget {
  const LevelUpApp({super.key, this.useGoogleFonts = true});

  /// Disabled in widget tests, which can't fetch fonts.
  final bool useGoogleFonts;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'levelUp',
      debugShowCheckedModeBanner: false,
      theme: RpgTheme.dark(useGoogleFonts: useGoogleFonts),
      home: const RootGate(),
    );
  }
}
