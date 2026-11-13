import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/mobile_session_home.dart';

void main() {
  testWidgets('top bar switches lists and opens search until closed',
      (tester) async {
    final taps = <String>[];
    final ctl = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MobileHomeTopBar(
          agents: false,
          controller: ctl,
          focusNode: FocusNode(),
          onChanged: (v) => taps.add('q:$v'),
          onSessions: () => taps.add('sessions'),
          onAgents: () => taps.add('agents'),
          onSettings: () => taps.add('settings'),
        ),
      ),
    ));
    await tester.tap(find.text('Agents'));
    await tester.tap(find.byTooltip('Settings'));
    expect(taps, ['agents', 'settings']);

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(find.text('Agents'), findsNothing);
    await tester.enterText(find.byType(TextField), 'build');
    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();
    expect(ctl.text, isEmpty);
    expect(taps.last, 'q:');
    expect(find.text('Sessions'), findsOneWidget);
  });

  testWidgets('dock rings Mission Control while voice is on', (tester) async {
    var opened = 0, called = 0;
    Future<void> pump(bool live) => tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: MissionControlDock(
              live: live,
              badgeCount: 3,
              onOpen: () => opened++,
              onCall: () => called++,
            ),
          ),
        ));
    await pump(true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byTooltip('Mission Control, voice on'), findsOneWidget);
    expect(find.byTooltip('Voice call'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.text('Ask Mission Control'));
    await tester.tap(find.byTooltip('Voice call'));
    expect((opened, called), (1, 1));

    await pump(false);
    await tester.pump();
    expect(find.byTooltip('Mission Control'), findsOneWidget);
    expect(find.byTooltip('Start voice'), findsOneWidget);
  });
}
