import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/markdown_preview.dart';

void main() {
  const voice = '[attached file — read it at this exact path: /tmp/u/a.m4a]\n\n'
      '[Audio transcript for /tmp/u/a.m4a]\nplacement issue of the pin';

  test('voice notes, photos and files read as labels', () {
    expect(flattenMarkdown(voice), 'Voice note · placement issue of the pin');
    expect(
        flattenMarkdown(
            'fix this\n\n[attached image — call view_image on this exact path to see it: /tmp/u/b.png]'),
        'Photo · fix this');
    expect(
        flattenMarkdown(
            '[attached file — read it at this exact path: /tmp/u/report.pdf]'),
        'File report.pdf');
    expect(
        flattenMarkdown(
            '[attached image — call view_image on this exact path to see it: /tmp/u/b.png]'
            '[attached image — call view_image on this exact path to see it: /tmp/u/c.png]'),
        '2 photos');
    expect(
        flattenMarkdown('[attached file: /tmp/u/v.m4a]\n\n'
            '[Audio transcript for /tmp/u/v.m4a]\nkeep the context'),
        'Voice note · keep the context');
  });

  test('a marker cut off by truncation still reads as a label', () {
    expect(flattenMarkdown('[attached file — read it at this exact path: /tmp/snippet-upl'),
        'File');
  });

  test('titles drop markers and keep the words', () {
    expect(
        describeAttachments(
            'rename to Lobsang\n\n[attached image — call view_image on this exact path to see it: /tmp/u/x.jpg]',
            labels: false),
        'rename to Lobsang');
    expect(describeAttachments('plain', labels: false), 'plain');
  });
}
