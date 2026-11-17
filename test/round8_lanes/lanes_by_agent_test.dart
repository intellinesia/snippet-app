import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/agent_character.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/lanes.dart';
import 'package:snippet/theme.dart';

class _Client extends DaemonClient {
  _Client() : super('https://r8.invalid', 'test-token');
}

LaneInfo _l(String id, String title, String status,
        {String? agent,
        String? activity,
        String? summary,
        String? error,
        int min = 0}) =>
    LaneInfo(
      id: id,
      title: title,
      status: status,
      agent: agent,
      activity: activity,
      summary: summary,
      error: error,
      startedAt: DateTime.now()
          .toUtc()
          .subtract(Duration(minutes: min))
          .toIso8601String(),
    );

final _running = [
  _l('1', 'Golden baselines', 'running',
      activity: 'flutter test test/goldens', min: 12),
  _l('2', 'Audit 360px overflow', 'running',
      activity: 'Reading settings_panel.dart', min: 7),
  _l('3', 'Release note draft', 'running',
      agent: 'moss', activity: 'Writing CHANGELOG.md', min: 3),
];

final _needs = [
  _l('1', 'Golden baselines', 'failed',
      error: 'Two goldens differ on the Stone theme. The sidebar row is 2px '
          'taller than the baseline.'),
  _running[1],
  _l('4', 'Rename settings tokens', 'completed',
      summary: 'Renamed 14 tokens and updated every caller.'),
  _running[2],
];

final _done = [
  _l('1', 'Golden baselines', 'completed',
      summary: 'Regenerated 12 goldens; all pass on both themes.'),
  _l('2', 'Audit 360px overflow', 'completed',
      summary: 'Found 3 overflows at 360; fixed in settings.'),
  _l('4', 'Rename settings tokens', 'completed',
      summary: 'Renamed 14 tokens and updated every caller.'),
  _l('5', 'Try Flux for barge-in', 'cancelled',
      summary: 'Stopped by Rook: superseded by the new plan.'),
  _l('3', 'Release note draft', 'completed',
      agent: 'moss', summary: 'Drafted the 0.42 release note in CHANGELOG.md.'),
];

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

Future<void> _pump(WidgetTester t, List<LaneInfo> lanes,
    {Size size = const Size(390, 844)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.runAsync(() async {
    await CharacterRoster.load();
    await ThemeManager.instance.setName('stone');
  });
  await t.pumpWidget(RepaintBoundary(
    key: const ValueKey('shot'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: LanesScreen(
        liveLanes: () => lanes,
        client: _Client(),
        sessionId: 's1',
        sessionTitle: 'Sidebar density',
        sessionAgentId: 'snippet',
        sessionAgentName: 'Rook',
      ),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
}

void _on(TargetPlatform p, String name, WidgetTesterCallback body) =>
    testWidgets(name, (t) async {
      debugDefaultTargetPlatformOverride = p;
      try {
        await body(t);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

void _phone(String name, WidgetTesterCallback body) =>
    _on(TargetPlatform.android, name, body);

void main() {
  _phone('running: two agents, status dots, footnote', (t) async {
    await _pump(t, _running);
    expect(find.text('Rook · 2 working'), findsOneWidget);
    expect(find.text('Moss · 1 working'), findsOneWidget);
    expect(find.text('12 min'), findsOneWidget);
    await _shot(t, 'lanes-c-run');
    await _unmount(t);
  });

  _phone('needs: failed row leads with Retry', (t) async {
    await _pump(t, _needs);
    expect(find.text('Rook · 1 needs you'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await _shot(t, 'lanes-c-needs');
    await _unmount(t);
  });

  _phone('done: counts per agent', (t) async {
    await _pump(t, _done);
    expect(find.text('Rook · 3 done, 1 cancelled'), findsOneWidget);
    expect(find.text('Moss · 1 done'), findsOneWidget);
    await _shot(t, 'lanes-c-done');
    await _unmount(t);
  });

  _on(TargetPlatform.macOS, 'desktop drawer: needs', (t) async {
    await _pump(t, _needs, size: const Size(460, 820));
    expect(find.text('Rook · 1 needs you'), findsOneWidget);
    await _shot(t, 'lanes-desktop-needs');
    await _unmount(t);
  });

  _on(TargetPlatform.macOS, 'desktop drawer: running', (t) async {
    await _pump(t, _running, size: const Size(460, 820));
    await _shot(t, 'lanes-desktop-run');
    await _unmount(t);
  });
}
