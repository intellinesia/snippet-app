import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../settings_form.dart';
import '../theme.dart';
import '../widgets.dart';
import 'settings_panel.dart';

export 'settings_panel.dart' show SettingsPage;

class DesktopSettingsPage extends StatefulWidget {
  const DesktopSettingsPage({
    super.key,
    required this.client,
    required this.instances,
    required this.active,
    required this.onRemove,
    this.onRename,
    this.onSelect,
    this.onAdd,
    required this.onBack,
    this.initialSection,
    this.fullPage = false,
    this.navWidth = _navWidth,
  });

  final DaemonClient client;
  final List<Instance> instances;
  final Instance? active;
  final void Function(Instance) onRemove;
  final void Function(Instance, String)? onRename;
  final void Function(Instance)? onSelect;
  final void Function(Instance)? onAdd;
  final VoidCallback onBack;
  final SettingsPage? initialSection;

  /// Takes the whole window: a back row heads the nav, content is centred.
  final bool fullPage;
  final double navWidth;

  @override
  State<DesktopSettingsPage> createState() => _DesktopSettingsPageState();
}

typedef _NavEntry = ({
  SettingsPage page,
  String label,
  String? icon,
  IconData? iconData,
});

const List<(String, List<_NavEntry>)> _groups = [
  (
    'This machine',
    [
      (
        page: SettingsPage.general,
        label: 'Machines',
        icon: null,
        iconData: LucideIcons.laptop300,
      ),
    ],
  ),
  (
    'Models',
    [
      (
        page: SettingsPage.models,
        label: 'Inference profiles',
        icon: 'cpu',
        iconData: null,
      ),
      (
        page: SettingsPage.routing,
        label: 'Routing',
        icon: 'route',
        iconData: null,
      ),
      (
        page: SettingsPage.accounts,
        label: 'Accounts',
        icon: 'users',
        iconData: null,
      ),
      (
        page: SettingsPage.usage,
        label: 'Usage',
        icon: 'gauge',
        iconData: null,
      ),
    ],
  ),
  (
    'Agents',
    [
      (
        page: SettingsPage.memory,
        label: 'Memory',
        icon: 'book-marked',
        iconData: null,
      ),
      (
        page: SettingsPage.wakes,
        label: 'Wakes',
        icon: 'repeat',
        iconData: null,
      ),
      (
        page: SettingsPage.keepWarm,
        label: 'Keep warm',
        icon: 'zap',
        iconData: null,
      ),
      (
        page: SettingsPage.scheduled,
        label: 'Scheduled',
        icon: 'calendar-clock',
        iconData: null,
      ),
      (
        page: SettingsPage.vault,
        label: 'Vault',
        icon: 'lock',
        iconData: null,
      ),
      (
        page: SettingsPage.webSearch,
        label: 'Web search',
        icon: 'globe',
        iconData: null,
      ),
      (
        page: SettingsPage.voice,
        label: 'Voice',
        icon: 'mic',
        iconData: null,
      ),
    ],
  ),
  (
    'This device',
    [
      (
        page: SettingsPage.appearance,
        label: 'Theme and accent',
        icon: 'sliders',
        iconData: null,
      ),
    ],
  ),
];

/// Round 5 density: a 224 rail of 30px rows.
const double _navWidth = 224;
const double _navRowHeight = 30;

class _DesktopSettingsPageState extends State<DesktopSettingsPage> {
  late SettingsPage _section = widget.initialSection ?? SettingsPage.general;

  @override
  void didUpdateWidget(covariant DesktopSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSection != null &&
        widget.initialSection != oldWidget.initialSection) {
      _section = widget.initialSection!;
    }
  }

  void _selectSection(SettingsPage page) {
    if (_section == page) return;
    setState(() => _section = page);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    if (kMobile) {
      return SettingsPanel(
        client: widget.client,
        instances: widget.instances,
        active: widget.active,
        onRemove: widget.onRemove,
        onRename: widget.onRename,
        onSelect: widget.onSelect,
        onAdd: widget.onAdd,
        onClose: widget.onBack,
        initialPage: _section,
      );
    }
    final borderSide =
        BorderSide(color: AppColors.line.withValues(alpha: 0.65));
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onBack,
      },
      child: Focus(
        autofocus: true,
        child: Material(
          // The dialog sat on glass; the full page must hide the app behind it.
          color: widget.fullPage ? AppColors.bg : AppColors.paneBg,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: widget.navWidth,
                decoration: BoxDecoration(
                  color: AppColors.tint1,
                  border: Border(right: borderSide),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.fullPage)
                      Padding(
                        // Clears the macOS traffic lights.
                        padding:
                            EdgeInsets.fromLTRB(12, kMacOS ? 40 : 12, 12, 0),
                        child: _BackRow(onTap: widget.onBack),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: Text('Settings',
                          style: sans(14,
                              weight: FontWeight.w600, color: AppColors.fg1)),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        children: [
                          for (final (group, entries) in _groups) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
                              child: Text(group,
                                  style: sans(12, color: Grouped.label)),
                            ),
                            for (final entry in entries)
                              _NavRow(
                                entry: entry,
                                selected: _section == entry.page,
                                onTap: () => _selectSection(entry.page),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Stack(children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color:
                          kMobile ? AppColors.pageCanvas : Colors.transparent,
                      child: _centred(SettingsSectionView(
                        client: widget.client,
                        instances: widget.instances,
                        active: widget.active,
                        page: _section,
                        onRemove: widget.onRemove,
                        onRename: widget.onRename,
                        onSelect: widget.onSelect,
                        onAdd: widget.onAdd,
                        onSelectPage: _selectSection,
                        onClose: widget.onBack,
                        v5Desktop: true,
                      )),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on _DesktopSettingsPageState {
  Widget _centred(Widget child) => !widget.fullPage
      ? child
      : Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820), child: child),
        );
}

class _BackRow extends StatelessWidget {
  const _BackRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HoverSurface(
        onTap: onTap,
        radius: R.of(12),
        hoverColor: AppColors.fg1.withValues(alpha: 0.035),
        child: SizedBox(
          height: _navRowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              AppIcon('chevron-left', size: 16, color: AppColors.fg3),
              const SizedBox(width: 10),
              Text('Back to app', style: sans(13, color: AppColors.fg2)),
            ]),
          ),
        ),
      );
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final _NavEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconColor = selected ? AppColors.fg1 : Grouped.iconColor;
    final radius = R.of(12);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: HoverSurface(
        onTap: onTap,
        selected: selected,
        radius: radius,
        selectedColor: Grouped.row,
        hoverColor: AppColors.fg1.withValues(alpha: 0.035),
        child: SizedBox(
          height: _navRowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              entry.iconData != null
                  ? Icon(entry.iconData, size: 16, color: iconColor)
                  : AppIcon(entry.icon!, size: 16, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, color: AppColors.fg1),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
