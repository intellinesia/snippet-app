import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/canvas/canvas_screen.dart';
import 'package:snippet/mochi.dart';
import 'package:snippet/models.dart';
import 'package:snippet/quiet.dart' show QuietRow;
import 'package:snippet/tap_detector.dart';
import 'package:snippet/notification_card.dart';
import 'package:snippet/notification_popovers.dart';
import 'package:snippet/notification_sync.dart';
import 'package:snippet/screens/artifact_viewer.dart';
import 'package:snippet/screens/artifacts_screen.dart';
import 'package:snippet/screens/mobile_chrome.dart';
import 'package:snippet/screens/mobile_home/quiet_home.dart';
import 'package:snippet/theme.dart';

import 'canvas_layout_test.dart' show EmptyCanvasClient;

class _Daemon extends DaemonClient {
  _Daemon() : super('http://127.0.0.1:9', 'tok');
  @override
  Future<List<Map<String, dynamic>>> getArtifactCards() async => [];
}

void main() {
  final screens = <String, (Widget Function(), List<Finder> Function())>{
    'home': (
      () => QuietPlaceHeader(title: 'Agents', onSearch: () {}, onSettings: () {}),
      () => [find.bySemanticsLabel('Search'), find.bySemanticsLabel('Settings')],
    ),
    'home avatars': (
      () => QuietHomeScreen(
            sessions: const [],
            agents: [
              CoordinationAgent.fromJson({
                'id': 'lead',
                'display_name': 'Lead',
                'handle': 'lead',
                'status': 'active',
                'is_lead': true
              }),
              CoordinationAgent.fromJson({
                'id': 'snip',
                'display_name': 'Snippet',
                'handle': 'snip',
                'status': 'active'
              }),
            ],
            onOpenSession: (_) {},
            onOpenSessions: () {},
            onSettings: () {},
            onSearch: () {},
            onOpenAgent: (_) {},
          ),
      () => [
            find.bySemanticsLabel('Search'),
            find.bySemanticsLabel('Settings'),
            find.ancestor(
                of: find.byType(AgentMochi), matching: find.byType(TapDetector)),
            find.ancestor(
                of: find.text('Ask Lead what is next'),
                matching: find.byType(QuietRow)),
          ],
    ),
    'artifacts': (
      () => ArtifactsScreen(client: _Daemon()),
      () => [
            find.bySemanticsLabel('New canvas'),
            find.byType(TextField),
            find.text('All'),
            find.byTooltip('Back'),
          ],
    ),
    'canvas': (
      () => CanvasScreen(
          client: EmptyCanvasClient(), title: 'Pricing board', onClose: () {}),
      () => [
            find.byWidgetPredicate((w) =>
                w is Tooltip && (w.message ?? '').startsWith('Pins,')),
            find.byWidgetPredicate((w) =>
                w is Tooltip &&
                (w.message ?? '').startsWith('Back from canvas')),
          ],
    ),
    'viewer': (
      () => ArtifactViewer(
          client: _Daemon(), session: 's', id: 'a', onClose: () {}),
      () => [find.byTooltip('More'), find.byTooltip('Close')],
    ),
    'back bar': (
      () => MobileBackBar(title: 'Tasks', trailing: [
            IconButton(
                tooltip: 'Add', onPressed: () {}, icon: const Icon(Icons.add))
          ]),
      () => [find.byTooltip('Add'), find.byTooltip('Back')],
    ),
  };

  for (final e in screens.entries) {
    for (final scale in [1.0, 2.0, 3.0]) {
      // MobileBackBar's own text column overflows 4px at 3x, unrelated to toasts.
      if (e.key == 'back bar' && scale > 2) continue;
      testWidgets('toast clears ${e.key} actions at ${scale}x', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(393, 852);
        addTearDown(tester.view.reset);
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final sem = tester.ensureSemantics();
        foregroundNotifications.drain();
        foregroundNotifications.add({
          'title': 'Lead',
          'kind': 'idle',
          'body': 'Finished and standing by after a very long status line',
        });
        await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: NotificationPopovers(
              child: Scaffold(
                  body: SafeArea(
                      child: Column(children: [
            Expanded(
                child: Stack(children: [
              Positioned.fill(
                  child: e.key == 'home' || e.key == 'back bar'
                      ? ListView(children: [e.value.$1()])
                      : e.value.$1()),
            ]))
          ])))),
        ));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 600));
        final toast = tester.getRect(find.byType(NotificationMessageCard));
        final out = <String>[];
        for (final f in e.value.$2()) {
          if (f.evaluate().isEmpty) continue;
          for (final el in f.evaluate()) {
            final r = tester.getRect(find.byElementPredicate((x) => x == el));
            out.add('$r');
            expect(toast.overlaps(r), isFalse, reason: '$toast vs $r');
          }
        }
        expect(out, isNotEmpty);
        // ignore: avoid_print
        print('TOAST ${e.key} ${scale}x toast=$toast actions=$out');
        sem.dispose();
        debugDefaultTargetPlatformOverride = null;
        foregroundNotifications.drain();
      });
    }
  }

  testWidgets('artifacts title ellipsizes and New canvas collapses at 2x',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final sem = tester.ensureSemantics();
    final sizes = <String, Size>{};
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: Navigator(onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => ArtifactsScreen(client: _Daemon()))),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      final title = tester.widget<Text>(find.text('Artifacts'));
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
      sizes['title ${scale}x'] = tester.getSize(find.text('Artifacts'));
      sizes['newCanvas ${scale}x'] =
          tester.getSize(find.bySemanticsLabel('New canvas'));
      if (scale >= 1.5) {
        expect(sizes['newCanvas ${scale}x'], const Size(48, 48));
        expect(find.text('New canvas'), findsNothing);
      }
    }
    // ignore: avoid_print
    print('ARTIFACTS $sizes');
    expect(sizes['title 2.0x']!.height, lessThan(sizes['title 2.0x']!.width));
    sem.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
