import 'package:flutter/material.dart';

import 'theme.dart';

/// Marks the deep-link target row: surface3 plate with a 2 pt fg1 left bar.
class SettingsTargetPlate extends StatelessWidget {
  const SettingsTargetPlate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(children: [
        Container(color: AppColors.surface3, child: child),
        Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 2,
            child: ColoredBox(color: AppColors.fg1)),
      ]);
}

/// Scrolls [key]'s row into view once it has been laid out.
void revealSettingsTarget(GlobalKey key) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final ctx = key.currentContext;
    if (ctx != null && ctx.mounted) {
      Scrollable.ensureVisible(ctx,
          alignment: 0.2, duration: const Duration(milliseconds: 1));
    }
  });
}

/// Page body inside the Settings dialog: the host draws title and close, so
/// the page keeps 24 pt side padding, left-aligned, with an optional
/// description row and primary action.
class SettingsChromelessPage extends StatelessWidget {
  const SettingsChromelessPage({
    super.key,
    required this.children,
    this.description = '',
    this.action,
  });
  final List<Widget> children;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (description.isNotEmpty || action != null) ...[
            Row(children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Text(description,
                        style: sans(12, weight: W.body, color: AppColors.fg3)),
                  ),
                ),
              ),
              if (action != null) ...[const SizedBox(width: 8), action!],
            ]),
            const SizedBox(height: 16),
          ],
          ...children,
        ]),
      );
}
