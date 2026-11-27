import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/chat/stage_bar.dart';
import 'package:snippet/chat/stage_header.dart';
import 'package:snippet/composer/chat_composer.dart';
import 'package:snippet/composer/composer_card.dart';
import 'package:snippet/composer/voice_note.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

// v19 D3: composer rest 56 high, radius 28, visual send circle 28 in a 48
// target, bottom 8 above the safe area. v19 XO-03 supersedes the old plain
// chat bar: header card x16 w=W-32 h58 r10, 30 avatar, one trailing icon.
void main() {
  for (final vw in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 1.35, 2.0]) {
      testWidgets('composer and header at $vw x$scale', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(vw, 852);
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(t.view.reset);
        final input = TextEditingController();
        final focus = FocusNode();
        final voice = VoiceNoteController(
            client: DaemonClient('http://127.0.0.1:9', 'tok'));
        var typed = false;
        await t.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          builder: (c, w) => MediaQuery(
              data: MediaQuery.of(c).copyWith(
                  textScaler: TextScaler.linear(scale),
                  padding: const EdgeInsets.only(bottom: 20)),
              child: w!),
          home: Scaffold(
            body: Column(children: [
              StageBar(
                  framed: false,
                  members: const [StageMember('sashy')],
                  title: 'Sashy',
                  subtitle: 'Idle',
                  onTap: () {},
                  onBack: () {}),
              const Spacer(),
              ChatComposer(
                input: input,
                focus: focus,
                hint: 'Reply to Sashy...',
                voice: voice,
                onSend: () => typed = true,
                canSend: () => input.text.isNotEmpty,
                hasDraft: () => input.text.isNotEmpty,
                onAttach: () {},
              ),
            ]),
          ),
        ));
        await t.pump(const Duration(milliseconds: 400));
        final pill = t.getRect(find.byType(ComposerPillSurface));
        final send = t.getRect(find.byType(ComposerSendButton));
        final header = find.byType(StageBar);
        final headerBox = t.getRect(header);
        final backIcon = find.descendant(
            of: header,
            matching: find.byWidgetPredicate(
                (w) => w is AppIcon && w.name == 'arrow-left'));
        final moreIcon = find.descendant(
            of: header,
            matching: find.byWidgetPredicate(
                (w) => w is AppIcon && w.name == 'more-vertical'));
        // ignore: avoid_print
        print('W $vw x$scale pill=$pill send=$send header=$headerBox');
        // Board (Android): a 52 s3 field inset 12, a separate 52 send.
        expect(pill.left, 12);
        expect(send.right, vw - 12);
        expect(pill.right, send.left - 8);
        if (scale == 1.0) expect(pill.height, 52);
        expect(pill.bottom, 852 - 28);
        expect(send.size, const Size(52, 52));
        expect(find.bySemanticsLabel('Send, unavailable'), findsOneWidget);
        expect(headerBox.width, vw);
        expect(headerBox.height, greaterThanOrEqualTo(64));
        expect(backIcon, findsOneWidget);
        expect(moreIcon, findsOneWidget);
        expect(t.takeException(), isNull);
        expect(typed, isFalse);
        // Three lines: the controls drop to a footer row, the pill grows.
        input.text = 'one\ntwo\nthree';
        await t.pump(const Duration(milliseconds: 400));
        final tall = t.getRect(find.byType(ComposerPillSurface));
        // ignore: avoid_print
        print('W $vw x$scale three lines pill height=${tall.height}');
        expect(tall.height, greaterThan(100));
        expect(t.getRect(find.byType(ComposerSendButton)).size, const Size(52, 52));
        expect(t.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
