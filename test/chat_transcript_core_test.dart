import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide testWidgets;
import 'package:flutter_test/flutter_test.dart' as flutter_test
    show testWidgets;
import 'package:snippet/chat/group_notice.dart';
import 'package:snippet/chat/group_post.dart';
import 'package:snippet/chat/run_head.dart';
import 'package:snippet/chat/system_notice.dart';
import 'package:snippet/message_reactions.dart';
import 'package:snippet/theme.dart';

// Desktop transcript core, spec_desktop_chat section 1 (MSG-01..18).
void main() {
  // Desktop layout; the override is reset inside each body, as the binding
  // checks it before tearDown.
  void testWidgets(String name, WidgetTesterCallback body) =>
      flutter_test.testWidgets(name, (t) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          await body(t);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

  Future<void> pump(WidgetTester t, Widget child, {double width = 720}) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1440, 900);
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [child]),
          ),
        ),
      ),
    ));
    await t.pump();
  }

  testWidgets('MSG-02 post: avatar 24, name and body at x+36, body col-40',
      (t) async {
    await pump(
      t,
      SoftLane(
        agentId: 'buddy',
        name: 'Buddy',
        time: '11:08',
        child: Text('word ' * 300, key: const Key('body')),
      ),
    );
    final name = t.getRect(find.text('Buddy'));
    final body = t.getRect(find.byKey(const Key('body')));
    expect(name.left, 36);
    expect(body.left, 36);
    expect(body.width, lessThanOrEqualTo(720 - 40));
    final nameStyle = t.widget<Text>(find.text('Buddy')).style!;
    expect(nameStyle.fontSize, 13);
    expect(nameStyle.fontWeight, FontWeight.w500);
    expect(nameStyle.color, AppColors.fg1);
    final time = t.widget<Text>(find.text('11:08')).style!;
    expect(time.fontSize, 11);
    expect(time.color, AppColors.fg3);
    expect(t.getRect(find.text('11:08')).left, greaterThan(name.right));
  });

  testWidgets('MSG-02 streaming caret, muted pill and selected plate',
      (t) async {
    await pump(
      t,
      const SoftLane(
        agentId: 'buddy',
        name: 'Buddy',
        streaming: true,
        muted: true,
        selected: true,
        child: Text('Booting Xvfb now'),
      ),
    );
    expect(find.byType(StreamingCaret), findsOneWidget);
    expect(find.text('Muted'), findsOneWidget);
    expect(t.widget<Text>(find.text('Buddy')).style!.color, AppColors.fg2);
    final plate = t.widget<DecoratedBox>(find
        .descendant(
            of: find.byType(SelectedPlate), matching: find.byType(DecoratedBox))
        .first);
    final d = plate.decoration as BoxDecoration;
    expect(d.color, AppColors.surface2);
    expect(d.borderRadius, BorderRadius.circular(10));
  });

  testWidgets('MSG-01 your bubble: s2 radius 8, pad 12x8, at most 360',
      (t) async {
    await pump(
        t,
        Align(
          alignment: Alignment.centerRight,
          child: SoftBubble(
              mine: true, child: Text('word ' * 200, key: const Key('b'))),
        ));
    final box = find.descendant(
        of: find.byType(SoftBubble), matching: find.byType(Container));
    final c = t.widget<Container>(box.first);
    final d = c.decoration as BoxDecoration;
    expect(d.color, AppColors.surface2);
    expect(d.borderRadius, BorderRadius.circular(8));
    expect(d.border, isNull);
    expect(c.padding,
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8));
    expect(t.getSize(box.first).width, 360);
  });

  testWidgets('MSG-01 meta: sending, read and failed with a 28 Retry',
      (t) async {
    var retried = false;
    await pump(
      t,
      Column(children: [
        const SentMeta(time: '11:06', state: SendState.sending),
        const SentMeta(time: '11:06', read: 'Read 11:06'),
        SentMeta(
            time: '11:06',
            state: SendState.failed,
            onRetry: () => retried = true),
      ]),
    );
    expect(find.text('Sending'), findsOneWidget);
    expect(find.text('Read 11:06'), findsOneWidget);
    expect(find.text('Not delivered'), findsOneWidget);
    final retry = find.widgetWithText(ChatButton, 'Retry');
    expect(t.getSize(retry).height, 28);
    await t.tap(retry);
    expect(retried, isTrue);
  });

  testWidgets('MSG-03 long post clamps at 8 lines with a 28 Show more',
      (t) async {
    final long = List.generate(20, (i) => 'Line $i').join('\n');
    await pump(
      t,
      CappedProse(
          body: long,
          builder: (text) => Text(text,
              style: const TextStyle(fontSize: 13, height: 19 / 13))),
    );
    await t.pump();
    final more = find.widgetWithText(ChatButton, 'Show more (8+ lines)');
    expect(more, findsOneWidget);
    expect(t.getSize(more).height, 28);
    expect(t.getSize(find.text(long)).height, greaterThan(kPostClampHeight));
    await t.tap(more);
    await t.pump();
    expect(find.widgetWithText(ChatButton, 'Show less'), findsOneWidget);
  });

  testWidgets('MSG-03 group header: name at x+36, 13/500', (t) async {
    await pump(t,
        const GroupPostHeader(agentId: 'buddy', name: 'Buddy', time: '11:08'));
    expect(t.getRect(find.text('Buddy')).left, 36);
    expect(t.widget<Text>(find.text('11:08')).style!.fontSize, 11);
  });

  testWidgets('MSG-05 chips: 24 high, own is s3, overflow folds to +n',
      (t) async {
    final groups = [
      for (var i = 0; i < 7; i++)
        ReactionGroup(
            name: ['👍', '👀', '✅', '😂', '❤️', '🎉', '🔥'][i],
            count: i + 1,
            mine: i == 0,
            actors: const ['human:me']),
    ];
    await pump(t, DeskReactionRow(reactions: groups, onReact: (_) {}));
    final chips = find.byType(DeskReactionChip);
    // Four chips, the +3 pill and the add chip.
    expect(chips, findsNWidgets(6));
    for (final e in chips.evaluate()) {
      expect(t.getSize(find.byWidget(e.widget)).height, 24);
    }
    expect(find.text('+3'), findsOneWidget);
    expect(t.getSize(find.widgetWithText(DeskReactionChip, '+3')).width, 40);
  });

  testWidgets('MSG-06 quoted reply: 34 high s2 card, deleted original',
      (t) async {
    await pump(
      t,
      const Column(children: [
        QuotedReplyLine(text: 'Redo group and session chat', author: 'You'),
        QuotedReplyLine(text: 'm9', deleted: true),
      ]),
    );
    expect(t.getSize(find.byType(QuotedReplyLine).first).height, 34);
    expect(find.text('Replying to You:'), findsOneWidget);
    expect(find.text('Original message deleted'), findsOneWidget);
    expect(find.text('m9'), findsNothing);
  });

  testWidgets('MSG-07 pending reply: one 32 strip, 28 clear target', (t) async {
    var cleared = false;
    await pump(
      t,
      PendingReplyBanner(
          author: 'Buddy',
          text: 'Landed the TextPainter cache',
          onClear: () => cleared = true),
    );
    expect(find.text('Replying to Buddy: Landed the TextPainter cache'),
        findsOneWidget);
    expect(t.getSize(find.byType(PendingReplyBanner)).height, 32 + 6);
    final x = find.bySemanticsLabel('Clear reply');
    expect(t.getSize(x).height, 28);
    await t.tap(x);
    expect(cleared, isTrue);
  });

  testWidgets('MSG-11/12 notice: 28 line, icon x+7, text x+22, expands',
      (t) async {
    final n = parseSystemNotice(
        '<session_stopped session="s1" title="Visual QA" status="stopped" /> · <last_said>Capturing light frames</last_said> · <note>quota hit</note>')!;
    await pump(t, SystemNoticeLine(notice: n));
    final text = find.text('Visual QA stopped');
    expect(t.getRect(text).left, 22);
    final icon = find.byType(Icon).first;
    expect(t.getRect(icon).left, 7);
    expect(t.getSize(icon).width, 14);
    expect(t.getSize(find.byType(SystemNoticeLine)).height,
        greaterThanOrEqualTo(28));
    final style = t.widget<Text>(text).style!;
    expect(style.fontSize, 12);
    expect(style.color, AppColors.fg2);
    await t.tap(text);
    await t.pump();
    expect(find.textContaining('Capturing light frames', findRichText: true),
        findsOneWidget);
    expect(
        find.textContaining('quota hit', findRichText: true), findsOneWidget);
  });

  test('goal notices are void', () {
    expect(parseSystemNotice('<goal id="g1"><note>Ship</note></goal>'), isNull);
    expect(
        parseSystemNotice('<goal_done id="g1"><note>Ship</note></goal_done>'),
        isNull);
  });

  testWidgets('MSG-22 group notice: centred 28 line', (t) async {
    await pump(
        t,
        const GroupNotice(
            text: "Lead approved Sashy's plan",
            kind: GroupNoticeKind.approved));
    expect(
        t.getSize(find.byType(GroupNotice)).height, greaterThanOrEqualTo(28));
    final r = t.getRect(find.text("Lead approved Sashy's plan"));
    expect(r.center.dx, greaterThan(360 - 20));
  });
}
