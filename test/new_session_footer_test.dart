import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/screens/new_session_picker.dart';
import 'package:snippet/theme.dart';

class _Daemon extends DaemonClient {
  _Daemon() : super('http://127.0.0.1:9', 'tok');
}

void main() {
  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('Choose folder scrolls clear of Start at ${scale}x',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      addTearDown(tester.view.reset);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: NewSessionPicker(
            client: _Daemon(),
            machineLabel: 'Local',
            onOpenFolder: (_, __) async {}),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      final start = find.byTooltip('Start');
      final row = find.text('Choose folder').last;
      await tester.ensureVisible(row);
      await tester.pump();
      final r = tester.getRect(row);
      final s = tester.getRect(start);
      // ignore: avoid_print
      print('NEWSESSION ${scale}x choose=$r start=$s');
      expect(r.overlaps(s), isFalse);
      expect(r.bottom, lessThanOrEqualTo(s.top));
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
