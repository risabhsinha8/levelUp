import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../providers/rpg_store_provider.dart';
import '../widgets/character_header.dart';
import 'quests_loot_screen.dart';
import 'season_tally_screen.dart';
import 'skill_tree_screen.dart';
import 'today_grid_screen.dart';

class _ShellTab {
  const _ShellTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

const _tabs = [
  _ShellTab('Today & Grid', LucideIcons.calendarCheck),
  _ShellTab('Skill Tree', LucideIcons.network),
  _ShellTab('Quests & Loot', LucideIcons.swords),
  _ShellTab('Season Tally', LucideIcons.barChart3),
];

/// Main navigation shell: persistent character header plus 4 tabs.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A phone app is often resumed the next morning: re-check the date so
  /// Today's Focus doesn't keep logging against yesterday.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(todayProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CharacterHeader(),
      body: IndexedStack(
        index: _index,
        children: [
          // Hidden tabs stay built; muting their tickers stops looping
          // animations (e.g. ready-to-forge nodes) from running offscreen.
          for (final (i, screen) in const [
            TodayGridScreen(),
            SkillTreeScreen(),
            QuestsLootScreen(),
            SeasonTallyScreen(),
          ].indexed)
            TickerMode(enabled: i == _index, child: screen),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(icon: Icon(tab.icon), label: tab.label),
        ],
      ),
    );
  }
}
