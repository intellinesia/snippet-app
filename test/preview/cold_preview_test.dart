import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/composer/cold_strip.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/transcript.dart';

Future<void> _shoot(WidgetTester tester, Size size, TargetPlatform platform, String name) async {
  debugDefaultTargetPlatformOverride = platform;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        body: Column(children: [
          const SizedBox(height: 120),
          const SystemRow(step: 'continued_lean', reasoning: ''),
          const Spacer(),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ColdStrip(resumeTokens: 152000, onLean: () {}, onFull: () {}),
            ),
          ),
          const SizedBox(height: 90),
        ]),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
  await expectLater(find.byKey(key), matchesGoldenFile('goldens/cold/$name.png'));
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  testWidgets('phone', (t) => _shoot(t, const Size(390, 844), TargetPlatform.android, 'phone'));
  testWidgets('desktop', (t) => _shoot(t, const Size(1280, 800), TargetPlatform.macOS, 'desktop'));
}
