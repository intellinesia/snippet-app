import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import 'settings_panel.dart';

export 'settings_panel.dart' show SettingsPage;
export 'settings_pages.dart'
    show kSettingsGroups, settingsPageLabel, settingsPageIcon;

SettingsPage _lastPage = SettingsPage.general;

/// The one Settings entry (spec S0): Settings is an overlay, never a tab or
/// a destination. Today this is the minimal desktop dialog: a centred card
/// hosting the page body; the list column, search and the phone sheet land
/// in the next steps of the Wave-3 spec.
Future<void> showSettings(
  BuildContext context, {
  required DaemonClient client,
  required List<Instance> instances,
  required Instance? active,
  required void Function(Instance) onRemove,
  void Function(Instance, String)? onRename,
  void Function(Instance)? onSelect,
  void Function(Instance)? onAdd,
  SettingsPage? page,
  String? backLabel,
}) {
  // Session-scoped: a plain reopen lands where the user last was.
  if (page != null) _lastPage = page;
  final shown = _lastPage;
  final still = reduceMotion(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close settings',
    barrierColor: AppColors.scrim,
    transitionDuration:
        still ? const Duration(milliseconds: 1) : const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, __) => _SettingsDialog(
      client: client,
      instances: instances,
      active: active,
      onRemove: onRemove,
      onRename: onRename,
      onSelect: onSelect,
      onAdd: onAdd,
      page: shown,
    ),
  );
}

/// Placeholder dialog (spec D1): centred surface2 card, radius 12,
/// min(960, 90% width) x min(640, 90% height), Esc closes.
class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog({
    required this.client,
    required this.instances,
    required this.active,
    required this.onRemove,
    required this.page,
    this.onRename,
    this.onSelect,
    this.onAdd,
  });

  final DaemonClient client;
  final List<Instance> instances;
  final Instance? active;
  final void Function(Instance) onRemove;
  final void Function(Instance, String)? onRename;
  final void Function(Instance)? onSelect;
  final void Function(Instance)? onAdd;
  final SettingsPage page;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(builder: (context, c) {
          final w = math.min(960.0, (c.maxWidth * 0.9).floorToDouble());
          final h = math.min(640.0, (c.maxHeight * 0.9).floorToDouble());
          return Center(
            child: SizedBox(
              width: w,
              height: h,
              child: Material(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: SettingsSectionView(
                  client: client,
                  instances: instances,
                  active: active,
                  page: page,
                  chromeless: true,
                  v5Desktop: true,
                  onRemove: onRemove,
                  onRename: onRename,
                  onSelect: onSelect,
                  onAdd: onAdd,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
