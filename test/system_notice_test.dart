import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat/system_notice.dart';

void main() {
  test('handed envelope reads as one line with its note', () {
    final n = parseSystemNotice(
        '<managed_by kind="handed" agent="snippet"><note>The user handed this session to snippet.</note></managed_by>')!;
    expect(n.summary, 'Handed to snippet');
    expect(n.detail, 'The user handed this session to snippet.');
  });

  test('unknown kind degrades to plain text, never tags', () {
    final n = parseSystemNotice(
        '<brand_new_thing id="1"><body>Hello &amp; welcome</body></brand_new_thing>')!;
    expect(n.summary, 'Brand new thing');
    expect(n.detail, 'Hello & welcome');
    expect(n.detail.contains('<'), isFalse);
  });

  test('typed text that starts with a tag is not an envelope', () {
    expect(parseSystemNotice('<div> is the element I meant'), isNull);
    expect(parseSystemNotice('plain words'), isNull);
  });
}
