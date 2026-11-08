import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

void main() {
  for (final platform in [TargetPlatform.linux, TargetPlatform.android]) {
    testWidgets('one real click fires a pressable button (${platform.name})',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: IconBtn('search', tooltip: 'Search', onTap: () => taps++),
          ),
        ),
      ));
      final g = await tester.startGesture(tester.getCenter(find.byType(IconBtn)));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 60));
      await g.up();
      await tester.pumpAndSettle();
      expect(taps, 1);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
