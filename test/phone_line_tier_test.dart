import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat/activity_dock.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/tool_activity.dart';
import 'package:snippet/transcript.dart';

ToolStep _ok() => ToolStep(
    tool: 'read_file', args: {'path': 'a.dart'}, result: {'status': 'ok'});
ToolStep _bad() => ToolStep(
    tool: 'bash',
    args: {'command': 'flutter test'},
    result: {
      'status': 'error',
      'data': {'exit_code': 1, 'stdout': '00:01 +1 -1: Some tests failed.'}
    });

Widget _host(Widget child) => MaterialApp(
    theme: buildAppTheme(), home: Scaffold(body: Center(child: child)));

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

  testWidgets('phone work line is a flat 48pt line and reports a failure',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await t.pumpWidget(_host(WorkLine(
        steps: [_ok(), _bad()],
        running: false,
        open: false,
        onTap: () {},
        took: const Duration(seconds: 42))));
    expect(find.textContaining('Worked for 42s'), findsOneWidget);
    expect(find.textContaining('failed', findRichText: true), findsOneWidget);
    expect(t.getSize(find.byType(WorkLine)).height, 48);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('collapsed activity pill shows the failure state', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var opened = false;
    await t.pumpWidget(_host(ActivityPill(
        steps: [_ok(), _bad()],
        agentId: 'snippet',
        took: const Duration(seconds: 42),
        onOpen: (_) => opened = true)));
    expect(find.textContaining('failed'), findsOneWidget);
    await t.tap(find.byType(ActivityPill));
    expect(opened, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });
}
