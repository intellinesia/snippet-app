import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';

class _Client extends DaemonClient {
  _Client(this.total) : super('https://daemon.invalid', 'tok');
  final int total;
  final calls = <int>[];

  @override
  Future<List<CoordinationEvent>> groupEvents(String id,
      {int after = 0, int limit = 100}) async {
    calls.add(after);
    return [
      for (var s = after + 1; s <= total && s <= after + limit; s++)
        CoordinationEvent.fromJson({
          'event_id': 'e$s',
          'thread_id': id,
          'sequence': s,
          'event_type': 'group_message',
          'actor_kind': 'agent',
          'actor_id': 'a',
          'payload': {'body': 'm$s'},
          'created_at': '2026-11-14T00:00:00Z',
        }),
    ];
  }
}

void main() {
  test('a group thread loads through to its newest event', () async {
    final c = _Client(1116);
    final all = await c.groupEventsAll('group:x');
    expect(all.length, 1116);
    expect(all.last.sequence, 1116);
    expect(c.calls, [0, 500, 1000]);
  });
}
