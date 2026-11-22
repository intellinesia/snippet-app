import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/tool_surface.dart';

void main() {
  test('grouped calls lower to the internal tool and their results follow', () {
    final events = <Map<String, dynamic>>[
      {
        'kind': 'tool_call',
        'tool_name': 'mcp__snippet__process',
        'arguments': {'action': 'watch', 'path': 'a.log'},
      },
      {'kind': 'tool_result', 'tool_name': 'mcp__snippet__process', 'result': {}},
      {
        'kind': 'tool_call',
        'tool_name': 'wake',
        'arguments': {'action': 'every', 'op': 'set', 'name': 'x'},
      },
    ];
    lowerToolEvents(events);
    expect(events[0]['tool_name'], 'monitor');
    expect(events[0]['arguments'], {'path': 'a.log', 'action': 'add'});
    expect(events[1]['tool_name'], 'monitor');
    expect(events[2]['tool_name'], 'wake_schedule');
    expect(events[2]['arguments'], {'name': 'x', 'action': 'set'});
  });

  test('a result in a later frame finds its call in prior events', () {
    final prior = lowerToolEvents([
      {
        'kind': 'tool_call',
        'tool_name': 'web',
        'arguments': {'action': 'search', 'query': 'q'},
      },
    ]);
    final added = [
      <String, dynamic>{'kind': 'tool_result', 'tool_name': 'web'},
    ];
    lowerToolEvents(added, prior: prior);
    expect(added[0]['tool_name'], 'web_search');
  });

  test('unknown actions and plain tools pass through', () {
    final events = <Map<String, dynamic>>[
      {'kind': 'tool_call', 'tool_name': 'read', 'arguments': {'path': 'x'}},
      {'kind': 'tool_call', 'tool_name': 'bash', 'arguments': {'command': 'ls'}},
    ];
    lowerToolEvents(events);
    expect(events[0]['tool_name'], 'read');
    expect(events[1]['tool_name'], 'bash');
  });

  test('internal names from newer daemons keep their name, args still lower', () {
    final events = <Map<String, dynamic>>[
      {
        'kind': 'tool_call',
        'tool_name': 'monitor',
        'surface_tool': 'process',
        'arguments': {'action': 'watch', 'path': 'a'},
      },
      {
        'kind': 'tool_call',
        'tool_name': 'monitor',
        'surface_tool': 'process',
        'arguments': {'action': 'add', 'path': 'a'},
      },
    ];
    lowerToolEvents(events);
    expect(events[0]['arguments'], {'path': 'a', 'action': 'add'});
    expect(events[1]['arguments'], {'action': 'add', 'path': 'a'});
  });
}
