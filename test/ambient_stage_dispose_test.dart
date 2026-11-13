import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/glass.dart';
import 'package:snippet/screens/mission_control/widgets/ambient_stage.dart';
import 'package:snippet/theme.dart';

import 'support/wake_fakes.dart';

void main() {
  testWidgets('desktop stage closes without creating a ticker in dispose',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    Glass.enabled = false;
    addTearDown(() => Glass.enabled = true);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: AmbientStage(
            client: FakeWakeClient(), animation: kAlwaysCompleteAnimation),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
