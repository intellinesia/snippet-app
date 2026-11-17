import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/mission_control/mission_control_state.dart';
import 'package:snippet/screens/session_coordination_cards.dart';
import 'package:snippet/theme.dart';

Future<void> _shot(WidgetTester t, String name) async {
  const dir = String.fromEnvironment('SHOT_DIR');
  if (dir.isEmpty) return;
  await t.runAsync(() async {
    final b = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('shot')));
    final img = await b.toImage();
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

const _long = 'The scraper finished and wrote 412 rows. I checked the diff and '
    'nothing else moved.\n\n> forwarded: please keep the schema as is\n\n'
    'Second paragraph with **detail** that only shows once expanded.';

List<Widget> _cards() => [
      MissionEnvelopeCard(
          envelope: const MissionEnvelope(
              isReport: true,
              taskId: 'eaa98084-1111',
              title: 'Scrape the price list',
              status: 'done',
              summary: _long)),
      MissionEnvelopeCard(
          envelope: const MissionEnvelope(
              isReport: false,
              taskId: 'bb12cc34-1111',
              title: 'Tidy the settings page',
              status: 'new',
              summary: 'Short brief.')),
      MissionEnvelopeCard(
          envelope: const MissionEnvelope(
              isReport: false,
              taskId: 'bb12cc34-1111',
              title: 'Tidy the settings page',
              status: 'review',
              review: 'findings',
              round: '2',
              summary: 'Two spacing bugs on the profile panel.')),
      MissionEnvelopeCard(
          envelope: const MissionEnvelope(
              isReport: false,
              taskId: 'bb12cc34-1111',
              title: 'Ship the build',
              status: 'plan',
              isPlan: true,
              summary: '- ~~Build~~\n- **Test** · now\n- Release')),
      const DirectMessageCard(
          message: DirectMessage(
              threadId: 't',
              fromId: 'session:snippet-mobile-8f8d298804/conversations/cd376b97-24e4',
              fromKind: 'agent',
              body: _long,
              messageKind: 'question',
              urgent: true,
              isReply: false)),
      const DirectMessageCard(
          message: DirectMessage(
              threadId: 't',
              fromId: 'agent:rook',
              fromKind: 'agent',
              body: 'Looks good to me.',
              messageKind: '',
              urgent: false,
              isReply: true)),
      const BoardMessageCard(
          message: BoardMessage(
              threadId: 'task:eaa98084-1111-2222',
              fromId: 'agent:rook',
              fromKind: 'agent',
              body: 'Posted a note on the board.')),
    ];

void main() {
  for (final (name, platform, width) in [
    ('phone', TargetPlatform.android, 390.0),
    ('desktop', TargetPlatform.linux, 720.0),
  ]) {
    testWidgets('coordination cards on $name', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1500);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: RepaintBoundary(
              key: const ValueKey('shot'),
              child: Container(
                color: AppColors.bg,
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  for (final c in _cards())
                    Padding(
                        padding: const EdgeInsets.only(bottom: 12), child: c),
                ]),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Scrape the price list'), findsOneWidget);
      expect(find.text('From the snippet-mobile session'), findsOneWidget);
      expect(find.textContaining('8f8d'), findsNothing);
      await _shot(tester, '${name}_coordination_cards');
      await tester.tap(find.text('Show more').first);
      await tester.pumpAndSettle();
      expect(find.text('Show less'), findsOneWidget);
      await _shot(tester, '${name}_coordination_cards_open');
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
