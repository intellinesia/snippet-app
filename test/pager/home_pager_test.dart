import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/mobile_session_home.dart';
import 'package:snippet/screens/mobile_shell.dart';

const _size = Size(390, 844);
final _shot = GlobalKey();

class _Host extends StatefulWidget {
  const _Host({this.inner});
  final Widget? inner;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int page = 0;
  final ctl = TextEditingController();
  final focus = FocusNode();

  @override
  Widget build(BuildContext context) => HomePagerScope(
        page: page,
        onPage: (p) => setState(() => page = p),
        child: RepaintBoundary(
          key: _shot,
          child: ColoredBox(
            color: const Color(0xFF121110),
            child: SafeArea(
              child: Column(children: [
                MobileHomeTopBar(
                  agents: page == 1,
                  controller: ctl,
                  focusNode: focus,
                  onChanged: (_) {},
                  onSessions: () {},
                  onAgents: () {},
                  onSettings: () {},
                ),
                Expanded(
                  child: HomePager(
                    sessions: widget.inner ?? _list('sessions', Colors.indigo),
                    agents: _list('agents', Colors.teal),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
}

Widget _list(String name, Color c) => ListView(
      key: Key(name),
      children: [
        for (var i = 0; i < 30; i++)
          Container(
            height: 72,
            margin: const EdgeInsets.fromLTRB(16, 2, 16, 0),
            color: c.withValues(alpha: 0.35),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 16),
            child: Text('$name $i'),
          ),
      ],
    );

void phoneTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    t.view.physicalSize = _size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    try {
      await body(t);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

HomePagerController _ctl(WidgetTester t) =>
    HomePagerScope.maybeOf(t.element(find.byType(HomePager)))!;

double _indicatorX(WidgetTester t) =>
    t.getTopLeft(find.byKey(const ValueKey('home-indicator'))).dx;

void main() {
  phoneTest('a 60% drag commits to Agents', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: _Host())));
    await t.dragFrom(const Offset(350, 400), const Offset(-234, 0));
    await t.pumpAndSettle();
    final state = t.state<_HostState>(find.byType(_Host));
    expect(state.page, 1);
    expect(_ctl(t).position, closeTo(1, 0.001));
  });

  phoneTest('a short drag springs back', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: _Host())));
    await t.dragFrom(const Offset(350, 400), const Offset(-60, 0));
    await t.pumpAndSettle();
    expect(t.state<_HostState>(find.byType(_Host)).page, 0);
    expect(_ctl(t).position, closeTo(0, 0.001));
  });

  phoneTest('indicator follows the finger mid-drag', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: _Host())));
    final x0 = _indicatorX(t);
    final g = await t.startGesture(const Offset(350, 400));
    await g.moveBy(const Offset(-30, 0));
    await g.moveBy(const Offset(-195, 0));
    await t.pump();
    expect(_ctl(t).position, closeTo(0.5, 0.01));
    final mid = _indicatorX(t);
    expect(mid, greaterThan(x0 + 20));
    final x1 = _indicatorX(t);
    await g.moveBy(const Offset(-39, 0));
    await t.pump();
    expect(_indicatorX(t), greaterThan(x1));

    const dir = String.fromEnvironment('SHOT_DIR');
    if (dir.isNotEmpty) {
      final boundary =
          _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final img = await boundary.toImage();
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$dir/home_pager_middrag.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
    await g.up();
    await t.pumpAndSettle();
  });

  phoneTest('tapping a segment switches', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: _Host())));
    await t.tap(find.text('Agents'));
    await t.pumpAndSettle();
    expect(t.state<_HostState>(find.byType(_Host)).page, 1);
    expect(_ctl(t).position, closeTo(1, 0.001));
    await t.tap(find.text('Sessions'));
    await t.pumpAndSettle();
    expect(t.state<_HostState>(find.byType(_Host)).page, 0);
    expect(_ctl(t).position, closeTo(0, 0.001));
  });

  phoneTest('vertical scroll still scrolls and does not page', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: _Host())));
    await t.drag(find.byKey(const Key('sessions')), const Offset(0, -300));
    await t.pumpAndSettle();
    expect(find.text('sessions 0'), findsNothing);
    expect(_ctl(t).position, 0);
  });

  phoneTest('a horizontal child scrollable keeps its own drag', (t) async {
    final inner = Column(children: [
      SizedBox(
        height: 120,
        child: ListView(
          key: const Key('hscroll'),
          scrollDirection: Axis.horizontal,
          children: [
            for (var i = 0; i < 20; i++) SizedBox(width: 120, child: Text('c$i')),
          ],
        ),
      ),
    ]);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: _Host(inner: inner))));
    await t.drag(find.byKey(const Key('hscroll')), const Offset(-250, 0));
    await t.pumpAndSettle();
    expect(t.state<_HostState>(find.byType(_Host)).page, 0);
    expect(_ctl(t).position, 0);
  });
}
