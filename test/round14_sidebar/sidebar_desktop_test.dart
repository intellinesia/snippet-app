import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/screens/shell_rail.dart' show kSidebarWidth;
import 'package:snippet/screens/sidebar.dart';
import 'package:snippet/screens/sidebar_mode.dart';
import 'package:snippet/swr.dart';
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

class _Client extends DaemonClient {
  _Client() : super('https://daemon.invalid', 'test');

  @override
  late final DeviceEventHub deviceEvents = DeviceEventHub.local();

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        for (final (id, name, text) in [
          ('mission-control', 'Mission Control', 'Filed as task 06bd2e9c in the sync'),
          ('scrapper', 'scrapper bois', 'snippet: Confirmed, one himalaya send'),
          ('snippet', 'Snippet', 'Mostly wrapping yesterday\'s LinkedIn work'),
          ('gowy', 'Gowy', 'Restarted while Growth Advisor was running'),
          ('rust', 'Rust TUI Expert', 'Restarted while Rust TUI Expert ran'),
        ])
          CoordinationAgent.fromJson({
            'id': id,
            'display_name': name,
            'handle': id,
            'status': 'active',
            'last_message': {
              'text': text,
              'from_user': false,
              'at': DateTime.now()
                  .subtract(Duration(hours: id.length))
                  .toIso8601String(),
            },
          }),
      ];
}

SessionInfo _s(String id, String title, int ago) => SessionInfo.fromJson({
      'id': id,
      'title': title,
      'folder': '/workspace/repo',
      'branch': 'main',
      'last_active': DateTime.now().millisecondsSinceEpoch ~/ 1000 - ago,
    });

Widget _app(Widget side) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: RepaintBoundary(
          key: const ValueKey('shot'),
          child: ColoredBox(
            color: AppColors.bg,
            child: Row(children: [
              SizedBox(width: kSidebarWidth, child: side),
              const Expanded(child: SizedBox()),
            ]),
          ),
        ),
      ),
    );

Sidebar _sidebar(DaemonClient c) => Sidebar(
      instances: const [],
      active: null,
      client: c,
      selectedSessionId: 's1',
      sessions: [
        _s('s1', 'Restyle the desktop sidebar', 60),
        _s('s2', 'Mobile perf: scene renderer', 4000),
        _s('s3', 'Fix voice barge-in', 90000),
        _s('mission-control', 'Mission Control', 30),
      ],
      sessionsLoading: false,
      onRefreshSessions: () {},
      onNewSession: () {},
      onSelectInstance: (_) {},
      onOpenMissionControl: () {},
      onOpenSession: (_, __, ___) {},
      onAddInstance: () {},
      onRenameInstance: (_, __) {},
      onRemoveInstance: (_) {},
      onSessionDeleted: (_) {},
      health: const {},
      onRefreshHealth: () {},
      topInset: false,
      onOpenPalette: () {},
      mobileHome: MobileHome.chats,
      onMobileHome: (_) {},
      settingsSection: null,
      onSettingsSection: (_) {},
      agent: null,
      onAgent: (_) {},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester t, bool agents) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1280, 800);
    addTearDown(t.view.reset);
    sidebarAgentsFirst.value = agents;
    addTearDown(() => sidebarAgentsFirst.value = false);
    await t.pumpWidget(_app(_sidebar(_Client())));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(seconds: 1));
    }
  }

  testWidgets('agents list uses 60px rows and a 288px sidebar', (t) async {
    await pump(t, true);
    expect(kSidebarWidth, 288);
    expect(t.getSize(find.byType(Sidebar)).width, 288);
    expect(find.text('Ctrl K'), findsOneWidget);
    await _shot(t, 'sidebar_agents');
    expect(t.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('sessions list renders in the same metrics', (t) async {
    await pump(t, false);
    await _shot(t, 'sidebar_sessions');
    expect(t.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
