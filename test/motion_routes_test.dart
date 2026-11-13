import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/motion_routes.dart';
import 'package:snippet/screens/mobile_shell.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/screens/sidebar.dart';
import 'package:snippet/theme.dart';

class _Client extends DaemonClient {
  _Client() : super('https://daemon.invalid', 'test');
}

void main() {
  test('sheetMotion uses 320ms open and 220ms close', () {
    expect(sheetMotion.duration, const Duration(milliseconds: 320));
    expect(sheetMotion.reverseDuration, const Duration(milliseconds: 220));
  });

  group('AppPageRoute on Android', () {
    Future<void> pushSecond(WidgetTester t, {bool disableAnimations = false}) async {
      await t.pumpWidget(MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (ctx) => Scaffold(
              key: const Key('page1'),
              body: Center(
                child: TextButton(
                  key: const Key('push'),
                  onPressed: () => pushApp<void>(
                    ctx,
                    (_) => Scaffold(
                      key: const Key('page2'),
                      body: const Center(child: Text('Second')),
                    ),
                  ),
                  child: const Text('Push'),
                ),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.byKey(const Key('push')));
    }

    testWidgets('slides incoming from right and parallax-shifts outgoing',
        (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await pushSecond(t);
        await t.pump();
        await t.pump(const Duration(milliseconds: 170));
        expect(t.getTopLeft(find.byKey(const Key('page2'))).dx, greaterThan(0));
        expect(t.getTopLeft(find.byKey(const Key('page1'))).dx, lessThan(0));
        await t.pumpAndSettle();
        expect(t.getTopLeft(find.byKey(const Key('page2'))).dx, closeTo(0, 0.5));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('pops on an edge drag past 1/3 threshold', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await pushSecond(t);
        await t.pumpAndSettle();

        final g = await t.startGesture(const Offset(8, 300));
        await g.moveBy(const Offset(160, 0));
        await g.moveBy(const Offset(160, 0));
        await t.pump();
        expect(t.getTopLeft(find.byKey(const Key('page2'))).dx, closeTo(320, 2));
        expect(t.getTopLeft(find.byKey(const Key('page1'))).dx, lessThan(0));
        await g.up();
        await t.pumpAndSettle();

        expect(find.byKey(const Key('page2')), findsNothing);
        expect(find.byKey(const Key('page1')), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('cancels edge drag below 1/3 threshold', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await pushSecond(t);
        await t.pumpAndSettle();

        await t.timedDragFrom(
          const Offset(8, 300),
          const Offset(200, 0),
          const Duration(seconds: 1),
        );
        await t.pumpAndSettle();

        expect(find.byKey(const Key('page2')), findsOneWidget);
        expect(t.getTopLeft(find.byKey(const Key('page2'))).dx, closeTo(0, 0.5));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('pops on fast fling from left edge', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await pushSecond(t);
        await t.pumpAndSettle();

        await t.flingFrom(const Offset(8, 300), const Offset(100, 0), 1200);
        await t.pumpAndSettle();

        expect(find.byKey(const Key('page2')), findsNothing);
        expect(find.byKey(const Key('page1')), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('reduced motion uses 150ms fade and no slide', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await pushSecond(t, disableAnimations: true);
        await t.pump();
        await t.pump(const Duration(milliseconds: 75));

        expect(find.byKey(const Key('page2')), findsOneWidget);
        expect(t.getTopLeft(find.byKey(const Key('page2'))).dx, closeTo(0, 0.01));
        expect(t.getTopLeft(find.byKey(const Key('page1'))).dx, closeTo(0, 0.01));

        await t.pump(const Duration(milliseconds: 90));
        expect(find.byKey(const Key('page2')), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  testWidgets('AppPageRoute on desktop does not enable edge pop swipe',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await t.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              key: const Key('push'),
              onPressed: () => pushApp<void>(
                ctx,
                (_) => const Scaffold(key: Key('page2'), body: Text('Second')),
              ),
              child: const Text('Push'),
            ),
          ),
        ),
      ));
      await t.tap(find.byKey(const Key('push')));
      await t.pumpAndSettle();

      await t.timedDragFrom(
        const Offset(8, 300),
        const Offset(350, 0),
        const Duration(milliseconds: 300),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('page2')), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  group('MobileShell session slide & Android edge swipe', () {
    testWidgets('slides session in from right and edge-swipes back past 1/3',
        (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        var chatsOpen = true;
        late StateSetter hostSetState;

        Widget buildShell() => MaterialApp(
              theme: buildAppTheme(),
              home: StatefulBuilder(
                builder: (ctx, setState) {
                  hostSetState = setState;
                  return MobileShell(
                    activeTabBody: const SizedBox.expand(
                      child: ColoredBox(key: Key('tab'), color: Colors.blue),
                    ),
                    sidebar: const SizedBox.expand(
                      child: ColoredBox(key: Key('side'), color: Colors.red),
                    ),
                    hasActiveTab: true,
                    chatsOpen: chatsOpen,
                    drilledDown: false,
                    mobileHome: MobileHome.chats,
                    onClearDrillDown: () {},
                    onMobileHome: (_) {},
                    onCloseChats: () {},
                    onOpenChats: () => setState(() => chatsOpen = true),
                  );
                },
              ),
            );

        await t.pumpWidget(buildShell());
        await t.pumpAndSettle();

        hostSetState(() => chatsOpen = false);
        await t.pump();
        await t.pump(const Duration(milliseconds: 170));
        expect(t.getTopLeft(find.byKey(const Key('tab'))).dx, greaterThan(0));
        expect(t.getTopLeft(find.byKey(const Key('side'))).dx, lessThan(0));

        await t.pumpAndSettle();
        expect(t.getTopLeft(find.byKey(const Key('tab'))).dx, closeTo(0, 0.5));

        // Drag below 1/3 cancels.
        await t.timedDragFrom(
          const Offset(8, 300),
          const Offset(200, 0),
          const Duration(seconds: 1),
        );
        await t.pumpAndSettle();
        expect(chatsOpen, isFalse);

        // Drag past 1/3 commits pop back to chats.
        final g = await t.startGesture(const Offset(8, 300));
        await g.moveBy(const Offset(160, 0));
        await g.moveBy(const Offset(160, 0));
        await t.pump();
        expect(t.getTopLeft(find.byKey(const Key('tab'))).dx, closeTo(320, 2));
        await g.up();
        await t.pumpAndSettle();
        expect(chatsOpen, isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('Sidebar home tab & settings transitions', () {
    Widget buildSidebar(MobileHome home) => MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Sidebar(
              instances: const [],
              active: null,
              client: _Client(),
              selectedSessionId: null,
              sessions: const [],
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
              health: const {'https://daemon.invalid': true},
              onRefreshHealth: () {},
              topInset: false,
              mobileHome: home,
              onMobileHome: (_) {},
              settingsSection: null,
              onSettingsSection: (_) {},
              agent: null,
              onAgent: (_) {},
            ),
          ),
        );

    testWidgets('Sessions <-> Agents crossfades with 8px slide and Settings pushes/pops from right',
        (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await t.pumpWidget(buildSidebar(MobileHome.chats));
        await t.pumpAndSettle();

        // Chats -> Agents: incoming Agents slides from +8px -> 0.
        await t.pumpWidget(buildSidebar(MobileHome.agents));
        await t.pump();
        await t.pump(const Duration(milliseconds: 60));
        final agentsDx =
            t.getTopLeft(find.byKey(const ValueKey('mobile-agents'))).dx;
        expect(agentsDx, greaterThan(0));
        expect(agentsDx, lessThanOrEqualTo(8.0));
        await t.pumpAndSettle();

        // Agents -> Chats: incoming Chats slides from -8px -> 0.
        await t.pumpWidget(buildSidebar(MobileHome.chats));
        await t.pump();
        await t.pump(const Duration(milliseconds: 60));
        final chatsDx =
            t.getTopLeft(find.byKey(const ValueKey('mobile-chats'))).dx;
        expect(chatsDx, lessThan(0));
        expect(chatsDx, greaterThanOrEqualTo(-8.0));
        await t.pumpAndSettle();

        // Chats -> Settings: Settings slides in from right (> 50px mid-flight).
        await t.pumpWidget(buildSidebar(MobileHome.settings));
        await t.pump();
        await t.pump(const Duration(milliseconds: 120));
        final settingsInDx =
            t.getTopLeft(find.byKey(const ValueKey('mobile-settings'))).dx;
        final chatsParallaxDx =
            t.getTopLeft(find.byKey(const ValueKey('mobile-chats'))).dx;
        expect(settingsInDx, greaterThan(50));
        expect(chatsParallaxDx, lessThan(0));
        await t.pumpAndSettle();

        // Settings -> Chats: Settings slides out to the right (> 50px mid-flight).
        await t.pumpWidget(buildSidebar(MobileHome.chats));
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        final settingsOutDx =
            t.getTopLeft(find.byKey(const ValueKey('mobile-settings'))).dx;
        expect(settingsOutDx, greaterThan(50));
        await t.pumpAndSettle();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
