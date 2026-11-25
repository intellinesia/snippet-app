import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat/chat_style.dart';
import 'package:snippet/chat/desktop_rich_cards.dart';
import 'package:snippet/markdown_widgets.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart' show MarkdownBody;

Widget _shell(Widget child, {double width = 560}) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: child,
          ),
        ),
      ),
    );

void desktopTestWidgets(
    String description, Future<void> Function(WidgetTester t) body) {
  testWidgets(description, (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(900, 700);
    try {
      await body(t);
    } finally {
      t.view.reset();
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  desktopTestWidgets(
      'desktop file chip, voice row, and action use locked heights', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(900, 700);
    await t.pumpWidget(_shell(Column(mainAxisSize: MainAxisSize.min, children: [
      const DesktopFileChip(
          icon: 'file-text', name: 'report.pdf', sizeLabel: '1.2 MB'),
      const SizedBox(height: 8),
      const DesktopVoiceNoteRow(durationLabel: '0:12'),
      const SizedBox(height: 8),
      DesktopRichButton('Open', onTap: () {}),
    ])));
    expect(t.getSize(find.byType(DesktopFileChip)).height, 28);
    expect(
        t.getSize(find.byType(DesktopFileChip)).width, lessThanOrEqualTo(320));
    expect(t.getSize(find.byType(DesktopVoiceNoteRow)).height, 48);
    expect(t.getSize(find.byType(DesktopRichButton)).height, 28);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('1.2 MB'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  desktopTestWidgets(
      'desktop draft card exposes use and dismiss 28-point actions', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(900, 700);
    var used = 0;
    var dismissed = 0;
    await t.pumpWidget(_shell(DesktopDraftBlock(
      text: 'A quiet draft reply',
      onUse: () => used++,
      onDismiss: () => dismissed++,
    )));
    expect(find.text('Draft'), findsOneWidget);
    expect(find.text('Use draft'), findsOneWidget);
    await t.tap(find.text('Use draft'));
    await t.tap(find.text('Dismiss'));
    expect(used, 1);
    expect(dismissed, 1);
    expect(t.getSize(find.text('Use draft')).height, greaterThan(0));
    expect(t.takeException(), isNull);
  });

  desktopTestWidgets(
      'desktop markdown code block uses surface card and 28-hit tools',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(900, 700);
    await t.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Builder(
            builder: (c) => MarkdownBody(
              data: '```dart\nvoid main() { print("hello"); }\n```',
              styleSheet: chatMarkdownStyle(c, mine: false),
              builders: {'pre': PreBlockBuilder()},
            ),
          ),
        ),
      ),
    ));
    expect(find.text('dart'), findsOneWidget);
    expect(find.byTooltip('Copy'), findsOneWidget);
    final targets = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 28 && w.height == 28);
    expect(targets, findsAtLeastNWidgets(2));
    expect(t.takeException(), isNull);
  });

  desktopTestWidgets('proposed PR and commit cards render exact state words',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(900, 700);
    await t.pumpWidget(_shell(Column(mainAxisSize: MainAxisSize.min, children: [
      const DesktopPullRequestCard(
        number: 42,
        title: 'Tighten desktop cards',
        state: DesktopPullRequestState.checksFailing,
        checksPassed: 2,
        checksTotal: 4,
      ),
      const SizedBox(height: 8),
      const DesktopCommitCard(
          hash: 'abc1234', message: 'Align desktop rich cards'),
    ])));
    expect(find.text('PR #42 Tighten desktop cards'), findsOneWidget);
    expect(find.text('checks 2/4 · Checks failing'), findsOneWidget);
    expect(find.text('abc1234'), findsOneWidget);
    expect(find.text('Align desktop rich cards'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
