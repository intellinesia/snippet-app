import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/composer_strip.dart';
import 'package:snippet/media_views.dart';
import 'package:snippet/screens/mobile_shell.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/theme.dart';

class _Client extends DaemonClient {
  _Client() : super('https://daemon.invalid', 'test');
}

Widget _shell(bool chatsVisible) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: MobileShell(
        activeTabBody: Container(
            color: AppColors.surface1,
            alignment: Alignment.center,
            child: const Text('Mission')),
        sidebar: Container(
            color: AppColors.bg,
            alignment: Alignment.center,
            child: const Text('Sessions')),
        hasActiveTab: true,
        chatsOpen: chatsVisible,
        drilledDown: false,
        mobileHome: MobileHome.chats,
        onClearDrillDown: () {},
        onMobileHome: (_) {},
        onCloseChats: () {},
        missionPair: true,
        onSwipeToMission: () {},
        onSwipeToSessions: () {},
      ),
    );

void main() {
  const sizes = {
    'phone': Size(390, 844),
    'small': Size(320, 690),
    'desk': Size(1280, 800),
  };

  for (final e in sizes.entries) {
    testWidgets('shell mid-drag ${e.key}', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = e.value;
      addTearDown(t.view.reset);
      await t.pumpWidget(_shell(true));
      await t.pump(const Duration(milliseconds: 400));
      final g = await t.startGesture(Offset(e.value.width / 2, 300));
      await g.moveBy(const Offset(40, 0));
      await g.moveBy(Offset(e.value.width * .3, 0));
      await t.pump();
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('goldens/gestures/shell_drag_${e.key}.png'));
      await g.up();
      await t.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('image viewer mid-drag ${e.key}', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = e.value;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
            builder: (ctx) => TextButton(
                key: const Key('o'),
                onPressed: () => showImageViewer(ctx,
                    client: _Client(), path: '/tmp/a.png'),
                child: const Text('open'))),
      ));
      await t.tap(find.byKey(const Key('o')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      final g = await t.startGesture(Offset(e.value.width / 2, 300));
      await g.moveBy(const Offset(0, 20));
      await g.moveBy(const Offset(0, 150));
      await t.pump();
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('goldens/gestures/viewer_drag_${e.key}.png'));
      await g.up();
      await t.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('recorder strip', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(390, 200);
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Center(
          child: DesktopRecorderStrip(
            recording: false,
            time: '0:12',
            playing: false,
            wave: Container(height: 4, color: AppColors.fg3),
            onDiscard: () {},
            onPlay: () {},
            onStop: () {},
            onSend: () {},
            onSeek: (_) {},
          ),
        ),
      ),
    ));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/gestures/recorder_strip.png'));
    debugDefaultTargetPlatformOverride = null;
  });
}
