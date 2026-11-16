import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/chat/chat_card.dart';
import 'package:snippet/mochi.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agent_questions_card.dart';
import 'package:snippet/theme.dart';

CoordinationEvent _ask() => CoordinationEvent.fromJson({
      'event_id': 'eq',
      'sequence': 1,
      'actor_kind': 'agent',
      'actor_id': 'research',
      'idempotency_key': 'k-eq',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'payload': {
        'auto': 'ask',
        'body': 'One question',
        'question': {
          'session': 'sess-ask',
          'questions': [
            {
              'id': 'target',
              'text': 'Which deployment target?',
              'answer_kind': {
                'kind': 'single_choice',
                'choices': [
                  {'value': 'staging', 'label': 'Staging'},
                  {'value': 'prod', 'label': 'Production'},
                ],
              },
            },
          ],
        },
      },
    });

SessionInfo _session(String status) =>
    SessionInfo.fromJson({'id': 'sess-ask', 'status': status});

Future<void> _pump(WidgetTester t) async {
  t.view.physicalSize = const Size(360, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final q = _ask();
  await t.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: SingleChildScrollView(
        child: AgentQuestionsCard(
          event: q,
          question: q.payload['question'] as Map<dynamic, dynamic>,
          client: DaemonClient('https://daemon.invalid', 'test-token'),
          events: [q],
        ),
      ),
    ),
  ));
  await t.pump();
}

void main() {
  tearDown(() => knownSessions.remove('sess-ask'));

  testWidgets('question from a session that moved on shows as outdated',
      (t) async {
    knownSessions['sess-ask'] = _session('idle');
    await _pump(t);
    expect(find.text('No longer waiting on this'), findsOneWidget);
    expect(find.text('Staging'), findsNothing);
  });

  testWidgets('question from a waiting session stays answerable', (t) async {
    knownSessions['sess-ask'] = _session('waiting_for_input');
    await _pump(t);
    expect(find.text('Staging'), findsOneWidget);
    expect(find.text('No longer waiting on this'), findsNothing);
  });

  testWidgets('agent asks take the asking agent colour', (t) async {
    await t.runAsync(CharacterRoster.load);
    expect(agentTintFor('research'), isNotNull);
    await _pump(t);
    final ctx = t.element(find.text('Staging'));
    expect(ChatCardAccent.of(ctx), agentTintFor('research'));
  });
}
