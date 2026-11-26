import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/crew_status.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/session_handoff.dart';
import 'package:snippet/screens/session_list_row.dart';
import 'package:snippet/screens/sidebar.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/transcript.dart';

SessionInfo s(String id,
        {String? owner,
        String? agent,
        String? worker,
        String status = 'idle',
        bool run = false,
        bool cameBack = false,
        int? finishedAt,
        int? seenAt,
        String? summary,
        int at = 0}) =>
    SessionInfo.fromJson({
      'id': id,
      'title': 'Chat $id',
      'folder': '/workspace/repo',
      'status': status,
      'running': run,
      'last_active': at,
      if (owner != null) 'owner_agent_id': owner,
      if (agent != null) 'agent_id': agent,
      if (worker != null) 'worker_agent_id': worker,
      if (cameBack) 'came_back': true,
      if (finishedAt != null) 'finished_at': finishedAt,
      if (seenAt != null) 'user_seen_at': seenAt,
      if (summary != null) 'result_summary': summary,
    });

class _FakeHandoffClient extends DaemonClient {
  _FakeHandoffClient() : super('https://daemon.invalid', 'test');
  final calls = <(String, String, String?)>[];
  Map<String, dynamic> result = {'session': 's1', 'pending': false};

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        CoordinationAgent.fromJson(
            {'id': 'snippet', 'display_name': 'Snippet', 'status': 'active'}),
        CoordinationAgent.fromJson({
          'id': 'rook',
          'display_name': 'Rook',
          'status': 'active',
          'capabilities': ['reviews', 'tests'],
        }),
        CoordinationAgent.fromJson(
            {'id': 'paused', 'display_name': 'Paused', 'status': 'paused'}),
        CoordinationAgent.fromJson({
          'id': 'lead',
          'display_name': 'Lead',
          'status': 'active',
          'kind': 'lead',
        }),
      ];

  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async => [
        SessionInfo.fromJson(
            {'id': 's1', 'title': 't', 'owner_agent_id': 'snippet'}),
      ];

  @override
  Future<Map<String, dynamic>> handOffSession(String session, String toAgent,
      {String? note}) async {
    calls.add((session, toAgent, note));
    return result;
  }
}

void main() {
  group('SessionInfo handoff fields', () {
    test('parses owner and came-back fields, all optional', () {
      final j = s('a',
          owner: 'rook',
          cameBack: true,
          finishedAt: 100,
          seenAt: 50,
          summary: '  Done the thing  ');
      expect(j.ownerAgentId, 'rook');
      expect(j.cameBack, isTrue);
      expect(j.finishedAt, 100);
      expect(j.userSeenAt, 50);
      expect(j.resultSummary, 'Done the thing');
      // Older daemon: none of the keys present.
      final old = SessionInfo.fromJson({'id': 'b', 'title': 't'});
      expect(old.ownerAgentId, isNull);
      expect(old.cameBack, isFalse);
      expect(old.finishedAt, isNull);
      expect(old.resultSummary, isNull);
    });

    test('displayAgentId falls back worker > agent > owner > snippet', () {
      expect(s('a', worker: 'w', agent: 'g', owner: 'o').displayAgentId, 'w');
      expect(s('a', agent: 'g', owner: 'o').displayAgentId, 'g');
      expect(s('a', owner: 'o').displayAgentId, 'o');
      expect(s('a').displayAgentId, 'snippet');
    });

    test('markSeen clears cameBack and stamps userSeenAt', () {
      final j = s('a', cameBack: true, finishedAt: 100, seenAt: 50);
      final seen = j.markSeen();
      expect(seen.cameBack, isFalse);
      expect(seen.userSeenAt, greaterThan(50));
      expect(seen.finishedAt, 100);
      expect(seen.resultSummary, j.resultSummary);
    });
  });

  group('came back grouping', () {
    test('sessionCameBack needs the flag and loses to needs-you', () {
      expect(sessionCameBack(s('a', cameBack: true)), isTrue);
      expect(sessionCameBack(s('a')), isFalse);
      expect(
          sessionCameBack(s('a', cameBack: true, status: 'waiting_for_input')),
          isFalse);
      expect(
          sessionCameBack(
              s('a', cameBack: true, agent: 'x').withStatus('in_review')),
          isFalse);
    });

    test('crew does not count idle plain sessions as snippet work', () {
      final crew = deriveCrew([
        CoordinationAgent.fromJson(
            {'id': 'snippet', 'display_name': 'Snippet'}),
        CoordinationAgent.fromJson({'id': 'rook', 'display_name': 'Rook'}),
      ], [
        s('idle'), // plain idle session owned by snippet
        s('busy', run: true), // plain running session owned by snippet
        s('ask', status: 'waiting_for_input'),
        s('theirs', agent: 'rook'),
      ]);
      final snippet = crew.firstWhere((e) => e.agent.id == 'snippet');
      final rook = crew.firstWhere((e) => e.agent.id == 'rook');
      // 'ask' waits on the user, which outranks 'busy' still running.
      expect(snippet.state, CrewState.needsYou);
      expect(snippet.sessions.map((x) => x.id), containsAll(['busy', 'ask']));
      expect(rook.state, CrewState.standingBy);
      expect(rook.sessions.single.id, 'theirs');
    });
  });

  group('HandoffNotice', () {
    Widget wrap(Widget child) =>
        MaterialApp(theme: buildAppTheme(), home: Scaffold(body: child));

    testWidgets('done reads takes over from with the note and who',
        (tester) async {
      await tester.pumpWidget(wrap(const HandoffNotice(event: {
        'kind': 'session_handoff',
        'from': 'snippet',
        'to': 'rook',
        'note': 'take it from here',
        'by': 'human',
      })));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Rook takes over from Snippet', findRichText: true),
          findsOneWidget);
      expect(find.textContaining('"take it from here"'), findsOneWidget);
      expect(find.textContaining('you'), findsOneWidget);
    });

    testWidgets('pending reads as takes over after this turn', (tester) async {
      await tester.pumpWidget(wrap(const HandoffNotice(event: {
        'kind': 'session_handoff',
        'from': 'snippet',
        'to': 'rook',
        'pending': true,
      })));
      expect(find.text('Rook takes over after this turn', findRichText: true),
          findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
    });
  });

  group('SessionHandOffSheet', () {
    testWidgets('lists active agents minus owner and calls the API',
        (tester) async {
      final client = _FakeHandoffClient();
      String? handed;
      var pending = false;
      await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
              body: SessionHandOffSheet(
            client: client,
            sessionId: 's1',
            onHandedOff: (name, p) {
              handed = name;
              pending = p;
            },
          ))));
      await tester.pumpAndSettle();
      expect(find.text('Rook'), findsOneWidget);
      expect(find.text('Paused'), findsNothing);
      expect(find.text('MC'), findsNothing);
      await tester.tap(find.text('Rook'));
      await tester.enterText(find.byType(TextField), 'finish the migration');
      client.result = {'session': 's1', 'pending': true};
      await tester.tap(find.text('Hand to Rook'));
      await tester.pumpAndSettle();
      expect(client.calls, [('s1', 'rook', 'finish the migration')]);
      expect(handed, 'Rook');
      expect(pending, isTrue);
    });
  });

  group('sidebar came back', () {
    // The agents section's SWR retry backoff outlives the tree; let it lapse.
    Future<void> drain(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 2));
    }

    Widget sidebar(List<SessionInfo> sessions) {
      return MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 900,
            child: Sidebar(
              instances: const [],
              active: null,
              client: DaemonClient('https://daemon.invalid', 'test'),
              selectedSessionId: null,
              sessions: sessions,
              sessionsLoading: false,
              onRefreshSessions: () {},
              onNewSession: () {},
              onSelectInstance: (_) {},
              onOpenLead: () {},
              onOpenSession: (_, __, ___) {},
              onAddInstance: () {},
              onRenameInstance: (_, __) {},
              onRemoveInstance: (_) {},
              onSessionDeleted: (_) {},
              health: const {},
              onRefreshHealth: () {},
              topInset: false,
              onOpenPalette: null,
              mobileHome: MobileHome.chats,
              onMobileHome: (_) {},
              agent: null,
              onAgent: (_) {},
            ),
          ),
        ),
      );
    }

    testWidgets('came-back rows group under Completed with their summary',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.pumpWidget(sidebar([
        s('done',
            cameBack: true,
            finishedAt: 100,
            summary: 'Shipped the fix',
            at: 100),
        s('live', run: true, status: 'running', at: 200),
        s('ask', status: 'waiting_for_input', at: 300),
      ]));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Needs you'), findsOneWidget);
      await drain(tester);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('markSeen drops the row from Completed', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final sessions = [
        s('done', cameBack: true, finishedAt: 100, summary: 'Shipped', at: 100),
      ];
      await tester.pumpWidget(sidebar(sessions));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Completed'), findsOneWidget);
      // Simulate the optimistic patch the shell applies on sessionSeen.
      await tester.pumpWidget(sidebar(
          [for (final x in sessions) x.id == 'done' ? x.markSeen() : x]));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Completed'), findsNothing);
      await drain(tester);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
