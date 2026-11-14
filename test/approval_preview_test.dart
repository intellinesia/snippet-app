import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/notification_text.dart';

void main() {
  const text =
      '⚠ uses vault secret(s) [APIFY_TOKEN] — TOKEN="\$APIFY_TOKEN" python3 - <<\'PY\' import os,json,urllib.request';

  test('approval preview prefers the call label', () {
    expect(
      approvalPreview({
        'type': 'approval',
        'tool': 'bash',
        'text': text,
        'label': 'Check Apify limits',
      }),
      'Use APIFY_TOKEN: Check Apify limits',
    );
  });

  test('approval preview without a label shows the command', () {
    expect(
      approvalPreview({'type': 'approval', 'tool': 'bash', 'text': text}),
      startsWith('Use APIFY_TOKEN: python3 - <<'),
    );
  });

  test('questions are not approvals', () {
    expect(approvalPreview({'type': 'question', 'text': 'Which one?'}), isNull);
  });
}
