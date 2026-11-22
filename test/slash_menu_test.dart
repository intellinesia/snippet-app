import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/composer/slash_menu.dart';

List<SlashItem> items({bool goal = false, bool mc = false}) => slashItems(
    goalOngoing: goal, isMc: mc, resumeMode: 'ask', settleOn: true);

void main() {
  group('parseSlash', () {
    test('start of input and after whitespace', () {
      expect(parseSlash('/', 1)!.query, '');
      expect(parseSlash('/com', 4)!.query, 'com');
      final q = parseSlash('hello /fo', 9)!;
      expect(q.query, 'fo');
      expect(q.start, 6);
    });
    test('no match mid-word or past the caret', () {
      expect(parseSlash('a/b', 3), isNull);
      expect(parseSlash('/fork now', 9), isNull);
      expect(parseSlash('/fork', 0), isNull);
    });
    test('goal text is split off', () {
      final q = parseSlash('/goal ship it', 13)!;
      expect(q.query, 'goal');
      expect(q.rest, 'ship it');
      expect(q.start, 0);
      expect(parseSlash('/goal ', 6)!.rest, '');
    });
  });

  group('filterSlash', () {
    test('matches label and command', () {
      expect(filterSlash(items(), 'comp').map((i) => i.command), ['/compact']);
      expect(filterSlash(items(), 'resume').single.cmd, SlashCmd.resume);
      expect(filterSlash(items(), 'zzz'), isEmpty);
    });
    test('wakes only for Lead; goal label flips', () {
      expect(items().any((i) => i.cmd == SlashCmd.wakes), isFalse);
      expect(items(mc: true).any((i) => i.cmd == SlashCmd.wakes), isTrue);
      expect(items(goal: true).first.label, 'Cancel goal');
    });
  });

  test('formatTokens', () {
    expect(formatTokens(131000), '~131k');
    expect(formatTokens(900), '~900');
  });
}
