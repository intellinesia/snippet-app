import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/chat/chat_info.dart';
import 'package:snippet/screens/desktop_home.dart';
import 'package:snippet/screens/group_messaging.dart';

import 'support/agent_shell_harness.dart';

Object? _groupsExtra(String path) {
  if (path == '/groups') {
    return [
      {
        'id': 'g1',
        'title': 'App Redesign',
        'members': [
          {'kind': 'human', 'id': 'local'},
          {'kind': 'agent', 'id': 'snippet'},
          {'kind': 'agent', 'id': 'reviewer'},
        ],
        'lead': 'snippet',
        'created_at': '2026-11-20T00:00:00Z',
        'last_event_at': '2026-11-25T18:48:00Z',
      },
    ];
  }
  if (path == '/groups/g1/events') {
    return [
      {
        'event_id': 'ge1',
        'thread_id': 'group:g1',
        'partition_key': 'g1',
        'sequence': 1,
        'event_type': 'group_message',
        'actor_kind': 'agent',
        'actor_id': 'snippet',
        'payload_version': 1,
        'payload': {'body': 'Alpha release note'},
        'idempotency_key': 'ge1',
        'created_at': '2026-11-25T18:48:00Z',
      },
    ];
  }
  return null;
}

Future<void> _openHomeThenGroup(WidgetTester tester) async {
  // Places live in the sidebar's icon footer.
  await tester.tap(find.byTooltip('Home').first);
  await settle(tester);
  expect(find.byType(DesktopHome), findsOneWidget);

  await tester.tap(find.byKey(const ValueKey('group-row-g1')));
  await settle(tester, 8);
}

Future<void> _collapseSidebar(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await settle(tester);
}

void main() {
  for (final size in const [Size(1440, 900), Size(1024, 700)]) {
    testWidgets(
        'group conversation replaces its Home host at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
      final daemon = await tester
          .runAsync(() => FakeDaemon.start(extra: _groupsExtra));
      try {
        await mountShell(tester, daemon!, size: size);
        await _openHomeThenGroup(tester);

        expect(find.byType(GroupThreadScreen), findsOneWidget);
        // XO-03: the members panel is closed until the header opens it.
        expect(find.byType(GroupInfoPanel), findsNothing);
        expect(find.byKey(const ValueKey('chat-header-bar')), findsOneWidget);
        await tester.tap(find.byTooltip('Show panel'));
        await settle(tester);
        expect(find.byType(GroupInfoPanel), findsOneWidget);
        expect(find.byType(DesktopHome), findsNothing,
            reason: 'the Home host must be offstage, not painted beneath chat');

        final widthBeforeCollapse =
            tester.getRect(find.byType(GroupThreadScreen)).width;
        await _collapseSidebar(tester);
        expect(find.byType(GroupThreadScreen), findsOneWidget);
        expect(tester.getRect(find.byType(GroupThreadScreen)).width,
            greaterThan(widthBeforeCollapse + 100),
            reason: 'the Ctrl+B collapse must actually remove the sidebar width');
        expect(find.byType(DesktopHome), findsNothing,
            reason: 'collapsing the sidebar must not expose the Home host');
        expect(tester.takeException(), isNull);
      } finally {
        await closeShell(tester);
        await tester.runAsync(() => daemon!.server.close(force: true));
      }
    });
  }
}
