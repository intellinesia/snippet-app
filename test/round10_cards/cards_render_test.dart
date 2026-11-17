import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agent_thread_cards.dart';
import 'package:snippet/screens/artifact_viewer.dart';
import 'package:snippet/theme.dart';

class _Client extends DaemonClient {
  _Client() : super('https://daemon.invalid', 'test-token');

  @override
  Future<List<ArtifactInfo>> artifacts(String session) async => [
        ArtifactInfo.fromJson({
          'id': 'a1',
          'title': 'LinkedIn Cisco AI Candidates',
          'kind': 'markdown',
          'versions': [
            {'n': 1, 'url': '/a1/v1'}
          ],
        })
      ];

  @override
  Future<String> artifactText(String signedPath) async =>
      '## Findings\n\nTwo strong **Cisco AI security** leader posts in the '
      'last 24 hours, from 20 profiles and 22 raw records. Six items:\n'
      '- `one`\n- two\n';
}

CoordinationEvent _ev(Map<String, dynamic> payload) =>
    CoordinationEvent.fromJson({
      'event_id': 'e${payload.hashCode}',
      'sequence': 1,
      'actor_kind': 'agent',
      'actor_id': 'snippet',
      'created_at': '2026-11-16T12:00:00Z',
      'payload': payload,
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

void main() {
  testWidgets('approval, artifact and task result cards', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final client = _Client();
    final cards = [
      agentThreadEventCard(
        _ev({
          'approval': {
            'status': 'approved',
            'command':
                'python3 ~/.snippet/goals/daily-linkedin/scrape.py --since 24h',
            'summary': 'python3 scrape',
            'task_title': 'LinkedIn sync',
          },
        }),
        client: client,
        agentId: 'snippet',
      ),
      agentThreadEventCard(
        _ev({
          'artifact': {
            'id': 'a1',
            'session': 's1',
            'title': 'LinkedIn Cisco AI Candidates',
            'kind': 'markdown',
            'version': 1,
          },
        }),
        client: client,
        agentId: 'snippet',
      ),
      agentThreadEventCard(
        _ev({
          'task_result': {
            'title': 'Daily LinkedIn sync script',
            'status': 'done',
            'session_id': 's2',
            'summary':
                'Scraped and handed two candidates to x-scout. Nothing posted to the feed because the posting queue was paused for the weekend.',
          },
        }),
        client: client,
        agentId: 'snippet',
      ),
    ];
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: RepaintBoundary(
          key: const ValueKey('shot'),
          child: ColoredBox(
            color: AppColors.bg,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(52, 56, 52, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final c in cards) ...[c!, const SizedBox(height: 20)],
                ],
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Ran a command'), findsOneWidget);
    expect(find.text('Approved · LinkedIn sync'), findsOneWidget);
    expect(find.text('Document · v1'), findsOneWidget);
    expect(find.textContaining('Two strong Cisco AI security'), findsOneWidget);
    expect(find.textContaining('`'), findsNothing);
    expect(find.textContaining('**'), findsNothing);
    expect(find.textContaining('Task done · 16 Nov'), findsOneWidget);
    expect(find.text('Show more'), findsNothing);
    await _shot(tester, 'cards');
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
