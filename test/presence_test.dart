import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/device_events.dart';
import 'package:snippet/models.dart';
import 'package:snippet/presence.dart';
import 'package:snippet/swr.dart';

Map<String, dynamic> frame(String session, String state,
        {String agent = 'a', String detail = '', int since = 1000}) =>
    {
      'kind': 'agent_presence',
      'session': session,
      'agent': agent,
      'state': state,
      'detail': detail,
      'since': since,
    };

SessionInfo sess(String id, String agent) => SessionInfo.fromJson(
    {'id': id, 'title': id, 'status': 'running', 'agent_id': agent});

void main() {
  late DateTime now;
  PresenceStore store() => PresenceStore(null, () => now);
  setUp(() => now = DateTime.fromMillisecondsSinceEpoch(1010 * 1000));

  test('event parses presence fields and ignores unknown ones', () {
    final e = DeviceEvent.fromJson({...frame('s', 'tool', detail: 'bash'), 'x': 1});
    expect((e.agent, e.state, e.detail, e.since), ('a', 'tool', 'bash', 1000));
    expect(DeviceEvent.fromJson({'kind': 'status'}).since, 0);
  });

  test('ignores other kinds and keeps the latest per session', () {
    final s = store();
    s.handle({'kind': 'status', 'session': 's1', 'state': 'thinking'});
    expect(s.forSession('s1'), isNull);
    s.handle(frame('s1', 'thinking'));
    s.handle(frame('s1', 'typing', since: 1005));
    expect(s.forSession('s1')!.state, 'typing');
    s.handle(frame('s1', 'idle', since: 1008));
    expect(s.forSession('s1'), isNull);
  });

  test('presenceForAgent picks the most recent non-idle', () {
    final s = store();
    s.handle(frame('s1', 'thinking', since: 1000));
    s.handle(frame('s2', 'tool', detail: 'bash', since: 1005));
    s.handle(frame('s3', 'idle', since: 1009));
    s.handle(frame('s4', 'typing', agent: 'b', since: 1009));
    final p = s.presenceForAgent(
        'a', [sess('s1', 'a'), sess('s2', 'a'), sess('s3', 'a'), sess('s4', 'b')]);
    expect(p!.state, 'tool');
    expect(p.detail, 'bash');
    expect(s.presenceForAgent('zzz', [sess('s1', 'a')]), isNull);
  });

  test('stale thinking older than ten minutes is absent', () {
    final s = store();
    s.handle(frame('s1', 'thinking', since: 1000));
    now = DateTime.fromMillisecondsSinceEpoch((1000 + 601) * 1000);
    expect(s.forSession('s1'), isNull);
    s.handle(frame('s2', 'waiting', detail: 'user', since: 1000));
    expect(s.forSession('s2')!.state, 'waiting');
  });

  test('reconnect clears the store', () {
    final s = store();
    s.handle(frame('s1', 'thinking'));
    s.handle({'kind': DeviceEventHub.reconnected});
    expect(s.forSession('s1'), isNull);
  });
}
