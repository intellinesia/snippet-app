import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/widgets.dart' show AppIcon;
import 'package:snippet/screens/agent_messaging.dart';
import 'package:snippet/screens/agent_panel.dart';
import 'package:snippet/chat/chat_info.dart' show AgentInfoPanel;
import 'package:snippet/chat/chat_style.dart' show ChatHeader;
import 'package:snippet/screens/memory_screen.dart';

import 'support/agent_shell_harness.dart';

void main() {
  Finder title() => find.descendant(
      of: find.byType(ChatHeader), matching: find.text('Snippet'));

  testWidgets(
      'desktop agent tab: the title opens the docked info panel; actions open beside it',
      (tester) async {
    final daemon = (await tester.runAsync(FakeDaemon.start))!;
    addTearDown(() => daemon.server.close(force: true));
    await openAgentTab(tester, daemon, 'snippet');

    expect(find.byType(AgentThreadScreen), findsOneWidget);
    expect(find.byTooltip('Agent actions'), findsNothing);
    expect(find.byType(AgentSidePanel), findsNothing);

    await tester.tap(title());
    await settle(tester, 2);
    expect(find.byType(AgentSidePanel), findsOneWidget);
    expect(find.byType(AgentInfoPanel), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);

    await tester.tap(find.text('Memory').last);
    await settle(tester);
    expect(find.byType(MemoryScreen), findsOneWidget);
    expect(find.byType(AgentInfoPanel), findsNothing);
    expect(find.text('Info'), findsOneWidget);

    await tester.tap(find.text('Info'));
    await settle(tester, 2);
    expect(find.byType(AgentInfoPanel), findsOneWidget);

    await tester.tap(find.byTooltip('Hide panel'));
    await settle(tester, 2);
    expect(find.byType(AgentSidePanel), findsNothing);
    await tester.tap(find.byTooltip('Show panel'));
    await settle(tester, 2);
    expect(find.byType(AgentSidePanel), findsOneWidget);

    await closeShell(tester);
  });

  testWidgets('the docked info panel carries every agent option',
      (tester) async {
    final daemon = (await tester.runAsync(FakeDaemon.start))!;
    addTearDown(() => daemon.server.close(force: true));
    await openAgentTab(tester, daemon, 'snippet');

    await tester.tap(title());
    await settle(tester, 2);
    for (final label in [
      'Inbox',
      'Board',
      'Desk',
      'Memory',
      'Wakes and reporting',
      'Delete agent',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    final chevrons = find.byWidgetPredicate(
        (w) => w is AppIcon && w.name == 'chevron-right');
    final rights = {
      for (final e in chevrons.evaluate())
        if (tester.getTopRight(find.byWidget(e.widget).first).dx > 1000)
          tester.getTopRight(find.byWidget(e.widget).first).dx.round()
    };
    expect(rights.length, 1, reason: 'row arrows share one right edge');
    await closeShell(tester);
  });
}
