import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/chat/message_body.dart';
import 'package:snippet/media_views.dart';
import 'package:snippet/theme.dart';

void main() {
  testWidgets('a sent voice note shows as a player, not its markers',
      (tester) async {
    final client = DaemonClient('https://daemon.invalid', 'test');
    const body = '[attached file — read it at this exact path: /tmp/x.m4a]\n\n'
        '[Audio transcript for /tmp/x.m4a]\nThe draft link please.';
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: ChatMessageBody(client: client, body: body, mine: true),
      ),
    ));
    expect(find.byType(VoiceNote), findsOneWidget);
    expect(find.textContaining('exact path'), findsNothing);
    expect(find.textContaining('Audio transcript for'), findsNothing);
  });
}
