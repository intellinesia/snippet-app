import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/group_messaging.dart';

GroupSummary _g(List<String> agents, {List<String> replying = const [], Map? turn}) =>
    GroupSummary.fromJson({
      'id': 'group:1',
      'title': 't',
      'members': [for (final a in agents) {'kind': 'agent', 'id': a}],
      'replying': replying,
      if (turn != null) 'turn': turn,
    });

void main() {
  String name(String id) => id.toUpperCase();

  test('nothing in flight shows no status', () {
    expect(groupActivityStatus(_g(['a', 'b']), name), isNull);
  });

  test('the turn holder wins when several agents share the room', () {
    final g = _g(['a', 'b'], replying: ['b'], turn: {'agent': 'a', 'since': 1});
    expect(groupActivityStatus(g, name), 'A has the turn');
  });

  test('a lone agent never shows the turn', () {
    final g = _g(['a'], turn: {'agent': 'a', 'since': 1});
    expect(groupActivityStatus(g, name), isNull);
  });

  test('replying names one, two, then counts the rest', () {
    expect(groupActivityStatus(_g(['a'], replying: ['a']), name), 'A is replying');
    expect(groupActivityStatus(_g(['a', 'b'], replying: ['a', 'b']), name),
        'A and B are replying');
    expect(
        groupActivityStatus(_g(['a', 'b', 'c', 'd'], replying: ['a', 'b', 'c', 'd']), name),
        'A, B and 2 more are replying');
  });
}
