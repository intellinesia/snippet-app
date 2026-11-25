import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/menu_widgets.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/session_handoff.dart';
import 'package:snippet/theme.dart';

class _Client extends DaemonClient {
  _Client() : super('http://127.0.0.1:9090', 'tok');
  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async => [];
  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        CoordinationAgent.fromJson({
          'id': 'moss',
          'display_name': 'Moss',
          'handle': 'moss',
          'status': 'active'
        }),
        CoordinationAgent.fromJson({
          'id': 'pip',
          'display_name': 'Pip',
          'handle': 'pip',
          'status': 'active'
        }),
      ];
}

Future<BuildContext> _pump(WidgetTester tester) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  SharedPreferences.setMockInitialValues({});
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  late BuildContext ctx;
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(body: Builder(builder: (c) {
      ctx = c;
      return const SizedBox.expand();
    })),
  ));
  return ctx;
}

void main() {
  testWidgets('toast action fires and dismisses', (tester) async {
    final ctx = await _pump(tester);
    var fired = 0;
    toast(ctx, 'Forked to X', actionLabel: 'Open', onAction: () => fired++);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(fired, 1);
    expect(find.text('Forked to X'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('normal toast leaves after 3s', (tester) async {
    final ctx = await _pump(tester);
    toast(ctx, 'Saved');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2800));
    expect(find.text('Saved'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Saved'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('danger toast with action holds 8s and swipes up away', (tester) async {
    final ctx = await _pump(tester);
    toast(ctx, 'Busy', danger: true, actionLabel: 'Retry', onAction: () {});
    await tester.pump(const Duration(seconds: 7));
    expect(find.text('Busy'), findsOneWidget);
    await tester.drag(find.text('Busy'), const Offset(0, -80));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Busy'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('fork sheet returns the chosen value', (tester) async {
    final ctx = await _pump(tester);
    bool? result = true;
    var done = false;
    showForkSheet(ctx, fromLabel: 'Build 7', totalMessages: 160)
        .then((v) {
      result = v;
      done = true;
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Keeps everything up to "Build 7"'), findsOneWidget);
    expect(find.text('All 160 messages'), findsOneWidget);
    await tester.tap(find.text('Full history'));
    await tester.pump();
    await tester.tap(find.text('Fork'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(done, isTrue);
    expect(result, false);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('handoff button disabled until a pick', (tester) async {
    final ctx = await _pump(tester);
    showHandOffSheet(ctx, client: _Client(), sessionId: 's', ownerId: 'rook');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Hand off'), findsOneWidget);
    await tester.tap(find.text('Hand off'));
    await tester.pump();
    expect(find.text('Hand to Moss'), findsNothing);
    await tester.tap(find.text('Moss'));
    await tester.pump();
    expect(find.text('Hand to Moss'), findsOneWidget);
    expect(find.text('Note for Moss (optional)'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
