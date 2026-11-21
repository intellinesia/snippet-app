import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/mission_control/mission_control_state.dart';

void main() {
  test('parses a watch envelope into name, mode and new lines', () {
    const text = '<watch name="inbox" watch_id="w1" mode="stream" event="change" lines="2" held="3">\n<body>\nmsg from alice: lunch at 1?\nmsg from bob: PR approved\n</body>\n<note>your own watch fired.</note>\n</watch>';
    final w = parseWatchEnvelope(text)!;
    expect(w.name, 'inbox');
    expect(w.mode, 'stream');
    expect(w.event, 'change');
    expect(w.held, 3);
    expect(w.lines, ['msg from alice: lunch at 1?', 'msg from bob: PR approved']);
  });

  test('keeps a --- line inside the output', () {
    const text = '<watch name="x" mode="poll" event="change" lines="2">\n<body>\na\n---\n</body>\n<note>n</note>\n</watch>';
    expect(parseWatchEnvelope(text)!.lines, ['a', '---']);
  });

  test('extracts the note from a wake envelope', () {
    const text = '<wake set="2026-11-14T04:18:03Z">\n<note>You asked to be woken now.</note>\n<wake_note>Check CI on #150 &amp; merge.</wake_note>\n<instructions>Do what the note says.</instructions>\n</wake>';
    expect(parseWakeNote(text), 'Check CI on #150 & merge.');
    expect(parseWakeNote('hello'), isNull);
    expect(parseWatchEnvelope('<wake set="x"/>'), isNull);
  });

  test('labels queued envelopes by kind and sender', () {
    expect(
        queuedEnvelopeLabel(
            '<direct_message event_id="e1" from="agent:mission-control" from_kind="agent">\n<body>Run scrape</body>\n</direct_message>'),
        'Message from mission-control: Run scrape');
    expect(
        queuedEnvelopeLabel(
            '<agent_reply from="agent:mission-control">\n<body>Task is done.</body>\n</agent_reply>'),
        'Reply from mission-control: Task is done.');
    expect(queuedEnvelopeLabel('plain [text]'), isNull);
  });
}
