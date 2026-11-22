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
    expect(parseSystemNotice('<b>hi</b> there'), isNull);
    expect(parseSystemNotice('plain words'), isNull);
  });

  test('session_no_reply formats cleanly with note', () {
    final n = parseSystemNotice(
        '<session_no_reply session="s1"><note>the work ended without replying.</note></session_no_reply>')!;
    expect(n.summary, 'Session ended without replying');
    expect(n.detail, 'the work ended without replying.');
    expect(n.detail.contains('<'), isFalse);
  });

  test('concatenated session_stopped with sibling fragments merges cleanly', () {
    final n = parseSystemNotice(
        '<session_stopped session="s1" title="Build" status="idle" /> · <last_said>All done</last_said> · <note>message.send reaches it.</note>')!;
    expect(n.summary, 'Build idle');
    expect(n.detail, 'All done\n\nmessage.send reaches it.');
    expect(n.detail.contains('<'), isFalse);

    final unclosed = parseSystemNotice(
        '<session_stopped session="s1" title="Build" status="stopped"> · <last_said>Wrapped up</last_said> · <note>Follow up if needed.</note>')!;
    expect(unclosed.summary, 'Build stopped');
    expect(unclosed.detail, 'Wrapped up\n\nFollow up if needed.');
  });

  test('multiple joined top-level envelopes combine summaries and details', () {
    final n = parseSystemNotice(
        '<session_stopped session="s1" title="Build" status="idle"><last_said>Done</last_said></session_stopped> · <session_no_reply session="s2"><note>No reply from s2</note></session_no_reply>')!;
    expect(n.summary, 'Build idle · Session ended without replying');
    expect(n.detail, 'Done\n\nNo reply from s2');
    expect(n.detail.contains('<'), isFalse);
  });
}
