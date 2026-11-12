import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/approval_code.dart';
import 'package:snippet/media_views.dart';
import 'package:snippet/models.dart';
import 'package:snippet/mochi.dart';
import 'package:snippet/screens/agent_messaging.dart';
import 'package:snippet/screens/agent_thread_cards.dart';
import 'package:snippet/screens/artifact_viewer.dart';
import 'package:snippet/screens/presented_file_card.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/transcript.dart';
import 'package:snippet/transcript_card.dart';
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

class _Client extends DaemonClient {
  _Client(this.thread, {this.artifactList = const []})
      : super('https://daemon.invalid', 'test-token');
  final List<CoordinationEvent> thread;
  final List<ArtifactInfo> artifactList;
  final _events = DeviceEventHub.local();

  @override
  DeviceEventHub get deviceEvents => _events;

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
  Future<List<ArtifactInfo>> artifacts(String session) async => artifactList;
}

Future<void> _open(
  WidgetTester t,
  List<CoordinationEvent> thread, {
  List<ArtifactInfo> artifacts = const [],
}) async {
  t.view.physicalSize = const Size(390, 844) * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: AgentThreadScreen(
        client: _Client(thread, artifactList: artifacts),
        agentId: 'growth',
        agentName: 'Growth',
      ),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
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

  testWidgets('audio payload renders AudioTranscriptCard with play button',
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

    expect(find.byType(AudioTranscriptCard), findsOneWidget);
    expect(find.byType(VoiceNote), findsOneWidget);
    expect(find.text('Here is my quick voice update.'), findsOneWidget);
    expect(find.text('0:05'), findsOneWidget);
    expect(find.bySemanticsLabel('Play voice note'), findsOneWidget);
    expect(find.byType(AgentMochi), findsWidgets);
    expect(find.byType(Bubble), findsNothing);
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

    expect(find.byType(MediaRow), findsOneWidget);
    expect(find.byType(ArtifactRow), findsOneWidget);
    expect(find.text('Harness Map'), findsOneWidget);
    expect(find.textContaining('Document · v2'), findsOneWidget);
    expect(find.byType(Bubble), findsNothing);

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

    expect(find.byType(TranscriptCard), findsOneWidget);
    expect(find.text('Which deployment target should we use?'), findsOneWidget);
    expect(find.text('Staging cluster'), findsOneWidget);
    expect(find.text('Safe preview environment'), findsOneWidget);
    expect(find.text('Production cluster'), findsOneWidget);
    expect(find.text('Chosen'), findsOneWidget);
    expect(find.text('Answered'), findsOneWidget);
    expect(find.byType(Bubble), findsNothing);
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
    expect(find.text('Approved'), findsOneWidget);

    expect(find.text('3 tool calls'), findsOneWidget);
    expect(find.byType(DenseToolRow), findsNothing);

    await t.tap(find.text('3 tool calls'));
    await t.pump();
    expect(find.byType(DenseToolRow), findsNWidgets(3));
    expect(find.textContaining('lib/models.dart'), findsOneWidget);
    expect(find.textContaining('flutter analyze'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('plain body still renders Bubble for both human and agent',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await _open(t, [
      _ev(1, 'human', 'Can you check the logs?'),
      _ev(2, 'agent', 'All clear, no errors found.'),
    ]);

    expect(find.byType(Bubble), findsNWidgets(2));
    expect(find.text('Can you check the logs?'), findsOneWidget);
    expect(find.text('All clear, no errors found.'), findsOneWidget);
    final bubbles = t.widgetList<Bubble>(find.byType(Bubble)).toList();
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
    final card = find.byType(TranscriptCard);
    expect(card, findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
    expect(t.getSize(card).width, lessThanOrEqualTo(740));
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
}
