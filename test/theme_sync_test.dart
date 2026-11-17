import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/glass.dart';
import 'package:snippet/models.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';

class _FakeThemeDaemon extends DaemonClient {
  _FakeThemeDaemon({
    this.activeSet = true,
    this.initialActiveId = 'black',
    List<ThemeSummary>? initialThemes,
    List<CoordinationAgent>? agents,
  })  : _activeId = initialActiveId,
        _agents = agents ?? const [],
        super('https://daemon.invalid', 'tok') {
    if (initialThemes != null) {
      for (final t in initialThemes) {
        _summaries[t.id] = t;
      }
    }
    _summaries.putIfAbsent(
      'black',
      () => ThemeSummary.fromPreset(allPresets.first),
    );
    _summaries.putIfAbsent(
      'nord',
      () => ThemeSummary.fromPreset(
          allPresets.firstWhere((p) => p.name == 'nord')),
    );
  }

  final DeviceEventHub _events = DeviceEventHub.local();
  @override
  DeviceEventHub get deviceEvents => _events;

  bool activeSet;
  final String initialActiveId;
  String _activeId;
  final List<CoordinationAgent> _agents;
  final Map<String, ThemeSummary> _summaries = {};
  final Map<String, Map<String, dynamic>> docs = {};
  final Map<String, Map<String, dynamic>> resolvedOverrides = {};

  int getActiveCalls = 0;
  int listCalls = 0;
  final List<String> setActiveCalls = [];
  final List<(String, Map<String, dynamic>)> putCalls = [];
  final List<String> deletedIds = [];

  Map<String, dynamic> _docFor(String id) {
    final stored = docs[id];
    if (stored != null) return Map<String, dynamic>.of(stored);
    final preset =
        allPresets.where((p) => p.name == id).firstOrNull ?? allPresets.first;
    return {
      'schema': 1,
      'id': preset.name,
      'name': preset.label,
      'author': 'builtin',
      'accent': null,
      'color': preset.toColorJson(),
    };
  }

  Map<String, dynamic> _resolvedFor(String id) {
    final override = resolvedOverrides[id];
    if (override != null) return Map<String, dynamic>.of(override);
    final doc = _docFor(id);
    final baseId = doc['base'] as String?;
    final basePreset = baseId == null
        ? (allPresets.where((p) => p.name == id).firstOrNull ??
            allPresets.first)
        : (allPresets.where((p) => p.name == baseId).firstOrNull ??
            allPresets.first);
    final colorMap = Map<String, dynamic>.of(basePreset.toColorJson());
    if (doc['color'] is Map) {
      colorMap.addAll((doc['color'] as Map).cast<String, dynamic>());
    }
    return {
      'schema': 1,
      'id': id,
      'name': doc['name'] ?? id,
      if (baseId != null) 'base': baseId,
      'author': doc['author'] ?? 'user',
      'accent': doc['accent'],
      'color': colorMap,
      if (doc['type'] != null) 'type': doc['type'],
      if (doc['chat'] != null) 'chat': doc['chat'],
      if (doc['translucency'] != null) 'translucency': doc['translucency'],
      if (doc['border'] != null) 'border': doc['border'],
    };
  }

  @override
  Future<ResolvedTheme> getActiveTheme() async {
    getActiveCalls++;
    return ResolvedTheme.fromJson({
      'active_set': activeSet,
      'resolved': _resolvedFor(_activeId),
    });
  }

  @override
  Future<ResolvedTheme?> setActiveTheme(String id) async {
    setActiveCalls.add(id);
    _activeId = id;
    activeSet = true;
    return ResolvedTheme.fromJson({
      'active_set': true,
      'resolved': _resolvedFor(id),
    });
  }

  @override
  Future<ThemeDetail> getTheme(String id) async {
    final doc = _docFor(id);
    return ThemeDetail(
      document: doc,
      resolved: ResolvedTheme.fromJson(_resolvedFor(id)),
    );
  }

  @override
  Future<ThemeDetail?> putTheme(
      String id, Map<String, dynamic> document) async {
    final copy = Map<String, dynamic>.of(document);
    copy['id'] = id;
    copy['author'] ??= 'user';
    putCalls.add((id, copy));
    docs[id] = copy;
    final resolvedMap = _resolvedFor(id);
    final resolved = ResolvedTheme.fromJson(resolvedMap);
    _summaries[id] = ThemeSummary(
      id: id,
      name: resolved.name,
      author: 'user',
      builtin: false,
      base: resolved.base,
      preview: ThemePreview(
        bg: resolved.effectivePreset.bg,
        surface1: resolved.effectivePreset.surface1,
        fg1: resolved.effectivePreset.fg1,
        accent: resolved.effectivePreset.accent,
      ),
    );
    return ThemeDetail(document: copy, resolved: resolved);
  }

  @override
  Future<void> deleteTheme(String id) async {
    deletedIds.add(id);
    docs.remove(id);
    _summaries.remove(id);
    if (_activeId == id) _activeId = 'black';
  }

  @override
  Future<ThemeListResponse> listThemes() async {
    listCalls++;
    return ThemeListResponse(
      themes: _summaries.values.toList(),
      active: _activeId,
      activeSet: activeSet,
    );
  }

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => _agents;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ThemeManager.instance.resetForTest();
    Glass.enabled = true;
  });

  tearDown(() {
    ThemeManager.instance.resetForTest();
    Glass.enabled = true;
  });

  group('ThemePreset.fromJson and ResolvedTheme.fromJson', () {
    test('white preset is removed from allPresets and fallback resolves to black', () async {
      expect(allPresets.any((p) => p.name == 'white'), isFalse);
      SharedPreferences.setMockInitialValues({'theme_name': 'white'});
      await ThemeManager.instance.init();
      expect(ThemeManager.instance.activeId, 'black');
      expect(ThemeManager.instance.current.name, 'black');
    });

    test('ThemePreset.fromJson parses full and partial colour maps safely', () {
      final preset = ThemePreset.fromJson({
        'id': 'agent-sky',
        'name': 'Agent Sky',
        'color': {
          'bg': '#112233',
          'fg1': '#DDEEFF',
          'accent': '#80FFAA00',
          'invalid': 'not-a-color',
        },
      });
      expect(preset.name, 'agent-sky');
      expect(preset.label, 'Agent Sky');
      expect(preset.bg, const Color(0xFF112233));
      expect(preset.fg1, const Color(0xFFDDEEFF));
      expect(preset.accent, const Color(0x80FFAA00));
      // Unspecified slots fall back to Pure Black defaults.
      expect(preset.surface1, allPresets.first.surface1);
      expect(preset.danger, allPresets.first.danger);
    });

    test('ResolvedTheme.fromJson parses non-colour groups, responsive numbers and accent override', () {
      final resolved = ResolvedTheme.fromJson({
        'active_set': false,
        'resolved': {
          'schema': 1,
          'id': 'custom',
          'name': 'Custom',
          'base': 'nord',
          'author': 'user',
          'accent': 'emerald',
          'color': {
            'bg': '#2E3440',
            'accent': '#88C0D0',
          },
          'chat': {
            'sent': 'agent',
            'sentText': 'auto',
            'received': '#111111',
            'fontSize': {'phone': 18, 'desktop': 14},
            'bubbleRadius': 12,
            'runGap': 3.5,
            'groupGap': 14.0,
            'maxShare': {'phone': 0.85, 'desktop': 0.70},
            'avatarSize': {'phone': 30, 'desktop': 22},
          },
          'type': {
            'uiFont': 'Inter',
            'codeFont': 'JetBrainsMono',
          },
          'translucency': {
            'canvasAlpha': {'phone': 0.90, 'desktop': 0.72},
            'windowTint': 0.35,
            'glassFill': 0.50,
            'glassBlur': 18,
            'edgeBlur': false,
            'scrim': 0.61,
            'glassScrim': 0.33,
            'modalScrim': 0.55,
            'enabled': false,
          },
          'border': {
            'glassEdgeAlpha': 0.15,
          },
        },
      });

      expect(resolved.activeSet, isFalse);
      expect(resolved.base, 'nord');
      expect(resolved.accentName, 'emerald');
      expect(resolved.chat.sentRaw, 'agent');
      expect(resolved.chat.sentTextRaw, 'auto');
      expect(resolved.chat.received, const Color(0xFF111111));
      expect(resolved.chat.fontSize.resolve(mobile: true), 18);
      expect(resolved.chat.fontSize.resolve(mobile: false), 14);
      expect(resolved.chat.bubbleRadius.resolve(mobile: true), 12);
      expect(resolved.chat.bubbleRadius.resolve(mobile: false), 12);
      expect(resolved.chat.runGap, 3.5);
      expect(resolved.chat.groupGap, 14.0);
      expect(resolved.type.uiFont, 'Inter');
      expect(resolved.type.codeFont, 'JetBrainsMono');
      expect(resolved.translucency.windowTint, 0.35);
      expect(resolved.translucency.glassBlur, 18);
      expect(resolved.translucency.edgeBlur, isFalse);
      expect(resolved.translucency.enabled, isFalse);
      expect(resolved.border.glassEdgeAlpha, 0.15);

      final emerald = allAccents.firstWhere((a) => a.name == 'emerald');
      expect(resolved.effectivePreset.accent, emerald.accent);
      expect(resolved.effectivePreset.accentFg, emerald.accentFg);
    });
  });

  group('ThemeManager cache, migration and sync', () {
    test('init restores theme_active_json offline cache and falls back cleanly on corrupt cache', () async {
      final nord = allPresets.firstWhere((p) => p.name == 'nord');
      final cachedDoc = ResolvedTheme.fromPreset(
        nord,
        accentName: 'violet',
        uiFont: 'Inter',
        codeFont: 'JetBrainsMono',
      ).toJson();
      SharedPreferences.setMockInitialValues({
        ThemeManager.activeJsonPrefsKey: jsonEncode(cachedDoc),
      });

      await ThemeManager.instance.init();
      expect(ThemeManager.instance.activeId, 'nord');
      expect(ThemeManager.instance.customAccent?.name, 'violet');
      expect(ThemeManager.instance.currentFont.family, 'Inter');
      expect(ThemeManager.instance.currentMonoFont.family, 'JetBrainsMono');

      ThemeManager.instance.resetForTest();
      SharedPreferences.setMockInitialValues({
        ThemeManager.activeJsonPrefsKey: '{not-valid-json',
        'theme_name': 'ember',
      });
      await ThemeManager.instance.init();
      expect(ThemeManager.instance.activeId, 'ember');
    });

    test('migrates legacy prefs once when active_set is false and writes theme_active_json', () async {
      SharedPreferences.setMockInitialValues({
        'theme_name': 'nord',
        'accent_name': 'violet',
        'ui_font_family': 'Inter',
      });
      await ThemeManager.instance.init();
      final fake = _FakeThemeDaemon(activeSet: false);

      await ThemeManager.instance.syncFromDaemon(client: fake);

      expect(fake.putCalls.length, 1);
      expect(fake.putCalls.first.$1, 'custom');
      expect(fake.putCalls.first.$2['base'], 'nord');
      expect(fake.putCalls.first.$2['accent'], 'violet');
      expect(
        (fake.putCalls.first.$2['type'] as Map)['uiFont'],
        'Inter',
      );
      expect(fake.setActiveCalls, ['custom']);
      expect(ThemeManager.instance.activeId, 'custom');
      expect(ThemeManager.instance.migrated, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(ThemeManager.migratedPrefsKey), isTrue);
      expect(prefs.getString(ThemeManager.activeJsonPrefsKey), isNotEmpty);

      // Subsequent sync does not re-migrate even if activeSet somehow reports false.
      fake.activeSet = false;
      fake.putCalls.clear();
      await ThemeManager.instance.syncFromDaemon(client: fake);
      expect(fake.putCalls, isEmpty);
    });

    test('themes_changed event triggers Revalidator sync and accent change saves custom theme', () async {
      await ThemeManager.instance.init();
      final fake = _FakeThemeDaemon(activeSet: true, initialActiveId: 'black');
      ThemeManager.instance.bindClient(fake);
      await pumpEventQueue(times: 20);
      expect(ThemeManager.instance.activeId, 'black');

      final callsBeforeEvent = fake.getActiveCalls;
      fake.docs['agent-mint'] = {
        'schema': 1,
        'id': 'agent-mint',
        'name': 'Agent Mint',
        'author': 'agent:bot1',
        'color': {'bg': '#102018', 'accent': '#34D399'},
      };
      await fake.setActiveTheme('agent-mint');
      fake.deviceEvents.add({'kind': 'themes_changed'});
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await pumpEventQueue(times: 20);

      expect(fake.getActiveCalls, greaterThan(callsBeforeEvent));
      expect(ThemeManager.instance.activeId, 'agent-mint');
      expect(ThemeManager.instance.current.bg, const Color(0xFF102018));

      // Changing accent creates/updates custom theme preserving base='agent-mint'.
      await ThemeManager.instance.setAccentName('violet', client: fake);
      expect(fake.putCalls.last.$1, 'custom');
      expect(fake.putCalls.last.$2['base'], 'agent-mint');
      expect(fake.putCalls.last.$2['accent'], 'violet');
      expect(ThemeManager.instance.activeId, 'custom');
    });
  });

  group('ThemeListResponse', () {
    test('ThemeListResponse.fromJson accepts integer updated_at from daemon', () {
      final res = ThemeListResponse.fromJson({
        'live_groups': ['color', 'accent', 'type.uiFont', 'type.codeFont'],
        'active': 'custom',
        'active_set': true,
        'themes': [
          {
            'id': 'custom',
            'name': 'Custom',
            'author': 'user',
            'builtin': false,
            'base': 'obsidian',
            'updated_at': 1794774000,
            'preview': {
              'bg': '#FF0D0D0F',
              'surface1': '#FF141418',
              'fg1': '#FFFAFAFA',
              'accent': '#FF9DB0FF',
            },
          },
        ],
      });
      expect(res.active, 'custom');
      expect(res.activeSet, isTrue);
      expect(res.themes.single.id, 'custom');
      expect(res.themes.single.updatedAt, '1794774000');
      expect(res.themes.single.base, 'obsidian');
    });
  });
}
