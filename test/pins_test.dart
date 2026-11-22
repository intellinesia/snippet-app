import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/pins.dart';
import 'package:snippet/screens/agents_sidebar_panel.dart';
import 'package:snippet/screens/session_list_row.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/screens/sidebar.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

class _Client extends DaemonClient {
  _Client() : super('https://daemon.invalid', 'test');

  final DeviceEventHub _deviceEvents = DeviceEventHub.local();

  @override
  DeviceEventHub get deviceEvents => _deviceEvents;

  @override
  Future<ServerConfig> getConfig({bool force = false}) async =>
      ServerConfig.fromJson({
        'profiles': [
          {'name': 'claude', 'provider': 'claude-code'},
        ],
      });

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        CoordinationAgent.fromJson({
          'id': 'a1',
          'display_name': 'Alpha',
          'handle': 'alpha',
          'role': 'r',
          'status': 'active',
          'last_message': {
            'text': 'older',
            'from': 'agent',
            'at': '2026-11-10T10:00:00Z'
          },
        }),
        CoordinationAgent.fromJson({
          'id': 'a2',
          'display_name': 'Bravo',
          'handle': 'bravo',
          'role': 'r',
          'status': 'active',
          'last_message': {
            'text': 'newer',
            'from': 'agent',
            'at': '2026-11-12T10:00:00Z'
          },
        }),
      ];

  @override
  Future<List<GroupSummary>> groups() async => [
        GroupSummary.fromJson({
          'id': 'g1',
          'title': 'Ops Crew',
          'members': const [],
          'last_event_at': '2026-11-09T10:00:00Z',
          'created_at': '2026-11-01T00:00:00Z',
        }),
      ];
}

final _now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

SessionInfo _session(
  String id,
  String title, {
  String status = 'idle',
  String folder = '/home/dev/code/snippet-mobile',
}) =>
    SessionInfo.fromJson({
      'id': id,
      'title': title,
      'status': status,
      'last_active': _now - 600,
      'folder': folder,
      'settled': false,
    });

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Pins.instance.clear();
  });

  test('Pins toggles, keeps most-recently-pinned order, and persists', () async {
    expect(Pins.instance.isPinned(Pins.session, 's1'), isFalse);
    expect(Pins.instance.pinnedAt(Pins.session, 's1'), isNull);

    await Pins.instance.toggle(Pins.session, 's1');
    await Pins.instance.toggle(Pins.session, 's2');

    expect(Pins.instance.isPinned(Pins.session, 's1'), isTrue);
    expect(Pins.instance.isPinned(Pins.session, 's2'), isTrue);
    final t1 = Pins.instance.pinnedAt(Pins.session, 's1')!;
    final t2 = Pins.instance.pinnedAt(Pins.session, 's2')!;
    expect(t2, greaterThan(t1));
    expect(Pins.instance.ids(Pins.session), ['s2', 's1']);

    await Pins.instance.toggle(Pins.agent, 'a1', host: 'https://host-a');
    expect(
        Pins.instance.isPinned(Pins.agent, 'a1', host: 'https://host-a'),
        isTrue);
    expect(
        Pins.instance.isPinned(Pins.agent, 'a1', host: 'https://host-b'),
        isFalse);

    Pins.instance.clear();
    expect(Pins.instance.isPinned(Pins.session, 's1'), isFalse);

    await Pins.instance.load();
    expect(Pins.instance.isPinned(Pins.session, 's1'), isTrue);
    expect(Pins.instance.isPinned(Pins.session, 's2'), isTrue);
    expect(Pins.instance.ids(Pins.session), ['s2', 's1']);
    expect(
        Pins.instance.isPinned(Pins.agent, 'a1', host: 'https://host-a'),
        isTrue);

    await Pins.instance.toggle(Pins.session, 's2');
    expect(Pins.instance.isPinned(Pins.session, 's2'), isFalse);
    expect(Pins.instance.ids(Pins.session), ['s1']);
  });

  testWidgets('pinned agents and groups sort to top',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: AgentsSidebarPanel(client: _Client()))));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Ops Crew'));
      await tester.pumpAndSettle();
      expect(find.text('Pin'), findsOneWidget);
      await tester.tap(find.text('Pin'));
      await tester.pumpAndSettle();

      expect(find.text('Pinned'), findsOneWidget);
      final crewY = tester.getTopLeft(find.text('Ops Crew')).dy;
      final bravoY = tester.getTopLeft(find.text('Bravo')).dy;
      expect(crewY, lessThan(bravoY));

      await tester.longPress(find.text('Alpha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pin'));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.text('Alpha')).dy,
          lessThan(tester.getTopLeft(find.text('Ops Crew')).dy));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
