import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/crew_status.dart';
import 'package:snippet/models.dart';
import 'package:snippet/presence.dart';

SessionInfo s(String id,
        {String? agent,
        String? worker,
        String status = 'idle',
        bool run = false,
        int at = 0,
        Map<String, dynamic>? ask}) =>
    SessionInfo.fromJson({
      'id': id,
      'title': id,
      'status': run ? 'running' : status,
      'running': run,
      'last_active': at,
      'agent_id': agent,
      'worker_agent_id': worker,
      if (ask != null) 'attention': ask,
    });

CoordinationAgent a(String id) =>
    CoordinationAgent.fromJson({'id': id, 'display_name': id});

void main() {
  presenceCases();
  test('status is derived from sessions only', () {
    final crew = deriveCrew([
      a('r'),
      a('w'),
      a('i'),
      a('x')
    ], [
      s('s1',
          agent: 'r',
          status: 'waiting_for_input',
          ask: {'type': 'approval', 'text': 'Run it?'}),
      s('s2', worker: 'w', run: true),
      s('s3', agent: 'i'),
      s('s4', status: 'waiting_for_input'),
    ]);
    expect(crew.map((e) => e.state), [
      CrewState.needsYou,
      CrewState.working,
      CrewState.standingBy,
      CrewState.standingBy,
    ]);
    expect(crew[0].line, 'Run it?');
    expect(crew[0].isApproval, isTrue);
    expect(crew[3].lead, isNull);
    expect(crewSummary(crew), '1 waiting on you · 1 active task');
  });

  test('worker wins over owner and needs-you outranks working', () {
    final crew = deriveCrew([
      a('r'),
      a('o')
    ], [
      s('s1', agent: 'o', worker: 'r', run: true),
      s('s2', agent: 'r', status: 'waiting_for_input', at: 5),
    ]);
    expect(crew[0].state, CrewState.needsYou);
    expect(crew[0].sessions.map((x) => x.id), ['s2', 's1']);
    expect(crew[0].extra, 1);
    expect(crew[1].state, CrewState.standingBy);
  });
}

void presenceCases() {
  final now = DateTime.fromMillisecondsSinceEpoch(1010 * 1000);
  PresenceStore store(Map<String, dynamic> f) =>
      PresenceStore(null, () => now)..handle({'kind': 'agent_presence', 'agent': 'w', 'since': 1005, ...f});

  test('tool presence shows Running with detail on a working agent', () {
    final p = store({'session': 's2', 'state': 'tool', 'detail': 'bash'});
    final e = deriveCrew([a('w')], [s('s2', worker: 'w', run: true)], presence: p).single;
    expect(e.presenceWord, 'Running');
    expect(e.presenceDetail, 'bash');
    expect(e.line, 'Running bash');
  });

  test('waiting on user presence makes the agent needsYou', () {
    final p = store({'session': 's2', 'state': 'waiting', 'detail': 'user'});
    final e = deriveCrew([a('w')], [s('s2', worker: 'w', run: true)], presence: p).single;
    expect(e.state, CrewState.needsYou);
  });

  test('without presence the line is the session title', () {
    final e = deriveCrew([a('w')], [s('s2', worker: 'w', run: true)]).single;
    expect(e.line, 's2');
    expect(e.presenceWord, isNull);
  });
}
