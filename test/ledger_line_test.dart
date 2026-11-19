import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat/ledger_line.dart';
import 'package:snippet/tool_activity.dart';

ToolStep bash(String cmd, {int code = 0}) => ToolStep(
    tool: 'bash',
    args: {'command': cmd},
    result: {'data': {'exit_code': code, 'stdout': ''}});

ToolStep read(String path) =>
    ToolStep(tool: 'read_file', args: {'path': path}, result: {'data': {}});

ToolStep edit(String path, String find, String to) => ToolStep(
    tool: 'change_files',
    args: {
      'changes': [
        {'action': 'replace', 'path': path, 'find': find, 'with': to}
      ]
    },
    result: {'data': {}});

void main() {
  test('consecutive kinds fold into phrases with indices', () {
    final p = ledgerPhrases([
      read('lib/a.dart'),
      read('lib/b.dart'),
      edit('lib/cold_strip.dart', 'a\nb', 'a\nc\nd'),
      bash('flutter test'),
      bash('flutter test'),
    ]);
    expect(p.map((e) => e.text).toList(),
        ['Read 2 files', 'edited cold_strip.dart +2 −1', 'ran tests twice']);
    expect(p[0].indices, [0, 1]);
    expect(p[2].indices, [3, 4]);
  });

  test('a single read names the file; edits across files count them', () {
    expect(ledgerPhrases([read('lib/x/cold_strip.dart')]).single.text,
        'Read cold_strip.dart');
    final p = ledgerPhrases([
      edit('a.dart', 'x', 'y'),
      edit('b.dart', 'x', 'y'),
      edit('c.dart', 'x', 'y'),
    ]);
    expect(p.single.text, 'Edited 3 files');
  });

  test('failures are counted on their phrase and unknown tools are named', () {
    final p = ledgerPhrases([
      bash('make build', code: 2),
      const ToolStep(tool: 'ping_user', args: {}, result: {'data': {}}),
    ]);
    expect(p[0].text, 'Ran a command');
    expect(p[0].failNote, '(1 failed)');
    expect(p[1].text, 'used ping user');
  });
}
