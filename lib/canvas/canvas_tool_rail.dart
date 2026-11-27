import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// One entry in the vertical tool rail. A null [onTap] renders it disabled.
class CanvasRailTool {
  const CanvasRailTool({
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
    this.disabledHint,
  });

  final String icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final String? disabledHint;
}

/// Floating vertical rail of canvas tools (desktop).
class CanvasToolRail extends StatelessWidget {
  const CanvasToolRail({super.key, required this.tools});

  final List<CanvasRailTool> tools;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.all(S.s4),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(R.of(10)),
          border: Border.all(color: AppColors.paneLine, width: AppColors.hairline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (final t in tools) _RailButton(tool: t)],
        ),
      );
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.tool});
  final CanvasRailTool tool;

  @override
  Widget build(BuildContext context) {
    final enabled = tool.onTap != null;
    final fg = !enabled
        ? AppColors.fg4
        : tool.active
            ? PaneRow.labelOn
            : AppColors.fg3;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: tool.active,
      label: tool.label,
      hint: tool.disabledHint,
      excludeSemantics: true,
      child: Tooltip(
        message:
            enabled ? tool.label : '${tool.label}. ${tool.disabledHint ?? ''}',
        child: Material(
          color: tool.active ? PaneRow.plate : Colors.transparent,
          borderRadius: BorderRadius.circular(PaneRow.radius),
          child: InkWell(
            onTap: tool.onTap,
            borderRadius: BorderRadius.circular(PaneRow.radius),
            child: SizedBox(
              width: 28,
              height: 28,
              child: Center(
                child: AppIcon(tool.icon,
                    size: 13, color: fg, filled: tool.active),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
