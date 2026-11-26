import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/chat/ask_kit.dart';
import 'package:snippet/chat/canvas_ask_card.dart';
import 'package:snippet/chat/chat_card.dart';
import 'package:snippet/chat/chat_style.dart';
import 'package:snippet/chat/run_head.dart';
import 'package:snippet/chat/unread_divider.dart';
import 'package:snippet/composer/composer_card.dart';
import 'package:snippet/message_reactions.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

Future<void> _shot(WidgetTester t, String dir, String name) async {
  await t.runAsync(() async {
    final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('shot')));
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Widget _shell(Widget child) => RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: Scaffold(backgroundColor: AppColors.bg, body: child),
      ),
    );

Widget _composer() => Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: ComposerPillSurface(
        child: Row(children: [
          const SizedBox(width: 8),
          AppIcon('plus', size: 20, color: AppColors.fg2),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Message Rook',
                maxLines: 1,
                style: sans(15, height: 21 / 15, color: AppColors.fg3)),
          ),
          ComposerSendButton(enabled: true, onTap: () {}),
          const SizedBox(width: 4),
        ]),
      ),
    );

Widget _coreScene() => SafeArea(
      child: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              UnreadDivider(count: 3, onJump: () {}),
              const SizedBox(height: 10),
              SoftLane(
                agentId: 'rook',
                name: 'Rook',
                time: '12:41',
                child: Text(
                  'The phone thread is flat now: agent prose sits directly on the canvas, with the avatar and timestamp carrying the row structure.',
                  style: sans(15, height: 20 / 15, color: AppColors.fg1),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 40),
                child: MessageReactionChips(
                  reactions: const [
                    ReactionGroup(name: '👍', count: 2, mine: false, actors: ['agent:rook']),
                    ReactionGroup(name: '✅', count: 1, mine: true, actors: ['human:me']),
                  ],
                  mine: false,
                  onReact: (_) {},
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ChatBubble(
                  mine: true,
                  child: Text('Use the tonal treatment throughout.',
                      style: sans(15, height: 20 / 15, color: AppColors.fg1)),
                ),
              ),
              const SizedBox(height: 14),
              ChatCard(fill: AppColors.surface2, children: [
                const NeedsYouRow(trailing: 'Rook · 12:42'),
                const ChatCardHeader(title: 'Run the migration?', subtitle: 'Approval needed'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: const AskCommandPlate('flutter test test/v19_phone_capture_test.dart'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: ApprovalDecideButtons(
                      onAllowOnce: () {}, onAlways: () {}, onDeny: () {}),
                ),
              ]),
            ]),
          ),
        ),
        _composer(),
      ]),
    );

Widget _needsYouScene() => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: ChatCard(fill: AppColors.surface2, children: [
          const NeedsYouRow(trailing: 'Rook · 12:44'),
          const ChatCardHeader(title: 'Allow Rook to install the build dependency?'),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: const AskCommandPlate('flutter pub add infinite_scroll_pagination'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: ApprovalDecideButtons(
                onAllowOnce: () {}, onAlways: () {}, onDeny: () {}),
          ),
        ]),
      ),
    );

Widget _ask10Scene() => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: CanvasAskCard(
          const {
            'id': 'ask-v19',
            'canvas_id': 'canvas-v19',
            'kind': 'choose_one',
            'prompt': 'Which composer density should ship?',
            'asked_by': 'Rook',
            'rev': 7,
            'status': 'open',
            'options': [
              {'id': 'compact', 'label': 'Compact', 'subtitle': '56 px pill'},
              {'id': 'roomy', 'label': 'Roomy', 'subtitle': 'more breathing room'},
            ],
          },
          onAnswer: (value, {decision}) async => true,
        ),
      ),
    );

Future<void> _pumpCapture(
  WidgetTester t, {
  required Size size,
  required bool light,
  required Widget Function() scene,
}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = size;
  await ThemeManager.instance.setName(light ? 'quiet-light' : 'quiet');
  await t.pumpWidget(_shell(scene()));
  await t.pump(const Duration(milliseconds: 150));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  for (final size in [const Size(393, 852), const Size(360, 640)]) {
    for (final light in [false, true]) {
      final suffix = '${size.width.toInt()}x${size.height.toInt()}-${light ? 'light' : 'dark'}';
      testWidgets('v19 phone core $suffix', (t) async {
        const dir = String.fromEnvironment('SHOT_DIR');
        addTearDown(t.view.reset);
        await _pumpCapture(t, size: size, light: light, scene: _coreScene);
        expect(t.takeException(), isNull);
        if (dir.isNotEmpty) await _shot(t, dir, 'v19-phone-core-$suffix');
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('v19 needs-you approval $suffix', (t) async {
        const dir = String.fromEnvironment('SHOT_DIR');
        addTearDown(t.view.reset);
        await _pumpCapture(t, size: size, light: light, scene: _needsYouScene);
        expect(t.takeException(), isNull);
        if (dir.isNotEmpty) await _shot(t, dir, 'v19-needs-you-approval-$suffix');
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('v19 ASK-10 option ask $suffix', (t) async {
        const dir = String.fromEnvironment('SHOT_DIR');
        addTearDown(t.view.reset);
        await _pumpCapture(t, size: size, light: light, scene: _ask10Scene);
        await t.tap(find.text('Compact'));
        await t.pump(const Duration(milliseconds: 100));
        expect(t.takeException(), isNull);
        if (dir.isNotEmpty) await _shot(t, dir, 'v19-ask10-option-ask-$suffix');
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
