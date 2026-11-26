import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/chat/ask_kit.dart';
import 'package:snippet/screens/session.dart';

Map<String, dynamic> question() => {
      'questions': [
        {
          'id': 'q1',
          'text': 'Pick one.',
          'answer_kind': {
            'kind': 'single_choice',
            'choices': const [
              {'value': 'a', 'label': 'Alpha'},
              {'value': 'b', 'label': 'Beta'},
            ],
          },
        },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void useLinux() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
  }

  testWidgets('an inactive approval bar does not answer Enter', (tester) async {
    useLinux();
    var sent = 0;
    Widget bar(bool active) => MaterialApp(
          home: Scaffold(
            body: ApprovalBar(
              active: active,
              events: const [
                {
                  'kind': 'approval_request',
                  'tool_name': 'bash',
                  'summary': 'echo hi',
                  'index': 1,
                  'total': 1,
                },
              ],
              onSend: (_) => sent++,
            ),
          ),
        );

    await tester.pumpWidget(bar(false));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(sent, 0);

    await tester.pumpWidget(bar(true));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(sent, 1);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('an inactive question bar neither takes nor keeps focus',
      (tester) async {
    useLinux();
    Widget bar(bool active) => MaterialApp(
          home: Scaffold(
            body: QuestionBar(
                question: question(), active: active, onSend: (_) {}),
          ),
        );
    bool insideQuestion() => FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<QuestionBar>() !=
        null;

    await tester.pumpWidget(bar(false));
    await tester.pump();
    expect(insideQuestion(), isFalse);

    await tester.pumpWidget(bar(true));
    await tester.pump();
    await tester.pump();
    expect(insideQuestion(), isTrue);

    await tester.pumpWidget(bar(false));
    await tester.pump();
    expect(insideQuestion(), isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('digits typed into a free answer do not pick a choice',
      (tester) async {
    useLinux();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: QuestionBar(question: question(), onSend: (_) {}),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('Write your own answer'));
    await tester.pump();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.pump();

    final beta = tester
        .widgetList<AskChoicePill>(find.byType(AskChoicePill))
        .firstWhere((p) => p.label == 'Beta');
    expect(beta.selected, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });
}
