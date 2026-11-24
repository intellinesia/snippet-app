import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/platform.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/chat/choices.dart';
import 'package:snippet/chat/message_body.dart';
import 'package:snippet/composer/attachment_tile.dart';
import 'package:snippet/composer/composer_card.dart';
import 'package:snippet/desktop_pick.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agent_messaging.dart';
import 'package:snippet/screens/group_messaging.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';

class _RichFakeClient extends DaemonClient {
  _RichFakeClient(this.thread) : super('https://daemon.invalid', 'test-token');

  final List<CoordinationEvent> thread;
  final List<({String groupId, String body, String? inReplyTo})> groupPosts =
      [];
  final List<({String to, String body, String? replyTo})> directSent = [];
  final List<({String? name, int length})> uploads = [];
  final _deviceEvents = DeviceEventHub.local();

  @override
  DeviceEventHub get deviceEvents => _deviceEvents;

  @override
  Future<List<CoordinationEvent>> groupEvents(
    String id, {
    int after = 0,
    int limit = 100,
  }) async =>
      List<CoordinationEvent>.of(thread);

  @override
  Future<DirectThreadPage> agentThreadPage({
    required String peerId,
    String actorKind = 'human',
    String actorId = 'local',
    int afterSequence = 0,
    int? beforeSequence,
    bool latest = false,
    int limit = 100,
  }) async =>
      DirectThreadPage(events: List<CoordinationEvent>.of(thread));

  @override
  Future<CoordinationEvent> postGroup(
    String id, {
    required String body,
    List<String>? mentions,
    String? inReplyTo,
    String? reaction,
    bool remove = false,
  }) async {
    groupPosts.add((groupId: id, body: body, inReplyTo: inReplyTo));
    final ev = CoordinationEvent.fromJson({
      'event_id': 'gp-${groupPosts.length}',
      'sequence': thread.length + 1,
      'event_type': 'group_message',
      'actor_kind': 'human',
      'actor_id': 'local',
      'idempotency_key': 'kgp-${groupPosts.length}',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'payload': {
        'body': body,
        if (inReplyTo != null) 'in_reply_to': inReplyTo,
      },
    });
    thread.add(ev);
    return ev;
  }

  @override
  Future<CoordinationEvent> sendAgentMessage({
    required String toAgentId,
    required String body,
    String fromKind = 'human',
    String fromId = 'local',
    String? idempotencyKey,
    String? originSession,
    String? replyTo,
    String? reaction,
    bool remove = false,
  }) async {
    directSent.add((to: toAgentId, body: body, replyTo: replyTo));
    final ev = CoordinationEvent.fromJson({
      'event_id': 'dm-${directSent.length}',
      'sequence': thread.length + 1,
      'event_type': 'direct_message.sent',
      'actor_kind': fromKind,
      'actor_id': fromId,
      'idempotency_key': idempotencyKey ?? 'kdm-${directSent.length}',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'payload': {
        'body': body,
        if (replyTo != null) 'reply_to': replyTo,
      },
    });
    thread.add(ev);
    return ev;
  }

  @override
  Future<String> uploadFile(List<int> bytes,
      {String? name, String? dir}) async {
    uploads.add((name: name, length: bytes.length));
    return '/tmp/uploads/${name ?? 'file'}';
  }

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        CoordinationAgent.fromJson({
          'id': 'argon',
          'display_name': 'Argon',
          'handle': 'argon',
          'status': 'active',
        }),
      ];

  @override
  Future<void> markAgentThreadRead({
    required String peerId,
    String actorKind = 'human',
    String actorId = 'local',
  }) async {}

  @override
  Future<List<ArtifactInfo>> artifacts(String session) async => const [];
}

CoordinationEvent _event(
  String id,
  int seq,
  String actorKind,
  String body, {
  String actorId = 'argon',
  Map<String, dynamic> extra = const {},
}) =>
    CoordinationEvent.fromJson({
      'event_id': id,
      'sequence': seq,
      'actor_kind': actorKind,
      'actor_id': actorId,
      'idempotency_key': 'k-$id',
      'created_at': DateTime.utc(2026, 11, 14, 10, 0, seq).toIso8601String(),
      'payload': {'body': body, ...extra},
    });

class _FakePickedFile extends PickedLocalFile {
  final Uint8List bytes;
  const _FakePickedFile({
    required super.name,
    required super.path,
    required this.bytes,
  });

  @override
  Future<Uint8List> readAsBytes() async => bytes;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ChatChoices', () {
    testWidgets('renders pills, taps unpicked, disables when chosen',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final picked = <String>[];
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 240,
            child: ChatChoices(
              choices: const ['Ship it', 'Hold off', 'Need edits'],
              onPick: picked.add,
            ),
          ),
        ),
      ));

      expect(find.text('Ship it'), findsOneWidget);
      expect(find.text('Hold off'), findsOneWidget);
      expect(find.text('Need edits'), findsOneWidget);
      final pillBox = tester.getSize(find
          .ancestor(of: find.text('Ship it'), matching: find.byType(InkWell))
          .first);
      expect(pillBox.height, greaterThanOrEqualTo(40));

      await tester.tap(find.text('Hold off'));
      expect(picked, ['Hold off']);

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ChatChoices(
            choices: const ['Ship it', 'Hold off', 'Need edits'],
            chosen: 'Hold off',
            onPick: picked.add,
          ),
        ),
      ));
      await tester.tap(find.text('Ship it'));
      expect(picked, ['Hold off'],
          reason: 'remaining pills are disabled once chosen');
      debugDefaultTargetPlatformOverride = null;
    });

    test('chosenReplyFor ignores earlier events and reaction events', () {
      final target = _event('e2', 2, 'agent', 'Which direction?', extra: {
        'choices': ['Option A', 'Option B'],
      });
      final events = [
        _event('e1', 1, 'human', 'Option A',
            actorId: 'local', extra: {'in_reply_to': 'e2'}),
        target,
        _event('e3', 3, 'human', '',
            actorId: 'local',
            extra: {'kind': 'reaction', 'reaction': '👍', 'reply_to': 'e2'}),
        _event('e4', 4, 'human', '  Option B  ',
            actorId: 'local', extra: {'in_reply_to': 'e2'}),
      ];
      expect(chosenReplyFor(target, events), 'Option B');
    });

    testWidgets('GroupThreadScreen tap posts in_reply_to and locks choices',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final group = GroupSummary.fromJson({
        'id': 'g1',
        'title': 'Launch',
        'members': [
          {'kind': 'agent', 'id': 'argon'},
          {'kind': 'human', 'id': 'local'},
        ],
      });
      final client = _RichFakeClient([
        _event('e1', 1, 'agent', 'Ready to publish?', extra: {
          'choices': ['Publish now', 'Save draft'],
        }),
      ]);

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: GroupThreadScreen(client: client, group: group),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }

      expect(find.byType(ChatChoices), findsOneWidget);
      await tester.tap(find.text('Publish now'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(client.groupPosts, hasLength(1));
      expect(client.groupPosts.single.groupId, 'g1');
      expect(client.groupPosts.single.body, 'Publish now');
      expect(client.groupPosts.single.inReplyTo, 'e1');

      await tester.tap(find.text('Save draft'));
      await tester.pump();
      expect(client.groupPosts, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('AgentThreadScreen renders choices and replies with replyTo',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final client = _RichFakeClient([
        _event('e1', 1, 'agent', 'Pick a tone:', actorId: 'growth', extra: {
          'choices': ['Direct', 'Warm'],
        }),
      ]);

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: AgentThreadScreen(
          client: client,
          agentId: 'growth',
          agentName: 'Growth',
        ),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }

      expect(find.byType(ChatChoices), findsOneWidget);
      await tester.tap(find.text('Warm'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(client.directSent, hasLength(1));
      expect(client.directSent.single.to, 'growth');
      expect(client.directSent.single.body, 'Warm');
      expect(client.directSent.single.replyTo, 'e1');
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('Draft blockquote copy card', () {
    testWidgets('renders card with Copy button, copies plain text and toasts',
        (tester) async {
      String? clipboardText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final client = DaemonClient('https://daemon.invalid', 'test');
      const body = 'Here is your draft:\n\n'
          '> First line of **the** draft.\n>\n'
          '> Second paragraph here.';
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ChatMessageBody(client: client, body: body, mine: false),
        ),
      ));

      // Phones show Use draft (copies when no chat is open), desktop Copy.
      final action = find.text(kMobile ? 'Use draft' : 'Copy');
      expect(action, findsOneWidget);
      expect(find.textContaining('First line of the draft.'), findsOneWidget);

      await tester.tap(action);
      await tester.pump();
      expect(
        clipboardText,
        'First line of the draft.\n\nSecond paragraph here.',
      );
      expect(find.text('Copied'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('Link cards', () {
    test('describeLinkUrl formats LinkedIn post and generic URLs', () {
      final li = describeLinkUrl(Uri.parse(
          'https://www.linkedin.com/posts/jane-doe_building-fast-agents-in-dart-activity-7261234567890123456-AbCd'));
      expect(li.host, 'linkedin.com');
      expect(li.title, 'jane doe · building fast agents in dart');

      final generic = describeLinkUrl(
          Uri.parse('https://docs.example.com/guides/getting-started/'));
      expect(generic.host, 'docs.example.com');
      expect(generic.title, 'getting started');

      final root = describeLinkUrl(Uri.parse('https://example.com/'));
      expect(root.host, 'example.com');
      expect(root.title, 'example.com');
    });

    testWidgets(
        'renders standalone URLs as cards, preserves mention bolding and inline links',
        (tester) async {
      final client = DaemonClient('https://daemon.invalid', 'test');
      const body = 'Hey @argon read this:\n'
          'https://www.linkedin.com/posts/jane-doe_shipping-rich-chat-activity-7269999999999999999-XyZ\n'
          'Also see https://example.com/inline-ref in context.';

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ChatMessageBody(
            client: client,
            body: body,
            mine: false,
            markdown: (t) => groupMarkdownWithMentions(t, {'argon'}),
          ),
        ),
      ));

      expect(find.text('jane doe · shipping rich chat'), findsOneWidget);
      expect(find.text('linkedin.com'), findsOneWidget);
      expect(find.textContaining('@argon', findRichText: true), findsOneWidget);
      expect(
          find.textContaining('https://example.com/inline-ref',
              findRichText: true),
          findsOneWidget);
    });
  });

  group('Group composer attachments', () {
    testWidgets('picked file shows tile in group composer and posts marker',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final tmp = Directory.systemTemp.createTempSync('group_attach_test_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final docFile = File('${tmp.path}/notes.txt')
        ..writeAsStringSync('launch notes');

      final group = GroupSummary.fromJson({
        'id': 'g1',
        'title': 'Launch',
        'members': [
          {'kind': 'agent', 'id': 'argon'},
          {'kind': 'human', 'id': 'local'},
        ],
      });
      final client = _RichFakeClient([]);

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: GroupThreadScreen(
          client: client,
          group: group,
          pickFiles: () async => [
            _FakePickedFile(
              name: 'notes.txt',
              path: docFile.path,
              bytes: Uint8List.fromList('launch notes'.codeUnits),
            ),
          ],
        ),
      ));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      await tester.tap(find.byTooltip('Attach'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(client.uploads, hasLength(1));
      expect(find.byType(ComposerAttachmentTile), findsOneWidget);
      expect(find.text('notes.txt'), findsOneWidget);

      await tester.tap(find.byType(DeskActionButton));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(client.groupPosts, hasLength(1));
      expect(
        client.groupPosts.single.body,
        contains(
            '[attached file — read it at this exact path: /tmp/uploads/notes.txt]'),
      );
      expect(find.byType(ComposerAttachmentTile), findsNothing);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('picked image posts view_image marker', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // Minimal valid 1x1 transparent PNG.
      final pngBytes = Uint8List.fromList([
        137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0,
        1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68,
        65, 84, 120, 156, 99, 96, 0, 0, 0, 2, 0, 1, 226, 33, 188, 51, 0, 0, 0,
        0, 73, 69, 78, 68, 174, 66, 96, 130,
      ]);
      final tmp = Directory.systemTemp.createTempSync('group_img_test_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final imgFile = File('${tmp.path}/shot.png')..writeAsBytesSync(pngBytes);

      final group = GroupSummary.fromJson({
        'id': 'g1',
        'title': 'Launch',
        'members': [
          {'kind': 'agent', 'id': 'argon'},
          {'kind': 'human', 'id': 'local'},
        ],
      });
      final client = _RichFakeClient([]);

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: GroupThreadScreen(
          client: client,
          group: group,
          pickFiles: () async => [
            _FakePickedFile(
              name: 'shot.png',
              path: imgFile.path,
              bytes: pngBytes,
            ),
          ],
        ),
      ));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      await tester.tap(find.byTooltip('Attach'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.byType(ComposerAttachmentTile), findsOneWidget);

      await tester.tap(find.byType(DeskActionButton));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(client.groupPosts, hasLength(1));
      expect(
        client.groupPosts.single.body,
        contains(
            '[attached image — call view_image on this exact path to see it: /tmp/uploads/shot.png]'),
      );
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
