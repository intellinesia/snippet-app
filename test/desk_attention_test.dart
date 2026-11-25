import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/desk_attention.dart';
import 'package:snippet/models.dart';
import 'package:snippet/theme.dart';

SessionInfo _ask(String id, {String type = 'approval', int at = 1}) =>
    SessionInfo.fromJson({
      'id': id,
      'title': 'Chat $id',
      'status': 'waiting_for_input',
      'last_active': at,
      'attention': {
        'type': type,
        'tool': 'bash',
        'text': type == 'approval' ? 'flutter build linux' : 'Which one?',
      },
    });

void main() {
  Widget host(List<SessionInfo> sessions, {String? exclude}) => MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: DeskAttentionScope(
            client: DaemonClient('https://daemon.invalid', 'test'),
            asks: DeskAttentionScope.asksFrom(sessions),
            onOpen: (_) {},
            child:
                SizedBox(width: 680, child: DeskAttentionBar(exclude: exclude)),
          ),
        ),
      );

  testWidgets('shows other sessions asks, never the one on screen',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final plain = SessionInfo.fromJson(
        {'id': 'idle', 'title': 'Idle', 'status': 'waiting_for_input'});
    await tester.pumpWidget(host([_ask('a', at: 2), plain], exclude: 'a'));
    expect(find.byKey(const Key('deskAttention')), findsNothing);

    var opened = '';
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: DeskAttentionScope(
          client: DaemonClient('https://daemon.invalid', 'test'),
          asks: DeskAttentionScope.asksFrom(
              [_ask('a', at: 2), _ask('b', type: 'question', at: 1)]),
          onOpen: (s) => opened = s.id,
          child: const SizedBox(width: 680, child: DeskAttentionBar()),
        ),
      ),
    ));
    expect(find.text('2 things need you'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);

    await tester.tap(find.text('Review'));
    await tester.pump();
    expect(opened, 'a');
    debugDefaultTargetPlatformOverride = null;
  });
}
