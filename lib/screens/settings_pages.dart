import 'package:flutter/material.dart';

import '../phosphor_icons.dart';
import 'settings_panel.dart' show SettingsPage;

/// One row in the settings page list shared by the dialog's list column and
/// the phone sheet's index.
typedef SettingsPageRow = ({
  SettingsPage page,
  String label,
  String? icon,
  IconData? iconData,
});

/// The 13 settings pages in their 4 groups (spec D2): This machine, Models,
/// Agents, This device. Scheduled and Keep warm are their own rows even
/// though their bodies live inside the wakes screens.
const List<(String, List<SettingsPageRow>)> settingsPageGroups = [
  (
    'This machine',
    [
      (
        page: SettingsPage.general,
        label: 'Machines',
        icon: null,
        iconData: PhIcons.monitor,
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
        icon: 'analytics',
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
        page: SettingsPage.scheduled,
        label: 'Scheduled',
        icon: 'scheduled',
        iconData: null,
      ),
      (
        page: SettingsPage.keepWarm,
        label: 'Keep warm',
        icon: 'timer',
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

SettingsPageRow? settingsPageRow(SettingsPage page) {
  for (final (_, rows) in settingsPageGroups) {
    for (final row in rows) {
      if (row.page == page) return row;
    }
  }
  return null;
}

String settingsPageLabel(SettingsPage page) =>
    settingsPageRow(page)?.label ?? 'Settings';

String settingsPageIcon(SettingsPage page) =>
    settingsPageRow(page)?.icon ?? 'laptop';
