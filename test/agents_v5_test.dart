import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/presence.dart';
import 'package:snippet/screens/agent_card.dart';
import 'package:snippet/screens/agent_questions_card.dart';
import 'package:snippet/screens/session_coordination_cards.dart';
import 'package:snippet/screens/mission_control/mission_control_state.dart'
    show WorkerQuestion;
import 'package:snippet/theme.dart';

CoordinationAgent _agent(Map<String, dynamic> j) =>
    CoordinationAgent.fromJson({'id': 'a1', 'display_name': 'Ada', ...j});

void main() {
  group('cleanAgentStatusText', () {
    test('drops a group id when the title is unknown', () {
      expect(
          cleanAgentStatusText('posted to group:6e76e84e-1234-4abc-8def-0123456789ab done'),
          'posted to done');
    });

    test('maps a group id to its title', () {
      expect(
        cleanAgentStatusText('handoff to group:6e76e84e-1234-4abc-8def-0123456789ab',
            groupTitles: {
              '6e76e84e-1234-4abc-8def-0123456789ab': 'XDR+ISE demo'
            }),
        'handoff to XDR+ISE demo',
      );
    });

    test('strips task uuids and bare uuids', () {
      expect(
          cleanAgentStatusText(
              'finished task d1f38552-4a3d-4e5f-8a9b-0c1d2e3f4a5b and d1f38552-4a3d-4e5f-8a9b-0c1d2e3f4a5b'),
          'finished and');
    });

    test('collapses separators left behind', () {
      expect(cleanAgentStatusText('Working · · group:abc-123'), 'Working');
    });
  });

  group('agentStatusLine', () {
    test('needs you prefixes the context', () {
      final a = _agent({
        'task_counts': {'blocked': 1},
        'last_message': {'text': 'May I delete the previews?', 'from': 'agent'},
      });
      expect(agentStatusLine(a),
          'Waiting on you · Asked: May I delete the previews?');
    });

    test('working shows the message, recent shows Asked for questions', () {
      final w = _agent({
        'task_counts': {'in_progress': 1},
        'last_message': {'text': 'Reviewing #131 · cargo test', 'from': 'agent'},
      });
      expect(agentStatusLine(w), 'Reviewing #131 · cargo test');
      final r = _agent({
        'last_message': {
          'text': 'should seats nest under the parent row?',
          'from': 'agent'
        },
      });
      expect(agentStatusLine(r),
          'Asked: should seats nest under the parent row?');
    });

    test('your own last message is prefixed', () {
      final a = _agent({
        'last_message': {'text': 'ship it', 'from': 'user'},
      });
      expect(agentStatusLine(a), 'You: ship it');
    });
  });

  group('agentGroupFor', () {
    test('waiting presence is needs you, open work is working', () {
      final idle = _agent({'task_counts': {}});
      expect(agentGroupFor(idle), AgentGroup.recent);
      final working = _agent({'task_counts': {'todo': 2}});
      expect(agentGroupFor(working), AgentGroup.working);
      final waiting = _agent({'task_counts': {}});
      expect(
        agentGroupFor(waiting,
            presence: const Presence(state: 'waiting', detail: 'user')),
        AgentGroup.needsYou,
      );
    });
  });

  group('questionAnswerSystemLine', () {
    CoordinationEvent ev(Map<String, dynamic> payload,
            {String actor = 'human'}) =>
        CoordinationEvent.fromJson({
          'event_id': 'e1',
          'actor_kind': actor,
          'payload': payload,
        });

    test('answer events collapse to a system line, skips say Skipped', () {
      expect(
        questionAnswerSystemLine(ev({
          'auto': 'answer',
          'answer_to': 'q1',
          'body': 'Pick one?\n→ Staging',
        })),
        'Answered',
      );
      expect(
        questionAnswerSystemLine(ev({
          'auto': 'answer',
          'answer_to': 'q1',
          'body': 'Pick one?\n→ user skipped the question',
        })),
        'Skipped',
      );
      expect(questionAnswerSystemLine(ev({'body': 'hello'})), isNull);
      expect(
        questionAnswerSystemLine(ev({'auto': 'answer'}, actor: 'agent')),
        isNull,
      );
    });
  });

  group('AgentQuestionsCard v5', () {
    CoordinationEvent qev() => CoordinationEvent.fromJson({
          'event_id': 'eq',
          'actor_kind': 'agent',
          'payload': {
            'auto': 'ask',
            'question': {
              'session': 'sess-1',
              'questions': [
                {
                  'id': 'target',
                  'text': 'Which deployment target?',
                  'answer_kind': {
                    'kind': 'single_choice',
                    'choices': [
                      {'value': 'staging', 'label': 'Staging', 'recommended': true},
                      {'value': 'prod', 'label': 'Production'},
                    ],
                  },
                },
              ],
            },
          },
        });

    Future<void> pump(WidgetTester t, Widget card) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: SingleChildScrollView(child: card))));
      await t.pump();
      debugDefaultTargetPlatformOverride = null;
    }

    testWidgets('shows the v5 header, numbered options and Skip/Answer',
        (t) async {
      final e = qev();
      final client = _QClient();
      await pump(
          t,
          AgentQuestionsCard(
              event: e,
              question: e.payload['question'] as Map<dynamic, dynamic>,
              client: client,
              events: [e]));
      expect(find.text('Question'), findsOneWidget);
      expect(find.text('1 of 1'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
      expect(find.text('Staging'), findsOneWidget);
      expect(find.text('Recommended'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Answer'), findsOneWidget);
      expect(find.text('Send'), findsNothing);
    });

    testWidgets('Skip posts the skipped marker for every question', (t) async {
      final e = qev();
      final client = _QClient();
      await pump(
          t,
          AgentQuestionsCard(
              event: e,
              question: e.payload['question'] as Map<dynamic, dynamic>,
              client: client,
              events: [e]));
      await t.tap(find.text('Skip'));
      await t.pump();
      expect(client.calls, hasLength(1));
      expect(client.calls.single.answers['target'], 'user skipped the question');
      expect(client.calls.single.text, contains('user skipped the question'));
      expect(find.text('Skipped'), findsOneWidget);
    });

    testWidgets('answered card collapses to Answered: <choice>', (t) async {
      final e = qev();
      final client = _QClient();
      final answer = CoordinationEvent.fromJson({
        'event_id': 'ea',
        'actor_kind': 'human',
        'payload': {
          'auto': 'answer',
          'answer_to': 'eq',
          'answers': {'target': 'prod'},
          'body': 'Which deployment target?\n→ Production',
        },
      });
      await pump(
          t,
          AgentQuestionsCard(
              event: e,
              question: e.payload['question'] as Map<dynamic, dynamic>,
              client: client,
              events: [e, answer]));
      expect(find.text('Answered: Production'), findsOneWidget);
      expect(find.text('Answer'), findsNothing);
      expect(find.text('Skip'), findsNothing);
    });

    testWidgets('WorkerQuestionCard uses the v5 question frame', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await t.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
              body: WorkerQuestionCard(
                  question: WorkerQuestion(
                      taskId: 't1',
                      task: 'Review #131',
                      question: 'Merge or hold?')))));
      await t.pump();
      debugDefaultTargetPlatformOverride = null;
      expect(find.text('Question'), findsOneWidget);
      expect(find.text('Merge or hold?'), findsOneWidget);
      expect(find.textContaining('Mission Control answers'), findsOneWidget);
    });
  });
}

class _QCall {
  _QCall(this.text, this.answers);
  final String text;
  final Map<String, dynamic> answers;
}

class _QClient extends DaemonClient {
  _QClient() : super('https://daemon.invalid', 'test-token');
  final List<_QCall> calls = [];

  @override
  Future<String> answerAgentQuestion({
    required String session,
    required String questionEventId,
    required String text,
    required Map<String, dynamic> answers,
  }) async {
    calls.add(_QCall(text, answers));
    return 'human-answer-1';
  }
}
