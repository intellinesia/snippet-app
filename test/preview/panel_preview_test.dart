import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/agent_shell_harness.dart';

Object? _extra(String path) {
  if (path == '/wake-runs') return {'runs': []};
  if (path == '/tasks') return [];
  if (path.endsWith('/inbox')) {
    return {
      'entries': [
        {
          'id': 3,
          'source': 'message',
          'from_kind': 'agent',
          'from_id': 'reviewer',
          'title': 'Review of the cold strip',
          'text': 'Looks right on the phone. On desktop the strip could sit closer to the composer.',
          'created_at': '2026-11-09T00:10:00Z',
        },
        {
          'id': 2,
          'source': 'offer',
          'from_kind': 'human',
          'from_id': 'local',
          'task_id': 't-1',
          'title': 'Polish the agent panel',
          'text': 'Keep every agent action inside the right panel on desktop.',
          'created_at': '2026-11-08T21:00:00Z',
        },
      ]
    };
  }
  return null;
}

Future<void> _shot(WidgetTester tester, String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/panel/$name.png'));

Future<void> _menu(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Agent actions'));
  await settle(tester, 2);
  await tester.tap(find.text(label).last);
}

void main() {
  testWidgets('agent tab', (tester) async {
    final daemon = (await tester.runAsync(() => FakeDaemon.start(extra: _extra)))!;
    addTearDown(() => daemon.server.close(force: true));
    await openAgentTab(tester, daemon, 'snippet');
    await _shot(tester, 'agent_default');
    await _menu(tester, 'Inbox');
    await settle(tester, 12);
    await _shot(tester, 'inbox_panel');
    await tester.tap(find.text('Review of the cold strip'));
    await settle(tester, 4);
    await _shot(tester, 'inbox_record_panel');
    await tester.tap(find.byTooltip('Agent actions'));
    await settle(tester, 2);
    await _shot(tester, 'actions_menu');
    await tester.tap(find.text('Wakes and reporting').last);
    await settle(tester, 40);
    await _shot(tester, 'wakes_panel');
    await closeShell(tester);
  });
}
