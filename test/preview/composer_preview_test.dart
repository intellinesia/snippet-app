import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:snippet/api.dart';
import 'package:snippet/crew_status.dart';
import 'package:snippet/crew_widgets.dart';
import 'package:snippet/models.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/screens/agent_messaging.dart';
import 'package:snippet/screens/agent_records.dart';
import 'package:snippet/screens/agents_sidebar_panel.dart';
import 'package:snippet/screens/create_agent_form.dart';
import 'package:snippet/screens/mission_control/coordination_agent_detail.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/screens/sidebar.dart';

int get _now => DateTime.now().millisecondsSinceEpoch ~/ 1000;

Map<String, dynamic> _agentJson(String id, String name, String role,
        {String status = 'active', String? profile, List sessions = const []}) =>
    {
      'id': id,
      'display_name': name,
      'handle': id,
      'kind': 'agent',
      'status': status,
      'role': role,
      if (profile != null) 'profile': profile,
      'capabilities': ['code', 'review'],
      'assigned_sessions': sessions,
    };

Map<String, dynamic> _msg(int seq, String actor, String text) => {
      'event_id': 'e$seq',
      'thread_id': 'direct:human:local:agent:snippet',
      'partition_key': 'snippet',
      'sequence': seq,
      'event_type': 'direct_message',
      'actor_kind': actor,
      'actor_id': actor == 'human' ? 'local' : 'snippet',
      'payload_version': 1,
      'payload': {'body': text},
      'idempotency_key': 'e$seq',
      'created_at': '2026-11-08T09:${seq.toString().padLeft(2, '0')}:00Z',
    };

Map<String, dynamic> _inbox(int id, String source, String from, String text,
        {String? kind, String? title, String? to}) =>
    {
      'id': id,
      'event_id': 'i$id',
      'source': source,
      'thread_id': 't$id',
      'from_kind': from == 'human' ? 'human' : 'agent',
      'from_id': from,
      if (to != null) 'to_id': to,
      if (kind != null) 'post_kind': kind,
      if (title != null) 'title': title,
      'text': text,
      'created_at': '2026-11-08T0${id % 9}:1${id % 6}:00Z',
    };

class _Fake extends DaemonClient {
  _Fake() : super('https://daemon.invalid', 'test');
  @override
  late final DeviceEventHub deviceEvents = DeviceEventHub.local();

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        _agentJson('snippet', 'Snippet', 'Implementer',
            profile: 'opus', sessions: [
          {'id': 's2', 'title': 'Desktop UI follow-up', 'last_active': 0},
          {'id': 's3', 'title': 'Notification stack build', 'last_active': 0},
        ]),
        _agentJson('rust-pr-reviewer', 'Rust PR Reviewer', 'Code reviewer',
            profile: 'sonnet', sessions: [
          {'id': 's1', 'title': 'PR 412', 'last_active': 0}
        ]),
        _agentJson('web-researcher',
            'Web Research Specialist for Competitive Landscape', 'Researcher and long-horizon planner',
            profile: 'sonnet'),
        _agentJson('revenue-scout', 'Revenue Scout', 'Research and planning',
            status: 'disabled'),
        _agentJson('x', 'X', 'Ops'),
      ].map(CoordinationAgent.fromJson).toList();

  @override
  Future<List<CoordinationEvent>> agentThread({
    required String peerId,
    String actorKind = 'human',
    String actorId = 'local',
    int afterSequence = 0,
    int limit = 100,
  }) async =>
      [
        _msg(1, 'human', 'Can you take the desktop sidebar polish next?'),
        _msg(2, 'agent',
            'On it. I will start with the row density and the settled group, then send you screenshots.'),
        _msg(3, 'human', 'Also check the 320px layout.'),
        _msg(4, 'agent',
            'Done with the first pass. Rows are now 44pt tall with a 15pt title and 12pt meta line. Want me to open a PR?'),
      ].map(CoordinationEvent.fromJson).toList();

  @override
  Future<void> markAgentThreadRead(
      {required String peerId,
      String actorKind = 'human',
      String actorId = 'local'}) async {}

  @override
  Future<List<InboxEntry>> agentInbox(String agentId,
          {String? contains,
          String? kind,
          int? before,
          int limit = 50}) async =>
      [
        _inbox(1, 'message', 'human', 'Can you take the desktop sidebar polish next?'),
        _inbox(2, 'offer', 'mission-control',
            'Polish the session list typography and the settled group.',
            kind: 'question', title: 'Sidebar polish'),
        _inbox(3, 'room', 'rust-pr-reviewer',
            'Blocked on the unsafe block in lanes.rs, need a decision.',
            kind: 'blocker'),
        _inbox(4, 'message', 'snippet', 'Note to self: rerun goldens.',
            to: 'snippet'),
        _inbox(5, 'message', 'web-researcher',
            'Here is the competitor teardown you asked for, with 14 links and a summary of each pricing page that goes on for quite a while to test wrapping behaviour.'),
      ].map(InboxEntry.fromJson).toList();

  @override
  Future<ServerConfig> getConfig({bool force = false}) async =>
      ServerConfig.fromJson({
        'profiles': [
          {'name': 'opus', 'provider': 'anthropic', 'model': 'claude-opus'}
        ]
      });

  @override
  WebSocketChannel events() => _Socket(null);
  @override
  WebSocketChannel attach(String sessionId) => _Socket(_snapshot());
}

class _Socket extends StreamChannelMixin implements WebSocketChannel {
  _Socket(Map<String, dynamic>? snap) {
    _c = StreamController<dynamic>.broadcast();
    if (snap != null) Timer(const Duration(milliseconds: 5), () => _c.add(jsonEncode(snap)));
  }
  late final StreamController<dynamic> _c;
  @override
  Stream get stream => _c.stream;
  @override
  late final WebSocketSink sink = _Sink(_c.sink);
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;
  @override
  Future<void> get ready => Future.value();
}

class _Sink implements WebSocketSink {
  _Sink(this._s);
  final StreamSink _s;
  @override
  void add(dynamic data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream stream) => Future.value();
  @override
  Future close([int? closeCode, String? closeReason]) => _s.close();
  @override
  Future get done => _s.done;
}

Map<String, dynamic> _snapshot() {
  var i = 0;
  Map<String, dynamic> ev(Map<String, dynamic> m) =>
      {...m, 'created_at': '2026-11-08T09:${(i++).toString().padLeft(2, '0')}:00Z'};
  final events = [
    ev({'kind': 'user_input', 'text': 'status? anything stuck overnight'}),
    ev({
      'kind': 'tool_call',
      'tool_name': 'list_mission_tasks',
      'arguments': {'status': 'active'}
    }),
    ev({
      'kind': 'tool_result',
      'tool_name': 'list_mission_tasks',
      'result': {'status': 'ok', 'tasks': 4}
    }),
    ev({
      'kind': 'tool_call',
      'tool_name': 'inspect_session',
      'arguments': {'session_id': 'ui-polish-emil'}
    }),
    ev({
      'kind': 'tool_result',
      'tool_name': 'inspect_session',
      'result': {'status': 'ok', 'state': 'running'}
    }),
    ev({
      'kind': 'assistant_text',
      'text':
          'Morning, boss. Four tasks are active:\n\n- **ui-polish-emil** is running, 3 of 5 audits done\n- **Quarry post** finished, waiting for your review\n- **Cisco scan** is blocked on a token\n\nOne thing needs you: the `unsafe` block in `lanes.rs`. Shall I approve it?\n\n```bash\ncargo test --lib --offline\n```'
    }),
    ev({
      'kind': 'user_input',
      'text':
          '[mission_task_report]\ntask_id: task-1\ntitle: Quarry post\nstatus: done\nsummary: Draft published to Buffer, 3 images attached.\n[/mission_task_report]\nWorkflow W3 instructions.'
    }),
    ev({
      'kind': 'lane_spawned',
      'id': 'lane1',
      'title': 'Audit session list typography'
    }),
    ev({
      'kind': 'assistant_text',
      'text': 'Understood. I have spawned a worker for the typography audit and will report back.'
    }),
    ev({'kind': 'user_input', 'text': 'yes approve it, then ping me when the audit lands'}),
  ];
  return {
    'wire': 'snapshot',
    'status': 'idle',
    'workspace': '/home/boss/.snippet/mission-control',
    'title': 'Mission Control',
    'events': events,
    'approval_mode': 'auto',
    'total_tokens': 48210,
    'context_window': 200000,
    'last_prompt_tokens': 41000,
    'total_events': events.length,
    'lanes': [
      {
        'id': 'lane1',
        'title': 'Audit session list typography',
        'status': 'running',
        'started_at': DateTime.now().toUtc().subtract(const Duration(minutes: 4)).toIso8601String(),
      }
    ],
  };
}

SessionInfo _s(String id, String title,
        {String folder = '/home/boss/code/snippet-mobile',
        String status = 'idle',
        int ago = 600,
        int? add,
        int? del,
        int files = 0,
        bool settled = false,
        String? agent,
        String? branch,
        Map<String, dynamic>? ask}) =>
    SessionInfo.fromJson({
      'id': id,
      'title': title,
      'folder': folder,
      'status': status,
      'running': status == 'running',
      'last_active': _now - ago,
      if (add != null) 'changes': {'files': files, 'added': add, 'removed': del ?? 0},
      'settled': settled,
      if (settled) 'settled_at': _now - ago,
      if (agent != null) 'worker_agent_id': agent,
      if (branch != null) 'branch': branch,
      if (ask != null) 'attention': ask,
    });

List<SessionInfo> _sessions() => [
      _s('1', 'Slate accent and press feedback',
          status: 'running', ago: 5, add: 142, del: 31, files: 6, agent: 'snippet', branch: 'ui-polish-emil'),
      _s('2', 'TUI gets stuck when listing sessions',
          status: 'waiting_for_input', ago: 120, ask: {'type': 'approval', 'text': 'Run cargo test?'}),
      _s('3',
          'Investigate why the Android release build fails on CI after the Gradle plugin upgrade to 8.7',
          ago: 3600, add: 12873, del: 9402, files: 214, branch: 'fix/gradle'),
      _s('4', '(untitled)', ago: 7200),
      _s('5', 'Add regression coverage', ago: 86400, add: 8, del: 0, files: 1),
      _s('6', 'Quarry post', folder: '/home/boss/code/technoxi', ago: 90000, add: 40, del: 12, files: 3),
      _s('7', 'Cisco MINT page 日本語のタイトルがとても長い場合', folder: '/home/boss/code/technoxi', ago: 200000),
      _s('8', 'Old: migrate notifications', ago: 900000, settled: true, add: 5, del: 5, files: 2),
      _s('9', 'Old: voiceprint enrol', ago: 1200000, settled: true),
      _s('10', 'Docs sweep', folder: '/home/boss/code/very-long-project-name-for-monorepo-backend-services', ago: 300, status: 'running', add: 3, del: 1, files: 1),
    ];

Widget _sidebar(
        {required MobileHome home,
        List<SessionInfo>? sessions,
        CoordinationAgent? agent,
        bool topInset = false,
        String? selected}) =>
    Scaffold(
      backgroundColor: AppColors.bg,
      body: Sidebar(
        instances: const [],
        active: null,
        client: _Fake(),
        selectedSessionId: selected,
        sessions: sessions,
        sessionsLoading: false,
        onRefreshSessions: () {},
        onNewSession: () {},
        onSelectInstance: (_) {},
        onOpenMissionControl: () {},
        onOpenSession: (_, __, ___) {},
        onAddInstance: () {},
        onRenameInstance: (_, __) {},
        onRemoveInstance: (_) {},
        onSessionDeleted: (_) {},
        health: const {},
        onRefreshHealth: () {},
        topInset: topInset,
        mobileHome: home,
        onMobileHome: (_) {},
        settingsSection: null,
        onSettingsSection: (_) {},
        agent: agent,
        onAgent: (_) {},
      ),
    );

Future<void> _shoot(WidgetTester tester, Widget home, Size size, String name,
    {TargetPlatform platform = TargetPlatform.android,
    Future<void> Function(WidgetTester)? after}) async {
  debugDefaultTargetPlatformOverride = platform;
  final prevOnError = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exception.toString().contains('audioplayers')) return;
    prevOnError?.call(d);
  };
  addTearDown(() => FlutterError.onError = prevOnError);
  DaemonClient.wsConnector = null;
  SharedPreferences.setMockInitialValues({});
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: home,
    ),
  ));
  for (var n = 0; n < 8; n++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  if (after != null) {
    await after(tester);
    for (var n = 0; n < 6; n++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }
  final ex = tester.takeException();
  if (ex != null) fail('EXCEPTION in $name: $ex');
  await expectLater(find.byKey(key), matchesGoldenFile('goldens/composer/$name.png'));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 70));
  debugDefaultTargetPlatformOverride = null;
}

const _phone = Size(390, 844);
const _small = Size(320, 690);
const _desk = Size(1280, 800);
const _draft = 'Can you look at the sidebar row density and tell me whether the\nsettled group still reads as secondary?\nAlso check the 320px layout.';

Future<void> _type(WidgetTester t, String text) async {
  await t.enterText(find.byType(TextField).last, text);
}

Widget _session({bool embedded = false}) => Scaffold(
    body: SessionScreen(
        client: _Fake(),
        sessionId: 'composer-sess',
        title: 'Slate accent',
        embedded: embedded,
        onMenu: () {}));

Widget _thread({bool embedded = false}) => Scaffold(
    body: AgentThreadScreen(
        client: _Fake(),
        agentId: 'snippet',
        agentName: 'Snippet',
        embedded: embedded,
        showBack: !embedded,
        onClose: () {}));

Future<void> _seedSession(WidgetTester t, bool draft) async {
  final st = t.state(find.byType(SessionScreen)) as dynamic;
  st.debugSeedComposer(
      model: 'Opus 4.1',
      provider: 'anthropic',
      file: draft ? 'release-notes.md' : null);
  if (draft) await _type(t, _draft);
}

Future<void> _seedThread(WidgetTester t, bool draft) async {
  if (!draft) return;
  final st = t.state(find.byType(AgentThreadScreen)) as dynamic;
  st.debugSeedAttachment('release-notes.md');
  await _type(t, _draft);
}

void main() {
  for (final d in [false, true]) {
    final sfx = d ? 'draft' : 'empty';
    testWidgets('session phone 390 $sfx', (t) async {
      await _shoot(t, _session(), _phone, 'session_phone390_$sfx',
          after: (t) => _seedSession(t, d));
    });
    testWidgets('session phone 320 $sfx', (t) async {
      await _shoot(t, _session(), _small, 'session_phone320_$sfx',
          after: (t) => _seedSession(t, d));
    });
    testWidgets('session desktop $sfx', (t) async {
      await _shoot(t, _session(embedded: true), _desk, 'session_desktop_$sfx',
          platform: TargetPlatform.macOS, after: (t) => _seedSession(t, d));
    });
    testWidgets('thread phone $sfx', (t) async {
      await _shoot(t, _thread(), _phone, 'thread_phone_$sfx',
          after: (t) => _seedThread(t, d));
    });
    testWidgets('thread desktop $sfx', (t) async {
      await _shoot(t, _thread(embedded: true), _desk, 'thread_desktop_$sfx',
          platform: TargetPlatform.macOS, after: (t) => _seedThread(t, d));
    });
  }
}
