import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/screens/settings_panel.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/wake_models.dart';

import '../support/wake_fakes.dart';

class _McFake extends DaemonClient {
  _McFake() : super('https://daemon.invalid', 'test');
  @override
  late final DeviceEventHub deviceEvents = DeviceEventHub.local();
  @override
  Future<ServerConfig> getConfig({bool force = false}) async =>
      ServerConfig.fromJson({});
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


class _Client extends FakeWakeClient {
  _Client()
      : super(
            wakeState: WakeSchedule.fromJson(wakeJson()),
            warmState: KeepWarmEntry.fromJson(keepWarmJson()));

  @override
  Future<ServerConfig> getConfig({bool force = false}) async =>
      ServerConfig.fromJson({
        'voice': {'enabled': true, 'max_seconds': 180}
      });

  @override
  Future<AmbientSettings> getAmbientSettings() async =>
      AmbientSettings.fromJson({
        'stt': 'assemblyai',
        'tts_provider': 'rime',
        'assemblyai_key_set': true,
        'rime_key_set': false,
        'rime_voice': 'cove',
        'wake_phrases': ['snippet', 'hey snippet'],
      });

  @override
  Future<Map<String, List<Account>>> getAccounts() async => {
        'chatgpt': [
          Account.fromJson({'id': 'a', 'label': 'Personal Plus', 'active': true}),
          Account.fromJson({'id': 'b', 'label': 'Work Pro', 'active': false}),
        ],
        'xai': [],
        'claude-code': [
          Account.fromJson({'id': 'c', 'label': 'Max 20x', 'active': true}),
        ],
      };
}

const _inst = Instance(name: 'mac', url: 'https://mac.tail1234.ts.net', token: 't');
const _long = Instance(
    name: 'macbook-pro-of-a-very-long-name',
    url: 'https://macbook-pro-of-a-very-long-name.tail1234.ts.net',
    token: 'u');
const _other = Instance(name: 'build-box', url: 'https://build-box.tail1234.ts.net', token: 'v');

Future<void> _show(WidgetTester t, Size size, bool mobile, Widget child) async {
  debugDefaultTargetPlatformOverride =
      mobile ? TargetPlatform.android : TargetPlatform.macOS;
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: Scaffold(backgroundColor: AppColors.bg, body: child),
  ));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 400));
  }
}

Widget _panel(SettingsPage? section,
        {bool mobile = true, bool long = false}) =>
    SettingsPanel(
      client: _Client(),
      instances: long ? const [_long, _other] : const [_inst],
      active: long ? _long : _inst,
      onRemove: (_) {},
      onClose: () {},
      embedded: mobile,
      section: mobile ? section : null,
      initialPage: mobile ? null : section,
    );


Future<void> _mc(WidgetTester t, Size size, bool mobile, String name) async {
  debugDefaultTargetPlatformOverride =
      mobile ? TargetPlatform.android : TargetPlatform.macOS;
  DaemonClient.wsConnector = null;
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exception.toString().contains('audioplayers')) return;
    prev?.call(d);
  };
  addTearDown(() => FlutterError.onError = prev);
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: Scaffold(
        body: SessionScreen(
            client: _McFake(),
            sessionId: 'mission-control',
            title: 'Mission Control',
            onMenu: () {})),
  ));
  for (var n = 0; n < 8; n++) {
    await t.pump(const Duration(milliseconds: 250));
  }
  await expectLater(find.byType(Scaffold).first,
      matchesGoldenFile('goldens/settings2/$name.png'));
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump(const Duration(seconds: 70));
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  SharedPreferences.setMockInitialValues({});
  const sizes = {
    'p390': Size(390, 844),
    'p320': Size(320, 690),
  };
  const desk = Size(1280, 800);
  final pages = {
    'home': null,
    'general': SettingsPage.general,
    'wakes': SettingsPage.wakes,
    'accounts': SettingsPage.accounts,
    'voice': SettingsPage.voice,
    'websearch': SettingsPage.webSearch,
  };
  for (final s in sizes.entries) {
    for (final e in pages.entries) {
      testWidgets('${s.key} ${e.key}', (t) async {
        await _show(t, s.value, true, _panel(e.value));
        await expectLater(find.byType(Scaffold),
            matchesGoldenFile('goldens/settings2/${s.key}_${e.key}.png'));
        debugDefaultTargetPlatformOverride = null;
      });
    }
    testWidgets('${s.key} general long', (t) async {
      await _show(t, s.value, true, _panel(SettingsPage.general, long: true));
      await expectLater(find.byType(Scaffold),
          matchesGoldenFile('goldens/settings2/${s.key}_general_long.png'));
      debugDefaultTargetPlatformOverride = null;
    });
    testWidgets('${s.key} mc', (t) => _mc(t, s.value, true, '${s.key}_mc'));
  }
  for (final e in pages.entries) {
    if (e.value == null) continue;
    testWidgets('desk ${e.key}', (t) async {
      await _show(t, desk, false, _panel(e.value, mobile: false));
      await expectLater(find.byType(Scaffold),
          matchesGoldenFile('goldens/settings2/desk_${e.key}.png'));
      debugDefaultTargetPlatformOverride = null;
    });
  }
  testWidgets('desk home', (t) async {
    await _show(t, desk, false, _panel(SettingsPage.general, mobile: false));
    await expectLater(find.byType(Scaffold),
        matchesGoldenFile('goldens/settings2/desk_nav.png'));
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('desk general long', (t) async {
    await _show(
        t, desk, false, _panel(SettingsPage.general, mobile: false, long: true));
    await expectLater(find.byType(Scaffold),
        matchesGoldenFile('goldens/settings2/desk_general_long.png'));
    debugDefaultTargetPlatformOverride = null;
  });
}
