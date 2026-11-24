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

// Spec C section G: composer rest 56 high, radius 24, send circle 44 in a 48
// target, bottom 8 above the safe area; header back 48 at x0, avatar 32 at x56.
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
        final back = t.getRect(find.byTooltip('Back'));
        final more = t.getRect(find.byTooltip('More'));
        // ignore: avoid_print
        print('W $vw x$scale pill=$pill send=$send back=$back more=$more');
        expect(pill.left, 16);
        expect(pill.right, vw - 16);
        if (scale == 1.0) expect(pill.height, 56);
        expect(pill.bottom, 852 - 28);
        expect(send.size, const Size(48, 48));
        expect(t.getSize(find.descendant(
            of: find.byType(ComposerSendButton),
            matching: find.byType(SizedBox)).at(1)), const Size(44, 44));
        expect(find.bySemanticsLabel('Send, unavailable'), findsOneWidget);
        expect(back.left, 0);
        expect(back.size, const Size(48, 48));
        expect(more.size, const Size(48, 48));
        expect(t.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
        expect(typed, isFalse);
      });
    }
  }
}
