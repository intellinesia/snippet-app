import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/composer/attachment_hover_preview.dart';

void main() {
  test('meta line combines type from extension and size', () {
    expect(attachmentMetaLine(name: 'a.PNG', sizeBytes: 1258291),
        'PNG image · 1.2 MB');
    expect(attachmentMetaLine(name: 'r.pdf', sizeBytes: 225280),
        'PDF · 220 KB');
    expect(attachmentMetaLine(name: 'r.pdf'), 'PDF');
    expect(attachmentMetaLine(name: 'p', pastedText: 'a\nb'), 'Text · 2 lines');
  });
}
