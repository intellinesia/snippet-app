import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/transcript.dart';

Map<String, dynamic> _e(String kind, [int? ms]) =>
    {'kind': kind, if (ms != null) 'at_ms': ms};

void main() {
  test('a run is timed from the message before it to the reply after it', () {
    final events = [
      _e('user_input', 1000),
      _e('tool_call', 3000),
      _e('tool_result', 9000),
      _e('assistant_text', 43000),
    ];
    expect(transcriptRunDuration(events, 1, 3), const Duration(seconds: 42));
  });

  test('without a closing reply the run ends at its own last stamp', () {
    final events = [
      _e('assistant_text', 1000),
      _e('tool_call', 2000),
      _e('tool_result', 6000),
      _e('user_input', 900000),
    ];
    expect(transcriptRunDuration(events, 1, 3), const Duration(seconds: 5));
  });

  test('unstamped or sub-second runs have no duration', () {
    expect(
        transcriptRunDuration(
            [_e('user_input'), _e('tool_call'), _e('assistant_text')], 1, 2),
        isNull);
    expect(
        transcriptRunDuration([
          _e('user_input', 1000),
          _e('tool_call', 1200),
          _e('assistant_text', 1500)
        ], 1, 2),
        isNull);
  });

  testWidgets('the fold label uses the stamped duration', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: CollapsedActivity(const [
          DenseToolRow(
              tool: 'read_file',
              args: {'path': 'a.dart'},
              result: {'status': 'ok'}),
        ], took: const Duration(seconds: 42)),
      ),
    ));
    // Phone lists the steps in full (board); the stamped duration rides
    // the fold's semantics summary instead of a visible label.
    expect(find.byType(QuietStepLine), findsOneWidget);
  });
}
