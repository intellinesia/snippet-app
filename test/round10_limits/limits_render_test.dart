import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/accounts_screen.dart';
import 'package:snippet/theme.dart';

int get _now => DateTime.now().millisecondsSinceEpoch ~/ 1000;

Map<String, dynamic> _w(num pct, int minutes, int resetIn) => {
      'used_percent': pct,
      'window_minutes': minutes,
      'resets_at': _now + resetIn,
    };

class _Daemon extends DaemonClient {
  _Daemon() : super('http://127.0.0.1:1', 'tok');

  @override
  Future<Map<String, List<Account>>> getAccounts() async => {
        'chatgpt': [
          Account.fromJson({
            'id': 'c1',
            'label': 'snipextt@icloud.com',
            'limited_until': _now + 18 * 3600 + 28 * 60,
            'usage': {'primary': _w(100, 43200, 20 * 86400)},
          }),
          Account.fromJson({
            'id': 'c2',
            'label': 'snipextt@gmail.com',
            'active': true,
            'usage': {'primary': _w(38, 43200, 20 * 86400)},
          }),
        ],
        'xai': [
          Account.fromJson({'id': 'x1', 'label': 'x sub', 'active': true}),
        ],
        'claude': [
          Account.fromJson({
            'id': 'k1',
            'label': 'Account 1',
            'limited_until': _now + 31 * 60 + 30,
            'usage': {
              'primary': _w(100, 300, 31 * 60),
              'secondary': _w(70, 10080, 3 * 86400),
            },
          }),
          Account.fromJson({
            'id': 'k2',
            'label': 'intellinesia',
            'limited_until': _now + 61,
            'usage': {
              'primary': _w(100, 300, 61),
              'secondary': _w(94, 10080, 3 * 86400),
            },
          }),
          Account.fromJson({
            'id': 'k3',
            'label': 'newest',
            'active': true,
            'usage': {
              'primary': _w(79, 300, 3600),
              'secondary': _w(10, 10080, 5 * 86400),
            },
          }),
        ],
        'devin': [
          Account.fromJson({
            'id': 'd1',
            'label': 'Account 1',
            'active': true,
            'usage': {
              'primary': _w(0, 10080, 5 * 86400),
              'secondary': _w(0, 10080, 5 * 86400),
            },
          }),
        ],
      };
}

Future<void> _shot(WidgetTester t, String name) async {
  const dir = String.fromEnvironment('SHOT_DIR');
  if (dir.isEmpty) return;
  await t.runAsync(() async {
    final b = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('shot')));
    final img = await b.toImage();
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('phone accounts list shows meters, not a sentence',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1100);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: RepaintBoundary(
          key: const ValueKey('shot'),
          child: ColoredBox(
            color: AppColors.bg,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 48, 12, 16),
              child: AccountsScreen(client: _Daemon(), embedded: true),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await _shot(tester, 'limits');

    expect(find.textContaining('window'), findsNothing);
    expect(find.text('Back in 31m'), findsOneWidget);
    expect(find.text('In use'), findsNWidgets(4));
    expect(find.text('5 hours'), findsNWidgets(3));
    // Devin's duplicated window collapses to a single meter.
    expect(find.text('Week'), findsNWidgets(4));
    expect(find.text('Month'), findsNWidgets(2));
    debugDefaultTargetPlatformOverride = null;
  });
}
