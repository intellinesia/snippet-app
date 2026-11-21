import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets.dart';
import '../../tap_detector.dart';

enum TaskView { board, list }

/// Board / List segmented switch for the desktop Tasks tab.
class TaskViewToggle extends StatelessWidget {
  const TaskViewToggle(
      {super.key, required this.value, required this.onChanged});

  final TaskView value;
  final ValueChanged<TaskView> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(TaskView v, String label, String icon) {
      final on = v == value;
      return TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(v),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: on ? AppColors.surface3 : Colors.transparent,
            borderRadius: BorderRadius.circular(R.of(8)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon(icon, size: 13, color: on ? AppColors.fg1 : AppColors.fg3),
            const SizedBox(width: 6),
            Text(label,
                style: sans(12, color: on ? AppColors.fg1 : AppColors.fg3)),
          ]),
        ),
      );
    }

    return Container(
      height: 28,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.of(8)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg(TaskView.board, 'Board', 'kanban'),
        seg(TaskView.list, 'List', 'list'),
      ]),
    );
  }
}
