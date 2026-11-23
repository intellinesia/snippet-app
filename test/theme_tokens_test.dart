import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/chat_scene.dart';
import 'package:snippet/highlight.dart';
import 'package:snippet/main.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/term.dart';
import 'package:snippet/theme.dart';

class _FakeTokensDaemon extends DaemonClient {
  _FakeTokensDaemon() : super('https://daemon.invalid', 'tok');

  final DeviceEventHub _events = DeviceEventHub.local();
  @override
  DeviceEventHub get deviceEvents => _events;

  final Map<String, Map<String, dynamic>> resolvedDocs = {};
  String _activeId = 'black';

  Map<String, dynamic> _resolvedFor(String id) {
    final override = resolvedDocs[id];
    if (override != null) return Map<String, dynamic>.of(override);
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

  @override
  Future<ResolvedTheme> getActiveTheme() async => ResolvedTheme.fromJson({
        'active_set': true,
        'resolved': _resolvedFor(_activeId),
      });

  @override
  Future<ResolvedTheme?> setActiveTheme(String id) async {
    _activeId = id;
    return ResolvedTheme.fromJson({
      'active_set': true,
      'resolved': _resolvedFor(id),
    });
  }

  @override
  Future<ThemeListResponse> listThemes() async => ThemeListResponse(
        themes: [ThemeSummary.fromPreset(allPresets.first)],
        active: _activeId,
        activeSet: true,
      );
}

// Captured old constants before C2 (lib/theme.dart).
const _oldRadii = <String, double>{
  'xs': 4.0,
  'sm': 6.0,
  'chip': 6.0,
  'md': 8.0,
  'card': 10.0,
  'lg': 12.0,
  'sheetTop': 20.0,
  'pill': 999.0,
};

const _oldSpace = <String, double>{
  's2': 2.0,
  's4': 4.0,
  's6': 6.0,
  's8': 8.0,
  's12': 12.0,
  's16': 16.0,
  's20': 20.0,
  's24': 24.0,
  's32': 32.0,
  's40': 40.0,
};

const _oldMetrics = <String, double>{
  'gutter': 16.0,
  'navRow': 52.0,
  'minTarget': 44.0,
  'appBarHeight': 56.0,
  'pageTitle': 24.0,
  'sectionTitle': 18.0,
  'rowTitle': 15.0,
  'body': 17.0,
  'meta': 12.0,
  'monoMeta': 10.0,
  'rowHeight': 52.0,
  'rowPadH': 12.0,
  'tabStripHeight': 56.0,
  'tabIconSize': 28.0,
  'tabActionSize': 52.0,
};

const _oldWeights = <String, FontWeight>{
  'body': FontWeight.w400,
  'label': FontWeight.w500,
  'title': FontWeight.w500,
  'strong': FontWeight.w500,
};

const _oldDurations = <String, Duration>{
  'press': Duration(milliseconds: 100),
  'quick': Duration(milliseconds: 150),
  'fast': Duration(milliseconds: 180),
  'base': Duration(milliseconds: 220),
  'open': Duration(milliseconds: 240),
  'close': Duration(milliseconds: 180),
  'page': Duration(milliseconds: 260),
  'slow': Duration(milliseconds: 300),
  'pulse': Duration(milliseconds: 1150),
};

const _oldEnterCurve = Cubic(0.32, 0.72, 0, 1);
const _oldExitCurve = Cubic(0.23, 1, 0.32, 1);
const _oldMoveCurve = Curves.easeInOut;

const _oldEmberAnsi = <Color>[
  Color(0xff1B1917),
  Color(0xffE5745F),
  Color(0xff7FB88F),
  Color(0xffD4923C),
  Color(0xff9DB0FF),
  Color(0xffC79BD8),
  Color(0xff7FC4C0),
  Color(0xffCFC8BC),
  Color(0xff7A7368),
  Color(0xffEE9583),
  Color(0xff9DCCA9),
  Color(0xffE3A85A),
  Color(0xffB4C3FF),
  Color(0xffD8B4E6),
  Color(0xff9FD6D2),
  Color(0xffEDE7DD),
];

void _expectTsMatches(
  String label,
  TextStyle actual, {
  required double size,
  required FontWeight weight,
  required double height,
  required double? tracking,
  required Color color,
  required String fontFamily,
  bool tabular = false,
  double tolerance = 1e-9,
}) {
  expect(actual.fontSize, closeTo(size, tolerance), reason: '$label.fontSize');
  expect(actual.fontWeight, weight, reason: '$label.fontWeight');
  expect(actual.height, closeTo(height, tolerance), reason: '$label.height');
  if (tracking == null) {
    expect(actual.letterSpacing, isNull, reason: '$label.letterSpacing');
  } else {
    expect(actual.letterSpacing, closeTo(tracking, tolerance),
        reason: '$label.letterSpacing');
  }
  expect(actual.color, color, reason: '$label.color');
  expect(actual.fontFamily, fontFamily, reason: '$label.fontFamily');
  if (tabular) {
    expect(actual.fontFeatures, const [FontFeature.tabularFigures()],
        reason: '$label.fontFeatures');
  } else {
    expect(actual.fontFeatures, isNull, reason: '$label.fontFeatures');
  }
}

void _assertAllDefaultTokens({required bool mobile}) {
  expect(R.xs, _oldRadii['xs']);
  expect(R.sm, _oldRadii['sm']);
  expect(R.chip, _oldRadii['chip']);
  expect(R.md, _oldRadii['md']);
  expect(R.card, _oldRadii['card']);
  expect(R.lg, _oldRadii['lg']);
  expect(R.sheetTop, _oldRadii['sheetTop']);
  expect(R.pill, _oldRadii['pill']);

  expect(S.s2, _oldSpace['s2']);
  expect(S.s4, _oldSpace['s4']);
  expect(S.s6, _oldSpace['s6']);
  expect(S.s8, _oldSpace['s8']);
  expect(S.s12, _oldSpace['s12']);
  expect(S.s16, _oldSpace['s16']);
  expect(S.s20, _oldSpace['s20']);
  expect(S.s24, _oldSpace['s24']);
  expect(S.s32, _oldSpace['s32']);
  expect(S.s40, _oldSpace['s40']);

  expect(M.gutter, _oldMetrics['gutter']);
  expect(M.navRow, _oldMetrics['navRow']);
  expect(M.minTarget, _oldMetrics['minTarget']);
  expect(M.appBarHeight, _oldMetrics['appBarHeight']);
  expect(M.pageTitle, _oldMetrics['pageTitle']);
  expect(M.sectionTitle, _oldMetrics['sectionTitle']);
  expect(M.rowTitle, _oldMetrics['rowTitle']);
  expect(M.body, _oldMetrics['body']);
  expect(M.meta, _oldMetrics['meta']);
  expect(M.monoMeta, _oldMetrics['monoMeta']);
  expect(M.rowHeight, _oldMetrics['rowHeight']);
  expect(M.rowPadH, _oldMetrics['rowPadH']);
  expect(M.tabStripHeight, _oldMetrics['tabStripHeight']);
  expect(M.tabIconSize, _oldMetrics['tabIconSize']);
  expect(M.tabActionSize, _oldMetrics['tabActionSize']);

  expect(W.body, _oldWeights['body']);
  expect(W.label, _oldWeights['label']);
  expect(W.title, _oldWeights['title']);
  expect(W.strong, _oldWeights['strong']);

  expect(Motion.press, _oldDurations['press']);
  expect(Motion.quick, _oldDurations['quick']);
  expect(Motion.fast, _oldDurations['fast']);
  expect(Motion.base, _oldDurations['base']);
  expect(Motion.open, _oldDurations['open']);
  expect(Motion.close, _oldDurations['close']);
  expect(Motion.page, _oldDurations['page']);
  expect(Motion.slow, _oldDurations['slow']);
  expect(Motion.pulse, _oldDurations['pulse']);
  expect(Motion.enter.a, _oldEnterCurve.a);
  expect(Motion.enter.b, _oldEnterCurve.b);
  expect(Motion.enter.c, _oldEnterCurve.c);
  expect(Motion.enter.d, _oldEnterCurve.d);
  expect(Motion.exit.a, _oldExitCurve.a);
  expect(Motion.exit.b, _oldExitCurve.b);
  expect(Motion.exit.c, _oldExitCurve.c);
  expect(Motion.exit.d, _oldExitCurve.d);
  expect(Motion.move, _oldMoveCurve);
  expect(sheetMotion.duration, const Duration(milliseconds: 320));
  expect(sheetMotion.reverseDuration, const Duration(milliseconds: 220));

  _expectTsMatches(
    'TS.pageTitle',
    TS.pageTitle(),
    size: mobile ? 28 : 20,
    weight: FontWeight.w500,
    height: mobile ? 34 / 28 : 26 / 20,
    tracking: mobile ? -0.56 : -0.08,
    color: AppColors.fg1,
    fontFamily: ThemeManager.defaultFont,
  );
  _expectTsMatches(
    'TS.sectionTitle',
    TS.sectionTitle(),
    size: mobile ? 20 : 16,
    weight: FontWeight.w500,
    height: mobile ? 26 / 20 : 22 / 16,
    tracking: mobile ? -0.08 : 0.0,
    color: AppColors.fg1,
    fontFamily: ThemeManager.defaultFont,
  );
  _expectTsMatches(
    'TS.rowTitle',
    TS.rowTitle(),
    size: mobile ? 16 : 13,
    weight: FontWeight.w500,
    height: mobile ? 22 / 16 : 18 / 13,
    tracking: 0.0,
    color: AppColors.fg1,
    fontFamily: ThemeManager.defaultFont,
  );
  _expectTsMatches(
    'TS.body',
    TS.body(),
    size: mobile ? 16 : 14,
    weight: FontWeight.w400,
    height: mobile ? 24 / 16 : 22 / 14,
    tracking: 0.0,
    color: AppColors.fg2,
    fontFamily: ThemeManager.defaultFont,
  );
  _expectTsMatches(
    'TS.ui',
    TS.ui(),
    size: mobile ? 14 : 13,
    weight: FontWeight.w400,
    height: mobile ? 20 / 14 : 18 / 13,
    tracking: 0.0,
    color: AppColors.fg2,
    fontFamily: ThemeManager.defaultFont,
  );
  _expectTsMatches(
    'TS.label',
    TS.label(),
    size: mobile ? 13 : 12,
    weight: FontWeight.w500,
    height: mobile ? 18 / 13 : 16 / 12,
    tracking: 0.0,
    color: AppColors.fg2,
    fontFamily: ThemeManager.defaultFont,
  );
  _expectTsMatches(
    'TS.meta',
    TS.meta(),
    size: mobile ? 13 : 12,
    weight: FontWeight.w400,
    height: mobile ? 18 / 13 : 16 / 12,
    tracking: 0.0,
    color: AppColors.fg3,
    fontFamily: ThemeManager.defaultFont,
    tabular: true,
  );
  _expectTsMatches(
    'TS.caption',
    TS.caption(),
    size: mobile ? 12 : 11,
    weight: FontWeight.w400,
    height: mobile ? 16 / 12 : 14 / 11,
    tracking: 0.0,
    color: AppColors.fg3,
    fontFamily: ThemeManager.defaultFont,
  );
  _expectTsMatches(
    'TS.overline',
    TS.overline(),
    size: mobile ? 12 : 11,
    weight: FontWeight.w500,
    height: mobile ? 16 / 12 : 14 / 11,
    tracking: mobile ? 12 * 0.06 : 11 * 0.06,
    color: AppColors.fg3,
    fontFamily: ThemeManager.defaultFont,
  );
  _expectTsMatches(
    'TS.reading',
    TS.reading(),
    size: mobile ? 16 : 14,
    weight: FontWeight.w400,
    height: mobile ? 26 / 16 : 22 / 14,
    tracking: 0.0,
    color: AppColors.fg1,
    fontFamily: ThemeManager.defaultFont,
  );
  _expectTsMatches(
    'TS.code',
    TS.code(),
    size: mobile ? 13 : 12,
    weight: FontWeight.w400,
    height: mobile ? 20 / 13 : 18 / 12,
    tracking: null,
    color: AppColors.fg2,
    fontFamily: ThemeManager.defaultMonoFont,
    tabular: true,
  );
  _expectTsMatches(
    'TS.codeSmall',
    TS.codeSmall(),
    size: 12,
    weight: FontWeight.w400,
    height: 16 / 12,
    tracking: null,
    color: AppColors.fg3,
    fontFamily: ThemeManager.defaultMonoFont,
    tabular: true,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ThemeManager.instance.resetForTest();
    ChatScene.instance.resetForTest();
    debugDefaultTargetPlatformOverride = null;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    ThemeManager.instance.resetForTest();
    ChatScene.instance.resetForTest();
  });

  group('Zero regression on default black theme', () {
    test('all R/S/M/W/Motion/TS/terminal/syntax values match defaults on desktop',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await ThemeManager.instance.init();
      _assertAllDefaultTokens(mobile: false);

      final term = resolvedTerminalTheme();
      expect(
        <Color>[
          term.black,
          term.red,
          term.green,
          term.yellow,
          term.blue,
          term.magenta,
          term.cyan,
          term.white,
          term.brightBlack,
          term.brightRed,
          term.brightGreen,
          term.brightYellow,
          term.brightBlue,
          term.brightMagenta,
          term.brightCyan,
          term.brightWhite,
        ],
        _oldEmberAnsi,
      );
      expect(resolveHighlightTheme(), same(atomOneDarkTheme));
    });

    test('all R/S/M/W/Motion/TS values match defaults on phone', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await ThemeManager.instance.init();
      _assertAllDefaultTokens(mobile: true);
    });

    test('daemon-resolved scalar rounded heights match desktop TS within 1e-3 and toJson emits pairs',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final fake = _FakeTokensDaemon();
      fake.resolvedDocs['black-rounded'] = {
        'schema': 1,
        'id': 'black-rounded',
        'name': 'Black Rounded',
        'author': 'builtin',
        'color': allPresets.first.toColorJson(),
        'type': {
          'styles': {
            'pageTitle': {
              'size': {'phone': 28, 'desktop': 20},
              'weight': 500,
              'height': 1.3,
              'tracking': -0.08,
            },
            'sectionTitle': {
              'size': {'phone': 20, 'desktop': 16},
              'weight': 500,
              'height': 1.375,
              'tracking': 0.0,
            },
            'rowTitle': {
              'size': {'phone': 16, 'desktop': 13},
              'weight': 500,
              'height': 1.385,
              'tracking': 0.0,
            },
            'body': {
              'size': {'phone': 16, 'desktop': 14},
              'weight': 400,
              'height': 1.571,
              'tracking': 0.0,
            },
            'ui': {
              'size': {'phone': 14, 'desktop': 13},
              'weight': 400,
              'height': 1.385,
              'tracking': 0.0,
            },
            'label': {
              'size': {'phone': 13, 'desktop': 12},
              'weight': 500,
              'height': 1.333,
              'tracking': 0.0,
            },
            'meta': {
              'size': {'phone': 13, 'desktop': 12},
              'weight': 400,
              'height': 1.333,
              'tracking': 0.0,
            },
            'caption': {
              'size': {'phone': 12, 'desktop': 11},
              'weight': 400,
              'height': 1.273,
              'tracking': 0.0,
            },
            'overline': {
              'size': {'phone': 12, 'desktop': 11},
              'weight': 500,
              'height': 1.273,
              'tracking': 0.66,
            },
            'reading': {
              'size': {'phone': 16, 'desktop': 14},
              'weight': 400,
              'height': 1.571,
              'tracking': 0.0,
            },
            'code': {
              'size': {'phone': 13, 'desktop': 12},
              'weight': 400,
              'height': 1.5,
              'tracking': 0.0,
            },
            'codeSmall': {
              'size': 12,
              'weight': 400,
              'height': 1.333,
              'tracking': 0.0,
            },
          },
        },
      };

      await ThemeManager.instance.applyTheme('black-rounded', client: fake);
      _expectTsMatches(
        'rounded.rowTitle',
        TS.rowTitle(),
        size: 13,
        weight: FontWeight.w500,
        height: 18 / 13,
        tracking: 0.0,
        color: AppColors.fg1,
        fontFamily: ThemeManager.defaultFont,
        tolerance: 1e-3,
      );
      _expectTsMatches(
        'rounded.body',
        TS.body(),
        size: 14,
        weight: FontWeight.w400,
        height: 22 / 14,
        tracking: 0.0,
        color: AppColors.fg2,
        fontFamily: ThemeManager.defaultFont,
        tolerance: 1e-3,
      );
      _expectTsMatches(
        'rounded.overline',
        TS.overline(),
        size: 11,
        weight: FontWeight.w500,
        height: 14 / 11,
        tracking: 11 * 0.06,
        color: AppColors.fg3,
        fontFamily: ThemeManager.defaultFont,
        tolerance: 1e-3,
      );
      _expectTsMatches(
        'rounded.codeSmall',
        TS.codeSmall(),
        size: 12,
        weight: FontWeight.w400,
        height: 16 / 12,
        tracking: null,
        color: AppColors.fg3,
        fontFamily: ThemeManager.defaultMonoFont,
        tabular: true,
        tolerance: 1e-3,
      );

      // Default ResolvedTheme.toJson emits {phone, desktop} pairs for height & tracking.
      final defaultJson =
          ResolvedTheme.fromPreset(allPresets.first).toJson();
      final pageTitleJson =
          (defaultJson['type'] as Map)['styles']['pageTitle'] as Map;
      expect(pageTitleJson['height'], {'phone': 34 / 28, 'desktop': 26 / 20});
      expect(pageTitleJson['tracking'], {'phone': -0.56, 'desktop': -0.08});
    });
  });

  group('Custom theme tokens and restore', () {
    test('applies radiusScale, density, type.scale, motion.speed, ansi, syntax and restores defaults',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final fake = _FakeTokensDaemon();
      final customAnsi = [
        for (var i = 0; i < 16; i++)
          i == 1 ? '#FF1122' : formatThemeColor(ThemeTerminalTokens.defaultAnsi[i]),
      ];
      fake.resolvedDocs['custom-tokens'] = {
        'schema': 1,
        'id': 'custom-tokens',
        'name': 'Custom Tokens',
        'author': 'user',
        'color': allPresets.first.toColorJson(),
        'shape': {
          'radiusScale': 1.5,
        },
        'space': {
          'density': 1.25,
        },
        'type': {
          'scale': 1.1,
          'weights': {
            'body': 300,
            'strong': 700,
          },
        },
        'motion': {
          'speed': 2.0,
          'curves': {
            'enter': [0.1, 0.2, 0.3, 0.4],
          },
        },
        'terminal': {
          'ansi': customAnsi,
        },
        'syntax': {
          'keyword': '#FF00FF',
          'comment': '#00FF00',
        },
      };

      await ThemeManager.instance.applyTheme('custom-tokens', client: fake);
      expect(R.card, 15.0);
      expect(R.pill, 999.0);
      expect(S.s16, 20.0);
      expect(M.body, closeTo(17.0 * 1.1, 1e-9));
      expect(W.body, FontWeight.w300);
      expect(W.strong, FontWeight.w700);
      expect(TS.body().fontSize, closeTo(14.0 * 1.1, 1e-9));
      expect(Motion.base, const Duration(milliseconds: 110));
      expect(Motion.enter.a, 0.1);
      expect(sheetMotion.duration, const Duration(milliseconds: 160));

      final term = resolvedTerminalTheme();
      expect(term.red, const Color(0xFFFF1122));
      expect(term.green, ThemeTerminalTokens.defaultAnsi[2]);

      final syntax = resolveHighlightTheme();
      expect(syntax['keyword']?.color, const Color(0xFFFF00FF));
      expect(syntax['comment']?.color, const Color(0xFF00FF00));
      expect(syntax['comment']?.fontStyle, FontStyle.italic);
      expect(syntax['string']?.color, atomOneDarkTheme['string']?.color);

      // Switching back to black restores every default.
      await ThemeManager.instance.applyTheme('black', client: fake);
      _assertAllDefaultTokens(mobile: false);
      expect(resolvedTerminalTheme().red, ThemeTerminalTokens.defaultAnsi[1]);
      expect(resolveHighlightTheme(), same(atomOneDarkTheme));
    });

    test('backdrop.scene acts as default only when user has not chosen a scene',
        () async {
      final fake = _FakeTokensDaemon();
      fake.resolvedDocs['with-aurora'] = {
        'schema': 1,
        'id': 'with-aurora',
        'name': 'Aurora Theme',
        'author': 'user',
        'color': allPresets.first.toColorJson(),
        'backdrop': {'scene': 'aurora', 'params': <String, dynamic>{}},
      };

      await ThemeManager.instance.init();
      await ChatScene.instance.init();
      expect(ChatScene.instance.userChosen, isFalse);
      expect(ChatScene.instance.scene, ChatScene.none);

      await ThemeManager.instance.applyTheme('with-aurora', client: fake);
      expect(ChatScene.instance.scene, 'aurora');

      await ThemeManager.instance.applyTheme('black', client: fake);
      expect(ChatScene.instance.scene, ChatScene.none);

      // Once user picks a scene (even Off), theme backdrop no longer overrides it.
      await ChatScene.instance.set(ChatScene.none);
      expect(ChatScene.instance.userChosen, isTrue);
      await ThemeManager.instance.applyTheme('with-aurora', client: fake);
      expect(ChatScene.instance.scene, ChatScene.none);
    });
  });

  group('Widget tree rebuild on theme change', () {
    testWidgets(
        'const-free subtree rebuilds with new R/S/TS tokens without losing state or navigation',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final fake = _FakeTokensDaemon();
        fake.resolvedDocs['scaled'] = {
          'schema': 1,
          'id': 'scaled',
          'name': 'Scaled',
          'author': 'user',
          'color': allPresets.first.toColorJson(),
          'shape': {'radiusScale': 1.5},
          'space': {'density': 1.25},
          'type': {'scale': 1.1},
        };

        await tester.pumpWidget(
          const SnippetApp(home: _TokenProbeHome()),
        );
        await tester.pump();

        // Push a route and mutate StatefulWidget counter state inside it.
        await tester.tap(find.byKey(const Key('push-probe')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('inc-probe')));
        await tester.pump();
        expect(find.text('count=1'), findsOneWidget);

        double boxRadius() {
          final box =
              tester.widget<Container>(find.byKey(const Key('probe-box')));
          final dec = box.decoration as BoxDecoration;
          return (dec.borderRadius as BorderRadius).topLeft.x;
        }

        double padLeft() {
          final pad =
              tester.widget<Padding>(find.byKey(const Key('probe-pad')));
          return (pad.padding as EdgeInsets).left;
        }

        double bodyFontSize() {
          final text =
              tester.widget<Text>(find.byKey(const Key('probe-text')));
          return text.style!.fontSize!;
        }

        expect(boxRadius(), 10.0);
        expect(padLeft(), 16.0);
        expect(bodyFontSize(), 14.0);

        // Apply theme change through ThemeManager.
        await ThemeManager.instance.applyTheme('scaled', client: fake);
        await tester.pump();

        // Subtree updated to new tokens while preserving pushed route & state.
        expect(find.text('count=1'), findsOneWidget);
        expect(boxRadius(), 15.0);
        expect(padLeft(), 20.0);
        expect(bodyFontSize(), closeTo(14.0 * 1.1, 1e-9));

        // Pop returns to the still-intact home route.
        navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('push-probe')), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}

class _TokenProbeHome extends StatelessWidget {
  const _TokenProbeHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          key: const Key('push-probe'),
          onPressed: () {
            navigatorKey.currentState!.push(
              MaterialPageRoute<void>(builder: (_) => const _TokenProbePage()),
            );
          },
          child: const Text('Push'),
        ),
      ),
    );
  }
}

class _TokenProbePage extends StatefulWidget {
  const _TokenProbePage();

  @override
  State<_TokenProbePage> createState() => _TokenProbePageState();
}

class _TokenProbePageState extends State<_TokenProbePage> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        key: const Key('probe-pad'),
        padding: EdgeInsets.all(S.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: const Key('probe-box'),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.card),
              ),
              child: Text(
                'count=$_count',
                key: const Key('probe-text'),
                style: TS.body(),
              ),
            ),
            TextButton(
              key: const Key('inc-probe'),
              onPressed: () => setState(() => _count++),
              child: const Text('Inc'),
            ),
          ],
        ),
      ),
    );
  }
}
