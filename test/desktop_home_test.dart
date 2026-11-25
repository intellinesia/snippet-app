import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/crew_status.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/desktop_home.dart';

CoordinationAgent _agent(String id,
        {String status = 'active', int needsYou = 0}) =>
    CoordinationAgent.fromJson({
      'id': id,
      'display_name': id == 'sleep' ? 'Sleepy' : id,
      'status': status,
      'needs_you': needsYou,
    });

SessionInfo _session(String id, String agent,
        {bool waiting = false, bool running = false}) =>
    SessionInfo.fromJson({
      'id': id,
      'title': id,
      'agent_id': agent,
      'status': waiting ? 'waiting_for_input' : (running ? 'running' : 'idle'),
      'running': running,
      if (waiting) 'attention': {'type': 'question', 'text': 'Continue?'},
    });

void main() {
  test(
      'bucketing keeps needs and working separate and folds asleep into available',
      () {
    final agents = [
      _agent('need'),
      _agent('work'),
      _agent('idle'),
      _agent('sleep', status: 'asleep'),
    ];
    final sections = deriveHomeSections(
      deriveCrew(agents, [
        _session('ask', 'need', waiting: true),
        _session('run', 'work', running: true),
      ]),
      const [],
    );

    expect(sections.needs.map((e) => e.agent.id), ['need']);
    expect(sections.working.map((e) => e.agent.id), ['work']);
    expect(sections.available.map((e) => e.agent.id), ['idle', 'sleep']);
    expect(sections.groupAsks, isEmpty);
    expect(sections.needsCount, 1);
  });

  test('desktop opt-in buckets daemon-reported agent needs without duplicates',
      () {
    final agents = [
      _agent('flagged', needsYou: 2),
      _agent('both', needsYou: 1),
      _agent('plain'),
    ];
    final sessions = [_session('ask', 'both', waiting: true)];

    final defaultCrew = deriveCrew(agents, sessions);
    expect(defaultCrew[0].state, CrewState.standingBy);

    final sections = deriveHomeSections(
      deriveCrew(agents, sessions, includeAgentNeedsYou: true),
      const [],
    );

    expect(sections.needs.map((e) => e.agent.id), ['flagged', 'both']);
    expect(sections.needsCount, 2);
  });

  test('a direct ask without a backing session can surface as its group ask',
      () {
    final direct = CrewEntry(
      agent: _agent('direct'),
      state: CrewState.needsYou,
      sessions: const [],
      lead: null,
    );
    final backedSession = _session('backed', 'backed', waiting: true);
    final backed = CrewEntry(
      agent: _agent('backed'),
      state: CrewState.needsYou,
      sessions: [backedSession],
      lead: backedSession,
    );
    final group = GroupSummary.fromJson({
      'id': 'g1',
      'title': 'Crew',
      'members': [
        {'kind': 'agent', 'id': 'direct'},
        {'kind': 'agent', 'id': 'backed'},
        {'kind': 'human', 'id': 'me'},
      ],
    });

    final sections = deriveHomeSections([direct, backed], [group]);

    expect(sections.needs.length, 2);
    expect(sections.groupAsks.map((g) => g.id), ['g1']);
    expect(sections.groupWaitingNames['g1'], ['direct']);
    expect(sections.needsCount, 3);
  });
}
