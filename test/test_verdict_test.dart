import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';
import 'package:snippet/tool_activity.dart';

ToolStep bash(String command, {int code = 0, String stdout = ''}) => ToolStep(
      tool: 'bash',
      args: {'command': command},
      result: {
        'status': 'ok',
        'data': {'exit_code': code, 'stdout': stdout},
      },
    );

void main() {
  test('piped flutter test with failures reads as failed', () {
    final s = bash('flutter test 2>&1 | tail -3',
        stdout: '00:04 +793 -1: Some tests failed.\n');
    expect(verifyOutputFailed(s), isTrue);
    expect(describeWork([s]).outcome, 'failed');
    final chip = stepChip(s)!;
    expect(chip.text, '793 passed, 1 failed');
    expect(chip.tone, StepChipTone.danger);
  });

  test('cargo failure in a later block is not hidden by a 0 failed block', () {
    final s = bash('cargo test 2>&1 | grep "test result"',
        stdout: 'test result: ok. 0 passed; 0 failed; 0 ignored\n'
            'test result: FAILED. 816 passed; 1 failed; 13 ignored\n');
    expect(describeWork([s]).outcome, 'failed');
    expect(stepChip(s)!.text, '816 passed, 1 failed');
  });

  test('a bare failure line with no counts still fails', () {
    final s = bash('cpu-slot flutter test test/a_test.dart | tail -1',
        stdout: 'Test failed. See exception logs above.\n');
    expect(describeWork([s]).outcome, 'failed');
    expect(stepChip(s)!.tone, StepChipTone.danger);
  });

  test('a clean run still passes', () {
    final s = bash('flutter test', stdout: '00:03 +12: All tests passed!\n');
    expect(verifyOutputFailed(s), isFalse);
    expect(describeWork([s]).outcome, 'passed');
    expect(stepChip(s)!.tone, StepChipTone.ok);
  });

  test('"0 failed" alone is a pass', () {
    final s = bash('cargo test',
        stdout: 'test result: ok. 40 passed; 0 failed; 0 ignored\n');
    expect(describeWork([s]).outcome, 'passed');
    expect(stepChip(s)!.text, '40 passed');
  });
}
