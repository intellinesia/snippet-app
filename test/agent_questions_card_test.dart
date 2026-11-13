import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agent_questions_card.dart';
import 'package:snippet/screens/agent_thread_cards.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

CoordinationEvent _ev(
  String id,
  String kind, [
  Map<String, dynamic> payload = const {},
]) =>
    CoordinationEvent.fromJson({
      'event_id': id,
      'sequence': 1,
      'actor_kind': kind,
      'idempotency_key': 'k-$id',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'payload': payload,
    });

Map<String, dynamic> _askPayload() => {
      'auto': 'ask',
      'body': 'Two quick questions',
      'question': {
        'session': 'sess-1',
        'questions': [
          {
            'id': 'target',
            'header': 'Deploy target',
            'text': 'Which deployment target?',
            'answer_kind': {
              'kind': 'single_choice',
              'choices': [
                {'value': 'staging', 'label': 'Staging', 'recommended': true},
                {'value': 'prod', 'label': 'Production'},
              ],
            },
          },
          {
            'id': 'notes',
            'text': 'Anything else?',
            'answer_kind': {'kind': 'free_text'},
          },
        ],
      },
    };

class _AnswerCall {
  _AnswerCall(this.session, this.questionEventId, this.text, this.answers);
  final String session;
  final String questionEventId;
  final String text;
  final Map<String, dynamic> answers;
}

class _Client extends DaemonClient {
  _Client() : super('https://daemon.invalid', 'test-token');
  final List<_AnswerCall> calls = [];
  Object? answerError;

  @override
  Future<String> answerAgentQuestion({
    required String session,
    required String questionEventId,
    required String text,
    required Map<String, dynamic> answers,
  }) async {
    calls.add(_AnswerCall(session, questionEventId, text, answers));
    final err = answerError;
    if (err != null) throw err;
    return 'human-answer-1';
  }
}

Future<void> _pump(WidgetTester t, Widget card) async {
  t.view.physicalSize = const Size(360, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: SingleChildScrollView(child: card)),
    ),
  );
  await t.pump();
}

void main() {
  testWidgets('renders every question and sends composed text and answers', (
    t,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final client = _Client();
    final q = _ev('eq', 'agent', _askPayload());
    final question = q.payload['question'] as Map<dynamic, dynamic>;
    await _pump(
      t,
      AgentQuestionsCard(
        event: q,
        question: question,
        client: client,
        events: [q],
      ),
    );

    expect(find.text('Deploy target'), findsOneWidget);
    expect(find.text('Which deployment target?'), findsOneWidget);
    expect(find.text('Anything else?'), findsOneWidget);
    expect(find.text('Staging'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);

    final send = find.widgetWithText(Btn, 'Answer');
    expect(send, findsOneWidget);
    expect(t.widget<Btn>(send).disabled, isTrue);

    await t.enterText(find.byType(TextField), 'ship it');
    await t.pump();
    expect(t.widget<Btn>(send).disabled, isFalse);

    await t.tap(send);
    await t.pump();

    expect(client.calls, hasLength(1));
    final call = client.calls.single;
    expect(call.session, 'sess-1');
    expect(call.questionEventId, 'eq');
    expect(call.answers, {'target': 'staging', 'notes': 'ship it'});
    expect(
      call.text,
      'Which deployment target?\n→ Staging\n\nAnything else?\n→ ship it',
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('answer event renders read-only with chosen choice highlighted', (
    t,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final client = _Client();
    final q = _ev('eq', 'agent', _askPayload());
    final question = q.payload['question'] as Map<dynamic, dynamic>;
    final answer = _ev('ea', 'human', {
      'auto': 'answer',
      'answer_to': 'eq',
      'answers': {'target': 'prod', 'notes': 'looks good'},
      'body':
          'Which deployment target?\n→ Production\n\nAnything else?\n→ looks good',
    });
    await _pump(
      t,
      AgentQuestionsCard(
        event: q,
        question: question,
        client: client,
        events: [q, answer],
      ),
    );

    expect(find.text('Answered: Production'), findsOneWidget);
    expect(find.text('Answered: looks good'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.widgetWithText(Btn, 'Answer'), findsNothing);
    expect(client.calls, isEmpty);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('409 shows the error inline and disables the inputs', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final client = _Client()
      ..answerError = const QuestionAnswerConflict(
        'This question is no longer waiting',
      );
    final q = _ev('eq', 'agent', _askPayload());
    final question = q.payload['question'] as Map<dynamic, dynamic>;
    await _pump(
      t,
      AgentQuestionsCard(
        event: q,
        question: question,
        client: client,
        events: [q],
      ),
    );

    await t.enterText(find.byType(TextField), 'ship it');
    await t.pump();
    await t.tap(find.widgetWithText(Btn, 'Answer'));
    await t.pump();

    expect(find.text('This question is no longer waiting'), findsOneWidget);
    expect(t.widget<AppField>(find.byType(AppField)).enabled, isFalse);
    expect(t.widget<Btn>(find.widgetWithText(Btn, 'Answer')).disabled, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('older single-question payload still uses the read-only card', (
    t,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final client = _Client();
    final ev = _ev('eq', 'agent', {
      'question': {
        'text': 'Pick a strategy',
        'kind': 'single_choice',
        'choices': [
          {'value': 'a', 'label': 'Alpha'},
          {'value': 'b', 'label': 'Beta'},
        ],
      },
    });
    final card = agentThreadEventCard(ev, client: client, agentId: 'growth');
    expect(card, isNot(isA<AgentQuestionsCard>()));
    await _pump(t, card!);
    expect(find.byType(AgentQuestionsCard), findsNothing);
    expect(find.text('Pick a strategy'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
