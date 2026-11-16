import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat/stage_header.dart';
import 'package:snippet/mochi.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: SizedBox(width: 360, child: child))));

  testWidgets('one member: title, subtitle and a tappable chip', (t) async {
    var taps = 0;
    await t.pumpWidget(host(StageHeader(
      members: const [StageMember('rook', state: AgentCharacterState.needs, badge: '?')],
      title: 'Sidebar density',
      subtitle: 'Rook · waiting on you · step 3 of 5',
      onTap: () => taps++,
      below: const StagePill(label: '2 lanes', icon: Icons.layers_outlined),
    )));
    expect(find.text('Sidebar density'), findsOneWidget);
    expect(find.text('Rook · waiting on you · step 3 of 5'), findsOneWidget);
    expect(find.text('2 lanes'), findsOneWidget);
    expect(find.byType(AgentMochi), findsOneWidget);
    await t.tap(find.text('Sidebar density'));
    expect(taps, 1);
    expect(t.takeException(), isNull);
  });

  testWidgets('a group shows at most three, the first largest', (t) async {
    await t.pumpWidget(host(const StageHeader(
      members: [StageMember('a'), StageMember('b'), StageMember('c'), StageMember('d')],
      title: 'Sidebar polish crew',
      subtitle: 'Moss is typing',
    )));
    final mochis = t.widgetList<AgentMochi>(find.byType(AgentMochi)).toList();
    expect(mochis, hasLength(3));
    expect(mochis.last.agentId, 'a');
    expect(mochis.last.size, StageHeader.leadSize);
    expect(t.takeException(), isNull);
  });
}
