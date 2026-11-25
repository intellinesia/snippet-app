import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/tasks/task_phone_new.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';

class Fake extends DaemonClient {
  Fake({this.fail = false, this.hasLead = true})
      : super('https://daemon.invalid', 'test-token');
  final DeviceEventHub _hub = DeviceEventHub.local();
  @override
  DeviceEventHub get deviceEvents => _hub;
  bool fail;
  bool hasLead;
  final created = <Map<String, dynamic>>[];
  final cancelled = <String>[];
  final sent = <String>[];
  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        CoordinationAgent.fromJson({'id': 'buddy', 'display_name': 'Buddy'}),
      ];
  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async => [
        if (hasLead) SessionInfo.fromJson({'id': 'sl', 'folder': '/x', 'agent_id': 'lead'}),
        SessionInfo.fromJson({'id': 'sb', 'folder': '/x', 'agent_id': 'buddy'}),
      ];
  @override
  Future<TaskItem> createTask(
      {required String title,
      required String sessionId,
      String description = '',
      int priority = 0}) async {
    if (fail) throw Exception('boom');
    created.add({'title': title, 'session': sessionId, 'priority': priority, 'desc': description});
    return TaskItem.fromJson({'id': 'new1', 'title': title, 'session_id': sessionId});
  }

  @override
  Future<TaskItem> setTaskStatus(String id, TaskStatus status) async {
    cancelled.add('$id:${status.wire}');
    return TaskItem.fromJson({'id': id, 'title': 'x', 'status': status.wire});
  }

  @override
  Future<CoordinationEvent> sendAgentMessage({
    required String toAgentId,
    required String body,
    String fromKind = 'human',
    String fromId = 'local',
    String? idempotencyKey,
    String? originSession,
    String? replyTo,
    String? reaction,
    bool remove = false,
  }) async {
    sent.add(body);
    return CoordinationEvent.fromJson(<String, dynamic>{});
  }
}

Widget wrap(double scale, Widget home) => MaterialApp(
      theme: buildAppTheme(),
      builder: (c, ch) => MediaQuery(
          data: MediaQuery.of(c).copyWith(
              textScaler: TextScaler.linear(scale), disableAnimations: true),
          child: ch!),
      home: home,
    );

void phoneTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Future<bool?> open(WidgetTester tester, Fake c, Size size, double scale,
    {double keyboard = 0}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(wrap(
      scale,
      Builder(
          builder: (ctx) => Scaffold(
                body: Center(
                    child: TextButton(
                        onPressed: () => showNewTaskSheet(ctx, c),
                        child: const Text('open'))),
              ))));
  await tester.tap(find.text('open'));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return null;
}

void main() {
  for (final w in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 1.35, 2.0]) {
      phoneTest('new task w=$w s=$scale', (tester) async {
        await open(tester, Fake(), Size(w, 852), scale);
        expect(tester.takeException(), isNull);
        final title = tester.getRect(find.byKey(const ValueKey('new-task-title')));
        final brief = tester.getRect(find.byKey(const ValueKey('new-task-brief')));
        final btn = tester.getRect(find.byKey(const ValueKey('create-task')));
        final owner = tester.getRect(find.byKey(const ValueKey('row-owner')));
        final prio = tester.getRect(find.byKey(const ValueKey('row-priority')));
        // field container is the title text field's parent box
        final titleBox = tester.getRect(find
            .ancestor(of: find.byKey(const ValueKey('new-task-title')), matching: find.byType(Container))
            .first);
        final briefBox = tester.getRect(find
            .ancestor(of: find.byKey(const ValueKey('new-task-brief')), matching: find.byType(Container))
            .first);
        // ignore: avoid_print
        print('w=$w s=$scale titleBox=$titleBox briefBox=$briefBox owner=$owner prio=$prio btn=$btn');
        expect(titleBox.left, 16);
        expect(titleBox.width, w - 32);
        expect(titleBox.height, 48);
        expect(briefBox.width, w - 32);
        expect(briefBox.height, greaterThanOrEqualTo(71.99));
        expect(btn.left, 16);
        expect(btn.width, w - 32);
        expect(btn.height, 48);
        expect(owner.height, greaterThanOrEqualTo(48));
        expect(prio.height, greaterThanOrEqualTo(48));
        expect(title.width, lessThan(w));
        expect(brief.width, lessThan(w));
        expect(btn.bottom, lessThanOrEqualTo(852));
        // disabled until text
        final label = find.text('Create task');
        expect(tester.widget<Text>(label).style!.color, AppColors.fg3);
        await tester.enterText(find.byKey(const ValueKey('new-task-title')), 'Ship');
        await tester.pump();
        expect(tester.widget<Text>(label).style!.color, AppColors.bg);
      });
    }
  }

  phoneTest('button stays above the keyboard at 360x640', (tester) async {
    await open(tester, Fake(), const Size(360, 640), 1, keyboard: 280);
    final btn = tester.getRect(find.byKey(const ValueKey('create-task')));
    // ignore: avoid_print
    print('keyboard btn=$btn');
    expect(btn.bottom, lessThanOrEqualTo(640 - 280));
    expect(btn.top, greaterThanOrEqualTo(0));
  });

  phoneTest('create files the task with owner session and priority, Undo cancels', (tester) async {
    final c = Fake();
    await open(tester, c, const Size(393, 852), 1);
    await tester.enterText(find.byKey(const ValueKey('new-task-title')), 'Ship it');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('create-task')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(c.created.single['session'], 'sl');
    expect(c.created.single['priority'], 1);
    expect(find.byKey(const ValueKey('create-task')), findsNothing);
    expect(find.text('Task added'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(c.cancelled, ['new1:cancelled']);
    await tester.pump(const Duration(seconds: 10));
  });

  phoneTest('failure keeps the sheet with a neutral error', (tester) async {
    final c = Fake(fail: true);
    await open(tester, c, const Size(393, 852), 1);
    await tester.enterText(find.byKey(const ValueKey('new-task-title')), 'Ship it');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('create-task')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    final err = find.text("Couldn't create the task. Try again.");
    expect(err, findsOneWidget);
    expect(tester.widget<Text>(err).style!.color, AppColors.fg2);
    expect(find.text('Create task'), findsOneWidget);
  });

  phoneTest('no routable session falls back to Lead', (tester) async {
    final c = Fake(hasLead: false);
    await open(tester, c, const Size(393, 852), 1);
    await tester.enterText(find.byKey(const ValueKey('new-task-title')), 'Ship it');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('create-task')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(c.created, isEmpty);
    expect(c.sent.single, contains('Title: Ship it'));
    await tester.pump(const Duration(seconds: 10));
  });
}
