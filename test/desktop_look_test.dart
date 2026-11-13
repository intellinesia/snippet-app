import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/desktop_look.dart';
import 'package:snippet/theme.dart';

Widget _app(Widget child) =>
    MaterialApp(theme: buildAppTheme(), home: Scaffold(body: child));

bool _hasTactilePaint(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .any((p) => p.foregroundPainter is TactilePainter);

void main() {
  tearDown(() {
    DesktopLook.instance
        .debugSet(tactile: true, wallpaper: DesktopLook.none, strength: 0.7);
  });

  testWidgets('tactile paints on desktop and follows the setting',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    DesktopLook.instance.debugSet(tactile: true);
    await tester.pumpWidget(_app(Tactile(
        radius: BorderRadius.circular(8),
        child: const SizedBox(width: 80, height: 30))));
    expect(_hasTactilePaint(tester), isTrue);
    DesktopLook.instance.debugSet(tactile: false);
    await tester.pump();
    expect(_hasTactilePaint(tester), isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('tactile is a no-op on phones', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(_app(Tactile(
        radius: BorderRadius.circular(8),
        child: const SizedBox(width: 80, height: 30))));
    expect(_hasTactilePaint(tester), isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('chat wallpaper draws only when an image is chosen',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    DesktopLook.instance.debugSet(wallpaper: DesktopLook.none);
    await tester.pumpWidget(_app(const SizedBox.expand(child: ChatWallpaper())));
    expect(find.byType(Image), findsNothing);
    DesktopLook.instance
        .debugSet(wallpaper: DesktopLook.image, imagePath: '/tmp/none.png');
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(DecoratedBox), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
