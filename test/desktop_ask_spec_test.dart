import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/call_prompt_card.dart';
import 'package:snippet/call_tracking.dart';
import 'package:snippet/components.dart' show Spinner;
import 'package:snippet/chat/ask_kit.dart';
import 'package:snippet/chat/canvas_ask_card.dart';
import 'package:snippet/inline_flow.dart';
import 'package:snippet/screens/limit_card.dart';
import 'package:snippet/theme.dart';

Widget _host(Widget child, {double width = 560}) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Center(child: SizedBox(width: width, child: child)),
      ),
    );

void main() {
  void testDesktopWidgets(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testDesktopWidgets('open ask card uses the locked needs-you anatomy',
      (tester) async {
    await tester.pumpWidget(_host(DesktopAskCard(
      meta: 'Sashy · 2m',
      title: 'Run the full test suite?',
      payload: const AskCommandPlate('flutter test'),
      actions: [
        AskButton('Deny', onTap: () {}),
        AskButton('Approve', variant: AskButtonVariant.primary, onTap: () {}),
      ],
    )));

    expect(find.text('Needs you'), findsOneWidget);
    expect(find.text('Sashy · 2m'), findsOneWidget);
    expect(find.text('Run the full test suite?'), findsOneWidget);
    expect(find.text('flutter test'), findsOneWidget);
    expect(find.text('Deny'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);

    final approve = tester.getSize(
        find.byWidgetPredicate((w) => w is AskButton && w.label == 'Approve'));
    expect(approve.height, 28);
    final material = tester.widget<Material>(find
        .ancestor(of: find.text('Approve'), matching: find.byType(Material))
        .first);
    expect(material.borderRadius, BorderRadius.circular(6));
  });

  testDesktopWidgets('choose-one option cards say Selected and expose a border',
      (tester) async {
    var picked = 0;
    await tester.pumpWidget(_host(StatefulBuilder(
      builder: (context, setState) => AskOptionGrid(options: [
        AskOptionCard(
            title: 'Option A',
            subtitle: 'Current',
            selected: picked == 0,
            onTap: () => setState(() => picked = 0)),
        AskOptionCard(
            title: 'Option B',
            subtitle: 'Revised',
            selected: picked == 1,
            onTap: () => setState(() => picked = 1)),
      ]),
    )));

    expect(find.text('Selected'), findsOneWidget);
    expect(find.text('Click to pick'), findsOneWidget);
    await tester.tap(find.text('Option B'));
    await tester.pump();
    expect(find.text('Selected'), findsOneWidget);
    expect(find.text('Click to pick'), findsOneWidget);

    final selectedMaterial = tester.widget<Material>(find
        .ancestor(of: find.text('Option B'), matching: find.byType(Material))
        .first);
    final shape = selectedMaterial.shape as RoundedRectangleBorder;
    expect(shape.side.color, AppColors.fg1);
  });

  testDesktopWidgets(
      'canvas choose-one ask answers and becomes a revision-pinned '
      'decided card', (tester) async {
    final answers = <String>[];
    await tester.pumpWidget(_host(CanvasAskCard(
      {
        'id': 'ask-1',
        'canvas_id': 'canvas-1',
        'kind': 'choose_one',
        'prompt': 'Which frame should ship?',
        'asked_by': 'Sashy',
        'status': 'open',
        'rev': 14,
        'options': [
          {'id': 'a', 'label': 'Frame A'},
          {'id': 'b', 'label': 'Frame B'},
        ],
      },
      onAnswer: (value, {decision}) async {
        answers.add(value);
        return true;
      },
    )));

    expect(find.text('Needs you'), findsOneWidget);
    expect(find.text('Sashy · r14'), findsOneWidget);
    expect(find.text('Which frame should ship?'), findsOneWidget);
    expect(find.text('Open on canvas'), findsOneWidget);

    await tester.tap(find.text('Frame A'));
    await tester.pump();
    expect(find.text('Selected'), findsOneWidget);
    await tester.tap(find.text('Answer'));
    await tester.pumpAndSettle();

    expect(answers, ['a']);
    expect(find.text('Needs you'), findsNothing);
    expect(find.textContaining('Answered'), findsOneWidget);
    expect(find.textContaining('pinned at r14'), findsOneWidget);
  });

  testDesktopWidgets(
      'canvas choose-many uses checkbox rows and a selection count',
      (tester) async {
    final answers = <String>[];
    await tester.pumpWidget(_host(CanvasAskCard(
      {
        'id': 'ask-2',
        'canvas_id': 'canvas-1',
        'kind': 'choose_many',
        'prompt': 'Which elements need revision?',
        'status': 'open',
        'rev': 15,
        'options': [
          {'id': 'hero', 'label': 'Hero frame'},
          {'id': 'nav', 'label': 'Navigation'},
        ],
      },
      onAnswer: (value, {decision}) async {
        answers.add(value);
        return true;
      },
    )));

    expect(find.text('0 of 2 selected'), findsOneWidget);
    await tester.tap(find.text('Hero frame'));
    await tester.pump();
    await tester.tap(find.text('Navigation'));
    await tester.pump();
    expect(find.text('2 of 2 selected'), findsOneWidget);
    await tester.tap(find.text('Answer'));
    await tester.pumpAndSettle();
    expect(answers, ['hero, nav']);
  });

  testDesktopWidgets('canvas free-text ask submits the typed answer',
      (tester) async {
    final answers = <String>[];
    await tester.pumpWidget(_host(CanvasAskCard(
      {
        'id': 'ask-free',
        'canvas_id': 'canvas-1',
        'kind': 'free_text',
        'prompt': 'What should the frame say?',
        'status': 'open',
        'rev': 18,
      },
      onAnswer: (value, {decision}) async {
        answers.add(value);
        return true;
      },
    )));
    await tester.enterText(find.byType(TextField), 'Make it quieter');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(answers, ['Make it quieter']);
    expect(find.textContaining('pinned at r18'), findsOneWidget);
  });

  testDesktopWidgets(
      'canvas approve-reject ask resolves as a rejected decision',
      (tester) async {
    final decisions = <String?>[];
    await tester.pumpWidget(_host(CanvasAskCard(
      {
        'id': 'ask-approval',
        'canvas_id': 'canvas-1',
        'kind': 'approve_reject',
        'prompt': 'Approve this revision?',
        'status': 'open',
        'rev': 19,
      },
      onAnswer: (value, {decision}) async {
        decisions.add(decision);
        return true;
      },
    )));
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(decisions, ['reject']);
    expect(find.text('Needs you'), findsNothing);
    expect(find.textContaining('Rejected'), findsWidgets);
    expect(find.textContaining('pinned at r19'), findsOneWidget);
  });

  testDesktopWidgets(
      'canvas expired ask is neutral, decided and revision-pinned',
      (tester) async {
    await tester.pumpWidget(_host(CanvasAskCard({
      'id': 'ask-3',
      'canvas_id': 'canvas-1',
      'kind': 'free_text',
      'prompt': 'What should change?',
      'status': 'expired',
      'rev': 16,
    })));

    expect(find.text('Needs you'), findsNothing);
    expect(find.textContaining('Expired'), findsWidgets);
    expect(find.textContaining('pinned at r16'), findsOneWidget);
    expect(find.text('Answer'), findsNothing);
  });

  testDesktopWidgets('canvas pin badge is compact and hidden at zero',
      (tester) async {
    await tester.pumpWidget(_host(const Column(children: [
      CanvasAskPinBadge(count: 0),
      CanvasAskPinBadge(count: 2),
    ])));
    expect(find.byKey(const ValueKey('canvas-ask-pin-badge')), findsOneWidget);
    expect(find.text('Question'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(
        tester
            .getSize(find.byKey(const ValueKey('canvas-ask-pin-badge')))
            .height,
        22);
  });

  testDesktopWidgets('inline confirm is a 30-high neutral strip',
      (tester) async {
    await tester.pumpWidget(_host(InlineConfirmStrip(
      title: 'Remove this machine?',
      body: 'Saved credentials are deleted.',
      confirmLabel: 'Confirm',
      onCancel: () {},
      onConfirm: () {},
    )));
    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    final strip = tester.getSize(find.byType(InlineConfirmStrip));
    expect(strip.height, lessThanOrEqualTo(30));

    await tester.pumpWidget(_host(InlineConfirmStrip(
      title: 'Remove this machine?',
      body: 'Saved credentials are deleted.',
      confirmLabel: 'Confirm',
      busy: true,
      onCancel: () {},
      onConfirm: () {},
    )));
    expect(find.byType(Spinner), findsOneWidget);
  });

  testDesktopWidgets(
      'call prompt rings as needs-you and tracking has no header',
      (tester) async {
    Future<bool> action(String _) async => true;
    await tester.pumpWidget(_host(CallPromptCard(
      status: const CallStatus(
        callId: 'call-1',
        phase: CallPhase.pending,
        url: 'https://daemon.invalid',
        title: 'Lead is calling: voice check-in',
        body: 'Accept to start tracking notes.',
      ),
      onAction: action,
    )));
    expect(find.text('Needs you'), findsOneWidget);
    expect(find.text('Lead is calling: voice check-in'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);

    await tester.pumpWidget(_host(CallPromptCard(
      status: const CallStatus(
        callId: 'call-1',
        phase: CallPhase.tracking,
        url: 'https://daemon.invalid',
      ),
      onAction: action,
    )));
    expect(find.text('Needs you'), findsNothing);
    expect(find.text('Stop'), findsOneWidget);
  });

  testDesktopWidgets('usage limit stays neutral unless a decision is required',
      (tester) async {
    final client = DaemonClient('https://daemon.invalid', 'test');
    final reset = DateTime.now().add(const Duration(hours: 2));
    await tester.pumpWidget(_host(LimitCard(
      client: client,
      session: 's1',
      profile: 'Claude',
      resetsAt: reset.millisecondsSinceEpoch ~/ 1000,
      options: const ['GPT-5'],
      settled: false,
    )));
    expect(find.text('Needs you'), findsOneWidget);
    expect(find.textContaining('Claude limit reached'), findsOneWidget);
    expect(find.text('Continue on GPT-5'), findsOneWidget);

    await tester.pumpWidget(_host(LimitCard(
      client: client,
      session: 's1',
      profile: 'Claude',
      resetsAt: reset.millisecondsSinceEpoch ~/ 1000,
      options: const [],
      settled: false,
    )));
    expect(find.text('Needs you'), findsNothing);
    expect(find.text('Wait for reset'), findsOneWidget);
  });
}
