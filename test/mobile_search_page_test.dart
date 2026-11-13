import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/screens/mobile_search_page.dart';
import 'package:snippet/theme.dart';

class _FakeClient extends DaemonClient {
  _FakeClient({List<TaskItem> taskItems = const [], List<CoordinationAgent> agentList = const []})
      : _taskItems = taskItems,
        _agentList = agentList,
        super('https://daemon.invalid', 'test-token');

  @override
  late final DeviceEventHub deviceEvents = DeviceEventHub.local();

  final List<TaskItem> _taskItems;
  final List<CoordinationAgent> _agentList;

  @override
  Future<List<TaskItem>> tasks(
          {String? status, String? agentId, int? limit}) async =>
      _taskItems;

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => _agentList;
}

void main() {
  final sessions = [
    SessionInfo.fromJson({
      'id': 's1',
      'title': 'Release plan',
      'folder': '/code/my-project',
      'profile': 'default',
    }),
    SessionInfo.fromJson({
      'id': 's2',
      'title': 'Unrelated chat',
      'folder': '/code/other',
    }),
  ];

  final tasks = [
    TaskItem.fromJson({'id': 't1', 'title': 'Release checklist', 'status': 'in_review'}),
  ];

  final agents = [
    CoordinationAgent.fromJson({
      'id': 'a1',
      'display_name': 'Release bot',
      'handle': 'release-bot',
      'status': 'active',
    }),
  ];

  Widget harness({
    DaemonClient? client,
    List<SessionInfo> sessionList = const [],
    void Function(String, String, String?)? onOpenSession,
    ValueChanged<CoordinationAgent>? onOpenAgent,
  }) {
    return MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => MobileSearchPage(
                client: client,
                sessions: sessionList,
                onOpenSession: onOpenSession ?? (_, __, ___) {},
                onOpenAgent: onOpenAgent ?? (_) {},
              ),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    );
  }

  Future<void> openPage(WidgetTester tester, Widget app) async {
    await tester.pumpWidget(app);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileSearchPage), findsOneWidget);
  }

  testWidgets('grouped sections appear for a query', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(390, 844) * 2.0;
      addTearDown(tester.view.reset);
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      await openPage(
        tester,
        harness(
          client: _FakeClient(taskItems: tasks, agentList: agents),
          sessionList: sessions,
        ),
      );

      await tester.enterText(find.byType(TextField), 'release');
      await tester.pumpAndSettle();

      expect(find.text('Sessions'), findsOneWidget);
      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('Agents'), findsOneWidget);
      expect(find.text('Release plan'), findsOneWidget);
      expect(find.text('my-project'), findsOneWidget);
      expect(find.text('Release checklist'), findsOneWidget);
      expect(find.text('In review'), findsOneWidget);
      expect(find.text('Release bot'), findsOneWidget);
      expect(find.text('Unrelated chat'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Cancel pops the page', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(390, 844) * 2.0;
      addTearDown(tester.view.reset);

      await openPage(tester, harness(client: _FakeClient(), sessionList: sessions));

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(MobileSearchPage), findsNothing);
      expect(find.text('open'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('tapping a session row calls onOpenSession', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(390, 844) * 2.0;
      addTearDown(tester.view.reset);

      String? openedId;
      String? openedTitle;
      String? openedProfile;
      await openPage(
        tester,
        harness(
          client: _FakeClient(),
          sessionList: sessions,
          onOpenSession: (id, title, profile) {
            openedId = id;
            openedTitle = title;
            openedProfile = profile;
          },
        ),
      );

      await tester.enterText(find.byType(TextField), 'release');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Release plan'));
      await tester.pumpAndSettle();

      expect(find.byType(MobileSearchPage), findsNothing);
      expect(openedId, 's1');
      expect(openedTitle, 'Release plan');
      expect(openedProfile, 'default');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
