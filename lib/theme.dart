import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'chat_scene.dart' show ChatScene;
import 'platform.dart';
export 'theme_models.dart';

// ---------------------------------------------------------------------------
// Theme presets — each one defines every color the app uses. Ported from the
// TUI's 13 presets (src/tui/theme.rs) plus mobile-specific surface/diff slots.
// ---------------------------------------------------------------------------

class ThemePreset {
  final String name;
  final String label;

  // Surfaces (darkest → lightest)
  final Color bg;
  final Color canvas;
  final Color floor;
  final Color surface1;
  final Color surface2;
  final Color surface3;

  // Foreground (brightest → faintest)
  final Color fg1;
  final Color fg2;
  final Color fg3;
  final Color fg4;

  // Borders
  final Color border;
  final Color border2;

  // Accent
  final Color accent;
  final Color accentHover;
  final Color accentFg;
  final Color accentBg;
  final Color accentLine;
  final Color accentRing;
  final Color accentFill;
  final Color accentFillHover;

  // Status
  final Color ok;
  final Color okBg;
  final Color run;
  final Color runBg;
  final Color danger;
  final Color dangerBg;

  // Diff
  final Color diffAddBg;
  final Color diffDelBg;
  final Color diffAddFg;
  final Color diffDelFg;
  final Color diffGutter;

  const ThemePreset({
    required this.name,
    required this.label,
    required this.bg,
    required this.canvas,
    required this.floor,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.fg1,
    required this.fg2,
    required this.fg3,
    required this.fg4,
    required this.border,
    required this.border2,
    required this.accent,
    required this.accentHover,
    required this.accentFg,
    required this.accentBg,
    required this.accentLine,
    required this.accentRing,
    required this.accentFill,
    required this.accentFillHover,
    required this.ok,
    required this.okBg,
    required this.run,
    required this.runBg,
    required this.danger,
    required this.dangerBg,
    required this.diffAddBg,
    required this.diffDelBg,
    required this.diffAddFg,
    required this.diffDelFg,
    required this.diffGutter,
  });

  factory ThemePreset.fromJson(
    Map<String, dynamic> json, {
    ThemePreset? fallback,
  }) {
    final fb = fallback ?? _quiet;
    final rawId = json['id'] as String?;
    final rawName = json['name'] as String?;
    final rawLabel = json['label'] as String?;
    final slug = (rawId != null && rawId.isNotEmpty)
        ? rawId
        : ((rawName != null && rawName.isNotEmpty) ? rawName : fb.name);
    final label = (rawId != null && rawId.isNotEmpty)
        ? ((rawName != null && rawName.isNotEmpty)
            ? rawName
            : (rawLabel ?? slug))
        : (rawLabel ?? rawName ?? slug);

    final rawColor = json['color'];
    final c = rawColor is Map ? rawColor.cast<String, dynamic>() : json;
    Color col(String key, Color def) => parseThemeColor(c[key]) ?? def;

    return ThemePreset(
      name: slug,
      label: label,
      bg: col('bg', fb.bg),
      canvas: col('canvas', fb.canvas),
      floor: col('floor', fb.floor),
      surface1: col('surface1', fb.surface1),
      surface2: col('surface2', fb.surface2),
      surface3: col('surface3', fb.surface3),
      fg1: col('fg1', fb.fg1),
      fg2: col('fg2', fb.fg2),
      fg3: col('fg3', fb.fg3),
      fg4: col('fg4', fb.fg4),
      border: col('border', fb.border),
      border2: col('border2', fb.border2),
      accent: col('accent', fb.accent),
      accentHover: col('accentHover', fb.accentHover),
      accentFg: col('accentFg', fb.accentFg),
      accentBg: col('accentBg', fb.accentBg),
      accentLine: col('accentLine', fb.accentLine),
      accentRing: col('accentRing', fb.accentRing),
      accentFill: col('accentFill', fb.accentFill),
      accentFillHover: col('accentFillHover', fb.accentFillHover),
      ok: col('ok', fb.ok),
      okBg: col('okBg', fb.okBg),
      run: col('run', fb.run),
      runBg: col('runBg', fb.runBg),
      danger: col('danger', fb.danger),
      dangerBg: col('dangerBg', fb.dangerBg),
      diffAddBg: col('diffAddBg', fb.diffAddBg),
      diffDelBg: col('diffDelBg', fb.diffDelBg),
      diffAddFg: col('diffAddFg', fb.diffAddFg),
      diffDelFg: col('diffDelFg', fb.diffDelFg),
      diffGutter: col('diffGutter', fb.diffGutter),
    );
  }

  Map<String, dynamic> toColorJson() => {
        'bg': formatThemeColor(bg),
        'canvas': formatThemeColor(canvas),
        'floor': formatThemeColor(floor),
        'surface1': formatThemeColor(surface1),
        'surface2': formatThemeColor(surface2),
        'surface3': formatThemeColor(surface3),
        'fg1': formatThemeColor(fg1),
        'fg2': formatThemeColor(fg2),
        'fg3': formatThemeColor(fg3),
        'fg4': formatThemeColor(fg4),
        'border': formatThemeColor(border),
        'border2': formatThemeColor(border2),
        'accent': formatThemeColor(accent),
        'accentHover': formatThemeColor(accentHover),
        'accentFg': formatThemeColor(accentFg),
        'accentBg': formatThemeColor(accentBg),
        'accentLine': formatThemeColor(accentLine),
        'accentRing': formatThemeColor(accentRing),
        'accentFill': formatThemeColor(accentFill),
        'accentFillHover': formatThemeColor(accentFillHover),
        'ok': formatThemeColor(ok),
        'okBg': formatThemeColor(okBg),
        'run': formatThemeColor(run),
        'runBg': formatThemeColor(runBg),
        'danger': formatThemeColor(danger),
        'dangerBg': formatThemeColor(dangerBg),
        'diffAddBg': formatThemeColor(diffAddBg),
        'diffDelBg': formatThemeColor(diffDelBg),
        'diffAddFg': formatThemeColor(diffAddFg),
        'diffDelFg': formatThemeColor(diffDelFg),
        'diffGutter': formatThemeColor(diffGutter),
      };

  ThemePreset withAccentOverride(AccentPreset? override) =>
      _withAccentOverride(this, override);
}

// Helper: build the palette. Surfaces follow a "surface ladder" — hierarchy
// comes from surface lift + hairlines, not drop shadows. Text follows a strict
// brightness ladder so fg1 > fg2 > fg3 > fg4 always holds.
ThemePreset _palette({
  required String name,
  required String label,
  required Color bg,
  required Color surface1,
  required Color surface2,
  required Color surface3,
  required Color border,
  required Color border2,
  required Color accent,
  required Color accentFg,
  Color fg1 = const Color(0xFFFFFFFF),
  Color fg2 = const Color(0xFFDCDCDC),
  Color fg3 = const Color(0xFFABABAB),
  Color fg4 = const Color(0xFF7A7A7A),
  Color ok = const Color(0xFF34D399),
  Color run = const Color(0xFFF59E0B),
  Color danger = const Color(0xFFFF5C5C),
  Color? diffAddFg,
  Color? diffDelFg,
  Color? diffAddBg,
  Color? diffDelBg,
}) {
  final hover = _lighten(accent, 0.06);
  return ThemePreset(
    name: name,
    label: label,
    bg: bg,
    canvas: bg,
    floor: bg,
    surface1: surface1,
    surface2: surface2,
    surface3: surface3,
    fg1: fg1,
    fg2: fg2,
    fg3: fg3,
    fg4: fg4,
    border: border,
    border2: border2,
    accent: accent,
    accentHover: hover,
    accentFg: accentFg,
    accentBg: accent.withValues(alpha: 0.14),
    accentLine: accent.withValues(alpha: 0.38),
    accentRing: accent.withValues(alpha: 0.45),
    accentFill: accent,
    accentFillHover: hover,
    ok: ok,
    okBg: ok.withValues(alpha: 0.13),
    run: run,
    runBg: run.withValues(alpha: 0.13),
    danger: danger,
    dangerBg: danger.withValues(alpha: 0.13),
    diffAddBg: diffAddBg ?? ok.withValues(alpha: 0.10),
    diffDelBg: diffDelBg ?? danger.withValues(alpha: 0.10),
    diffAddFg: diffAddFg ?? const Color(0xFF6EE7B7),
    diffDelFg: diffDelFg ?? const Color(0xFFFF8A8A),
    diffGutter: border2,
  );
}

// Quiet: warm graphite and paper, one amber signal kept for "needs you".
// Surfaces separate by tone; hairlines only where structure needs them.
final _quiet = _palette(
  name: 'quiet',
  label: 'Quiet',
  bg: const Color(0xFF121211),
  surface1: const Color(0xFF191918),
  surface2: const Color(0xFF222220),
  surface3: const Color(0xFF2C2C2A),
  border: const Color(0xFF2A2A28),
  border2: const Color(0xFF3A3A37),
  accent: const Color(0xFFEDEDEA),
  accentFg: const Color(0xFF121211),
  fg1: const Color(0xFFEDEDEA),
  fg2: const Color(0xFFB5B5B0),
  fg3: const Color(0xFF93938D),
  fg4: const Color(0xFF6A6A65),
  ok: const Color(0xFFB5B5B0),
  run: const Color(0xFFE9B44C),
  danger: const Color(0xFFF08A80),
  diffAddFg: const Color(0xFF9CC7AA),
  diffDelFg: const Color(0xFFE8A39C),
  diffAddBg: const Color(0xFF1C2620),
  diffDelBg: const Color(0xFF2A1D1C),
);

final _quietLight = _palette(
  name: 'quiet-light',
  label: 'Quiet Light',
  bg: const Color(0xFFFAFAF8),
  surface1: const Color(0xFFF0F0EC),
  surface2: const Color(0xFFE6E6E1),
  surface3: const Color(0xFFDCDCD5),
  border: const Color(0xFFE4E4DF),
  border2: const Color(0xFFD2D2CC),
  accent: const Color(0xFF1C1C1A),
  accentFg: const Color(0xFFFFFFFF),
  fg1: const Color(0xFF1C1C1A),
  fg2: const Color(0xFF55554F),
  fg3: const Color(0xFF6B6B65),
  fg4: const Color(0xFFA8A8A0),
  ok: const Color(0xFF55554F),
  run: const Color(0xFF8A5A00),
  danger: const Color(0xFFB3261E),
  diffAddFg: const Color(0xFF2E6A45),
  diffDelFg: const Color(0xFF9A3B33),
  diffAddBg: const Color(0xFFE8F1EA),
  diffDelBg: const Color(0xFFF7E7E5),
);

// High contrast: pure black or white, a 6E6E6A or 5C5C57 line, same layout.
final _hcDark = _palette(
  name: 'hc-dark',
  label: 'High contrast dark',
  bg: const Color(0xFF000000),
  surface1: const Color(0xFF121212),
  surface2: const Color(0xFF1E1E1E),
  surface3: const Color(0xFF2E2E2E),
  border: const Color(0xFF6E6E6A),
  border2: const Color(0xFF8A8A86),
  accent: const Color(0xFFFFFFFF),
  accentFg: const Color(0xFF000000),
  fg1: const Color(0xFFFFFFFF),
  fg2: const Color(0xFFE6E6E2),
  fg3: const Color(0xFFCFCFCA),
  fg4: const Color(0xFFA3A39E),
  ok: const Color(0xFFFFFFFF),
  run: const Color(0xFFFFC24D),
  danger: const Color(0xFFFFA49C),
  diffAddFg: const Color(0xFFA6E3B8),
  diffDelFg: const Color(0xFFFFA49C),
  diffAddBg: const Color(0xFF0E1F14),
  diffDelBg: const Color(0xFF24100E),
);

final _hcLight = _palette(
  name: 'hc-light',
  label: 'High contrast light',
  bg: const Color(0xFFFFFFFF),
  surface1: const Color(0xFFFFFFFF),
  surface2: const Color(0xFFEBEBE6),
  surface3: const Color(0xFFD9D9D3),
  border: const Color(0xFF5C5C57),
  border2: const Color(0xFF3B3B38),
  accent: const Color(0xFF000000),
  accentFg: const Color(0xFFFFFFFF),
  fg1: const Color(0xFF000000),
  fg2: const Color(0xFF1F1F1D),
  fg3: const Color(0xFF383835),
  fg4: const Color(0xFF5C5C57),
  ok: const Color(0xFF000000),
  run: const Color(0xFF6B4300),
  danger: const Color(0xFF8A1C14),
  diffAddFg: const Color(0xFF1F5A35),
  diffDelFg: const Color(0xFF8A1C14),
  diffAddBg: const Color(0xFFE3F2E7),
  diffDelBg: const Color(0xFFFBE3E0),
);

/// Four palettes only: Quiet dark and light, and their high-contrast pair.
/// System is a mode that picks dark or light, not a palette.
final List<ThemePreset> allPresets = [
  _quiet,
  _quietLight,
  _hcDark,
  _hcLight,
];

class AccentPreset {
  final String name;
  final String label;
  final Color accent;
  final Color accentFg;
  const AccentPreset({
    required this.name,
    required this.label,
    required this.accent,
    required this.accentFg,
  });
}

/// Accent recolours are gone: colour is status only. Kept empty so saved
/// accent names resolve to the default.
const List<AccentPreset> allAccents = [];

ThemePreset _withAccentOverride(ThemePreset base, AccentPreset? override) {
  if (override == null) return base;
  final a = override.accent;
  final hover = _lighten(a, 0.06);
  return ThemePreset(
    name: base.name,
    label: base.label,
    bg: base.bg,
    canvas: base.canvas,
    floor: base.floor,
    surface1: base.surface1,
    surface2: base.surface2,
    surface3: base.surface3,
    fg1: base.fg1,
    fg2: base.fg2,
    fg3: base.fg3,
    fg4: base.fg4,
    border: base.border,
    border2: base.border2,
    accent: a,
    accentHover: hover,
    accentFg: override.accentFg,
    accentBg: a.withValues(alpha: 0.14),
    accentLine: a.withValues(alpha: 0.38),
    accentRing: a.withValues(alpha: 0.45),
    accentFill: a,
    accentFillHover: hover,
    ok: base.ok,
    okBg: base.okBg,
    run: base.run,
    runBg: base.runBg,
    danger: base.danger,
    dangerBg: base.dangerBg,
    diffAddBg: base.diffAddBg,
    diffDelBg: base.diffDelBg,
    diffAddFg: base.diffAddFg,
    diffDelFg: base.diffDelFg,
    diffGutter: base.diffGutter,
  );
}

class FontPreset {
  final String family;
  final String label;
  final String description;
  const FontPreset({
    required this.family,
    required this.label,
    required this.description,
  });
}

const List<FontPreset> allFonts = [
  FontPreset(
    family: 'Cove',
    label: 'Cove',
    description: 'Rounded geometric with single-storey a',
  ),
  FontPreset(
    family: 'Geist',
    label: 'Geist',
    description: 'Crisp technical neo-grotesque',
  ),
  FontPreset(
    family: 'Inter',
    label: 'Inter',
    description: 'Classic high-legibility interface neo-grotesque',
  ),
  FontPreset(
    family: 'PlusJakartaSans',
    label: 'Plus Jakarta Sans',
    description: 'Sharp modern geometric grotesque',
  ),
  FontPreset(
    family: 'DMSans',
    label: 'DM Sans',
    description: 'Clean low-contrast geometric sans',
  ),
  FontPreset(
    family: 'SpaceGrotesk',
    label: 'Space Grotesk',
    description: 'Proportional technical display grotesque',
  ),
  FontPreset(
    family: 'IBMPlexSans',
    label: 'IBM Plex Sans',
    description: 'Engineered grotesque with crisp terminals',
  ),
  FontPreset(
    family: 'Manrope',
    label: 'Manrope',
    description: 'Modern semi-condensed geometric sans',
  ),
  FontPreset(
    family: 'Outfit',
    label: 'Outfit',
    description: 'Balanced geometric UI sans',
  ),
  FontPreset(
    family: 'Halden',
    label: 'Halden',
    description: 'Neutral neo-grotesque interface workhorse',
  ),
  FontPreset(
    family: 'Tessera',
    label: 'Tessera',
    description: 'Squared technical grotesque',
  ),
  FontPreset(
    family: 'Beacon',
    label: 'Beacon',
    description: 'High-legibility sans with tailed l and serifed I',
  ),
  FontPreset(
    family: 'Pebble',
    label: 'Pebble',
    description: 'Warm soft-square geometric sans',
  ),
  FontPreset(
    family: 'Mallow',
    label: 'Mallow',
    description: 'Friendly rounded sans with single-storey a',
  ),
  FontPreset(
    family: 'Rondel',
    label: 'Rondel',
    description: 'Poised geometric sans with tall ascenders',
  ),
  FontPreset(
    family: 'Alder',
    label: 'Alder',
    description: 'Warm humanist sans with open forms',
  ),
];

const List<FontPreset> allMonoFonts = [
  FontPreset(
    family: 'JetBrainsMono',
    label: 'JetBrains Mono',
    description: 'Developer monospace with tall x-height',
  ),
  FontPreset(
    family: 'GeistMono',
    label: 'Geist Mono',
    description: 'Technical Swiss monospace',
  ),
  FontPreset(
    family: 'FiraCode',
    label: 'Fira Code',
    description: 'Classic programming monospace',
  ),
  FontPreset(
    family: 'IBMPlexMono',
    label: 'IBM Plex Mono',
    description: 'Engineered technical monospace',
  ),
  FontPreset(
    family: 'SourceCodePro',
    label: 'Source Code Pro',
    description: 'Clean open-counter coding monospace',
  ),
  FontPreset(
    family: 'Inconsolata',
    label: 'Inconsolata',
    description: 'Humanist programmer monospace',
  ),
  FontPreset(
    family: 'Signal',
    label: 'Signal',
    description: 'Clean sans monospace with slab i, l and r',
  ),
  FontPreset(
    family: 'Fathom',
    label: 'Fathom',
    description: 'Squared geometric monospace with square dots',
  ),
  FontPreset(
    family: 'Tally',
    label: 'Tally',
    description: 'Warm slab monospace for code and logs',
  ),
];

// ---------------------------------------------------------------------------
// Color helpers
// ---------------------------------------------------------------------------

Color _lighten(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl
      .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
      .toColor()
      .withValues(alpha: c.a);
}

// ---------------------------------------------------------------------------
// ThemeManager — singleton, syncs active theme with daemon and caches offline
// ---------------------------------------------------------------------------

class ThemeManager extends ChangeNotifier {
  static const _legacyIndexKey = 'theme_index';
  static const _prefsKey = 'theme_name';
  static const _systemPrefsKey = 'theme_system';
  static const activeJsonPrefsKey = 'theme_active_json';
  static const defaultTheme = 'quiet';
  static const defaultFont = 'Inter';
  static const defaultMonoFont = 'GeistMono';
  static const _accentPrefsKey = 'accent_name';
  static const _fontPrefsKey = 'ui_font_family';
  static const _monoFontPrefsKey = 'mono_font_family';

  static final ThemeManager instance = ThemeManager._();
  ThemeManager._();

  ResolvedTheme _resolved = ResolvedTheme.fromPreset(_quiet);
  bool _system = true;

  /// True until the user picks a palette: dark or light follows the device.
  bool get followsSystem => _system;
  ResolvedTheme? _signedFor;
  String _signature = '';

  /// Changes only when the resolved tokens do, so list refreshes and
  /// reconnects do not force a full-tree rebuild.
  String get tokenSignature {
    if (!identical(_signedFor, _resolved)) {
      _signedFor = _resolved;
      _signature = jsonEncode(_resolved.toJson());
    }
    return _signature;
  }

  String? _activeId;

  static int _indexOr(Iterable<String> names, String name) {
    final i = names.toList().indexOf(name);
    return i < 0 ? 0 : i;
  }

  ResolvedTheme get resolved => _resolved;
  String get activeId => _activeId ?? _resolved.id;

  int get themeIndex {
    final id = _resolved.id == 'custom'
        ? (_resolved.base ?? defaultTheme)
        : _resolved.id;
    return _indexOr(allPresets.map((p) => p.name), id);
  }

  int get accentIndex {
    final a = _resolved.accentName;
    if (a == null || a.isEmpty) return -1;
    return allAccents.indexWhere((x) => x.name == a);
  }

  int get fontIndex =>
      _indexOr(allFonts.map((f) => f.family), _resolved.type.uiFont);
  int get monoFontIndex =>
      _indexOr(allMonoFonts.map((f) => f.family), _resolved.type.codeFont);

  /// Combined cache key so markdown style caches invalidate on any theme change.
  int get index => Object.hash(
        _resolved.id,
        _resolved.accentName,
        _resolved.type.uiFont,
        _resolved.type.codeFont,
        _resolved.type.scale,
        Object.hash(
          _resolved.type.weights.body,
          _resolved.type.weights.label,
          _resolved.type.weights.title,
          _resolved.type.weights.strong,
        ),
        _resolved.shape.radiusScale,
        _resolved.space.density,
        _resolved.motion.speed,
        _resolved.colorPreset.bg.toARGB32(),
        _resolved.colorPreset.accent.toARGB32(),
        _resolved.chat.sentRaw,
        _resolved.chat.sentTextRaw,
        _resolved.chat.fontSize.current,
        Object.hashAll([
          for (final e in _resolved.syntax.entries)
            Object.hash(e.key, e.value.toARGB32()),
        ]),
      );

  ThemePreset get baseTheme {
    if (_resolved.id == 'custom' && _resolved.base != null) {
      final match =
          allPresets.where((p) => p.name == _resolved.base).firstOrNull;
      if (match != null) return match;
    }
    return _resolved.colorPreset;
  }

  AccentPreset? get customAccent {
    final a = _resolved.accentName;
    if (a == null || a.isEmpty) return null;
    return allAccents.where((x) => x.name == a).firstOrNull;
  }

  ThemePreset get current => _resolved.effectivePreset;

  FontPreset get currentFont =>
      allFonts.where((f) => f.family == _resolved.type.uiFont).firstOrNull ??
      allFonts[_indexOr(allFonts.map((f) => f.family), defaultFont)];

  FontPreset get currentMonoFont =>
      allMonoFonts
          .where((f) => f.family == _resolved.type.codeFont)
          .firstOrNull ??
      allMonoFonts[
          _indexOr(allMonoFonts.map((f) => f.family), defaultMonoFont)];

  @visibleForTesting
  void resetForTest() {
    _resolved = ResolvedTheme.fromPreset(_quiet);
    _activeId = null;
    notifyListeners();
  }

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    var name = p.getString(_prefsKey);
    final legacy = p.getInt(_legacyIndexKey);
    if (name == null && legacy != null) {
      // Saved before Pure Black was prepended; index into the old order.
      // Old palette indexes no longer mean anything; follow the system.
      name = null;
      await p.remove(_legacyIndexKey);
    }
    if (name == 'white') name = defaultTheme;
    // Quiet v4 shipped as the default, but a saved choice always won, so
    // existing installs never saw it. Move them over once.
    if (p.getBool('quiet_v4_migrated') != true) {
      await p.setBool('quiet_v4_migrated', true);
      if (name != null) {
        name = null;
        await p.remove(_prefsKey);
        await p.remove(activeJsonPrefsKey);
      }
    }

    _system = p.getBool(_systemPrefsKey) ?? true;
    if (_system) name = null;
    // First run follows the system; a saved choice always wins.
    final systemLight =
        PlatformDispatcher.instance.platformBrightness == Brightness.light;
    final fallbackPreset = allPresets[_indexOr(allPresets.map((t) => t.name),
        name ?? (systemLight ? 'quiet-light' : defaultTheme))];
    final savedAccent = p.getString(_accentPrefsKey);
    final accentName = savedAccent != null &&
            savedAccent.isNotEmpty &&
            allAccents.any((a) => a.name == savedAccent)
        ? savedAccent
        : null;
    final savedFont = p.getString(_fontPrefsKey);
    final uiFont =
        savedFont != null && allFonts.any((f) => f.family == savedFont)
            ? savedFont
            : defaultFont;
    final savedMono = p.getString(_monoFontPrefsKey);
    final codeFont =
        savedMono != null && allMonoFonts.any((f) => f.family == savedMono)
            ? savedMono
            : defaultMonoFont;

    final cachedJson = _system ? null : p.getString(activeJsonPrefsKey);
    if (cachedJson != null && cachedJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(cachedJson);
        if (decoded is Map<String, dynamic>) {
          final cached =
              ResolvedTheme.fromJson(decoded, fallbackPreset: _quiet);
          if (cached.id != 'white') {
            _resolved = cached;
            _activeId = cached.id;
            notifyListeners();
            return;
          }
        }
      } catch (_) {}
    }

    _resolved = ResolvedTheme.fromPreset(
      fallbackPreset,
      accentName: accentName,
      uiFont: uiFont,
      codeFont: codeFont,
    );
    _activeId = _resolved.id;
    notifyListeners();
  }

  // Local only until the daemon theme store ships; the cache is what init restores.
  Future<void> _commit(ResolvedTheme next) async {
    final safe = next.id == 'white' ? ResolvedTheme.fromPreset(_quiet) : next;
    _resolved = safe;
    _activeId = safe.id;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(activeJsonPrefsKey, jsonEncode(safe.toJson()));
    } catch (_) {}
  }

  Future<void> applyTheme(String id) => setName(id);

  /// Follow the device: Quiet dark or light by the system brightness.
  Future<void> useSystem() async {
    _system = true;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_systemPrefsKey, true);
    } catch (_) {}
    final light =
        PlatformDispatcher.instance.platformBrightness == Brightness.light;
    final preset = allPresets[light ? 1 : 0];
    await _commit(ResolvedTheme.fromPreset(
      preset,
      accentName: null,
      uiFont: _resolved.type.uiFont,
      codeFont: _resolved.type.codeFont,
    ));
  }

  /// The device switched dark or light; only matters while following it.
  Future<void> syncSystem() async {
    if (!_system) return;
    final light =
        PlatformDispatcher.instance.platformBrightness == Brightness.light;
    final want = allPresets[light ? 1 : 0];
    if (_resolved.id == want.name) return;
    await useSystem();
  }

  Future<void> setIndex(int i) async {
    if (i < 0 || i >= allPresets.length) return;
    final preset = allPresets[i];
    _system = false;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_systemPrefsKey, false);
    } catch (_) {}
    if (_resolved.id == preset.name) return;
    await _commit(ResolvedTheme.fromPreset(
      preset,
      accentName: _resolved.accentName,
      uiFont: _resolved.type.uiFont,
      codeFont: _resolved.type.codeFont,
    ));
  }

  Future<void> setName(String name) async {
    final target = name == 'white' ? defaultTheme : name;
    final i = allPresets.indexWhere((p) => p.name == target);
    if (i >= 0) await setIndex(i);
  }

  Future<void> setAccentName(String? name) async {
    final nextName = (name == null || name.isEmpty)
        ? null
        : (allAccents.any((a) => a.name == name) ? name : null);
    if (nextName == _resolved.accentName) return;
    await _commit(_resolved.copyWith(accentName: nextName));
  }

  Future<void> setFontFamily(String family) async {
    if (!allFonts.any((f) => f.family == family)) return;
    if (family == _resolved.type.uiFont) return;
    await _commit(_resolved.copyWith(
      type: _resolved.type.copyWith(uiFont: family),
    ));
  }

  Future<void> setMonoFontFamily(String family) async {
    if (!allMonoFonts.any((f) => f.family == family)) return;
    if (family == _resolved.type.codeFont) return;
    await _commit(_resolved.copyWith(
      type: _resolved.type.copyWith(codeFont: family),
    ));
  }
}

/// Convenience accessor — same as `ThemeManager.instance.current`.
ThemePreset get currentTheme => ThemeManager.instance.current;

/// Marks every descendant element dirty so theme token updates reach subtrees
/// that read static getters without depending on [Theme.of].
void rebuildThemeElements(BuildContext context) {
  void rebuild(Element e) {
    e.markNeedsBuild();
    e.visitChildren(rebuild);
  }

  (context as Element).visitChildren(rebuild);
}

// ---------------------------------------------------------------------------
// AppColors — dynamic getters that read from the active theme preset. Every
// `AppColors.xxx` call site works unchanged; the value shifts when the user
// picks a different theme.
// ---------------------------------------------------------------------------

class AppColors {
  // Surfaces
  static Color get bg => currentTheme.bg;
  static Color get canvas => currentTheme.canvas.withValues(
      alpha: ThemeManager.instance.resolved.translucency.canvasAlpha.current);

  /// Full-page background: clear while the scene paints behind the page.
  static Color get pageBg =>
      ChatScene.instance.ready ? const Color(0x00000000) : bg;
  static Color get pageCanvas =>
      ChatScene.instance.ready ? const Color(0x00000000) : canvas;
  static Color get floor => currentTheme.floor;
  static Color get surface1 => currentTheme.surface1;
  static Color get surface2 => currentTheme.surface2;
  static Color get surface3 => currentTheme.surface3;

  static Color get base => currentTheme.bg;
  static Color get raised => currentTheme.surface1;
  static Color get overlay => currentTheme.surface2;
  static Color get hover => currentTheme.surface3;
  static Color get hoverPlate {
    if (currentTheme.name == 'quiet') return const Color(0xFF1F1F1D);
    if (currentTheme.name == 'quiet-light') return const Color(0xFFF4F4F0);
    return Color.lerp(currentTheme.surface1, currentTheme.surface2, 0.5)!;
  }

  static Color get line => currentTheme.border;
  static Color get lineStrong => currentTheme.border2;

  // Spec: dark rgba(0,0,0,0.58); light rgba(20,20,18,0.36) so paper stays warm.
  static Color get scrim => ThemeManager.instance.resolved.translucency.scrim ==
              0.6 &&
          currentTheme.bg.computeLuminance() > 0.18
      ? const Color(0x5C141412)
      : const Color(0xFF000000).withValues(
          alpha: ThemeManager.instance.resolved.translucency.scrim == 0.6
              ? 0.58
              : ThemeManager.instance.resolved.translucency.scrim);
  // Lighter, so a glass sheet still shows the page through its blur.
  static Color get glassScrim => const Color(0xFF000000).withValues(
      alpha: ThemeManager.instance.resolved.translucency.glassScrim);

  /// Behind every centred desktop dialog, Settings included.
  static Color get modalScrim => const Color(0xFF000000).withValues(
      alpha: ThemeManager.instance.resolved.translucency.modalScrim);

  /// Set while a chat wallpaper shows: side chrome goes opaque to frame it.
  static bool solidChrome = false;

  /// The user's chrome opacity; overrides [solidChrome] when set.
  static double? chromeAlpha;
  // Desktop Pure Black takes the reference's window, card and outline greys.
  static bool get _deskBlack => false;
  static Color get windowBg => kMobile
      ? currentTheme.bg
      : (_deskBlack
              ? const Color(0xFF09090A)
              // Quiet: the sidebar sits on s1, the centre pane on bg.
              : (currentTheme.name == 'quiet' ||
                      currentTheme.name == 'quiet-light')
                  ? currentTheme.surface1
                  : Color.lerp(currentTheme.bg, currentTheme.surface1, 0.45)!)
          .withValues(alpha: chromeAlpha ?? 1);

  /// Desktop window chrome; see-through while a scene plays behind the window.
  static Color get windowChrome => !kMobile && ChatScene.instance.active
      ? windowBg.withValues(alpha: 0.55)
      : windowBg;

  /// The inset desktop panel fill; see-through while a scene plays.
  static Color get panelFill => !kMobile && ChatScene.instance.active
      ? panelBg.withValues(alpha: 0.45)
      : panelBg;

  /// The inset desktop panel; phones keep the page background.
  static Color get panelBg => kMobile
      ? currentTheme.bg
      : (_deskBlack
          ? const Color(0xFF121213)
          : (currentTheme.name == 'quiet' ||
                  currentTheme.name == 'quiet-light')
              ? currentTheme.bg
              : currentTheme.surface1);
  static Color get panelOutline =>
      _deskBlack ? const Color(0xFF252526) : currentTheme.border;
  static Color get sidebarPanel => kMobile
      ? currentTheme.surface1
      : currentTheme.surface1.withValues(alpha: chromeAlpha ?? 1);
  static Color get paneBg =>
      kMobile ? currentTheme.bg : const Color(0x00000000);
  static Color get tint1 => kMobile
      ? currentTheme.surface1
      : currentTheme.fg1.withValues(alpha: 0.05);
  static Color get tint2 => kMobile
      ? currentTheme.surface2
      : currentTheme.fg1.withValues(alpha: 0.08);
  static Color get tint3 => kMobile
      ? currentTheme.surface3
      : currentTheme.fg1.withValues(alpha: 0.11);
  static Color get glassSurface => currentTheme.surface2;
  static Color get glassBorder => currentTheme.border;

  // Foreground
  static Color get fg1 => currentTheme.fg1;
  static Color get fg2 => currentTheme.fg2;
  static Color get fg3 => currentTheme.fg3;
  static Color get fg4 => currentTheme.fg4;

  // Borders
  static Color get border => currentTheme.border;
  static Color get border2 => currentTheme.border2;

  // Accent
  static Color get accent => currentTheme.accent;
  static Color get accentHover => currentTheme.accentHover;
  static Color get accentFg => currentTheme.accentFg;
  static Color get accentBg => currentTheme.accentBg;
  static Color get accentLine => currentTheme.accentLine;
  static Color get accentRing => currentTheme.accentRing;
  static Color get accentFill => currentTheme.accentFill;
  static Color get accentFillHover => currentTheme.accentFillHover;

  // Status
  static Color get ok => currentTheme.ok;
  static Color get okBg => currentTheme.okBg;
  static Color get run => currentTheme.run;

  /// Opaque amber tint for needs-you surfaces (attention bar, needs-you
  /// banner): 342F24 on dark, E8E4D9 on light (spec 3 rule G).
  static Color get attentionTint => currentTheme.bg.computeLuminance() > 0.18
      ? const Color(0xFFE8E4D9)
      : const Color(0xFF342F24);
  static Color get runBg => currentTheme.runBg;
  static Color get danger => currentTheme.danger;
  static Color get dangerBg => currentTheme.dangerBg;

  // Diff
  static Color get diffAddBg => currentTheme.diffAddBg;
  static Color get diffDelBg => currentTheme.diffDelBg;
  static Color get diffAddFg => currentTheme.diffAddFg;
  static Color get diffDelFg => currentTheme.diffDelFg;
  static Color get diffGutter => currentTheme.diffGutter;
}

Color get readingBg => AppColors.canvas;

// ---------------------------------------------------------------------------
// Radius — small and precise. Large radii read consumer/toy; a developer tool
// wants edges that feel engineered.
// ---------------------------------------------------------------------------

class R {
  static ThemeShapeTokens get _shape => ThemeManager.instance.resolved.shape;
  static double get _scale => math.max(0.0, _shape.radiusScale);

  static double get xs => _shape.radii.xs * _scale;
  static double get sm => _shape.radii.sm * _scale;
  static double get chip => _shape.radii.chip * _scale;
  static double get md => _shape.radii.md * _scale;
  static double get card => _shape.radii.card * _scale;
  static double get lg => _shape.radii.lg * _scale;
  static double get sheetTop => _shape.radii.sheetTop * _scale;
  static double get pill => _shape.radii.pill;

  /// An off-scale radius that still follows the theme's radius scale.
  static double of(double v) => v * _scale;
}

/// Outline of an agent avatar of [size], circle or squircle per the theme.
ShapeBorder avatarBorder(double size, {BorderSide side = BorderSide.none}) =>
    ThemeManager.instance.resolved.shape.avatar == 'squircle'
        ? RoundedSuperellipseBorder(
            side: side,
            borderRadius: BorderRadius.all(Radius.circular(size * 0.36)))
        : CircleBorder(side: side);

ShapeDecoration avatarDecoration(double size,
        {required Color color, BorderSide side = BorderSide.none}) =>
    ShapeDecoration(color: color, shape: avatarBorder(size, side: side));

AnimationStyle get sheetMotion => const AnimationStyle(
      // Spec G: 200 ms ease-out open and close, no spring.
      duration: Duration(milliseconds: 200),
      reverseDuration: Duration(milliseconds: 200),
      curve: Curves.easeOut,
      reverseCurve: Curves.easeOut,
    );

/// The only spacing values the app uses.
class S {
  // Phones always use the stock scale at density 1: a saved or imported theme
  // must not shrink the 16pt gutter below the spec.
  static ThemeSpaceScale get _scale =>
      kMobile ? ThemeSpaceScale.defaults : _space.scale;
  static ThemeSpaceTokens get _space => ThemeManager.instance.resolved.space;
  static double get _density =>
      kMobile ? 1.0 : math.max(0.0, _space.density);

  static double get s2 => _scale.s2 * _density;
  static double get s4 => _scale.s4 * _density;
  static double get s6 => _scale.s6 * _density;
  static double get s8 => _scale.s8 * _density;
  static double get s12 => _scale.s12 * _density;
  static double get s16 => _scale.s16 * _density;
  static double get s20 => _scale.s20 * _density;
  static double get s24 => _scale.s24 * _density;
  static double get s32 => _scale.s32 * _density;
  static double get s40 => _scale.s40 * _density;

  /// An off-scale spacing value that still follows the theme's density.
  static double of(double v) => v * _density;
}

/// Overlays lift with a surface step plus this shadow; nothing else casts one.
List<BoxShadow> get overlayShadow => const [
      BoxShadow(color: Color(0x73000000), blurRadius: 24, offset: Offset(0, 8)),
    ];

// ---------------------------------------------------------------------------
// Motion — the ONE place durations and curves are decided.
//
// Transitions used to pick their own number at each call site (11 distinct
// durations under 400ms), so the same gesture read differently on different
// screens. The stock Flutter curves are also too weak to read as intentional;
// these are the stronger custom variants.
// ---------------------------------------------------------------------------

class Motion {
  static ThemeMotionTokens get _motion => ThemeManager.instance.resolved.motion;
  static double get _speed => _motion.speed.clamp(0.1, 10.0);

  static Duration _scaled(int ms) => ms <= 0
      ? Duration.zero
      : Duration(milliseconds: (ms / _speed).round().clamp(1, 60000));

  /// Pointer-down acknowledgement — the fastest thing in the app.
  static Duration get press => _scaled(_motion.durations.press);

  /// Hover, colour and icon swaps.
  static Duration get quick => _scaled(_motion.durations.quick);

  /// A small surface appearing or changing: pills, chips, inline rows.
  static Duration get fast => _scaled(_motion.durations.fast);

  /// Panels, drawers, switches.
  static Duration get base => _scaled(_motion.durations.base);

  /// Sheets, menus and dialogs arriving.
  static Duration get open => _scaled(_motion.durations.open);

  /// Anything leaving — always shorter than it took to arrive.
  static Duration get close => _scaled(_motion.durations.close);

  /// Route push and pop.
  static Duration get page => _scaled(_motion.durations.page);

  /// A deliberate, infrequent change. Never for a repeated interaction.
  static Duration get slow => _scaled(_motion.durations.slow);

  /// One direction of the looping "working" breath on a live status glyph.
  static Duration get pulse => _scaled(_motion.durations.pulse);

  /// Fast start, long soft settle — the iOS sheet curve.
  static Cubic get enter {
    final c = _motion.curves.enter;
    return Cubic(c[0], c[1], c[2], c[3]);
  }

  static Cubic get exit {
    final c = _motion.curves.exit;
    return Cubic(c[0], c[1], c[2], c[3]);
  }

  static const move = Curves.easeInOut;
}

/// True when the platform asks for motion to be reduced.
///
/// Reduced motion means FEWER and gentler animations, not zero: opacity and
/// colour still help a person follow what changed, while position, scale and
/// looping motion are dropped. Every animated state change keeps a static cue
/// (colour, icon, label) regardless — motion is never the only channel.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

// ---------------------------------------------------------------------------
// Mobile metrics.
//
// The design language is one system at two densities, not two designs. Phones
// scale UP for touch (a 44pt minimum target) and down in density; they do NOT
// change the palette, the weight ramp, or the zero-border rule.
//
// These lived as inline `kMobile ? a : b` ternaries scattered across a 5k-line
// screen, which is how the two densities drifted apart. One table instead.
// ---------------------------------------------------------------------------

class M {
  // Pinned on phones like S.*: a saved theme must not shrink gutters or targets.
  static ThemeSpaceMetrics get _metrics => kMobile
      ? ThemeSpaceMetrics.defaults
      : ThemeManager.instance.resolved.space.metrics;
  static double get _typeScale => ThemeManager.instance.resolved.type.scale;

  /// Phone content follows the desktop pane/composer inset: 16px. Touch targets
  /// grow on mobile; the visual gutter does not become a second design system.
  static double get gutter => _metrics.gutter.current;

  /// Touch geometry. These are hit areas, not typography scales.
  static double get navRow => _metrics.navRow.current;
  static double get minTarget => _metrics.minTarget.current;
  static double get appBarHeight => _metrics.appBarHeight.current;

  /// Editorial hierarchy: page titles create a clear entry point, while section
  /// titles and row labels step down without collapsing into the same visual size.
  static double get pageTitle => 24.0 * _typeScale;
  static double get sectionTitle => 18.0 * _typeScale;

  /// Reading text is intentionally larger than compact metadata. The 15px row
  /// title keeps navigation scannable without competing with conversation prose.
  static double get rowTitle => 15.0 * _typeScale;
  static double get body => 17.0 * _typeScale;
  static double get meta => 12.0 * _typeScale;
  static double get monoMeta => 10.0 * _typeScale;

  /// Phone row geometry: a 52px visual rhythm with a >=44px target, rather than
  /// turning every row into a card.
  static double get rowHeight => _metrics.rowHeight.current;
  static double get rowPadH => _metrics.rowPadH.current;

  /// Legacy shell-strip metrics remain for narrow desktop only; phone navigation
  /// no longer renders that strip.
  static double get tabStripHeight => _metrics.tabStripHeight.current;
  static double get tabIconSize => _metrics.tabIconSize.current;
  static double get tabActionSize => _metrics.tabActionSize.current;
}

/// Inset between a pane's edge and the composer card.
///
/// Measured: the reference's card sits at x274 inside a pane starting at x258 —
/// 16px a side. The composer was previously full-bleed when embedded, which is
/// why it stuck to the sides of the shell.
const double kComposerGutter = 16;

// ---------------------------------------------------------------------------
// Typography — Geist for UI, Geist Mono for code.
//
// Two weights: 400 for prose, 500 for titles, row titles and controls. Nothing
// renders heavier than 500.
// ---------------------------------------------------------------------------

FontWeight _fontWeightFor(int value) {
  // Desktop never goes heavier than 500.
  final idx = ((value / 100).round() - 1)
      .clamp(0, kMobile ? FontWeight.values.length - 1 : 4);
  return FontWeight.values[idx];
}

/// Role weights — prefer these over raw `FontWeight.wNNN` so the ramp stays
/// consistent across the app.
class W {
  static ThemeTypeWeights get _weights =>
      ThemeManager.instance.resolved.type.weights;

  static FontWeight get body => _fontWeightFor(_weights.body);
  static FontWeight get label => _fontWeightFor(_weights.label);
  static FontWeight get title => _fontWeightFor(_weights.title);
  static FontWeight get strong => _fontWeightFor(_weights.strong);
}

FontWeight weightFor(FontWeight w) {
  final cap = kMobile
      ? math.max(FontWeight.w500.value, W.strong.value)
      : FontWeight.w500.value;
  return w.value > cap ? _fontWeightFor(cap) : w;
}

/// Text keeps the face's own spacing; only titles from 20px tighten, to -2%
/// at 28px.
double _tracking(double size) =>
    size < 20 ? 0 : size * -0.02 * ((size - 18) / 10).clamp(0.0, 1.0);

TextStyle sans(double size,
        {FontWeight? weight,
        double? height,
        double? spacing,
        Color? color,
        bool tabular = false}) =>
    TextStyle(
      fontFamily: kSansFamily,
      fontSize: size,
      fontWeight: weightFor(weight ?? W.body),
      height: height ?? 1.33,
      letterSpacing: spacing ?? _tracking(size),
      color: color ?? AppColors.fg2,
      // Proportional digits have different widths, so a ticking timer or a
      // counter shimmers and reflows as it updates. Geist ships `tnum`
      // (verified in the font's GSUB table), so this is a real substitution.
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );

TextStyle display(double size,
        {FontWeight? weight, Color? color, double? height}) =>
    TextStyle(
      fontFamily: kSansFamily,
      fontSize: size,
      fontWeight: weightFor(weight ?? W.title),
      height: height ?? 1.15,
      letterSpacing: _tracking(size),
      color: color ?? AppColors.fg1,
    );

/// Numbers, ids and labels: the UI face with tabular figures, not a code face.
TextStyle mono(double size,
        {FontWeight? weight,
        double? height,
        double? spacing,
        Color? color,
        bool tabular = true}) =>
    sans(size,
        weight: weight ?? W.body,
        height: height ?? 1.45,
        spacing: spacing,
        color: color ?? AppColors.fg1,
        tabular: tabular);

/// Real code: the user's chosen monospace face.
TextStyle codeMono(double size,
        {FontWeight? weight,
        double? height,
        double? spacing,
        Color? color,
        bool tabular = true}) =>
    // A monospace face is fixed-width already, so `tabular` defaults on and is
    // accepted only so call sites can share one signature with `sans()`.
    TextStyle(
      fontFamily: monoFamily,
      fontFamilyFallback: const ['GeistMono', 'monospace'],
      fontSize: size,
      fontWeight: weightFor(weight ?? W.body),
      height: height ?? 1.45,
      letterSpacing: spacing,
      color: color ?? AppColors.fg1,
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );

/// The ONE uppercase label style: small, 500, with POSITIVE tracking.
///
/// Small capitals need a little positive letter-spacing or the letters crowd
/// together. `_tracking()` is built for sentence-case UI text and runs tight
/// from 13px up, so uppercase labels pass their own `spacing:`.
/// Five call sites had drifted into three different treatments (no spacing,
/// `0.4`, `0.5`) with three different inks; this is the single replacement.
TextStyle caps(double size,
        {Color? color, double? spacing, FontWeight? weight}) =>
    sans(size,
        weight: weight ?? W.label,
        color: color,
        spacing: spacing ?? size * 0.06);

String get kSansFamily => ThemeManager.instance.currentFont.family;
const kSerifFamily = 'Literata';

/// The agent's own writing on a phone: a screen serif at a reading size, so a
/// long answer reads like a page rather than a wall of UI text.
TextStyle serif(double size,
        {FontWeight? weight,
        double? height,
        Color? color,
        FontStyle? fontStyle}) =>
    TextStyle(
      fontFamily: kSerifFamily,
      fontSize: size,
      fontWeight: weightFor(weight ?? W.body),
      fontStyle: fontStyle,
      height: height ?? 1.6,
      color: color ?? AppColors.fg1,
    );
const kMonoFamily = 'GeistMono';

String get monoFamily => ThemeManager.instance.currentMonoFont.family;

/// Type roles. Screens use these, not raw sizes.
class TS {
  static ThemeTypeTokens get _type => ThemeManager.instance.resolved.type;
  static ThemeTypeStyle _style(String key) =>
      _type.styles[key] ?? ThemeTypeTokens.defaultStyles[key]!;

  static TextStyle _sansStyle(
    String key,
    Color defaultColor, {
    Color? color,
    bool tabular = false,
  }) {
    final s = _style(key);
    final scale = _type.scale;
    return TextStyle(
      fontFamily: kSansFamily,
      fontSize: s.size.current * scale,
      fontWeight: _fontWeightFor(s.weight),
      height: s.height.current,
      letterSpacing: s.tracking.current * scale,
      color: color ?? defaultColor,
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );
  }

  static TextStyle _codeStyle(String key, Color defaultColor, {Color? color}) {
    final s = _style(key);
    final scale = _type.scale;
    final tracking = s.tracking.current * scale;
    return TextStyle(
      fontFamily: monoFamily,
      fontFamilyFallback: const ['GeistMono', 'monospace'],
      fontSize: s.size.current * scale,
      fontWeight: _fontWeightFor(s.weight),
      height: s.height.current,
      letterSpacing: tracking == 0.0 ? null : tracking,
      color: color ?? defaultColor,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static TextStyle pageTitle([Color? c]) =>
      _sansStyle('pageTitle', AppColors.fg1, color: c);
  static TextStyle sectionTitle([Color? c]) =>
      _sansStyle('sectionTitle', AppColors.fg1, color: c);
  static TextStyle rowTitle([Color? c]) =>
      _sansStyle('rowTitle', AppColors.fg1, color: c);
  static TextStyle body([Color? c]) =>
      _sansStyle('body', AppColors.fg2, color: c);
  static TextStyle ui([Color? c]) => _sansStyle('ui', AppColors.fg2, color: c);
  static TextStyle label([Color? c]) =>
      _sansStyle('label', AppColors.fg2, color: c);
  static TextStyle meta([Color? c]) =>
      _sansStyle('meta', AppColors.fg3, color: c, tabular: true);
  static TextStyle caption([Color? c]) =>
      _sansStyle('caption', AppColors.fg3, color: c);
  static TextStyle overline([Color? c]) =>
      _sansStyle('overline', AppColors.fg3, color: c);

  /// The agent's prose: the body sans a step up, with reading line height.
  static TextStyle reading([Color? c]) =>
      _sansStyle('reading', AppColors.fg1, color: c);
  static TextStyle code([Color? c]) =>
      _codeStyle('code', AppColors.fg2, color: c);
  static TextStyle codeSmall([Color? c]) =>
      _codeStyle('codeSmall', AppColors.fg3, color: c);
}

// ---------------------------------------------------------------------------
// Material ThemeData — derived from the active palette.
// ---------------------------------------------------------------------------

ThemeData buildAppTheme() {
  final c = currentTheme;
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: kSansFamily,
    brightness:
        c.bg.computeLuminance() > 0.18 ? Brightness.light : Brightness.dark,
    colorScheme: ColorScheme(
      brightness:
          c.bg.computeLuminance() > 0.18 ? Brightness.light : Brightness.dark,
      surface: c.bg,
      primary: c.accentFill,
      secondary: c.accentFill,
      error: c.danger,
      onSurface: c.fg1,
      onPrimary: c.accentFg,
      onSecondary: c.accentFg,
      onError: Colors.white,
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: SnappyPageTransitionsBuilder(),
      TargetPlatform.iOS: SnappyPageTransitionsBuilder(),
      TargetPlatform.macOS: SnappyPageTransitionsBuilder(),
      TargetPlatform.windows: SnappyPageTransitionsBuilder(),
      TargetPlatform.linux: SnappyPageTransitionsBuilder(),
    }),
    dividerColor: c.border,
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: c.accent.withValues(alpha: 0.35),
      cursorColor: c.accent,
      selectionHandleColor: c.accent,
    ),
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    // Phones: no square flash under a finger; the row itself is the feedback.
    highlightColor:
        kMobile ? Colors.transparent : c.surface3.withValues(alpha: 0.7),
    hoverColor:
        kMobile ? Colors.transparent : c.surface3.withValues(alpha: 0.5),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface2,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      surfaceTintColor: Colors.transparent,
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.lg),
          side: BorderSide(color: c.border)),
    ),
    // One UI family everywhere. A second near-identical sans-serif: at UI
    // sizes the two are almost indistinguishable, so every Material widget
    // (menus, tooltips, dialogs, text fields) rendered in a different family
    // than the app's own text around it — which reads as a mistake rather than
    // a pairing. One UI family.
    textTheme: _weightedTextTheme(base.textTheme
        .apply(fontFamily: kSansFamily, bodyColor: c.fg1, displayColor: c.fg1)),
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 12),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.accentFill,
      foregroundColor: c.accentFg,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.lg)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: c.accent),
    ),
  );
}

/// Material widgets inherit their weights from here, so this is the single
/// place that decides what reads as "heavy". Body copy stays at 400 and only
/// titles/labels step up to 500 — no 600+ anywhere in the inherited theme.
TextTheme _weightedTextTheme(TextTheme t) {
  TextStyle? w(TextStyle? s, FontWeight weight) =>
      s?.copyWith(fontWeight: weightFor(weight));
  return t.copyWith(
    displayLarge: w(t.displayLarge, W.label),
    displayMedium: w(t.displayMedium, W.label),
    displaySmall: w(t.displaySmall, W.label),
    headlineLarge: w(t.headlineLarge, W.label),
    headlineMedium: w(t.headlineMedium, W.label),
    headlineSmall: w(t.headlineSmall, W.label),
    titleLarge: w(t.titleLarge, W.label),
    titleMedium: w(t.titleMedium, W.label),
    titleSmall: w(t.titleSmall, W.label),
    bodyLarge: w(t.bodyLarge, W.body),
    bodyMedium: w(t.bodyMedium, W.body),
    bodySmall: w(t.bodySmall, W.body),
    labelLarge: w(t.labelLarge, W.label),
    labelMedium: w(t.labelMedium, W.label),
    labelSmall: w(t.labelSmall, W.label),
  );
}

/// Route transition: a short slide with a fade, settling on [Motion.enter].
/// The outgoing page drifts a little the other way so the two read as one move.
class SnappyPageTransitionsBuilder extends PageTransitionsBuilder {
  const SnappyPageTransitionsBuilder();

  @override
  Duration get transitionDuration => Motion.page;

  @override
  Duration get reverseTransitionDuration => Motion.close;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduceMotion(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    final incoming = CurvedAnimation(
        parent: animation, curve: Motion.enter, reverseCurve: Motion.exit);
    final outgoing = CurvedAnimation(
        parent: secondaryAnimation,
        curve: Motion.enter,
        reverseCurve: Motion.exit);
    return SlideTransition(
      position: Tween(begin: Offset.zero, end: const Offset(-0.06, 0))
          .animate(outgoing),
      child: SlideTransition(
        position: Tween(begin: const Offset(0.08, 0), end: Offset.zero)
            .animate(incoming),
        child: FadeTransition(opacity: incoming, child: child),
      ),
    );
  }
}

/// The status bar height, read from the view too: a sheet route can strip the
/// top padding from the context a full-height sheet sees.
double statusBarInset(BuildContext context) {
  final view = View.of(context);
  final fromView = view.padding.top / view.devicePixelRatio;
  final fromContext = MediaQuery.maybePaddingOf(context)?.top ?? 0;
  return fromContext > fromView ? fromContext : fromView;
}
