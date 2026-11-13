import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/ambient/live_caption.dart';
import 'package:snippet/glass.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/mission_control/widgets/ambient_desktop_panel.dart';

AmbientEvent _ev(String id, String text, {String? verdict}) =>
    AmbientEvent.fromJson({
      'id': id,
      'text': text,
      'status': 'done',
      'verdict': verdict,
      'started_at': DateTime.now()
          .subtract(const Duration(minutes: 5))
          .toUtc()
          .toIso8601String(),
    });

void main() {



  testWidgets('renders header, caption and recent rows', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    Glass.enabled = false;
    addTearDown(() => Glass.enabled = true);
    final feed = LiveCaptionFeed()..apply({'text': 'hello panel', 'final': false});
    var toggled = 0, closed = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: AmbientDesktopPanel(
            stateWord: 'Listening',
            live: true,
            color: Colors.green,
            canToggle: true,
            onToggle: () => toggled++,
            onClose: () => closed++,
            feed: feed,
            recent: [_ev('1', 'turn on the lights', verdict: 'command'), _ev('2', 'second line')],
          ),
        ),
      ),
    ));
    expect(find.text('Listening'), findsOneWidget);
    expect(find.text('End'), findsOneWidget);
    expect(find.byKey(const ValueKey('ambient-caption')), findsOneWidget);
    expect(find.text('“hello panel”'), findsOneWidget);
    expect(find.text('turn on the lights'), findsOneWidget);
    expect(find.text('command'), findsOneWidget);
    expect(find.text('second line'), findsOneWidget);
    expect(find.text('5m'), findsNWidgets(2));
    await tester.tap(find.text('End'));
    expect(toggled, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('empty state and Start when off', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    Glass.enabled = false;
    addTearDown(() => Glass.enabled = true);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: AmbientDesktopPanel(
            stateWord: 'Off',
            live: false,
            color: Colors.green,
            canToggle: true,
            onToggle: () {},
            onClose: () {},
            feed: LiveCaptionFeed(),
            recent: const [],
          ),
        ),
      ),
    ));
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Nothing heard yet'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
