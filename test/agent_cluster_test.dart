import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/chat/agent_cluster.dart';
import 'package:snippet/chat/chat_style.dart';

void main() {
  Future<void> pump(WidgetTester tester, List<String> ids) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(child: AgentCluster(ids: ids, size: 44)),
        ),
      ));

  testWidgets('one id renders a single disc', (tester) async {
    await pump(tester, ['a']);
    expect(find.byType(MochiDisc), findsOneWidget);
  });

  testWidgets('two ids render two overlapping discs', (tester) async {
    await pump(tester, ['a', 'b']);
    expect(find.byType(MochiDisc), findsNWidgets(2));
  });

  testWidgets('three ids render three discs in a triangle', (tester) async {
    await pump(tester, ['a', 'b', 'c']);
    expect(find.byType(MochiDisc), findsNWidgets(3));
    expect(find.textContaining('+'), findsNothing);
  });

  testWidgets('five ids show two discs and a +3 count', (tester) async {
    await pump(tester, ['a', 'b', 'c', 'd', 'e']);
    expect(find.byType(MochiDisc), findsNWidgets(2));
    expect(find.text('+3'), findsOneWidget);
  });
}
