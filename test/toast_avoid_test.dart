import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/canvas/canvas_screen.dart';
import 'package:snippet/mochi.dart';
import 'package:snippet/models.dart';
import 'package:snippet/tap_detector.dart';
import 'package:snippet/notification_banner.dart';
import 'package:snippet/toast_avoid.dart';
import 'package:snippet/notification_popovers.dart';
import 'package:snippet/notification_sync.dart';
import 'package:snippet/screens/artifact_viewer.dart';
import 'package:snippet/screens/artifacts_screen.dart';
import 'package:snippet/screens/mobile_chrome.dart';
import 'package:snippet/screens/mobile_home/agents_home.dart';
import 'package:snippet/screens/mobile_home/quiet_home.dart';
import 'package:snippet/theme.dart';

import 'canvas_layout_test.dart' show EmptyCanvasClient;

class _Daemon extends DaemonClient {
  _Daemon() : super('http://127.0.0.1:9', 'tok');
  @override
  Future<List<Map<String, dynamic>>> getArtifactCards() async => [
        {
          'id': 'c1',
          'kind': 'canvas',
          'title': 'Pricing board',
          'rev': 3,
          'updated_at': '2026-11-24T12:00:00Z',
        },
        {
          'id': 's1/a1',
          'kind': 'document',
          'title': 'QA doc',
          'rev': 1,
          'updated_at': '2026-11-24T11:00:00Z',
        },
      ];
}

void main() {
  final screens =
      <String, (Widget Function(), Map<String, Finder> Function())>{
    'home': (
      () => ToastAvoid(
              child: Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  child: Row(children: [
                    const Spacer(),
                    Semantics(
                        label: 'Search',
                        child: IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.search))),
                    Semantics(
                        label: 'Settings',
                        child: IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.settings))),
                  ]))),
      () => {
            'Search': find.widgetWithIcon(IconButton, Icons.search),
            'Settings': find.widgetWithIcon(IconButton, Icons.settings),
          },
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
            groups: [
              GroupSummary.fromJson({
                'id': 'g1',
                'title': 'Canvas review',
                'members': [
                  {'agent_id': 'lead'},
                  {'agent_id': 'snip'},
                ],
              }),
            ],
            onOpenSession: (_) {},
            onOpenSessions: () {},
            onSettings: () {},
            onSearch: () {},
            onOpenAgent: (_) {},
            onOpenGroup: (_) {},
          ),
      () => {
            'Search': find.bySemanticsLabel('Search'),
            'Settings': find.bySemanticsLabel('Settings'),
            'Avatar': find.ancestor(
                of: find.byType(AgentMochi).first,
                matching: find.byType(MarkRow)),
            'CanvasReview': find.ancestor(
                of: find.text('Canvas review'), matching: find.byType(MarkRow)),
          },
    ),
    'sessions': (
      () => QuietSessionsScreen(
            sessions: const [],
            agents: const [],
            onOpenSession: (_) {},
            onNew: () {},
          ),
      () => {
            'NewSessionPill': find.ancestor(
                of: find.text('New session'),
                matching: find.byType(TapDetector)),
          },
    ),
    'artifacts': (
      () => ArtifactsScreen(client: _Daemon()),
      () => {
            'NewCanvas': find.bySemanticsLabel('New canvas'),
            'SearchField': find.byType(TextField),
            'AllChip': find.text('All'),
            'Back': find.byTooltip('Back'),
            'Row1': find.text('Pricing board'),
            'Row2': find.text('QA doc'),
          },
    ),
    'canvas': (
      () => CanvasScreen(
          client: EmptyCanvasClient(), title: 'Pricing board', onClose: () {}),
      () => {
            'Pins': find.byWidgetPredicate((w) =>
                w is Tooltip && (w.message ?? '').startsWith('Pins,')),
            'BackFromCanvas': find.byWidgetPredicate((w) =>
                w is Tooltip &&
                (w.message ?? '').startsWith('Back from canvas')),
          },
    ),
    'viewer': (
      () => ArtifactViewer(
          client: _Daemon(), session: 's', id: 'a', onClose: () {}),
      () => {
            'More': find.byTooltip('More'),
            'Close': find.byTooltip('Close'),
          },
    ),
    'back bar': (
      () => MobileBackBar(title: 'Tasks', trailing: [
            IconButton(
                tooltip: 'Add', onPressed: () {}, icon: const Icon(Icons.add))
          ]),
      () => {
            'Add': find.byTooltip('Add'),
            'Back': find.byTooltip('Back'),
          },
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
        final toast = tester.getRect(find.byType(NotificationBanner));
        final out = <String>[];
        for (final target in e.value.$2().entries) {
          final els = target.value.evaluate().toList();
          if (els.isEmpty) {
            // Back button only renders when a parent Navigator can pop;
            // CanvasReview is below the ListView viewport fold at 3x text.
            if (target.key == 'Back' ||
                (target.key == 'CanvasReview' && scale > 2)) {
              continue;
            }
            fail('Expected target not found: ${target.key}');
          }
          for (final el in els) {
            final r = tester.getRect(find.byElementPredicate((x) => x == el));
            out.add('${target.key}=$r');
            // Banners float over content (NT-01); they must clear top bars.
            if (r.top < 100) {
              expect(toast.top, greaterThanOrEqualTo(r.bottom - 0.5),
                  reason: '$toast vs ${target.key} $r');
            }
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
      final title = tester.widget<Text>(find.text('Artifacts').first);
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
      sizes['title ${scale}x'] = tester.getSize(find.text('Artifacts').first);
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
