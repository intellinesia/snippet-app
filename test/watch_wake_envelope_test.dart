import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/mission_control/mission_control_state.dart';

void main() {
  test('parses a watch envelope into name, mode and new lines', () {
    const text = '[watch]\nname: inbox\nwatch_id: w1\nmode: stream\nevent: change\nlines: 2\nheld: 3\n---\nmsg from alice: lunch at 1?\nmsg from bob: PR approved\n---\nnote: your own watch fired.\n[/watch]';
    final w = parseWatchEnvelope(text)!;
    expect(w.name, 'inbox');
    expect(w.mode, 'stream');
    expect(w.event, 'change');
    expect(w.held, 3);
    expect(w.lines, ['msg from alice: lunch at 1?', 'msg from bob: PR approved']);
  });

  test('keeps a --- line inside the output', () {
    const text = '[watch]\nname: x\nmode: poll\nevent: change\nlines: 2\n---\na\n---\n---\nnote: n\n[/watch]';
    expect(parseWatchEnvelope(text)!.lines, ['a', '---']);
  });

  test('extracts the note from a wake envelope', () {
    const text = '[wake]\nYou asked to be woken now (set 2026-11-14T04:18:03Z).\n\nCheck CI on #150.\n\nDo what the note says; schedule_wake again if it still needs waiting.';
    expect(parseWakeNote(text), 'Check CI on #150.');
    expect(parseWakeNote('hello'), isNull);
    expect(parseWatchEnvelope('[wake]\nx'), isNull);
  });
}
