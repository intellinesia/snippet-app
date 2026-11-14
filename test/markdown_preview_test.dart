import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/markdown_preview.dart';
import 'package:snippet/screens/agent_card.dart';

List<(String, TextStyle?)> _runs(InlineSpan span, [TextStyle? up]) {
  final out = <(String, TextStyle?)>[];
  if (span is TextSpan) {
    final s = up == null ? span.style : up.merge(span.style);
    if (span.text != null) out.add((span.text!, s));
    for (final c in span.children ?? const <InlineSpan>[]) {
      out.addAll(_runs(c, s));
    }
  }
  return out;
}

void main() {
  const base = TextStyle(fontSize: 13);

  test('flattens block syntax, keeps inline marks', () {
    expect(flattenMarkdown('## Plan\n- **Me**: tests\n- `scout`: docs'),
        'Plan · **Me**: tests · `scout`: docs');
    expect(flattenMarkdown('Split by strengths: - **Me**: x'),
        'Split by strengths: **Me**: x');
    expect(flattenMarkdown('see [the PR](https://x.y/1)'), 'see the PR');
  });

  test('styles bold, code, italic and strike', () {
    final runs = _runs(markdownPreviewSpan(
        'Latest from **@theo** via `scout`, *soon* ~~old~~ snake_case', base));
    final text = runs.map((r) => r.$1).join();
    expect(text, 'Latest from @theo via scout, soon old snake_case');
    final byText = {for (final r in runs) r.$1: r.$2};
    expect(byText['@theo']!.fontWeight, isNot(FontWeight.w400));
    expect(byText['scout']!.fontFamily, isNotNull);
    expect(byText['soon']!.fontStyle, FontStyle.italic);
    expect(byText['old']!.decoration, TextDecoration.lineThrough);
  });

  test('code nested inside bold', () {
    final runs = _runs(markdownPreviewSpan('**Me (`snippet`)**: tests', base));
    expect(runs.map((r) => r.$1).join(), 'Me (snippet): tests');
    final code = runs.firstWhere((r) => r.$1 == 'snippet').$2!;
    expect(code.fontFamily, isNotNull);
    expect(code.fontWeight, isNot(FontWeight.w400));
  });

  test('status text keeps markdown for rendering', () {
    expect(cleanAgentStatusText('Split:\n- **Me (`snippet`)**: tests'),
        'Split: **Me (`snippet`)**: tests');
  });
}
