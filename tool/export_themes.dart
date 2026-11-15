import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:snippet/chat_scene.dart';
import 'package:snippet/theme.dart';

String _hex(Color c) {
  final argb = c.toARGB32();
  if ((argb >> 24) & 0xFF == 0xFF) {
    return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
  return '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}

Map<String, dynamic> _colorGroup(ThemePreset p) => {
      'bg': _hex(p.bg),
      'canvas': _hex(p.canvas),
      'floor': _hex(p.floor),
      'surface1': _hex(p.surface1),
      'surface2': _hex(p.surface2),
      'surface3': _hex(p.surface3),
      'fg1': _hex(p.fg1),
      'fg2': _hex(p.fg2),
      'fg3': _hex(p.fg3),
      'fg4': _hex(p.fg4),
      'border': _hex(p.border),
      'border2': _hex(p.border2),
      'accent': _hex(p.accent),
      'accentHover': _hex(p.accentHover),
      'accentFg': _hex(p.accentFg),
      'accentBg': _hex(p.accentBg),
      'accentLine': _hex(p.accentLine),
      'accentRing': _hex(p.accentRing),
      'accentFill': _hex(p.accentFill),
      'accentFillHover': _hex(p.accentFillHover),
      'ok': _hex(p.ok),
      'okBg': _hex(p.okBg),
      'run': _hex(p.run),
      'runBg': _hex(p.runBg),
      'danger': _hex(p.danger),
      'dangerBg': _hex(p.dangerBg),
      'diffAddBg': _hex(p.diffAddBg),
      'diffDelBg': _hex(p.diffDelBg),
      'diffAddFg': _hex(p.diffAddFg),
      'diffDelFg': _hex(p.diffDelFg),
      'diffGutter': _hex(p.diffGutter),
    };

Map<String, dynamic> _chatGroup() => {
      'sent': '#3A3A3C',
      'sentText': '#FFFFFF',
      'received': '#26262A',
      'receivedText': '#FFFFFF',
      'card': '#1C1C1E',
      'cardButton': '#2C2C2E',
      'meta': '#8E8E93',
      'glass': '#CC2C2C2E',
      'fontSize': {'phone': 16, 'desktop': 13.5},
      'bubbleRadius': {'phone': 18, 'desktop': 16},
      'runGap': 2.0,
      'groupGap': 10.0,
      'maxShare': {'phone': 0.78, 'desktop': 0.66},
      'avatarSize': {'phone': 28, 'desktop': 24},
      'agentReplies': 'bubble',
      'longReplies': 'bubble',
    };

Map<String, dynamic> _typeGroup() => {
      'uiFont': ThemeManager.defaultFont,
      'codeFont': ThemeManager.defaultMonoFont,
      'scale': 1.0,
      'weights': {
        'body': W.body.value,
        'label': W.label.value,
        'title': W.title.value,
        'strong': W.strong.value,
      },
      'styles': {
        for (final e in ThemeTypeTokens.defaultStyles.entries)
          e.key: e.value.toJson(),
      },
    };

Map<String, dynamic> _shapeGroup() => {
      'radiusScale': 1.0,
      'radii': {
        'xs': R.xs,
        'sm': R.sm,
        'chip': R.chip,
        'md': R.md,
        'card': R.card,
        'lg': R.lg,
        'sheetTop': R.sheetTop,
        'pill': R.pill,
      },
      'avatar': 'circle',
    };

Map<String, dynamic> _borderGroup() => {
      'width': 1.0,
      'hairline': 1.0,
      'cards': true,
      'glassEdgeAlpha': 0.08,
    };

Map<String, dynamic> _translucencyGroup() => {
      'canvasAlpha': {'phone': 1.0, 'desktop': 0.78},
      'windowTint': 0.35,
      'glassFill': 0.62,
      'glassBlur': 24.0,
      'edgeBlur': true,
      'scrim': 0.6,
      'glassScrim': 0.35,
      'modalScrim': 0.38,
      'enabled': true,
    };

Map<String, dynamic> _spaceGroup() => {
      'density': 1.0,
      'scale': {
        's2': S.s2,
        's4': S.s4,
        's6': S.s6,
        's8': S.s8,
        's12': S.s12,
        's16': S.s16,
        's20': S.s20,
        's24': S.s24,
        's32': S.s32,
        's40': S.s40,
      },
      'metrics': {
        'gutter': M.gutter,
        'navRow': M.navRow,
        'minTarget': M.minTarget,
        'appBarHeight': M.appBarHeight,
        'rowHeight': M.rowHeight,
        'rowPadH': M.rowPadH,
        'tabStripHeight': M.tabStripHeight,
        'tabIconSize': M.tabIconSize,
        'tabActionSize': M.tabActionSize,
      },
    };

List<double> _cubic(Cubic c) => [c.a, c.b, c.c, c.d];

Map<String, dynamic> _motionGroup() => {
      'speed': 1.0,
      'durations': {
        'press': Motion.press.inMilliseconds,
        'quick': Motion.quick.inMilliseconds,
        'fast': Motion.fast.inMilliseconds,
        'base': Motion.base.inMilliseconds,
        'open': Motion.open.inMilliseconds,
        'close': Motion.close.inMilliseconds,
        'page': Motion.page.inMilliseconds,
        'slow': Motion.slow.inMilliseconds,
        'pulse': Motion.pulse.inMilliseconds,
      },
      'curves': {
        'enter': _cubic(Motion.enter),
        'exit': _cubic(Motion.exit),
      },
    };

Map<String, dynamic> _backdropGroup() => {
      'scene': ChatScene.none,
      'params': <String, dynamic>{},
    };

Map<String, dynamic> _terminalGroup() => {
      // Same 16 ANSI slots as _emberTheme in lib/term.dart.
      'ansi': const [
        '#1B1917',
        '#E5745F',
        '#7FB88F',
        '#D4923C',
        '#9DB0FF',
        '#C79BD8',
        '#7FC4C0',
        '#CFC8BC',
        '#7A7368',
        '#EE9583',
        '#9DCCA9',
        '#E3A85A',
        '#B4C3FF',
        '#D8B4E6',
        '#9FD6D2',
        '#EDE7DD',
      ],
    };

Map<String, dynamic> _syntaxGroup() => {
      for (final entry in atomOneDarkTheme.entries)
        if (entry.value.color != null) entry.key: _hex(entry.value.color!),
    };

Map<String, dynamic> presetToSchema1(ThemePreset p) => {
      'schema': 1,
      'id': p.name,
      'name': p.label,
      'accent': null,
      'color': _colorGroup(p),
      'chat': _chatGroup(),
      'type': _typeGroup(),
      'shape': _shapeGroup(),
      'border': _borderGroup(),
      'translucency': _translucencyGroup(),
      'space': _spaceGroup(),
      'motion': _motionGroup(),
      'backdrop': _backdropGroup(),
      'terminal': _terminalGroup(),
      'syntax': _syntaxGroup(),
    };

void main() {
  test('export builtin themes to build/builtin.json', () {
    final presets = allPresets.where((p) => p.name != 'white').toList();
    final docs = [for (final p in presets) presetToSchema1(p)];
    final out = File('build/builtin.json');
    out.parent.createSync(recursive: true);
    out.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(docs)}\n');
    expect(docs.length, presets.length);
  });
}
