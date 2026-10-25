import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../domain/rpg_engine.dart';
import '../providers/rpg_store_provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/loot_table_view.dart';
import '../widgets/quest_form_sheet.dart';
import '../widgets/quest_log_view.dart';

/// Tab 3: "Quest Log (Feats)" and "Loot Table".
class QuestsLootScreen extends ConsumerStatefulWidget {
  const QuestsLootScreen({super.key});

  @override
  ConsumerState<QuestsLootScreen> createState() => _QuestsLootScreenState();
}

class _QuestsLootScreenState extends ConsumerState<QuestsLootScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() => setState(() {}));
  int? _month;

  int get _currentMonth {
    final state = ref.read(rpgStateProvider);
    return RpgEngine.calculateSeasonMonthIndex(
      state.currentSeason,
      ref.watch(todayProvider),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(rpgStateProvider);
    final current = _currentMonth;
    final month = _month ?? current;
    final styles = RpgStyles.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          TabBar(
            controller: _tabs,
            indicatorColor: RpgColors.gold,
            labelColor: RpgColors.gold,
            unselectedLabelColor: RpgColors.ink,
            labelStyle: styles.stat.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            unselectedLabelStyle: styles.stat.copyWith(fontSize: 13),
            dividerColor: RpgColors.outline,
            tabs: const [
              Tab(
                icon: Icon(LucideIcons.scrollText, size: 18),
                text: 'Quest Log (Feats)',
              ),
              Tab(icon: Icon(LucideIcons.gem, size: 18), text: 'Loot Table'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                QuestLogView(
                  monthIndex: month,
                  currentMonthIndex: current,
                  onMonthChanged: (m) => setState(() => _month = m),
                  onAddMainQuest: () => showQuestFormSheet(
                    context,
                    monthIndex: month,
                    isMainQuest: true,
                  ),
                  onAddSideQuest: () =>
                      showQuestFormSheet(context, monthIndex: month),
                ),
                const LootTableView(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _tabs.index == 0
          ? FloatingActionButton.extended(
              onPressed: () => showQuestFormSheet(context, monthIndex: month),
              backgroundColor: RpgColors.gold,
              foregroundColor: RpgColors.obsidian,
              icon: const Icon(LucideIcons.plus),
              label: const Text('New Quest'),
            )
          : null,
    );
  }
}
