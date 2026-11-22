import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/lead/lead_state.dart';

void main() {
  test('direct message envelope carries kind and urgency', () {
    final m = parseDirectMessage(
        '<direct_message thread_id="t" from="agent:a" kind="blocker" urgency="urgent">\n<body>stuck</body>\n</direct_message>');
    expect(m!.messageKind, 'blocker');
    expect(m.urgent, isTrue);
    expect(m.body, 'stuck');
  });

  test('untyped envelope stays plain', () {
    final m = parseDirectMessage('<direct_message thread_id="t" from="agent:a">\n<body>hi</body>\n</direct_message>');
    expect(m!.messageKind, '');
    expect(m.urgent, isFalse);
  });

  test('a question notification leads with the question itself', () {
    expect(
        userQuestionLead({
          'questions': {
            'questions': [
              {'text': 'Ship the APK now?'},
              {'text': 'Which build?'}
            ]
          }
        }),
        'Ship the APK now? (+1 more)');
    expect(userQuestionLead({'questions': [{'text': 'Merge it?'}]}), 'Merge it?');
    expect(userQuestionLead({}), 'Needs your input');
  });

  test('ambient resume notes with attributes are recognised', () {
    expect(isAmbientResume('<ambient_resume interrupted_reply="Two quick">x</ambient_resume>'), isTrue);
    expect(isAmbientResume('<ambient_resume>x</ambient_resume>'), isTrue);
  });
}
