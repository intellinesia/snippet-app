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
const List<(String, List<SettingsPageRow>)> kSettingsGroups = [
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
  for (final (_, rows) in kSettingsGroups) {
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

/// The single keyword source for Settings search and the command palette
/// (spec X2.2), plus each page's existing one-line description.
const Map<SettingsPage, (String, List<String>)> _kSettingsMeta = {
  SettingsPage.general: (
    'Machines this app connects to, and how sessions behave.',
    ['machines', 'connection', 'notifications', 'approvals'],
  ),
  SettingsPage.appearance: (
    'Theme palette, accent colour, UI typeface and code font saved on this device.',
    ['theme', 'accent', 'color', 'font', 'typeface', 'cove', 'geist'],
  ),
  SettingsPage.models: (
    'Models, providers and the keys they use',
    ['inference', 'models', 'providers', 'keys']
  ),
  SettingsPage.routing: (
    'Which model does each kind of work',
    ['fallback', 'limits', 'priority'],
  ),
  SettingsPage.usage: (
    'Tokens and rate limits by provider',
    ['tokens', 'cost', 'billing', 'limits'],
  ),
  SettingsPage.memory: (
    'What agents remember between sessions',
    ['remember'],
  ),
  SettingsPage.scheduled: (
    'Recurring jobs and when they next run',
    ['recurring', 'cron'],
  ),
  SettingsPage.wakes: (
    'When agents wake up on their own',
    ['wake', 'schedule', 'agents'],
  ),
  SettingsPage.keepWarm: (
    'Sessions kept cached so replies stay quick',
    ['keep warm', 'cache', 'warm'],
  ),
  SettingsPage.vault: (
    'Secrets agents use without seeing them',
    ['secrets', 'keys', 'credentials'],
  ),
  SettingsPage.voice: (
    'Voice notes and how they are transcribed',
    ['voice notes', 'transcription', 'speech model', 'microphone'],
  ),
  SettingsPage.webSearch: (
    'Let agents search and read the web',
    ['exa', 'search', 'internet', 'browse'],
  ),
  SettingsPage.accounts: (
    'Signed-in subscriptions and rotation',
    ['subscription', 'rotation', 'chatgpt', 'xai', 'claude'],
  ),
};

String settingsPageDescription(SettingsPage page) =>
    _kSettingsMeta[page]?.$1 ?? '';

List<String> settingsPageKeywords(SettingsPage page) =>
    _kSettingsMeta[page]?.$2 ?? const [];

String settingsPageGroup(SettingsPage page) {
  for (final (group, rows) in kSettingsGroups) {
    if (rows.any((r) => r.page == page)) return group;
  }
  return '';
}

/// One search hit: the page row and the line shown under its name.
typedef SettingsHit = ({SettingsPageRow row, String snippet});

/// Pages in list order where every word of [query] is in the label, group,
/// row value or keywords; an empty query matches nothing.
List<SettingsHit> searchSettingsPages(String query,
    {Map<SettingsPage, String> values = const {}}) {
  final words = query.toLowerCase().split(RegExp(r'\s+'))
    ..removeWhere((w) => w.isEmpty);
  if (words.isEmpty) return const [];
  final hits = <SettingsHit>[];
  for (final (group, rows) in kSettingsGroups) {
    for (final row in rows) {
      final value = values[row.page] ?? '';
      final keys = settingsPageKeywords(row.page);
      final hay =
          [row.label, group, value, ...keys].join(' ').toLowerCase();
      if (!words.every(hay.contains)) continue;
      final named = '${row.label} $group'.toLowerCase();
      final keyHit = words.every(named.contains)
          ? null
          : keys.where((k) => words.any(k.contains)).firstOrNull;
      final desc = settingsPageDescription(row.page);
      final snippet = keyHit != null
          ? 'Matches "$keyHit"'
          : (desc.isNotEmpty ? desc : (value.isNotEmpty ? value : group));
      hits.add((row: row, snippet: snippet));
    }
  }
  return hits;
}
