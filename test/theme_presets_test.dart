import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/theme.dart';

// WCAG contrast ratio; Color.computeLuminance() is relative luminance.
double _ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

const _newIds = ['ink', 'mist', 'navy', 'paper', 'graphite', 'oled'];

// Hand-tuned accentBg / runBg from spec_themes.md §2 (design tonal_sel /
// tonal_needs). Every other slot uses _palette's derived defaults.
const _tonal = {
  'ink': (Color(0xFF222534), Color(0xFF2E281A)),
  'mist': (Color(0xFFE8F1FB), Color(0xFFF0ECE3)),
  'navy': (Color(0xFF1E374E), Color(0xFF313336)),
  'paper': (Color(0xFFE7EEEC), Color(0xFFEEE8DD)),
  'graphite': (Color(0xFF2F353C), Color(0xFF3D3626)),
  'oled': (Color(0xFF2D2E30), Color(0xFF2F291C)),
};

ThemePreset _preset(String name) =>
    allPresets.firstWhere((p) => p.name == name);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('allPresets has ten entries in spec order', () {
    expect(allPresets.length, 10);
    expect(allPresets.map((p) => p.name).toList(), [
      'quiet',
      'quiet-light',
      'ink',
      'mist',
      'navy',
      'paper',
      'graphite',
      'oled',
      'hc-dark',
      'hc-light',
    ]);
    expect(allPresets.map((p) => p.label).toList().sublist(2, 8),
        ['Ink', 'Mist', 'Slate Navy', 'Paper', 'Graphite', 'OLED']);
  });

  test('new presets keep a strict foreground ladder against bg', () {
    for (final id in _newIds) {
      final p = _preset(id);
      final ladder =
          [p.fg1, p.fg2, p.fg3, p.fg4].map((c) => _ratio(c, p.bg)).toList();
      for (var i = 0; i < ladder.length - 1; i++) {
        expect(ladder[i], greaterThan(ladder[i + 1]),
            reason: '$id fg${i + 1} must out-contrast fg${i + 2} on bg');
      }
    }
  });

  test('fg1-fg3 clear 4.5 on bg and every surface of the new six', () {
    // Scoped to the new six: quiet-light's existing fg3/surface3 sits at
    // 4.28 and is left untouched per spec.
    for (final id in _newIds) {
      final p = _preset(id);
      final surfaces = [p.bg, p.surface1, p.surface2, p.surface3];
      for (final (i, fg) in [p.fg1, p.fg2, p.fg3].indexed) {
        for (final s in surfaces) {
          expect(_ratio(fg, s), greaterThanOrEqualTo(4.5),
              reason: '$id fg${i + 1} must meet AA on its surfaces');
        }
      }
    }
  });

  test('new presets clear accent and on-accent contrast', () {
    for (final id in _newIds) {
      final p = _preset(id);
      expect(_ratio(p.accent, p.bg), greaterThanOrEqualTo(3.0),
          reason: '$id accent must read against bg');
      expect(_ratio(p.accentFg, p.accent), greaterThanOrEqualTo(4.5),
          reason: '$id accentFg must meet AA on accent');
    }
  });

  test('new presets use the hand-tuned tonal accents', () {
    for (final id in _newIds) {
      final p = _preset(id);
      final (accentBg, runBg) = _tonal[id]!;
      expect(p.accentBg, accentBg, reason: '$id accentBg');
      expect(p.runBg, runBg, reason: '$id runBg');
    }
    final quiet = _preset('quiet');
    expect(quiet.accentBg, quiet.accent.withValues(alpha: 0.14));
    expect(quiet.runBg, quiet.run.withValues(alpha: 0.13));
  });

  test('setName activates each new preset and changes the signature', () async {
    final tm = ThemeManager.instance..resetForTest();
    final seen = <String>{tm.tokenSignature};
    for (final id in _newIds) {
      await tm.setName(id);
      expect(tm.activeId, id);
      expect(seen.add(tm.tokenSignature), isTrue,
          reason: 'switching to $id must change tokenSignature');
    }
    tm.resetForTest();
  });

  test('themePairs covers every preset with a valid counterpart', () {
    final names = allPresets.map((p) => p.name).toSet();
    for (final name in names) {
      expect(themePairs.containsKey(name), isTrue,
          reason: '$name needs a brightness pair');
      expect(names.contains(themePairs[name]), isTrue,
          reason: 'themePairs[$name] must be a real preset');
    }
  });
}
