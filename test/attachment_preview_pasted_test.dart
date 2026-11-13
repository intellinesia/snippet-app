import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/composer/attachment_preview.dart';

Future<void> _run(WidgetTester t, TargetPlatform p, Size size) async {
  debugDefaultTargetPlatformOverride = p;
  try {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final text = List.generate(48, (i) => 'line $i ${'x' * 60}').join('\n');
    var removed = 0;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () => showAttachmentPreview(
            c,
            [PreviewAttachment(name: 'Pasted', pastedText: text)],
            0,
            onRemove: (_) => removed++,
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('Pasted text'), findsOneWidget);
    expect(find.text('48 lines · ${(text.length / 1024).toStringAsFixed(1)} KB'),
        findsOneWidget);
    expect(find.text('Insert as text'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.textContaining('characters'), findsNothing);
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(find.text('Done'), findsNothing);
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  testWidgets('desktop pasted preview', (t) async {
    await _run(t, TargetPlatform.linux, const Size(1280, 800));
  });
  testWidgets('phone pasted preview', (t) async {
    await _run(t, TargetPlatform.android, const Size(390, 844));
  });
}
