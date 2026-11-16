import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/motion_routes.dart';
import 'package:snippet/screens/agent_records.dart';

void main() {
  testWidgets('phone: inbox stacks on the agent page, back returns to it',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.of(ctx).push(AppPageRoute<void>(
            builder: (page) => Scaffold(
              body: TextButton(
                onPressed: () => openAgentRecordsPage(
                    page, 'Inbox', 'Rook', () => const Text('inbox body')),
                child: const Text('agent page'),
              ),
            ),
          )),
          child: const Text('agent list'),
        ),
      ),
    ));
    await tester.tap(find.text('agent list'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('agent page'));
    await tester.pumpAndSettle();
    expect(find.text('inbox body'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('inbox body'), findsNothing);
    expect(find.text('agent page'), findsOneWidget);
  });
}
