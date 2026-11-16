import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:snippet/api.dart';
import 'package:snippet/approval_code.dart';
import 'package:snippet/chat/chat_card.dart';
import 'package:snippet/chat/chat_style.dart';
import 'package:snippet/media_views.dart';
import 'package:snippet/models.dart';
import 'package:snippet/mochi.dart';
import 'package:snippet/screens/agent_messaging.dart';
import 'package:snippet/screens/agent_questions_card.dart';
import 'package:snippet/screens/agent_thread_cards.dart';
import 'package:snippet/screens/artifact_viewer.dart';
import 'package:snippet/shell_panel.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/transcript.dart';
import 'package:snippet/widgets.dart';

CoordinationEvent _ev(
  int n,
  String kind,
  String body, [
  Map<String, dynamic> extra = const {},
]) =>
    CoordinationEvent.fromJson({
      'event_id': 'e$n',
      'sequence': n,
      'actor_kind': kind,
      'idempotency_key': 'k$n',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'payload': {'body': body, ...extra},
    });

class _VerdictCall {
  _VerdictCall(this.taskId, this.verdict, this.findings);
  final String taskId;
  final String verdict;
  final List<String> findings;
}

class _Client extends DaemonClient {
  _Client(
    this.thread, {
    this.artifactList = const [],
    Map<String, TaskItem>? tasksById,
  })  : tasksMap = tasksById ?? {},
        super('https://daemon.invalid', 'test-token');
  List<CoordinationEvent> thread;
  final List<ArtifactInfo> artifactList;
  final Map<String, TaskItem> tasksMap;
  final Map<String, int> getTaskCalls = {};
  final List<_VerdictCall> verdicts = [];
  Object? verdictError;
  int sessionsCalls = 0;
  int threadPageCalls = 0;
  final _events = DeviceEventHub.local();

  @override
  DeviceEventHub get deviceEvents => _events;

  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async {
    sessionsCalls++;
    return const [];
  }

  @override
  Future<List<CoordinationEvent>> agentThread({
    required String peerId,
    String actorKind = 'human',
    String actorId = 'local',
    int afterSequence = 0,
    int limit = 100,
  }) async =>
      thread;

  @override
  Future<DirectThreadPage> agentThreadPage({
    required String peerId,
    String actorKind = 'human',
    String actorId = 'local',
    int afterSequence = 0,
    int limit = 100,
  }) async {
    threadPageCalls++;
    return DirectThreadPage(events: thread);
  }

  @override
  Future<List<ArtifactInfo>> artifacts(String session) async => artifactList;

  @override
  Future<TaskItem> getTask(String id) async {
    getTaskCalls[id] = (getTaskCalls[id] ?? 0) + 1;
    final t = tasksMap[id];
    if (t == null) throw Exception('no task $id');
    return t;
  }

  @override
  Future<TaskStatus> submitTaskVerdict(
    String taskId,
    String verdict, [
    List<String> findings = const [],
  ]) async {
    verdicts.add(_VerdictCall(taskId, verdict, findings));
    final err = verdictError;
    if (err != null) throw err;
    final next =
        verdict == 'approve' ? TaskStatus.done : TaskStatus.inProgress;
    final cur = tasksMap[taskId];
    if (cur != null) {
      tasksMap[taskId] = cur.movedTo(next);
    }
    return next;
  }
}

Future< _Client> _open(
  WidgetTester t,
  List<CoordinationEvent> thread, {
  List<ArtifactInfo> artifacts = const [],
  Map<String, TaskItem>? tasksById,
  _Client? client,
}) async {
  t.view.physicalSize = const Size(390, 844) * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final c = client ??
      _Client(thread, artifactList: artifacts, tasksById: tasksById);
  await t.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: AgentThreadScreen(
        client: c,
        agentId: 'growth',
        agentName: 'Growth',
      ),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  return c;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('daemonRelativeUrl resolves relative path with base URL and token', () {
    final client = DaemonClient('https://daemon.invalid:8443', 'sec-tok');
    expect(
      daemonRelativeUrl(client, '/artifacts/s/abc/memo.m4a'),
      'https://daemon.invalid:8443/artifacts/s/abc/memo.m4a?token=sec-tok',
    );
    expect(
      daemonRelativeUrl(client, '/artifacts/raw?sig=xyz'),
      'https://daemon.invalid:8443/artifacts/raw?sig=xyz&token=sec-tok',
    );
  });

  testWidgets('audio payload renders a voice note, transcript hidden',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await _open(t, [
      _ev(1, 'agent', 'Voice transcript fallback', {
        'attachment': {
          'kind': 'audio',
          'url': '/artifacts/s/signed-123/memo.m4a',
          'duration_ms': 5000,
          'transcript': 'Here is my quick voice update.',
        },
      }),
    ]);

    expect(find.byType(AudioTranscriptCard), findsNothing);
    expect(find.byType(VoiceNote), findsOneWidget);
    expect(find.text('Here is my quick voice update.'), findsNothing);
    expect(find.text('0:05'), findsOneWidget);
    expect(find.bySemanticsLabel('Play voice note'), findsOneWidget);
    expect(find.byType(AgentMochi), findsWidgets);
    expect(find.byType(ChatBubble), findsNothing);
    final note = t.widget<VoiceNote>(find.byType(VoiceNote));
    expect(
      note.url,
      'https://daemon.invalid/artifacts/s/signed-123/memo.m4a?token=test-token',
    );
    await t.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'artifact payload renders presented-file card title and opens viewer',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const info = ArtifactInfo(
      id: 'art-7',
      title: 'Harness Map',
      kind: 'markdown',
      caption: 'System overview',
      versions: [
        ArtifactVersion(
          n: 2,
          createdAt: 1700000000,
          entry: 'index.md',
          source: '/tmp/index.md',
          url: '/artifacts/s/sig/index.md',
        ),
      ],
    );
    await _open(
      t,
      [
        _ev(1, 'agent', 'Shared artifact', {
          'artifact': {
            'session': 'sess-1',
            'id': 'art-7',
            'title': 'Harness Map',
            'version': 2,
            'url': '/artifacts/s/sig/index.md',
            'kind': 'markdown',
          },
        }),
      ],
      artifacts: const [info],
    );

    expect(find.byType(ChatCardFooter), findsOneWidget);
    expect(find.byType(ArtifactRow), findsOneWidget);
    expect(find.text('Harness Map'), findsOneWidget);
    expect(find.textContaining('Document · v2'), findsOneWidget);
    expect(find.byType(ChatBubble), findsNothing);

    await t.tap(find.text('Harness Map'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(ArtifactViewer), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'question payload lists choices read-only and marks answer when present',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await _open(t, [
      _ev(1, 'agent', 'Pick a strategy', {
        'question': {
          'text': 'Which deployment target should we use?',
          'kind': 'single_choice',
          'choices': [
            {
              'value': 'staging',
              'label': 'Staging cluster',
              'description': 'Safe preview environment',
            },
            {
              'value': 'prod',
              'label': 'Production cluster',
              'description': 'Live traffic',
            },
          ],
        },
        'answer': 'staging',
      }),
    ]);

    expect(find.text('Which deployment target should we use?'), findsOneWidget);
    expect(find.text('Staging cluster'), findsOneWidget);
    expect(find.text('Safe preview environment'), findsOneWidget);
    expect(find.text('Production cluster'), findsOneWidget);
    expect(find.text('Chosen'), findsOneWidget);
    expect(find.text('Question \u00b7 Answered'), findsOneWidget);
    expect(find.byType(ChatBubble), findsNothing);
    await t.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'approval and tool activity payloads render compact and expandable cards',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await _open(t, [
      _ev(1, 'agent', 'Approval needed', {
        'approval': {
          'command': 'git status --short',
          'summary': 'Check working tree',
          'status': 'approved',
        },
      }),
      _ev(2, 'agent', 'Tools ran', {
        'tool_activity': [
          {'name': 'read_file', 'summary': 'lib/models.dart', 'status': 'ok'},
          {'name': 'bash', 'summary': 'flutter analyze', 'status': 'ok'},
          {
            'name': 'change_files',
            'summary': 'lib/widgets.dart',
            'status': 'ok'
          },
        ],
      }),
    ]);

    expect(find.byType(ApprovalCode), findsOneWidget);
    expect(find.text('Check working tree'), findsOneWidget);
    expect(find.text('Approval \u00b7 Approved'), findsOneWidget);

    expect(
      find.textContaining('Growth edited 1 file, ran 1 command, read 1 file',
          findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Show'), findsOneWidget);
    expect(find.byType(DenseToolRow), findsNothing);

    await t.tap(find.text('Show'));
    await t.pump();
    expect(find.byType(DenseToolRow), findsNWidgets(3));
    expect(find.textContaining('lib/models.dart'), findsOneWidget);
    expect(find.textContaining('flutter analyze'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('plain body still renders ChatBubble for both human and agent',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await _open(t, [
      _ev(1, 'human', 'Can you check the logs?'),
      _ev(2, 'agent', 'All clear, no errors found.'),
    ]);

    expect(find.byType(ChatBubble), findsNWidgets(2));
    expect(find.text('Can you check the logs?'), findsOneWidget);
    expect(find.text('All clear, no errors found.'), findsOneWidget);
    // The list is reversed, so build order runs newest first.
    final bubbles =
        t.widgetList<ChatBubble>(find.byType(ChatBubble)).toList().reversed.toList();
    expect(bubbles[0].mine, isTrue);
    expect(bubbles[1].mine, isFalse);
    await t.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop wideCap constrains rich cards within 740px', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: AgentThreadScreen(
          client: _Client([
            _ev(1, 'agent', '', {
              'question': {
                'text': 'Proceed with migration?',
                'kind': 'yes_no',
              },
            }),
          ]),
          agentId: 'growth',
          agentName: 'Growth',
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Question'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
    final card = find.ancestor(
      of: find.text('Proceed with migration?'),
      matching: find.byType(Container),
    );
    expect(t.getSize(card.first).width, lessThanOrEqualTo(440));
    await t.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'task card renders only on latest event for taskId, approves and hides buttons',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final task = TaskItem.fromJson({
      'id': 't-100',
      'title': 'XDR+ISE demo: fix TTS acronyms',
      'description': 'Fix voiceover pronunciation',
      'status': 'in_review',
      'created_at': DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 30))
          .toIso8601String(),
      'updated_at': DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 30))
          .toIso8601String(),
    });
    final client = await _open(
      t,
      [
        _ev(1, 'agent', 'Started working on it.', {'about_task': 't-100'}),
        _ev(2, 'agent', 'v5 delivered: ISE spoken as Ice.',
            {'about_task': 't-100'}),
      ],
      tasksById: {'t-100': task},
    );

    // Earlier event is a ChatBubble; latest event is the task card.
    expect(find.byType(ChatBubble), findsOneWidget);
    expect(find.text('Started working on it.'), findsOneWidget);
    expect(find.text('XDR+ISE demo: fix TTS acronyms'), findsOneWidget);
    expect(find.textContaining('Task in review'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Send back'), findsOneWidget);
    expect(client.getTaskCalls['t-100'], 1);

    await t.tap(find.text('Approve'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));

    expect(client.verdicts, hasLength(1));
    expect(client.verdicts.single.taskId, 't-100');
    expect(client.verdicts.single.verdict, 'approve');
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Send back'), findsNothing);
    expect(find.textContaining('Task \u00b7 Done'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'task card send back opens sheet, submits changes, and shows 409 inline',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final task = TaskItem.fromJson({
      'id': 't-101',
      'title': 'Refine onboarding copy',
      'status': 'in_review',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final client = _Client(
      [
        _ev(1, 'agent', 'Ready for review.', {'task_id': 't-101'}),
      ],
      tasksById: {'t-101': task},
    )..verdictError =
        const TaskVerdictConflict('task `t-101` is done, not in_review');

    await _open(t, client.thread, client: client);

    expect(find.text('Refine onboarding copy'), findsOneWidget);
    await t.tap(find.text('Send back'));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField).last, 'Fix typo in paragraph 2');
    await t.pump();
    await t.tap(find.text('Send back').last);
    await t.pumpAndSettle();

    expect(client.verdicts, hasLength(1));
    expect(client.verdicts.single.verdict, 'changes');
    expect(client.verdicts.single.findings, ['Fix typo in paragraph 2']);
    expect(find.text('task `t-101` is done, not in_review'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('missing task falls back to rendering event as bubble',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await _open(t, [
      _ev(1, 'agent', 'Fallback message body', {'about_task': 'missing-id'}),
    ]);

    expect(find.byType(ChatBubble), findsOneWidget);
    expect(find.text('Fallback message body'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    await t.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('AgentQuestionsCard in agent chat uses chatStyle pills',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await _open(t, [
      _ev(1, 'agent', 'Ask', {
        'question': {
          'session': 's-1',
          'questions': [
            {
              'id': 'q1',
              'text': 'May I release the machine now?',
              'answer_kind': {
                'kind': 'single_choice',
                'choices': [
                  {
                    'value': 'yes',
                    'label': 'Yes, release',
                    'recommended': true,
                  },
                  {'value': 'no', 'label': 'Not yet'},
                ],
              },
            },
          ],
        },
      }),
    ]);

    final qCard = t.widget<AgentQuestionsCard>(find.byType(AgentQuestionsCard));
    expect(qCard.chatStyle, isTrue);
    expect(find.text('May I release the machine now?'), findsOneWidget);
    expect(find.text('Yes, release'), findsOneWidget);
    expect(find.text('Not yet'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  test('agentThreadEventCard dispatches payload keys in spec priority order',
      () {
    final client = DaemonClient('https://daemon.invalid', 'tok');
    final ev = _ev(1, 'agent', 'text', {
      'attachment': {'kind': 'audio', 'url': '/artifacts/a.m4a'},
      'artifact': {'id': 'x', 'title': 'Art'},
      'question': {'text': 'Q?'},
      'approval': {'summary': 'S', 'status': 'pending'},
      'tool_activity': [
        {'name': 'bash', 'summary': 'ls', 'status': 'ok'},
      ],
    });
    final card = agentThreadEventCard(ev, client: client, agentId: 'growth');
    expect(card, isA<Container>());
  });

  testWidgets('desk-forwarded approval names its session and offers decisions',
      (tester) async {
    final e = _ev(1, 'agent', 'Run cargo test', {
      'kind': 'approval',
      'auto': 'approval',
      'context': 'Needs the full suite before the PR.',
      'approval': {
        'session': 's1',
        'session_title': 'Fix login',
        'task_id': 't1',
        'task_title': 'Auth cleanup',
        'tool': 'bash',
        'summary': 'cargo test',
        'approval_id': '3:2026-11-13',
      },
    });
    final card = agentThreadEventCard(e,
        client: _Client(const []), agentId: 'builder');
    expect(card, isA<DeskApprovalCard>());
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: card!)));
    expect(find.text('t1 · Auth cleanup · Fix login'), findsOneWidget);
    expect(find.text('Needs the full suite before the PR.'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Deny'), findsOneWidget);
  });

  testWidgets(
      'task_result renders in direct agent thread with tone and opens session',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    String? openedSession;
    String? openedTitle;
    openSessionInTab = (_, id, title) {
      openedSession = id;
      openedTitle = title;
    };
    addTearDown(() => openSessionInTab = null);

    await _open(t, [
      _ev(1, 'agent', 'Done', {
        'task_result': {
          'task_id': 't-1',
          'title': 'Index docs',
          'status': 'done',
          'summary': 'Indexed **42** pages.',
          'session_id': 'sess-idx',
        },
      }),
      _ev(2, 'agent', 'Blocked', {
        'task_result': {
          'task_id': 't-2',
          'title': 'Push release',
          'status': 'blocked',
          'summary': 'Needs signing key.',
          'session_id': 'sess-rel',
        },
      }),
      _ev(3, 'agent', 'Failed', {
        'task_result': {
          'task_id': 't-3',
          'title': 'Run suite',
          'status': 'failed',
          'summary': '2 assertions failed.',
          'session_id': 'sess-fail',
        },
      }),
    ]);

    expect(find.byType(TaskResultCard), findsNWidgets(3));
    expect(find.text('Index docs'), findsOneWidget);
    expect(find.text('Push release'), findsOneWidget);
    expect(find.text('Run suite'), findsOneWidget);

    expect(t.widget<ChatCardPill>(find.ancestor(
      of: find.text('Done'),
      matching: find.byType(ChatCardPill),
    )).tone, ChatCardTone.ok);
    expect(t.widget<ChatCardPill>(find.ancestor(
      of: find.text('Blocked'),
      matching: find.byType(ChatCardPill),
    )).tone, ChatCardTone.warn);
    expect(t.widget<ChatCardPill>(find.ancestor(
      of: find.text('Failed'),
      matching: find.byType(ChatCardPill),
    )).tone, ChatCardTone.danger);

    await t.tap(find.text('Push release'));
    await t.pump();
    expect(openedSession, 'sess-rel');
    expect(openedTitle, 'Push release');

    await t.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  group('DeskApprovalCard outcomes', () {
    CoordinationEvent approvalEv({
      String eventId = 'e-app',
      String threadId = 'dm:human:local:agent:builder',
      Map<String, dynamic>? outcome,
    }) =>
        CoordinationEvent.fromJson({
          'event_id': eventId,
          'thread_id': threadId,
          'sequence': 1,
          'actor_kind': 'agent',
          'actor_id': 'builder',
          'idempotency_key': 'k-$eventId',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'payload': {
            'body': 'Run cargo test',
            'approval': {
              'session': 's1',
              'session_title': 'Fix login',
              'task_id': 't1',
              'task_title': 'Auth cleanup',
              'tool': 'bash',
              'summary': 'cargo test',
              'approval_id': '3:2026-11-13',
              if (outcome != null) 'outcome': outcome,
            },
          },
        });

    testWidgets('live card renders buttons without network probe and updates optimistically per widget',
        (t) async {
      final ch = _WsChannel();
      DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) {
        Timer(const Duration(milliseconds: 10),
            () => ch.incoming.add('{"wire":"snapshot"}'));
        return ch;
      };
      addTearDown(() => DaemonClient.wsConnector = null);

      final client = _Client(const []);
      final e1 = approvalEv(eventId: 'e-app-1');
      final e2 = approvalEv(eventId: 'e-app-2');
      await t.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Column(
            children: [
              DeskApprovalCard(
                key: const ValueKey('c1'),
                event: e1,
                approval: e1.payload['approval'] as Map,
                client: client,
              ),
              DeskApprovalCard(
                key: const ValueKey('c2'),
                event: e2,
                approval: e2.payload['approval'] as Map,
                client: client,
              ),
            ],
          ),
        ),
      ));
      await t.pump();

      expect(client.sessionsCalls, 0);
      expect(find.text('Approve'), findsNWidgets(2));
      expect(find.text('Deny'), findsNWidgets(2));

      await t.tap(find.descendant(
        of: find.byKey(const ValueKey('c1')),
        matching: find.text('Approve'),
      ));
      await t.pump(const Duration(milliseconds: 50));
      await t.pump(const Duration(milliseconds: 50));

      final sent = jsonDecode(ch.sent.single as String) as Map;
      expect(sent['kind'], 'approve');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('c1')),
          matching: find.text('Approved'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('c2')),
          matching: find.text('Approve'),
        ),
        findsOneWidget,
      );
    });

    for (final c in [
      (state: 'approved', label: 'Approved'),
      (state: 'denied', label: 'Denied'),
      (state: 'outdated', label: 'No longer waiting on this'),
    ]) {
      testWidgets('renders stored outcome ${c.state} with no network call',
          (t) async {
        final client = _Client(const []);
        final ev = approvalEv(
          outcome: {'state': c.state, 'at': '2026-11-15T12:00:00Z'},
        );
        await t.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: DeskApprovalCard(
              event: ev,
              approval: ev.payload['approval'] as Map,
              client: client,
            ),
          ),
        ));
        await t.pump();

        expect(client.sessionsCalls, 0);
        expect(find.text(c.label), findsOneWidget);
        expect(find.text('Approve'), findsNothing);
        expect(find.text('Deny'), findsNothing);
      });
    }

    testWidgets(
        'AgentThreadScreen refreshes on coordination_event_updated for its thread',
        (t) async {
      final live = approvalEv(threadId: 'dm:human:local:agent:builder');
      final resolved = approvalEv(
        threadId: 'dm:human:local:agent:builder',
        outcome: {'state': 'approved', 'at': '2026-11-15T12:00:00Z'},
      );
      final client = await _open(t, [live]);
      final before = client.threadPageCalls;

      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Approved'), findsNothing);

      client.thread = [resolved];
      client.deviceEvents.add({
        'kind': 'coordination_event_updated',
        'thread_id': 'dm:human:local:agent:other',
        'event_id': 'e-app',
      });
      await t.pump(const Duration(milliseconds: 400));
      expect(client.threadPageCalls, before);
      expect(find.text('Approve'), findsOneWidget);

      client.deviceEvents.add({
        'kind': 'coordination_event_updated',
        'thread_id': 'dm:human:local:agent:builder',
        'event_id': 'e-app',
      });
      await t.pump(const Duration(milliseconds: 400));
      await t.pump();

      expect(client.threadPageCalls, before + 1);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
  });

  testWidgets(
      'desk approval renders daemon decision after restart without static map and legacy rejected uses Denied',
      (t) async {
    final approvedEv = _ev(1, 'agent', 'Run cargo test', {
      'kind': 'approval',
      'approval': {
        'session': 's1',
        'tool': 'bash',
        'summary': 'cargo test',
        'approval_id': '3:2026-11-16',
      },
      'decision': {
        'kind': 'decision',
        'request': 'approval',
        'request_id': '3:2026-11-16',
        'outcome': 'approved',
        'by': 'human',
        'via': 'desk',
        'at': 1763250000,
      },
    });
    final deniedEv = _ev(2, 'agent', 'Push', {
      'kind': 'approval',
      'approval': {
        'session': 's1',
        'tool': 'bash',
        'summary': 'git push --force',
        'approval_id': '4:2026-11-16',
      },
      'decision': {
        'kind': 'decision',
        'request': 'approval',
        'request_id': '4:2026-11-16',
        'outcome': 'denied',
        'by': 'human',
        'via': 'app',
        'at': 1763250005,
      },
    });
    final outdatedEv = _ev(3, 'agent', 'Old', {
      'kind': 'approval',
      'approval': {
        'session': 's1',
        'tool': 'bash',
        'summary': 'rm -rf /tmp/x',
        'approval_id': '5:2026-11-16',
      },
      'decision': {
        'kind': 'decision',
        'request': 'approval',
        'request_id': '5:2026-11-16',
        'outcome': 'outdated',
        'by': 'human',
        'via': 'app',
        'at': 1763250010,
      },
    });
    final legacyDenied = _ev(4, 'agent', 'Legacy', {
      'approval': {
        'summary': 'Run rm',
        'status': 'denied',
      },
    });

    final client = _Client(const []);
    await t.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: ListView(
          children: [
            agentThreadEventCard(approvedEv, client: client, agentId: 'builder')!,
            agentThreadEventCard(deniedEv, client: client, agentId: 'builder')!,
            agentThreadEventCard(outdatedEv, client: client, agentId: 'builder')!,
            agentThreadEventCard(legacyDenied, client: client, agentId: 'builder')!,
          ],
        ),
      ),
    ));

    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Denied'), findsOneWidget);
    expect(find.text('No longer waiting on this'), findsOneWidget);
    expect(find.text('Approval · Denied'), findsOneWidget);
    expect(find.text('Approval · Rejected'), findsNothing);
    expect(find.text('Approve'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}

class _WsChannel extends StreamChannelMixin implements WebSocketChannel {
  final incoming = StreamController<dynamic>.broadcast();
  final sent = <dynamic>[];
  @override
  Stream get stream => incoming.stream;
  @override
  late final WebSocketSink sink = _WsSink(this);
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;
  @override
  Future<void> get ready => Future.value();
}

class _WsSink implements WebSocketSink {
  _WsSink(this.ch);
  final _WsChannel ch;
  @override
  void add(dynamic data) => ch.sent.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream stream) async {}
  @override
  Future close([int? closeCode, String? closeReason]) async {}
  @override
  Future get done => Future.value();
}
