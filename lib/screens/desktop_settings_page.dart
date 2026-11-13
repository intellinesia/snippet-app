import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
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
    'General',
    [
      (
        page: SettingsPage.general,
        label: 'Machines',
        icon: null,
        iconData: LucideIcons.laptop,
      ),
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
        page: SettingsPage.vault,
        label: 'Vault',
        icon: 'lock',
        iconData: null,
      ),
      (
        page: SettingsPage.wakes,
        label: 'Wakes',
        icon: 'repeat',
        iconData: null,
      ),
      (
        page: SettingsPage.voice,
        label: 'Voice',
        icon: 'mic',
        iconData: null,
      ),
      (
        page: SettingsPage.scheduled,
        label: 'Scheduled',
        icon: 'calendar-clock',
        iconData: null,
      ),
      (
        page: SettingsPage.webSearch,
        label: 'Web search',
        icon: 'globe',
        iconData: null,
      ),
    ],
  ),
  (
    'Appearance',
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
    final borderSide = BorderSide(color: AppColors.line.withValues(alpha: 0.65));
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onBack,
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: AppColors.paneBg,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 224,
                decoration: BoxDecoration(
                  color: AppColors.tint1,
                  border: Border(right: borderSide),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
                      child: Text('Settings',
                          style: sans(16, weight: W.title, color: AppColors.fg1)),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(
                            S.s8, 0, S.s8, S.s12),
                        children: [
                          for (final (group, entries) in _groups) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  10, 14, 10, S.s4),
                              child: Text(group,
                                  style: sans(12, color: AppColors.fg4)),
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
                  color: kMobile ? readingBg : Colors.transparent,
                  child: SettingsSectionView(
                    client: widget.client,
                    instances: widget.instances,
                    active: widget.active,
                    page: _section,
                    onRemove: widget.onRemove,
                    onRename: widget.onRename,
                    onSelect: widget.onSelect,
                    onAdd: widget.onAdd,
                    onSelectPage: _selectSection,
                    v5Desktop: true,
                  ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: IconBtn('x',
                        size: 32,
                        iconSize: 16,
                        tooltip: 'Close',
                        onTap: widget.onBack),
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
    final iconColor = selected ? AppColors.fg1 : AppColors.fg3;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.s2),
      child: HoverSurface(
        onTap: onTap,
        selected: selected,
        radius: R.md,
        selectedColor: AppColors.tint2,
        hoverColor: AppColors.fg1.withValues(alpha: 0.035),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 34),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(children: [
              if (entry.iconData != null)
                Icon(entry.iconData, size: 16, color: iconColor)
              else
                AppIcon(entry.icon!, size: 16, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(
                    14,
                    weight: selected ? W.label : W.body,
                    color: selected ? AppColors.fg1 : AppColors.fg2,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
