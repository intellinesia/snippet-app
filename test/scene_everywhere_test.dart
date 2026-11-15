import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/chat_scene.dart';
import 'package:snippet/motion_routes.dart';
import 'package:snippet/theme.dart';
import 'package:snippet_render/snippet_render.dart';

void main() {
  if (!shaderSurfaceSupported) return;

  Future<void> pushPage(WidgetTester tester, {bool nested = false}) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      theme: ThemeData(scaffoldBackgroundColor: AppColors.bg),
      home: const SizedBox(),
    ));
    nav.currentState!.push(AppPageRoute<void>(
      builder: (_) {
        const page = Scaffold(body: SizedBox(key: Key('page')));
        return nested ? const SceneBackdrop(child: page) : page;
      },
    ));
    await tester.pumpAndSettle();
  }

  Color? pageBg(WidgetTester tester) => Theme.of(tester.element(find.byKey(const Key('page'))))
      .scaffoldBackgroundColor;

  testWidgets('scene on: pushed page is clear and has one scene layer',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    await ChatScene.instance.set('aurora');
    addTearDown(() => ChatScene.instance.set(ChatScene.none));
    await pushPage(tester, nested: true);
    await tester.pump(const Duration(seconds: 6));
    expect(ChatScene.instance.ready, isTrue);
    expect(pageBg(tester), Colors.transparent);
    expect(AppColors.pageBg, Colors.transparent);
    expect(find.byType(ChatSceneLayer), findsOneWidget);
    expect(find.byType(ShaderView), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('scene off: pushed page is opaque with no layer content',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    await ChatScene.instance.set(ChatScene.none);
    await pushPage(tester);
    expect(pageBg(tester), AppColors.bg);
    expect(AppColors.pageBg, AppColors.bg);
    expect(find.byType(ShaderView), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
