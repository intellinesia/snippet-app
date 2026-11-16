import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/term.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

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
  testWidgets('key bar fits at 360 with no overflow', (t) async {
    phoneSize(t, 360);
    await t.pumpWidget(host(view(ClearScrollTerminal())));
    await t.pump();
    expect(t.takeException(), isNull);
    final bar = t.getRect(find.byKey(const ValueKey('term-keybar')));
    expect(bar.left, greaterThanOrEqualTo(0));
    expect(bar.right, lessThanOrEqualTo(360));
    for (final k in ['esc', 'tab', 'ctrl', '←', '↓', '↑', '→']) {
      final r = t.getRect(find.text(k));
      expect(r.right, lessThanOrEqualTo(360 - 16), reason: k);
    }
    final more = t.getRect(find.byKey(const ValueKey('term-more')));
    expect(more.right, lessThanOrEqualTo(360 - 16 + 0.5));
    expect(more.width, greaterThanOrEqualTo(34));
  });

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

  testWidgets('phone tabs render with selection and close', (t) async {
    phoneSize(t, 360);
    int? picked;
    int? closed;
    await t.pumpWidget(host(MobileTermTabs(
      tabs: [
        TermTab('Shell 1', termDotColor(alive: true, ended: false)),
        TermTab('Shell 2', termDotColor(alive: false, ended: true)),
      ],
      focus: 0,
      onSelect: (n) => picked = n,
      onRename: (_) {},
      onClose: (n) => closed = n,
    )));
    expect(find.text('Shell 1'), findsOneWidget);
    expect(find.text('Shell 2'), findsOneWidget);
    expect(t.getSize(find.byType(TermTabChip).first).height, 32);
    await t.tap(find.text('Shell 2'));
    expect(picked, 1);
    await t.tap(find.descendant(
        of: find.byType(TermTabChip).first, matching: find.byType(AppIcon)));
    expect(closed, 0);
    expect(termDotColor(alive: false, ended: true), AppColors.fg4);
    expect(termDotColor(alive: true, ended: false), AppColors.ok);
  });

  testWidgets('desktop dock bar and footer render', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    t.view.devicePixelRatio = 2;
    t.view.physicalSize = const Size(620, 400) * 2;
    addTearDown(t.view.reset);
    var added = 0;
    await t.pumpWidget(host(Column(children: [
      TermDockBar(
        tabs: [TermTab('Shell 1', termDotColor(alive: true, ended: false))],
        focus: 0,
        onSelect: (_) {},
        onRename: (_) {},
        onClose: (_) {},
        onNew: () => added++,
      ),
      Expanded(
        child: SessionTermView(
          alive: true,
          terminal: ClearScrollTerminal(),
          onInput: (_) {},
          onResize: (_, __) {},
          onClose: () {},
          showChrome: false,
          flat: true,
          cwd: '~/code/app',
          branch: 'main',
        ),
      ),
    ])));
    await t.pump();
    await t.pump();
    expect(find.text('Shell 1'), findsOneWidget);
    expect(find.text('~/code/app'), findsOneWidget);
    expect(find.text('main'), findsOneWidget);
    expect(find.textContaining(' × '), findsOneWidget);
    await t.tap(find.byTooltip('New terminal'));
    expect(added, 1);
    expect(t.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
