import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/composer/attachment_tile.dart';
import 'package:snippet/composer/chat_composer.dart';
import 'package:snippet/composer/cold_strip.dart';
import 'package:snippet/composer/desktop_composer.dart';
import 'package:snippet/composer/voice_note.dart';
import 'package:snippet/theme.dart';

import 'support/wake_fakes.dart';

Future<void> _pumpComposer(
  WidgetTester tester, {
  required TextEditingController input,
  required VoiceNoteController voice,
  bool running = false,
  List<Widget> attachments = const [],
  FocusNode? focus,
}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: ChatComposer(
          input: input,
          focus: focus ?? FocusNode(),
          hint: 'Message agent',
          voice: voice,
          onSend: () {},
          canSend: () => input.text.trim().isNotEmpty,
          hasDraft: () => input.text.trim().isNotEmpty,
          onAttach: () {},
          running: running,
          onStop: running ? () {} : null,
          attachments: () => attachments.isEmpty
              ? null
              : ComposerAttachmentBar(tiles: attachments),
        ),
      ),
    ),
  ));
  await tester.pump();
}

DeskActionButton _action(WidgetTester tester) =>
    tester.widget<DeskActionButton>(find.byType(DeskActionButton));

void main() {
  testWidgets('desktop composer swaps mic, send and stop in one action slot',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final input = TextEditingController();
    final voice = VoiceNoteController(client: FakeWakeClient());
    addTearDown(input.dispose);
    addTearDown(voice.dispose);

    await _pumpComposer(tester, input: input, voice: voice);
    expect(_action(tester).icon, 'mic');

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    expect(_action(tester).icon, 'arrow-up');

    await tester.pumpWidget(const SizedBox.shrink());
    input.clear();
    await _pumpComposer(tester, input: input, voice: voice, running: true);
    expect(_action(tester).icon, 'stop');
    expect(find.byType(DeskActionButton), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop attachments are dense surface rows inside the card',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final input = TextEditingController();
    final voice = VoiceNoteController(client: FakeWakeClient());
    addTearDown(input.dispose);
    addTearDown(voice.dispose);

    await _pumpComposer(tester, input: input, voice: voice, attachments: [
      ComposerAttachmentTile(
        name: 'notes.txt',
        isImage: false,
        isAudio: false,
        uploading: false,
        onRemove: () {},
        sizeBytes: 2048,
      ),
    ]);
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('2 KB'), findsOneWidget);
    expect(
        tester.getSize(find.byType(ComposerAttachmentTile).first).height, 44);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop composer focus stays ringless', (tester) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final input = TextEditingController();
    final voice = VoiceNoteController(client: FakeWakeClient());
    final focus = FocusNode();
    addTearDown(input.dispose);
    addTearDown(voice.dispose);
    addTearDown(focus.dispose);

    await _pumpComposer(tester, input: input, voice: voice, focus: focus);
    focus.requestFocus();
    await tester.pump();

    final containers = tester
        .widgetList<Container>(find.ancestor(
            of: find.byType(TextField), matching: find.byType(Container)))
        .toList();
    final card = containers.firstWhere((c) => c.decoration is BoxDecoration);
    final decoration = card.decoration as BoxDecoration;
    expect(decoration.border?.top.color, isNot(AppColors.fg3));
    expect(decoration.border?.top.color, Colors.transparent);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('cold and offline desktop composer states read as words',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Column(children: [
          DeskColdComposerStrip(mode: 'ask', onPick: (_) {}),
          DeskOfflineComposerNotice(
              message: 'Reconnecting', queued: 2, onRetry: () {}),
        ]),
      ),
    ));
    expect(find.text('Session is cold'), findsOneWidget);
    expect(find.text('Warm up'), findsOneWidget);
    expect(find.text('Reconnecting · 2 messages will send on reconnect'),
        findsOneWidget);
    expect(find.text('Retry now'), findsOneWidget);
    expect(tester.getSize(find.byType(DeskColdComposerStrip)).height, 36);
    expect(tester.getSize(find.byType(DeskOfflineComposerNotice)).height, 34);
  });
}
