import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/settings_overlay.dart';
import 'package:snippet/theme.dart';

class _FakeClient extends DaemonClient {
  _FakeClient() : super('http://127.0.0.1:1', 'tok');

  @override
  Future<bool> health({Duration timeout = const Duration(seconds: 2)}) async =>
      false;

  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async =>
      const [];
}

void _spec(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (t) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(t.view.reset);
    addTearDown(ThemeManager.instance.resetForTest);
    try {
      await body(t);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

final _behindKey = GlobalKey(debugLabel: 'behind');
final _behindFocus = FocusNode(debugLabel: 'behind');

Future<BuildContext> _host(WidgetTester t, double w, double h,
    {TargetPlatform platform = TargetPlatform.linux,
    double textScale = 1,
    EdgeInsets padding = EdgeInsets.zero}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(w, h);
  t.view.padding = FakeViewPadding(top: padding.top, bottom: padding.bottom);
  debugDefaultTargetPlatformOverride = platform;
  late BuildContext ctx;
  await t.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    builder: (c, child) => MediaQuery(
      data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(body: Builder(builder: (c) {
      ctx = c;
      return Center(
        child: ElevatedButton(
            key: _behindKey,
            focusNode: _behindFocus,
            onPressed: () {},
            child: const Text('Behind')),
      );
    })),
  ));
  return ctx;
}

Future<void> _open(WidgetTester t, BuildContext ctx,
    {SettingsPage? page, String? backLabel}) async {
  unawaited(showSettings(
    ctx,
    client: _FakeClient(),
    instances: const [],
    active: null,
    onRemove: (_) {},
    page: page,
    backLabel: backLabel,
    onSearchAll: (_) {},
  ));
  await t.pumpAndSettle();
}

Future<void> _type(WidgetTester t, String q) async {
  await t.enterText(
      find.descendant(
          of: find.byKey(const Key('settings-search')),
          matching: find.byType(TextField)),
      q);
  await t.pumpAndSettle();
}

List<String> _labels(WidgetTester t) {
  final out = <String>[];
  void walk(SemanticsNode n) {
    if (n.label.isNotEmpty) out.add(n.label);
    n.visitChildren((c) {
      walk(c);
      return true;
    });
  }

  walk(t.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
  return out;
}

void main() {
  _spec('D2 list: 13 rows, pitch 28, 4 groups, selected bar', (t) async {
    final ctx = await _host(t, 1440, 900);
    await _open(t, ctx, page: SettingsPage.general);
    final rows = find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith('settings-row-') &&
        (w.key as ValueKey<String>).value != 'settings-row-bar');
    expect(rows, findsNWidgets(13));
    final a = t.getRect(find.byKey(const Key('settings-row-models')));
    final b = t.getRect(find.byKey(const Key('settings-row-routing')));
    expect(a.height, 28);
    expect(b.top - a.top, 28);
    expect(find.byKey(const Key('settings-row-bar')), findsOneWidget);
    final list = t.getRect(find.byKey(const Key('settings-list')));
    final last =
        t.getRect(find.byKey(const Key('settings-row-appearance')));
    expect(last.bottom <= list.bottom, isTrue);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  _spec('D2 at 1440x560 the list scrolls and stays inside the card',
      (t) async {
    final ctx = await _host(t, 1440, 560);
    await _open(t, ctx);
    final card = t.getRect(find.byKey(const Key('settings-card')));
    expect(card.height, 504);
    final scroll = t.widget<ListView>(
        find.byKey(const Key('settings-list-rows')));
    expect(scroll.controller!.position.maxScrollExtent, greaterThan(0));
  });

  _spec('D4 search filters, Enter opens, Esc clears then closes', (t) async {
    final ctx = await _host(t, 1440, 900);
    await _open(t, ctx, page: SettingsPage.general);
    await _type(t, 'secrets');
    expect(find.text('Search results'), findsOneWidget);
    expect(find.byKey(const Key('settings-result-vault')), findsOneWidget);
    expect(find.byKey(const Key('settings-row-models')), findsNothing);
    expect(find.textContaining('1 result for'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.byKey(const Key('settings-title'))).data,
        'Vault');

    await _type(t, 'wombat');
    expect(find.byKey(const Key('settings-no-results')), findsOneWidget);
    expect(find.byKey(const Key('settings-list-empty')), findsOneWidget);
    expect(find.byKey(const Key('settings-search-all')), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('settings-card')), findsOneWidget);
    expect(find.byKey(const Key('settings-no-results')), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('settings-card')), findsNothing);
  });

  _spec('D6 keyboard: Down then Enter opens the next page', (t) async {
    final ctx = await _host(t, 1440, 900);
    await _open(t, ctx, page: SettingsPage.general);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.byKey(const Key('settings-title'))).data,
        'Inference profiles');
    await t.sendKeyEvent(LogicalKeyboardKey.end);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.byKey(const Key('settings-title'))).data,
        'Theme and accent');
  });

  _spec('D6 Tab 20 times never reaches the app behind', (t) async {
    final ctx = await _host(t, 1440, 900);
    await _open(t, ctx, page: SettingsPage.vault);
    final behind = _behindFocus;
    for (var i = 0; i < 20; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      expect(behind.hasFocus, isFalse, reason: 'tab $i');
    }
  });

  _spec('D6 app behind is excluded from semantics while open', (t) async {
    final handle = t.ensureSemantics();
    final ctx = await _host(t, 1440, 900);
    expect(_labels(t), contains('Behind'));
    await _open(t, ctx);
    expect(_labels(t), isNot(contains('Behind')));
    expect(find.bySemanticsLabel('Close settings'), findsWidgets);
    expect(find.bySemanticsLabel('Settings pages'), findsOneWidget);
    handle.dispose();
  });

  _spec('D5 deep link: page, back line, closes like Close', (t) async {
    final ctx = await _host(t, 1440, 900);
    await _open(t, ctx, page: SettingsPage.vault, backLabel: 'App Redesign');
    expect(t.widget<Text>(find.byKey(const Key('settings-title'))).data,
        'Vault');
    expect(find.text('Back to App Redesign'), findsOneWidget);
    final line = t.getRect(find.byKey(const Key('settings-back-line')));
    expect(line.height, 28);
    await t.tap(find.byKey(const Key('settings-back-line')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('settings-card')), findsNothing);
  });

  _spec('D5 plain reopen lands on the last page used', (t) async {
    final ctx = await _host(t, 1440, 900);
    await _open(t, ctx, page: SettingsPage.memory);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    await _open(t, ctx);
    expect(t.widget<Text>(find.byKey(const Key('settings-title'))).data,
        'Memory');
  });

  _spec('D7 760 wide: picker row, no list column', (t) async {
    final ctx = await _host(t, 760, 700);
    await _open(t, ctx, page: SettingsPage.general);
    expect(find.byKey(const Key('settings-list')), findsNothing);
    expect(find.byKey(const Key('settings-picker')), findsOneWidget);
    final search = t.getRect(find.byKey(const Key('settings-search')));
    expect(search.width, 210);
    await t.tap(find.byKey(const Key('settings-picker')));
    await t.pumpAndSettle();
    await t.tap(find.text('Routing').last);
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.byKey(const Key('settings-title'))).data,
        'Routing');
  });

  group('phone sheet', () {
    Future<BuildContext> phone(WidgetTester t, double w, double h,
            {double textScale = 1}) =>
        _host(t, w, h,
            platform: TargetPlatform.android,
            textScale: textScale,
            padding: const EdgeInsets.only(top: 22, bottom: 20));

    for (final (w, h) in const [(360.0, 640.0), (393.0, 852.0), (430.0, 932.0)]) {
      _spec('P1 $w x $h: full width, medium 60%, then large', (t) async {
        final ctx = await phone(t, w, h);
        await _open(t, ctx);
        final sheet = t.getRect(find.byKey(const Key('settings-sheet')));
        expect(sheet.width, w);
        // Visible height at medium = viewport minus the sheet top.
        expect((h - sheet.top - (0.6 * h).roundToDouble()).abs() <= 2, isTrue,
            reason: 'top ${sheet.top}');
        final grab = t.getRect(find.byKey(const Key('settings-sheet-grabber')));
        expect(grab.size, const Size(96, 48));
        final close = t.getRect(find.byKey(const Key('settings-sheet-close')));
        expect(close.size, const Size(48, 48));
        await t.tap(find.byKey(const Key('settings-sheet-grabber')));
        await t.pumpAndSettle();
        final large = t.getRect(find.byKey(const Key('settings-sheet')));
        expect((large.top - (22 + 8)).abs() <= 1, isTrue,
            reason: 'large top ${large.top}');
        expect(find.byType(BackdropFilter), findsNothing);
      });
    }

    for (final scale in const [1.0, 1.35, 2.0]) {
      _spec('P2 rows stay at least 48 at ${scale}x text', (t) async {
        final ctx = await phone(t, 393, 852, textScale: scale);
        await _open(t, ctx);
        final r = t.getRect(
            find.byKey(const Key('settings-sheet-row-general')));
        expect(r.height >= 48, isTrue);
        expect(t.takeException(), isNull);
      });
    }

    _spec('P3/P6 row opens page at large; back: page, index, closed',
        (t) async {
      final ctx = await phone(t, 393, 852);
      await _open(t, ctx);
      await t.tap(find.byKey(const Key('settings-sheet-row-models')));
      await t.pumpAndSettle();
      expect(
          t.widget<Text>(find.byKey(const Key('settings-sheet-title'))).data,
          'Inference profiles');
      expect(find.byKey(const Key('settings-sheet-back')), findsOneWidget);
      final top = t.getRect(find.byKey(const Key('settings-sheet'))).top;
      expect((top - 30).abs() <= 1, isTrue, reason: 'top $top');
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('settings-sheet-index')), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('settings-sheet')), findsNothing);
    });

    _spec('P5 deep link opens at large on the page with a 48 back row',
        (t) async {
      final ctx = await phone(t, 393, 852);
      await _open(t, ctx,
          page: SettingsPage.vault, backLabel: 'App Redesign');
      final top = t.getRect(find.byKey(const Key('settings-sheet'))).top;
      expect((top - 30).abs() <= 1, isTrue);
      final row = t.getRect(find.byKey(const Key('settings-sheet-back-line')));
      expect(row.height, 48);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('settings-sheet')), findsNothing);
    });

    _spec('P4 search: results, then back clears first', (t) async {
      final ctx = await phone(t, 360, 640);
      await _open(t, ctx);
      await t.enterText(
          find.descendant(
              of: find.byKey(const Key('settings-sheet-search')),
              matching: find.byType(TextField)),
          'voice');
      await t.pumpAndSettle();
      expect(find.byKey(const Key('settings-sheet-result-count')),
          findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('settings-sheet-index')), findsOneWidget);
      expect(find.byKey(const Key('settings-sheet')), findsOneWidget);
    });
  });
}
