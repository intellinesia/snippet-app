import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat_links.dart';

void main() {
  test('agent, thread and task links parse to their ids', () {
    expect(parseChatLink('agent:mobile-design'),
        (kind: ChatLinkKind.agent, id: 'mobile-design'));
    expect(parseChatLink('thread:group:3f2a-11'),
        (kind: ChatLinkKind.thread, id: 'group:3f2a-11'));
    expect(parseChatLink('thread:direct:agent:snippet|human:local'),
        (kind: ChatLinkKind.thread, id: 'direct:agent:snippet|human:local'));
    expect(parseChatLink('thread:direct:agent%3Asnippet%7Chuman%3Alocal'),
        (kind: ChatLinkKind.thread, id: 'direct:agent:snippet|human:local'));
    expect(parseChatLink('task:bca39e5d'),
        (kind: ChatLinkKind.task, id: 'bca39e5d'));
    expect(parseChatLink('task:task:bca39e5d'),
        (kind: ChatLinkKind.task, id: 'bca39e5d'));
  });

  test('other hrefs and empty ids are not chat links', () {
    for (final href in [
      null,
      '',
      'session:abc',
      'artifact:s/a@1',
      'https://example.com',
      'agent:',
      'task: ',
      'agent:two words',
      'notes.md',
    ]) {
      expect(parseChatLink(href), isNull, reason: href);
    }
  });
}
