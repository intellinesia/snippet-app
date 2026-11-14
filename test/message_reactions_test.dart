import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/message_reactions.dart';
import 'package:snippet/models.dart';

CoordinationEvent _react(String id, String actorKind, String actorId,
        String reaction,
        {bool removed = false}) =>
    CoordinationEvent.fromJson({
      'event_id': id,
      'event_type': 'group_message',
      'actor_kind': actorKind,
      'actor_id': actorId,
      'payload': {
        'body': '',
        'kind': 'reaction',
        'reply_to': 'm1',
        'reaction': reaction,
        if (removed) 'removed': true,
      },
      'idempotency_key': id,
      'created_at': '2026-11-14T10:00:00Z',
    });

void main() {
  test('reactions list who reacted and fold removals', () {
    final events = [
      _react('r1', 'human', 'human', '👍'),
      _react('r2', 'agent', 'x-scout', 'thumbs_up'),
      _react('r3', 'agent', 'scoutie', 'eyes'),
    ];
    var groups = groupMessageReactions(events)['m1']!;
    expect(groups.map((g) => g.name), ['👍', '👀']);
    expect(groups.first.actors.map(reactionActorLabel), ['You', 'x-scout']);
    expect(groups.first.mine, isTrue);

    events.add(_react('r4', 'human', 'human', '👍', removed: true));
    groups = groupMessageReactions(events)['m1']!;
    expect(groups.first.count, 1);
    expect(groups.first.mine, isFalse);

    events.add(_react('r5', 'agent', 'scoutie', 'eyes', removed: true));
    groups = groupMessageReactions(events)['m1']!;
    expect(groups.map((g) => g.name), ['👍']);

    events.add(_react('r6', 'agent', 'x-scout', '👍', removed: true));
    expect(groupMessageReactions(events)['m1'], isNull);
  });
}
