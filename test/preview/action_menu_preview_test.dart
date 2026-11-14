import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/components.dart';
import 'package:snippet/dialog_widgets.dart';
import 'package:snippet/theme.dart';

Widget _app(void Function(BuildContext) open) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
                key: const Key('open'),
                onPressed: () => open(ctx),
                child: const Text('Open')),
          ),
        ),
      ),
    );

void _session(BuildContext c, {bool settled = false}) => showAppSheet(c,
    title: 'YC demo video from Mac and phone recordings',
    subtitle: 'snippet-mobile',
    child: SheetActions([
      SheetAction('edit', 'Rename', () {}, detail: 'Change the title'),
      SheetAction('check', 'Select', () {}, detail: 'Pick several to settle or delete'),
      settled
          ? SheetAction('play', 'Wake', () {}, detail: 'Bring it back to the list')
          : SheetAction('archive', 'Settle', () {}, detail: 'Save its memory and park it'),
      SheetAction('trash', 'Delete', () {},
          danger: true,
          detail: 'Remove this chat and its history'),
    ]));

void main() {
  mainMore();
  for (final w in [390.0, 320.0]) {
    testWidgets('session menu $w', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = Size(w, w == 390 ? 844 : 690);
      addTearDown(t.view.reset);
      await t.pumpWidget(_app(_session));
      await t.tap(find.byKey(const Key('open')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('goldens/action_menu/session_${w.toInt()}.png'));
      debugDefaultTargetPlatformOverride = null;
    });
  }
}

void _agent(BuildContext c) => showAppSheet(c,
    title: 'Rust PR Reviewer',
    subtitle: 'Agent',
    child: SheetActions([
      SheetAction('edit', 'Nickname', () {}, tile: true),
      SheetAction('sparkles', 'Change colour', () {}, tile: true),
      SheetAction('calendar-clock', 'Wakes and reporting', () {},
          detail: 'When it wakes and where it reports'),
      SheetAction('cpu', 'Change inference profile', () {},
          detail: 'The model it runs on'),
      SheetAction('trash', 'Delete agent', () {},
          danger: true, detail: 'Remove the agent, its identity and notes'),
    ]));

void _folder(BuildContext c) => showAppSheet(c,
    title: 'Folder actions',
    subtitle: 'snippet-mobile',
    child: SheetActions([
      SheetAction('plus', 'New chat', () {}, tile: true),
      SheetAction('git-branch', 'Git', () {}, tile: true),
      SheetAction('upload', 'Upload', () {}, tile: true),
      SheetAction('folder-plus', 'New folder', () {}, tile: true),
    ]));

void mainMore() {
  for (final e in {'agent': _agent, 'folder': _folder}.entries) {
    testWidgets('${e.key} menu', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(390, 844);
      addTearDown(t.view.reset);
      await t.pumpWidget(_app(e.value));
      await t.tap(find.byKey(const Key('open')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('goldens/action_menu/${e.key}.png'));
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
