import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/term.dart';
import 'package:snippet/theme.dart';

Widget host(Widget child) => MaterialApp(
    theme: buildAppTheme(), home: Scaffold(body: child));

Widget view(ClearScrollTerminal term,
        {bool alive = true,
        bool ended = false,
        VoidCallback? onRestart,
        ValueChanged<Uint8List>? onInput}) =>
    SessionTermView(
      alive: alive,
      ended: ended,
      title: 'Shell 1',
      onRestart: onRestart,
      terminal: term,
      onInput: onInput ?? (_) {},
      onResize: (_, __) {},
      onClose: () {},
      mobileKeys: true,
      showChrome: false,
    );

void phoneSize(WidgetTester t, double w) {
  t.view.devicePixelRatio = 2;
  t.view.physicalSize = Size(w, 760) * 2;
  addTearDown(t.view.reset);
}

void main() {
  testWidgets('more opens the overflow keys and sends one', (t) async {
    phoneSize(t, 360);
    final sent = <String>[];
    await t.pumpWidget(host(view(ClearScrollTerminal(),
        onInput: (b) => sent.add(String.fromCharCodes(b)))));
    await t.tap(find.byKey(const ValueKey('term-more')));
    await t.pump();
    expect(find.byKey(const ValueKey('term-more-menu')), findsOneWidget);
    for (final k in ['alt', 'home', 'end', 'pgup', 'pgdn', 'del', 'F10']) {
      expect(find.text(k), findsOneWidget, reason: k);
    }
    expect(t.takeException(), isNull);
    await t.tap(find.text('home'));
    await t.pump();
    expect(sent, isNotEmpty);
    expect(find.byKey(const ValueKey('term-more-menu')), findsNothing);
  });

  testWidgets('ended shows the card, hides keys, and Restart calls back',
      (t) async {
    phoneSize(t, 390);
    var restarted = 0;
    final term = ClearScrollTerminal()
      ..write('ls\r\n\x1b[90m[process exited]\x1b[0m\r\n');
    await t.pumpWidget(host(view(term,
        alive: false, ended: true, onRestart: () => restarted++)));
    await t.pump();
    expect(find.text('Shell 1 ended'), findsOneWidget);
    expect(find.byKey(const ValueKey('term-keybar')), findsNothing);
    expect(find.byKey(const ValueKey('term-starting')), findsNothing);
    await t.tap(find.byKey(const ValueKey('term-restart')));
    expect(restarted, 1);
  });

  testWidgets('a shell still starting is not shown as ended', (t) async {
    phoneSize(t, 390);
    await t.pumpWidget(host(view(ClearScrollTerminal(), alive: false)));
    await t.pump();
    expect(find.byKey(const ValueKey('term-starting')), findsOneWidget);
    expect(find.byKey(const ValueKey('term-ended')), findsNothing);
    expect(find.byKey(const ValueKey('term-keybar')), findsOneWidget);
  });

}
