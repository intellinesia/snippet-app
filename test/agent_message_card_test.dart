import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/session_coordination_cards.dart';
import 'package:snippet/theme.dart';

void main() {
  testWidgets('short agent ids render without a range error', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(
        body: AgentMessageCard(agentId: 'moss', body: 'green', outbound: false),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('green'), findsOneWidget);
  });
}
