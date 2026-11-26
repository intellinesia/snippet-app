import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:snippet/widgets.dart' show IconBtn, MarkdownBody;
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat/chat_style.dart';
import 'package:snippet/markdown_widgets.dart';
import 'package:snippet/theme.dart';

// v19 RC-12: code block at W, 36-high header/copy affordance, scrolls horizontally.
void main() {
  for (final vw in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 1.35, 2.0]) {
      testWidgets('code block at $vw x$scale', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(vw, 852);
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(t.view.reset);
        await t.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          builder: (c, w) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: w!),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Builder(
                builder: (c) => MarkdownBody(
                  data:
                      '```dart\nvoid main() { print("a very long line that must scroll sideways and never wrap"); }\n```',
                  styleSheet: chatMarkdownStyle(c, mine: false),
                  builders: {'pre': PreBlockBuilder()},
                ),
              ),
            ),
          ),
        ));
        final copy = t.widget<IconBtn>(find
            .descendant(
                of: find.byType(MarkdownBody), matching: find.byType(IconBtn))
            .first);
        final scroller = t.getRect(find.byType(SingleChildScrollView).first);
        // ignore: avoid_print
        print('W $vw x$scale copy=$copy block=${scroller.width}');
        expect(copy.iconSize, 14);
        expect(scroller.width, vw - 56);
        expect(t.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
