import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'settings_pages.dart';
import 'settings_panel.dart';

export 'settings_panel.dart' show SettingsPage;
export 'settings_pages.dart'
    show kSettingsGroups, settingsPageLabel, settingsPageIcon;

SettingsPage _lastPage = SettingsPage.general;

/// The one Settings entry (spec S0): Settings is an overlay, never a tab or
/// a destination: a centred modal dialog on desktop, a sheet on the phone.
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
    // Spec D1: scrim over the whole window, no blur.
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
    transitionBuilder: (ctx, animation, _, child) {
      final t = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
          reverseCurve: Curves.easeOut);
      return FadeTransition(
        opacity: t,
        // The card enters with an 8 px rise; reduced motion keeps only the
        // 1 ms fade.
        child: still
            ? child
            : AnimatedBuilder(
                animation: t,
                builder: (_, child) => Transform.translate(
                  offset: Offset(0, 8 * (1 - t.value)),
                  child: child,
                ),
                child: child,
              ),
      );
    },
  );
}

/// The dialog shell (spec D1): centred surface2 card, list column on the
/// left, content pane with a 48-high header on the right. Esc closes.
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
    final dark = AppColors.bg.computeLuminance() < 0.5;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(builder: (context, c) {
          // Spec D1: min(960, 90% width) x min(640, 90% height), centred.
          final w = math.min(960.0, c.maxWidth * 0.9);
          final h = math.min(640.0, c.maxHeight * 0.9);
          // The list column collapses under 800; it narrows under 1100 (D7).
          final listW =
              c.maxWidth < 800 ? 0.0 : (c.maxWidth < 1100 ? 208.0 : 240.0);
          return Center(
            child: SizedBox(
              key: const Key('settings-card'),
              width: w,
              height: h,
              child: Semantics(
                scopesRoute: true,
                namesRoute: true,
                explicitChildNodes: true,
                label: 'Settings',
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: dark ? 0.4 : 0.22),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Material(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (listW > 0) _listColumn(listW),
                        Expanded(child: _contentPane(context)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Spec D2: surface1 column, radius-12 left corners (the card clips),
  /// 'Settings' 14/500 at x16 y8, 28 high. Rows and search land in D2's step.
  Widget _listColumn(double width) => Container(
        key: const Key('settings-list'),
        width: width,
        color: AppColors.surface1,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: SizedBox(
            height: 28,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Settings',
                  style: sans(14, weight: W.label, color: AppColors.fg1)),
            ),
          ),
        ),
      );

  /// Spec D1: content pane, 48-high header: page title, 'Esc' hint, a 28x28
  /// Close target: and a hairline under it, then the page body.
  Widget _contentPane(BuildContext context) => Column(
        key: const Key('settings-content'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            key: const Key('settings-header'),
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(children: [
                Expanded(
                  child: Text(
                    settingsPageLabel(page),
                    key: const Key('settings-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(16, weight: W.label, color: AppColors.fg1),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('Esc',
                      key: const Key('settings-esc-hint'),
                      style: sans(11, weight: W.body, color: AppColors.fg3)),
                ),
                Semantics(
                  button: true,
                  label: 'Close settings',
                  child: SizedBox(
                    key: const Key('settings-close'),
                    width: 28,
                    height: 28,
                    child: IconBtn('x',
                        size: 28,
                        iconSize: 14,
                        tooltip: 'Close settings',
                        onTap: () => Navigator.of(context).maybePop()),
                  ),
                ),
              ]),
            ),
          ),
          Container(height: 1, color: AppColors.line),
          Expanded(
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
        ],
      );
}
