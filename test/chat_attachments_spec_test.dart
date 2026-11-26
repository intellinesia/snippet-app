import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/composer/attachment_tile.dart';
import 'package:snippet/theme.dart';

// v19 CM-04: full-width attachment rows, 56 high, remove target 40.
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
        final remove = t.getSize(find.descendant(of: find.byKey(const Key('a.txt')), matching: find.byWidgetPredicate((w) => w is SizedBox && w.width == 40 && w.height == 40)).first);
        final w = vw - 32;
        // ignore: avoid_print
        print('W $vw x$scale tile=${a.width} x ${a.height}');
        expect(a.width, closeTo(w, 0.1));
        expect(a.height, 56);
        expect(t.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
        expect(remove, const Size(40, 40));
      });
    }
  }
}
