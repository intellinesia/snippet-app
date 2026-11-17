import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/agent_character.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/screens/agents_sidebar_panel.dart';
import 'package:snippet/screens/create_agent_form.dart';
import 'package:snippet/theme.dart';

class _Client extends DaemonClient {
  _Client(this.team) : super('https://agents7.invalid', 'test-token');

  final List<CoordinationAgent> team;
  final _deviceEvents = DeviceEventHub.local();

  @override
  DeviceEventHub get deviceEvents => _deviceEvents;

  @override
  List<CoordinationAgent>? cachedCoordinationAgents() => null;

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => team;

  @override
  Future<List<GroupSummary>> groups() async =>
      team.length > 2 ? [_group] : const [];
}

final _group = GroupSummary.fromJson({
  'id': 'group:1',
  'title': 'scrapper bois',
  'members': [
    {'kind': 'agent', 'id': 'snippet'},
    {'kind': 'agent', 'id': 'scout'},
  ],
  'preview': 'x-scout: Simon draft: A customer asked us this last month.',
  'created_at': '2026-11-12T00:00:00Z',
  'last_event_at': '2026-11-16T11:34:00Z',
});

CoordinationAgent _agent(String id, String name,
        {String? character, Map<String, int>? tasks, String? last}) =>
    CoordinationAgent.fromJson({
      'id': id,
      'display_name': name,
      'handle': id,
      'status': 'active',
      if (character != null) 'character': character,
      if (tasks != null) 'task_counts': tasks,
      if (last != null)
        'last_message': {
          'text': last,
          'from': 'agent',
          'at': DateTime(2026, 11, 16, 11, 34).toIso8601String(),
        },
    });

SessionInfo _running(String agent, String title) => SessionInfo.fromJson({
      'id': 's-$agent',
      'title': title,
      'status': 'running',
      'running': true,
      'agent_id': agent,
      'last_active': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'plan': {'done': 2, 'total': 5, 'current': 'Run tests and goldens'},
    });

Future<void> _shot(WidgetTester t, String name) async {
  const dir = String.fromEnvironment('SHOT_DIR');
  if (dir.isEmpty) return;
  await t.runAsync(() async {
    final b = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('shot')));
    final img = await b.toImage();
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _pump(WidgetTester t, List<CoordinationAgent> team,
    {List<SessionInfo> sessions = const []}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.runAsync(() async {
    await CharacterRoster.load();
    await ThemeManager.instance.setName('stone');
  });
  await t.pumpWidget(RepaintBoundary(
    key: const ValueKey('shot'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        backgroundColor: AppColors.pageBg,
        body: SafeArea(
          child: AgentsSidebarPanel(
            key: ValueKey('panel-${team.length}'),
            client: _Client(team),
            sessions: sessions,
            onOpenAgent: (_) {},
          ),
        ),
      ),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => ThemeManager.instance.resetForTest());

  testWidgets('defaults only: hero, Your team, Add an agent', (t) async {
    await _pump(t, [_agent('snippet', 'Rook', character: '01')]);
    expect(find.byKey(const ValueKey('agents-team-hero')), findsOneWidget);
    expect(find.text('Your agent · asleep'), findsOneWidget);
    expect(find.text('Your team'), findsOneWidget);
    expect(find.text('Add an agent'), findsOneWidget);
    expect(find.text('Code reviewer'), findsOneWidget);
    expect(find.text('Release manager'), findsOneWidget);
    expect(find.text('Describe your own'), findsOneWidget);
    expect(find.text('Or pick from 4 starters'), findsOneWidget);
    expect(find.text('New agent'), findsNothing);
    await _shot(t, 'agents-a-defaults');
    await _unmount(t);
  });

  testWidgets('a starter opens the create form prefilled', (t) async {
    await _pump(t, [_agent('snippet', 'Rook', character: '01')]);
    await t.tap(find.byKey(const ValueKey('agents-add-Code reviewer')));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(CreateAgentForm), findsOneWidget);
    final form = t.widget<CreateAgentForm>(find.byType(CreateAgentForm));
    expect(form.initialPrompt, agentStarters.first.prompt);
    expect(form.initialCharacter, agentStarters.first.character);
    expect(find.text(agentStarters.first.prompt), findsOneWidget);
    await _unmount(t);
  });

  testWidgets('busy: Working with a plan bar, Asleep, no New agent row',
      (t) async {
    await _pump(t, [
      _agent('snippet', 'Rook', character: '01'),
      _agent('wren', 'Wren', character: '04', last: 'Golden baselines'),
      _agent('pip', 'Pip', character: '06', last: 'Q3 churn brief'),
    ], sessions: [
      _running('snippet', 'Sidebar density')
    ]);
    expect(find.byKey(const ValueKey('agents-team-hero')), findsNothing);
    expect(find.text('Working'), findsOneWidget);
    expect(find.text('Asleep'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-plan-bar')), findsOneWidget);
    expect(find.textContaining('plan 3 of 5'), findsOneWidget);
    // The floating + adds agents; the list carries no add row.
    expect(find.text('New agent'), findsNothing);
    expect(find.text('scrapper bois'), findsOneWidget);
    expect(find.text('Add an agent'), findsNothing);
    await _shot(t, 'agents-a-busy');
    await _unmount(t);
  });

  testWidgets('no agents: empty hero and the starters', (t) async {
    await _pump(t, const []);
    expect(find.byKey(const ValueKey('agents-empty-hero')), findsOneWidget);
    expect(find.text('No agents yet'), findsOneWidget);
    expect(find.text('Your team'), findsNothing);
    expect(find.text('Add an agent'), findsOneWidget);
    expect(find.text('Describe your own'), findsOneWidget);
    await _shot(t, 'agents-a-none');
    await _unmount(t);
  });
}
