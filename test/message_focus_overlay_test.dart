import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/chat/chat_style.dart';
import 'package:snippet/chat/message_focus_overlay.dart';
import 'package:snippet/message_reactions.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/group_messaging.dart';
import 'package:snippet/swr.dart';

Future<void> _pumpFrames(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Swipe to reply', () {
    testWidgets('calls onReply only when dragged past 56px and springs back',
        (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      t.view.physicalSize = const Size(390, 844) * 3;
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      try {

      var replies = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: MessageBubbleInteractive(
                  text: 'Swipe me to reply',
                  onReply: () => replies++,
                  onReact: (_) {},
                  builder: (_, __, bubbleKey) => ChatBubbleRow(
                    mine: false,
                    child: KeyedSubtree(
                      key: bubbleKey,
                      child: const ChatBubble(
                        mine: false,
                        child: Text('Swipe me to reply'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Short drag (< 56px) does not trigger onReply.
      await t.dragFrom(const Offset(120, 422), const Offset(35, 0));
      await _pumpFrames(t);
      expect(replies, 0);

      // Drag past 56px shows the corner-up-left icon and triggers onReply.
      final gesture = await t.startGesture(const Offset(120, 422));
      await gesture.moveBy(const Offset(30, 0));
      await t.pump();
      await gesture.moveBy(const Offset(55, 0));
      await t.pump();
      expect(find.byIcon(LucideIcons.cornerUpLeft), findsOneWidget);

      await gesture.up();
      await _pumpFrames(t);
      expect(replies, 1);
      // After spring back, the reply icon hides again.
      expect(find.byIcon(LucideIcons.cornerUpLeft), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('ignores drags starting within 24px of left screen edge',
        (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      t.view.physicalSize = const Size(390, 844) * 3;
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      try {

      var replies = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MessageBubbleInteractive(
                text: 'Edge guarded bubble',
                onReply: () => replies++,
                onReact: (_) {},
                builder: (_, __, bubbleKey) => ChatBubbleRow(
                  mine: false,
                  child: KeyedSubtree(
                    key: bubbleKey,
                    child: const ChatBubble(
                      mine: false,
                      child: Text('Edge guarded bubble'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await t.dragFrom(const Offset(12, 422), const Offset(110, 0));
      await _pumpFrames(t);
      expect(replies, 0);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('ignores vertical drag and does not steal vertical scroll',
        (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      t.view.physicalSize = const Size(390, 844) * 3;
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      try {

      var replies = 0;
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              controller: controller,
              itemCount: 30,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.all(12),
                child: MessageBubbleInteractive(
                  text: 'Item $i',
                  onReply: () => replies++,
                  onReact: (_) {},
                  builder: (_, __, bubbleKey) => ChatBubbleRow(
                    mine: false,
                    child: KeyedSubtree(
                      key: bubbleKey,
                      child: ChatBubble(
                        mine: false,
                        child: Text('Item $i'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await t.drag(find.text('Item 5'), const Offset(12, -180));
      await _pumpFrames(t);
      expect(replies, 0);
      expect(controller.offset, greaterThan(50));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('MessageFocusOverlay', () {
    testWidgets(
        'shows quick reactions, +, Reply, Copy; Copy toasts and tap outside dismisses',
        (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      t.view.physicalSize = const Size(390, 844) * 3;
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      try {

      String? copiedText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      var replied = 0;
      String? reacted;

      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: MessageBubbleInteractive(
                  text: 'Copyable agent note',
                  mine: true,
                  onReply: () => replied++,
                  onReact: (e) => reacted = e,
                  focusBuilder: (_) => const ChatBubble(
                    mine: true,
                    child: Text('Copyable agent note'),
                  ),
                  builder: (_, __, bubbleKey) => ChatBubbleRow(
                    mine: true,
                    child: KeyedSubtree(
                      key: bubbleKey,
                      child: const ChatBubble(
                        mine: true,
                        child: Text('Copyable agent note'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await t.longPress(find.text('Copyable agent note'));
      await _pumpFrames(t);

      expect(find.byType(MessageFocusOverlay), findsOneWidget);
      for (final emoji in kMessageReactions) {
        expect(find.text(emoji), findsOneWidget);
      }
      expect(find.bySemanticsLabel('More reactions'), findsOneWidget);
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.byIcon(LucideIcons.cornerUpLeft), findsOneWidget);
      expect(find.byIcon(LucideIcons.copy), findsOneWidget);

      // Tap outside dismisses.
      await t.tapAt(const Offset(20, 40));
      await _pumpFrames(t);
      expect(find.byType(MessageFocusOverlay), findsNothing);
      expect(replied, 0);
      expect(reacted, isNull);

      // Open again and tap Copy.
      await t.longPress(find.text('Copyable agent note'));
      await _pumpFrames(t);
      await t.tap(find.text('Copy'));
      await _pumpFrames(t);
      expect(copiedText, 'Copyable agent note');
      expect(find.text('Copied'), findsOneWidget);
      // Let toast timer expire cleanly.
      await t.pump(const Duration(seconds: 3));

      // Open again and tap a quick reaction.
      await t.longPress(find.text('Copyable agent note'));
      await _pumpFrames(t);
      await t.tap(find.text('👍'));
      await _pumpFrames(t);
      expect(reacted, '👍');
      expect(find.byType(MessageFocusOverlay), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('caps very tall bubbles at 45% of screen height', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      t.view.physicalSize = const Size(390, 844) * 3;
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      try {

      final tallText = List.filled(45, 'Long line of text inside bubble').join('\n');
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: MessageBubbleInteractive(
                  text: tallText,
                  onReply: () {},
                  onReact: (_) {},
                  focusBuilder: (_) => ChatBubble(
                    mine: false,
                    child: Text(tallText),
                  ),
                  builder: (_, __, bubbleKey) => ChatBubbleRow(
                    mine: false,
                    child: KeyedSubtree(
                      key: bubbleKey,
                      child: ChatBubble(
                        mine: false,
                        child: Text(tallText),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await t.longPress(find.byType(ChatBubble));
      await _pumpFrames(t);

      expect(find.byType(MessageFocusOverlay), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MessageFocusOverlay),
          matching: find.byType(ShaderMask),
        ),
        findsOneWidget,
      );
      final overlayBubble = find.descendant(
        of: find.byType(MessageFocusOverlay),
        matching: find.byType(ShaderMask),
      );
      expect(t.getSize(overlayBubble).height, lessThanOrEqualTo(844 * 0.45 + 1));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
        'shifts bubble near bottom to keep actions on screen and honours reduced motion',
        (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      t.view.physicalSize = const Size(390, 844) * 3;
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      try {
        await t.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(390, 844),
                disableAnimations: true,
              ),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: MessageBubbleInteractive(
                      text: 'Bottom bubble',
                      onReply: () {},
                      onReact: (_) {},
                      focusBuilder: (_) => const ChatBubble(
                        mine: false,
                        child: Text('Bottom bubble'),
                      ),
                      builder: (_, __, bubbleKey) => ChatBubbleRow(
                        mine: false,
                        child: KeyedSubtree(
                          key: bubbleKey,
                          child: const ChatBubble(
                            mine: false,
                            child: Text('Bottom bubble'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await t.longPress(find.text('Bottom bubble'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 130));

        expect(find.byType(MessageFocusOverlay), findsOneWidget);
        // Under reduced motion, bubble and bars stay at scale 1.0 while fading.
        final transforms = t.widgetList<Transform>(find.descendant(
          of: find.byType(MessageFocusOverlay),
          matching: find.byType(Transform),
        ));
        for (final tr in transforms) {
          expect(tr.transform.getMaxScaleOnAxis(), closeTo(1.0, 0.001));
        }

        await t.pump(const Duration(milliseconds: 200));
        final copyRect = t.getRect(find.text('Copy'));
        expect(copyRect.bottom, lessThanOrEqualTo(844 - 12));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('Group chat interactions', () {
    testWidgets('long-press shows Copy and quick reactions, no Reply', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      t.view.physicalSize = const Size(390, 844) * 3;
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      try {

      final group = GroupSummary.fromJson({
        'id': 'g1',
        'title': 'Launch',
        'members': [
          {'kind': 'agent', 'id': 'argon'},
          {'kind': 'human', 'id': 'local'},
        ],
        'lead': 'argon',
      });
      final client = _FakeGroupClient([
        CoordinationEvent.fromJson({
          'event_id': 'e1',
          'sequence': 1,
          'actor_kind': 'agent',
          'actor_id': 'argon',
          'idempotency_key': 'k1',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'payload': {'body': 'Group message text'},
        }),
      ]);

      await t.pumpWidget(
        MaterialApp(
          home: GroupThreadScreen(client: client, group: group),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }

      await t.longPress(find.text('Group message text'));
      await _pumpFrames(t);

      expect(find.byType(MessageFocusOverlay), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Reply'), findsNothing);
      for (final emoji in kMessageReactions) {
        expect(find.text(emoji), findsOneWidget, reason: emoji);
      }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}

class _FakeGroupClient extends DaemonClient {
  _FakeGroupClient(this.thread) : super('https://daemon.invalid', 'test-token');
  final List<CoordinationEvent> thread;
  final _deviceEvents = DeviceEventHub.local();

  @override
  DeviceEventHub get deviceEvents => _deviceEvents;

  @override
  Future<List<CoordinationEvent>> groupEvents(
    String id, {
    int after = 0,
    int limit = 100,
  }) async =>
      thread;

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        CoordinationAgent.fromJson({
          'id': 'argon',
          'display_name': 'Argon',
          'handle': 'argon',
          'status': 'active',
        }),
      ];
}
