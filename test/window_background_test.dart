import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/screens/settings_panel.dart';
import 'package:snippet/window_background.dart';

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.linux);

  testWidgets('image under child when set, plain child otherwise',
      (tester) async {
    final f = File('${Directory.systemTemp.path}/wb_test.png')
      ..writeAsBytesSync(_png);
    await tester.pumpWidget(const MaterialApp(
        home: WindowBackground(child: Text('shell', key: Key('c')))));
    expect(find.byType(Image), findsNothing);
    WindowBackgroundStore.instance.path.value = f.path;
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(const Key('c')), findsOneWidget);
    WindowBackgroundStore.instance.path.value = null;
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    f.deleteSync();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('settings row shows on desktop only', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: AppearanceScreen()))));
    await tester.pump();
    expect(find.text('Transparent'), findsOneWidget);
    expect(find.text('Choose image'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: AppearanceScreen())));
    await tester.pump();
    expect(find.text('Choose image'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
