import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/chat/chat_info.dart';
import 'package:snippet/models.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';

import 'support/wake_fakes.dart';

GroupSummary _group() => GroupSummary.fromJson({
      'id': 'group:1',
      'title': 'jh',
      'members': [
        {'kind': 'human', 'id': 'human'},
        {'kind': 'agent', 'id': 'scout'},
      ],
      'lead': 'scout',
      'created_at': '2026-11-12T00:00:00Z',
    });

class _Client extends FakeWakeClient {
  final _events = DeviceEventHub.local();
  final titles = <String>[];

  @override
  DeviceEventHub get deviceEvents => _events;

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => const [];

  @override
  Future<GroupSummary> updateGroup(String id,
      {String? title,
      String? lead,
      List<String>? addMembers,
      List<String>? removeMembers}) async {
    if (title != null) titles.add(title);
    return GroupSummary.fromJson({
      'id': id,
      'title': title ?? 'jh',
      'members': [
        {'kind': 'human', 'id': 'human'},
        {'kind': 'agent', 'id': 'scout'},
      ],
      'lead': 'scout',
      'created_at': '2026-11-12T00:00:00Z',
    });
  }
}

Widget _app(Widget child) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: child),
    );

class _Dock extends StatefulWidget {
  const _Dock({required this.child});
  final Widget child;

  @override
  State<_Dock> createState() => _DockState();
}

class _DockState extends State<_Dock> {
  Widget? _page;

  @override
  Widget build(BuildContext context) => DockedInfoNav(
        push: (title, body) => setState(() => _page = Builder(builder: body)),
        pop: () => setState(() => _page = null),
        child: _page ?? widget.child,
      );
}

void main() {
  void desktop(WidgetTester tester) {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
  }

  testWidgets('docked group Rename is a nested page and Save updates the title',
      (tester) async {
    desktop(tester);
    final client = _Client();
    await tester.pumpWidget(_app(Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: 340,
        height: 800,
        child: GroupInfoPanel(
            client: client, group: _group(), docked: true, onClose: () {}),
      ),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Rename group'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Renamed');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(client.titles, ['Renamed']);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('dockedPick renders a page and returns the tapped value',
      (tester) async {
    desktop(tester);
    late BuildContext ctx;
    await tester.pumpWidget(_app(_Dock(
      child: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    )));
    var fellBack = false;
    final result = dockedPick<int>(ctx,
        title: 'Ping every',
        options: const [(5, '5 min', 'repeat'), (10, '10 min', null)],
        selected: 5,
        fallback: () async {
          fellBack = true;
          return null;
        });
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('5 min'), findsOneWidget);
    await tester.tap(find.text('10 min'));
    await tester.pumpAndSettle();
    expect(await result, 10);
    expect(fellBack, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('dockedPick falls back when not docked', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_app(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    final r = await dockedPick<int>(ctx,
        title: 't', options: const [(1, 'one', null)], fallback: () async => 7);
    expect(r, 7);
  });
}
