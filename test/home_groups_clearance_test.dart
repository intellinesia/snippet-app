import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';
import 'package:snippet/notification_popovers.dart';
import 'package:snippet/notification_sync.dart';
import 'package:snippet/quiet.dart';
import 'package:snippet/screens/mobile_home/quiet_home.dart';
import 'package:snippet/theme.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    for (final band in [false, true]) {
      testWidgets('first Groups row clears the tab bar at ${scale}x band=$band',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(393, 852);
        addTearDown(tester.view.reset);
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        foregroundNotifications.drain();
        if (band) {
          foregroundNotifications.add({
            'title': 'Lead',
            'kind': 'idle',
            'body': 'Finished and standing by after a very long status line',
          });
        }
        await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: NotificationPopovers(
              child: Scaffold(
            body: SafeArea(
                child: QuietHomeScreen(
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
                    {'agent_id': 'snip'}
                  ]
                })
              ],
              onOpenSession: (_) {},
              onOpenSessions: () {},
              onSettings: () {},
              onSearch: () {},
              onOpenAgent: (_) {},
              onAllAgents: () {},
              onArtifacts: () {},
            )),
            bottomNavigationBar: QuietTabBar(
                selected: QuietPlace.agents, onSelect: (_) {}, onNew: () {}),
          )),
        ));
        await tester.pump(const Duration(milliseconds: 700));
        final row = tester.getRect(find
            .ancestor(of: find.text('Canvas review'), matching: find.byType(QuietRow))
            .first);
        final tab = tester.getRect(find.byType(QuietTabBar));
        // ignore: avoid_print
        print('GROUPS ${scale}x band=$band row=$row tabTop=${tab.top}');
        expect(row.bottom, lessThanOrEqualTo(tab.top));
        foregroundNotifications.drain();
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
