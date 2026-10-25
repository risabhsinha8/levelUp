import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/rpg_theme.dart';
import '../widgets/habit_matrix_view.dart';
import '../widgets/today_focus_view.dart';

enum _TodayGridView { focus, matrix }

/// Tab 1: switches between "Today's Focus" and the "Monthly Matrix".
class TodayGridScreen extends StatefulWidget {
  const TodayGridScreen({super.key});

  @override
  State<TodayGridScreen> createState() => _TodayGridScreenState();
}

class _TodayGridScreenState extends State<TodayGridScreen> {
  _TodayGridView _view = _TodayGridView.focus;

  @override
  Widget build(BuildContext context) {
    final labelStyle = RpgStyles.of(context).stat.copyWith(fontSize: 12);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<_TodayGridView>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: RpgColors.gold.withValues(alpha: 0.16),
                selectedForegroundColor: RpgColors.gold,
                foregroundColor: RpgColors.ink,
                side: const BorderSide(color: RpgColors.outline),
                textStyle: labelStyle,
              ),
              segments: const [
                ButtonSegment(
                  value: _TodayGridView.focus,
                  icon: Icon(LucideIcons.sun, size: 16),
                  label: Text("Today's Focus"),
                ),
                ButtonSegment(
                  value: _TodayGridView.matrix,
                  icon: Icon(LucideIcons.layoutGrid, size: 16),
                  label: Text('Monthly Matrix'),
                ),
              ],
              selected: {_view},
              onSelectionChanged: (selection) =>
                  setState(() => _view = selection.single),
            ),
          ),
        ),
        Expanded(
          child: switch (_view) {
            _TodayGridView.focus => const TodayFocusView(),
            _TodayGridView.matrix => const HabitMatrixView(),
          },
        ),
      ],
    );
  }
}
