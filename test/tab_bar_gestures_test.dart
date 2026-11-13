import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/screens/shell_window_bar.dart';
import 'package:snippet/theme.dart';

void main() {
  testWidgets(
      'middle-click closes closable tabs, double-click empty space opens new session, tooltips include title and folder',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final client = DaemonClient('https://daemon.invalid', 'test');
    final mc = ShellTab.session(
      client: client,
      instanceUrl: 'https://daemon.invalid',
      sessionId: 'mission-control',
      title: 'Mission Control',
    );
    final s1 = ShellTab.session(
      client: client,
      instanceUrl: 'https://daemon.invalid',
      sessionId: 's1',
      title: 'Very Long Session Title That Truncates',
    );
    final s2 = ShellTab.session(
      client: client,
      instanceUrl: 'https://daemon.invalid',
      sessionId: 's2',
      title: 'Second Session',
    );

    final closed = <String>[];
    var newSessionCalls = 0;

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 44,
          child: MainTabsStrip(
            controller: ScrollController(),
            tabs: [mc, s1, s2],
            activeTab: s1,
            statusForTab: (_) => null,
            canCloseTab: (t) => !t.isMissionControl,
            onActivateTab: (_) {},
            onCloseTab: (t) => closed.add(t.sessionId ?? t.key),
            onNewSession: () => newSessionCalls++,
            chipKeyFor: (_) => GlobalKey(),
            folderFor: (t) => t.sessionId == 's1' ? 'snippet-mobile' : null,
          ),
        ),
      ),
    ));
    await tester.pump();

    // Tooltips have 600ms delay, full title, and folder name when present.
    final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip)).toList();
    final tabTips = tooltips.where((t) =>
        t.waitDuration == const Duration(milliseconds: 600));
    expect(
      tabTips.map((t) => t.message).toList(),
      [
        'Mission Control',
        'Very Long Session Title That Truncates\nsnippet-mobile',
        'Second Session',
      ],
    );

    // Middle-click on inactive closable tab s2 closes it.
    final middleDown = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await middleDown.down(tester.getCenter(find.text('Second Session')));
    await middleDown.up();
    await tester.pump();
    expect(closed, ['s2']);

    // Middle-click on active closable tab s1 also closes it.
    await middleDown.down(
        tester.getCenter(find.text('Very Long Session Title That Truncates')));
    await middleDown.up();
    await tester.pump();
    expect(closed, ['s2', 's1']);

    // Middle-click on non-closable MC tab does nothing.
    final mcChip = find.byType(TopWorkspaceTabChip).first;
    await middleDown.down(tester.getCenter(mcChip));
    await middleDown.up();
    await tester.pump();
    expect(closed, ['s2', 's1']);
    await middleDown.removePointer();

    // Double-click on a tab does NOT trigger new session.
    final s2Center = tester.getCenter(find.text('Second Session'));
    await tester.tapAt(s2Center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(s2Center);
    await tester.pump(const Duration(milliseconds: 300));
    expect(newSessionCalls, 0);

    // Double-click on empty space opens a new session.
    final emptySpace = find.byKey(const ValueKey('tab-strip-empty-space'));
    expect(emptySpace, findsOneWidget);
    final emptyCenter = tester.getCenter(emptySpace);
    await tester.tapAt(emptyCenter);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(emptyCenter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(newSessionCalls, 1);

    debugDefaultTargetPlatformOverride = null;
  });
}
