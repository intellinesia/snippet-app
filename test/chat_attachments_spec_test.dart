import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/composer/attachment_tile.dart';
import 'package:snippet/theme.dart';

// Spec C CH-07: tiles 161.5 x 118 in a two column tray, remove target 48.
void main() {
  for (final vw in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 1.35, 2.0]) {
      testWidgets('attachment tray at $vw x$scale', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(vw, 852);
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(t.view.reset);
        ComposerAttachmentTile tile(String n) => ComposerAttachmentTile(
            key: Key(n),
            name: n,
            isImage: false,
            isAudio: false,
            uploading: false,
            sizeBytes: 4012,
            onRemove: () {});
        await t.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          builder: (c, w) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: w!),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ComposerAttachmentBar(
                  tiles: [tile('a.txt'), tile('b.txt'), tile('c.txt')]),
            ),
          ),
        ));
        final a = t.getRect(find.byKey(const Key('a.txt')));
        final remove = t.getSize(find.descendant(of: find.byKey(const Key('a.txt')), matching: find.byWidgetPredicate((w) => w is SizedBox && w.width == 48 && w.height == 48)).first);
        final w = vw - 32;
        // ignore: avoid_print
        print('W $vw x$scale tile=${a.width} x ${a.height}');
        expect(a.width, closeTo((w - 28 - 10) / 2, 0.1));
        if (scale == 1.0) expect(a.height, 118);
        expect(a.height, greaterThanOrEqualTo(118));
        expect(t.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
        expect(remove, const Size(48, 48));
      });
    }
  }
}
