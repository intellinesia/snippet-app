import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

Future<BuildContext> _host(WidgetTester t, double w, double h) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(w, h);
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  late BuildContext ctx;
  await t.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(body: Builder(builder: (c) {
      ctx = c;
      return const SizedBox.expand();
    })),
  ));
  return ctx;
}

Future<void> _open(WidgetTester t, BuildContext ctx,
    {SettingsPage page = SettingsPage.general}) async {
  unawaited(showSettings(
    ctx,
    client: _FakeClient(),
    instances: const [],
    active: null,
    onRemove: (_) {},
    page: page,
  ));
  await t.pumpAndSettle();
}

Rect _card(WidgetTester t) => t.getRect(find.byKey(const Key('settings-card')));

double _barrierAlpha(WidgetTester t) => t
    .widget<AnimatedModalBarrier>(find.byType(AnimatedModalBarrier))
    .color
    .value!
    .a;

void main() {
  _spec('D1 1440x900: card 960x640 centred, list 240, header 48', (t) async {
    final ctx = await _host(t, 1440, 900);
    await _open(t, ctx);

    final card = _card(t);
    debugPrint('card=$card');
    expect(card.left, closeTo(240, 1));
    expect(card.top, closeTo(130, 1));
    expect(card.width, closeTo(960, 1));
    expect(card.height, closeTo(640, 1));

    final list = t.getRect(find.byKey(const Key('settings-list')));
    debugPrint('list=$list');
    expect(list.left, closeTo(card.left, 1));
    expect(list.width, closeTo(240, 1));

    final title = t.getTopLeft(find.byKey(const Key('settings-title')));
    debugPrint('title=$title label=${settingsPageLabel(SettingsPage.general)}');
    expect(title.dx, closeTo(card.left + 240 + 24, 1));

    final header = t.getSize(find.byKey(const Key('settings-header')));
    debugPrint('header=$header');
    expect(header.height, closeTo(48, 1));

    final close = t.getSize(find.byKey(const Key('settings-close')));
    debugPrint('close=$close');
    expect(close.width, greaterThanOrEqualTo(28));
    expect(close.height, greaterThanOrEqualTo(28));

    expect(find.byKey(const Key('settings-esc-hint')), findsOneWidget);
    expect(find.text('Esc'), findsOneWidget);

    final alpha = _barrierAlpha(t);
    debugPrint('barrier alpha dark=$alpha');
    expect(alpha, closeTo(0.58, 0.01));

    expect(find.byType(BackdropFilter), findsNothing);

    // Light: the scrim warms to rgba(20,20,18,0.36).
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    await ThemeManager.instance.setName('quiet-light');
    await t.pump();
    await _open(t, ctx);
    final lightAlpha = _barrierAlpha(t);
    debugPrint('barrier alpha light=$lightAlpha');
    expect(lightAlpha, closeTo(0.36, 0.01));
  });

  _spec('D1 1024x768: card 921.6x640, list 208', (t) async {
    final ctx = await _host(t, 1024, 768);
    await _open(t, ctx);
    final card = _card(t);
    debugPrint('card=$card');
    expect(card.width, closeTo(921.6, 1));
    expect(card.height, closeTo(640, 1));
    final list = t.getRect(find.byKey(const Key('settings-list')));
    debugPrint('list=$list');
    expect(list.width, closeTo(208, 1));
  });

  _spec('D1 1024x700: card 921.6x630', (t) async {
    final ctx = await _host(t, 1024, 700);
    await _open(t, ctx);
    final card = _card(t);
    debugPrint('card=$card');
    expect(card.width, closeTo(921.6, 1));
    expect(card.height, closeTo(630, 1));
  });

  _spec('D1 760x700: card 684x630, no list column', (t) async {
    final ctx = await _host(t, 760, 700);
    await _open(t, ctx);
    final card = _card(t);
    debugPrint('card=$card');
    expect(card.width, closeTo(684, 1));
    expect(card.height, closeTo(630, 1));
    expect(find.byKey(const Key('settings-list')), findsNothing);
  });

  _spec('D1 1440x560: card 960x504', (t) async {
    final ctx = await _host(t, 1440, 560);
    await _open(t, ctx);
    final card = _card(t);
    debugPrint('card=$card');
    expect(card.width, closeTo(960, 1));
    expect(card.height, closeTo(504, 1));
  });

  _spec('D1 Esc closes the dialog', (t) async {
    final ctx = await _host(t, 1440, 900);
    await _open(t, ctx);
    expect(find.byKey(const Key('settings-card')), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('settings-card')), findsNothing);
  });
}
