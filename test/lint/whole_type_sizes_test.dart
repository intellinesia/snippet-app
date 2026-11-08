import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _half = RegExp(
    r'(\b(?:sans|display|mono|codeMono|caps|serif)\(\s*|fontSize:\s*)'
    r'(?:kMobile\s*\?\s*[\d.]+\s*:\s*)?\d+\.\d');

void main() {
  test('text sizes are whole pixels', () {
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      final src = lines.join('\n');
      for (final m in _half.allMatches(src)) {
        final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
        hits.add('${f.path}:$line');
      }
    }
    expect(hits, isEmpty, reason: 'Use a TS role or a whole size');
  });
}
