import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/file_viewer.dart' show fileCrumbs;

void main() {
  test('home folds to ~ and short paths show in full', () {
    expect(fileCrumbs('/home/snippet/code/app/lib/a.dart'),
        ['~', '…', 'app', 'lib', 'a.dart']);
    expect(fileCrumbs('/Users/me/notes.md'), ['~', 'notes.md']);
    expect(fileCrumbs('/home/snippet/code/x.dart'), ['~', 'code', 'x.dart']);
  });

  test('id-like folders fold into the ellipsis', () {
    expect(
        fileCrumbs('/tmp/claude-1001/-home-snippet-code-snippet-mobile/'
            '8ae2cc54-05a2-4f8a-be69-850664a8fe73/scratchpad/render-files.png'),
        ['tmp', '…', 'scratchpad', 'render-files.png']);
  });

  test('expanded shows every segment', () {
    expect(fileCrumbs('/home/u/a/b/c/d.txt', expanded: true),
        ['~', 'a', 'b', 'c', 'd.txt']);
  });
}
