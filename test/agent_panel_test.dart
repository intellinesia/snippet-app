import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/agent_messaging.dart';
import 'package:snippet/screens/agent_panel.dart';
import 'package:snippet/screens/agent_records.dart';
import 'package:snippet/screens/memory_screen.dart';

import 'support/agent_shell_harness.dart';

void main() {
  testWidgets('desktop agent tab has one Actions menu and a right panel',
      (tester) async {
    final daemon = (await tester.runAsync(FakeDaemon.start))!;
    addTearDown(() => daemon.server.close(force: true));
    await openAgentTab(tester, daemon, 'snippet');

    expect(find.byType(AgentThreadScreen), findsOneWidget);
    expect(find.byTooltip('Agent actions'), findsOneWidget);
    expect(find.byTooltip('Actions'), findsNothing);
    expect(find.byType(AgentSidePanel), findsOneWidget);
    // No actions list in the panel: it opens on Memory, with Wakes and Profile.
    expect(find.byType(AgentActions), findsNothing);
    expect(find.text('Desk session'), findsNothing);
    expect(find.byType(MemoryScreen), findsOneWidget);
    expect(find.text('Wakes'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide panel'));
    await settle(tester, 2);
    expect(find.byType(AgentSidePanel), findsNothing);
    await tester.tap(find.byTooltip('Show panel'));
    await settle(tester, 2);
    expect(find.byType(AgentSidePanel), findsOneWidget);

    await tester.tap(find.text('Memory').first);
    await settle(tester);
    expect(find.byType(MemoryScreen), findsOneWidget);
    expect(find.byType(AgentSidePanel), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);

    await closeShell(tester);
  });

  testWidgets('the top menu opens an action inside the panel', (tester) async {
    final daemon = (await tester.runAsync(FakeDaemon.start))!;
    addTearDown(() => daemon.server.close(force: true));
    await openAgentTab(tester, daemon, 'snippet');

    await tester.tap(find.byTooltip('Agent actions'));
    await settle(tester, 2);
    for (final label in [
      'Desk session',
      'Memory',
      'Wakes and reporting',
      'Inference profile',
      'Delete agent',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    for (final label in ['Nickname', 'Avatar', 'Colour']) {
      expect(find.text(label), findsNothing, reason: label);
    }
    await tester.tap(find.text('Inference profile').last);
    await settle(tester);
    expect(find.text('Default (from Routing)'), findsOneWidget);
    expect(find.byType(AgentSidePanel), findsOneWidget);

    await closeShell(tester);
  });
}
