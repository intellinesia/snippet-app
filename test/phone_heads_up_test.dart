import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/mobile_kit/chrome.dart';
import 'package:snippet/phone_heads_up.dart';
import 'package:snippet/session_quick_send.dart';
import 'package:snippet/theme.dart';

Map<String, dynamic> _approval() => {
      'kind': 'waiting',
      'title': 'Duke | Lear Engineer',
      'body': 'Run the migration on the staging database?',
      'agent_id': 'snippet',
      'session': 's1',
      'attention': {'type': 'approval'},
    };

Future<void> _pump(WidgetTester t, Widget w) => t.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(body: Align(alignment: Alignment.topCenter, child: w))));

void main() {
  testWidgets('approval answers in place and dismisses', (t) async {
    QuickAction? sent;
    var dismissed = false;
    await _pump(
        t,
        PhoneHeadsUp(
          payload: _approval(),
          more: 2,
          onOpen: () {},
          onDismiss: () => dismissed = true,
          onHold: (_) {},
          send: (_, a) async {
            sent = a;
            return true;
          },
        ));
    expect(find.text('Duke'), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
    await t.tap(find.text('Go ahead'));
    await t.pump(const Duration(milliseconds: 100));
    expect(sent, isA<QuickApprove>());
    expect(dismissed, isTrue);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('tap opens; an upward flick dismisses', (t) async {
    var opened = false, dismissed = false;
    await _pump(
        t,
        PhoneHeadsUp(
          payload: const {'kind': 'done', 'title': 'Sashy', 'body': 'Merged'},
          more: 0,
          onOpen: () => opened = true,
          onDismiss: () => dismissed = true,
          onHold: (_) {},
        ));
    expect(find.text('Go ahead'), findsNothing);
    await t.tap(find.text('Merged'));
    expect(opened, isTrue);
    await t.fling(find.text('Merged'), const Offset(0, -80), 800);
    await t.pumpAndSettle();
    expect(dismissed, isTrue);
  });

  testWidgets('Agents tab carries the needs-you count, none at zero',
      (t) async {
    Widget bar(int n) => MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
            bottomNavigationBar: MkTabBar(
                tabs: const [
                  MkTab('Agents', 'home'),
                  MkTab('Sessions', 'chat')
                ],
                selected: 0,
                onSelect: (_) {},
                onCompose: () {},
                badges: {0: n})));
    await t.pumpWidget(bar(3));
    expect(find.byKey(const ValueKey('tab-badge-0')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    await t.pumpWidget(bar(0));
    expect(find.byKey(const ValueKey('tab-badge-0')), findsNothing);
  });
}
