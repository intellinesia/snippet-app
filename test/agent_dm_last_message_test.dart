import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';

void main() {
  test('withLastMessage swaps the preview and keeps the agent', () {
    final a = CoordinationAgent.fromJson({
      'id': 'scout',
      'display_name': 'X Scout',
      'last_message': {'text': 'Posted.', 'from': 'agent', 'at': '2026-11-13T08:00:00Z'},
    });
    final dm = a.withLastMessage(AgentLastMessage(
        text: 'can you look at this?',
        fromUser: true,
        at: DateTime.utc(2026, 11, 13, 9)));
    expect(dm.id, 'scout');
    expect(dm.displayName, 'X Scout');
    expect(dm.lastMessage?.text, 'can you look at this?');
    expect(dm.lastMessage?.fromUser, isTrue);
    expect(dm.lastMessage?.at, DateTime.utc(2026, 11, 13, 9));
    expect(a.withLastMessage(null).lastMessage, isNull);
  });
}
