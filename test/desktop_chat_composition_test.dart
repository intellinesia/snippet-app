import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/chat/chat_info.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/group_messaging.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';

class _Client extends DaemonClient {
  _Client(this.initialEvents) : super('https://daemon.invalid', 'token');

  final List<CoordinationEvent> initialEvents;
  final _hub = DeviceEventHub.local();

  @override
  DeviceEventHub get deviceEvents => _hub;

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        CoordinationAgent.fromJson(
            {'id': 'sashy', 'display_name': 'Sashy', 'status': 'active'}),
        CoordinationAgent.fromJson(
            {'id': 'duke', 'display_name': 'Duke', 'status': 'active'}),
      ];

  @override
  Future<List<CoordinationEvent>> groupEvents(
    String id, {
    int after = 0,
    int limit = 100,
  }) async =>
      [for (final e in initialEvents) if (e.sequence > after) e];
}

GroupSummary _group() => GroupSummary.fromJson({
      'id': 'g1',
      'title': 'App Redesign',
      'members': [
        {'kind': 'human', 'id': 'local'},
        {'kind': 'agent', 'id': 'sashy'},
        {'kind': 'agent', 'id': 'duke'},
      ],
      'lead': 'sashy',
      'created_at': '2026-11-20T00:00:00Z',
    });

CoordinationEvent _post() => CoordinationEvent.fromJson({
      'event_id': 'e1',
      'sequence': 1,
      'actor_kind': 'agent',
      'actor_id': 'sashy',
      'idempotency_key': 'k-e1',
      'created_at': '2026-11-25T18:48:00Z',
      'payload': {'body': 'Alpha release note'},
    });

void _desktop(WidgetTester tester, Size size) {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  for (final size in const [Size(1440, 900), Size(1024, 700)]) {
    testWidgets(
        'desktop group chat draws no in-pane head and keeps its transcript in the pane at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
      _desktop(tester, size);
      try {
        await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: GroupThreadScreen(client: _Client([_post()]), group: _group()),
        ));
        await _pumpFrames(tester);

        final material = tester.widget<Material>(find
            .descendant(
                of: find.byType(GroupThreadScreen),
                matching: find.byType(Material))
            .first);
        expect(material.color, AppColors.panelBg);
        expect(material.color!.a, 1.0);

        // The shell's XO-03 bar carries the identity; the screen draws no head.
        expect(find.text('App Redesign'), findsNothing);
        final screen = tester.getRect(find.byType(GroupThreadScreen));
        final transcript =
            tester.getRect(find.textContaining('Alpha release note').first);
        expect(transcript.top, greaterThanOrEqualTo(screen.top),
            reason: 'transcript content must stay inside the chat pane');
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('docked group info uses compact bounded member rows',
      (tester) async {
    _desktop(tester, const Size(1440, 900));
    try {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 340,
            height: 900,
            child: GroupInfoPanel(
                client: _Client(const []), group: _group(), docked: true),
          ),
        ),
      ));
      await _pumpFrames(tester);

      expect(find.text('You'), findsOneWidget);
      expect(find.text('Sashy'), findsWidgets);
      expect(find.text('Duke'), findsWidgets);
      final first = tester.getRect(find.text('You').first);
      final second = tester.getRect(find.text('Sashy').first);
      expect(second.top - first.top, 34,
          reason: '28-high member rows plus the bounded-card gap');
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
