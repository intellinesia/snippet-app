import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/mobile_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/mobile_home/quiet_home.dart';
import 'package:snippet/screens/mobile_home/agents_home.dart' show SpecSwitch;
import 'package:snippet/screens/mobile_home/sessions_list_phone.dart';
import 'package:snippet/theme.dart';

SessionInfo _s(String id, Map<String, dynamic> extra) =>
    SessionInfo.fromJson({
      'id': id,
      'folder': '/Users/x/snippet-mobile-all',
      'last_active': DateTime.now().millisecondsSinceEpoch ~/ 1000 - 240,
      ...extra,
    });

final _sessions = [
  _s('a', {'title': 'Wire the wake', 'status': 'running', 'branch': 'feat/wake'}),
  _s('b', {'title': '', 'status': 'idle'}),
  _s('c', {'title': 'Ask me', 'status': 'waiting_for_input'}),
  _s('d', {'title': 'Broke', 'status': 'failed', 'branch': 'feat/wake'}),
];

Widget _wrap(double scale, Widget home) => MaterialApp(
      theme: buildAppTheme(),
      builder: (c, ch) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: ch!),
      home: Scaffold(body: home),
    );

Widget _screen(List<SessionInfo> l) => QuietSessionsScreen(
    sessions: l, agents: const [], onOpenSession: (_) {}, onNew: () {});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final w in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 1.35, 2.0]) {
      testWidgets('sessions list w=$w s=$scale', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(w, 852);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_wrap(scale, _screen(_sessions)));
        await tester.pump();
        expect(tester.takeException(), isNull);
        final t = tester.widget<Text>(find.text('Sessions').last);
        expect(t.style!.fontSize, 28);
        expect(tester.getTopLeft(find.text('Sessions').last).dx, 16);
        // Connected filter group: segments at least 44 high, tight gaps.
        final chipAll = tester.getRect(find.bySemanticsLabel('All, 4'));
        expect(chipAll.height, greaterThanOrEqualTo(44));
        final chipW = tester.getRect(find.bySemanticsLabel('Working, 1'));
        expect(chipW.left - chipAll.right, lessThanOrEqualTo(4));
        for (final l in ['Filter', 'Search']) {
          final r = tester.getRect(find.bySemanticsLabel(l));
          expect(r.width, greaterThanOrEqualTo(kAndroidLook ? 48 : 44));
          expect(r.height, greaterThanOrEqualTo(kAndroidLook ? 48 : 44));
        }
        expect(tester.getRect(find.bySemanticsLabel('Search')).right, w - 4);
        expect(tester.getRect(find.bySemanticsLabel('Filter')).right, w - 52);
        // Rows.
        final rows = find.byType(SessionRowPhone);
        expect(rows, findsNWidgets(4));
        for (final e in rows.evaluate()) {
          final r = tester.getRect(find.byElementPredicate((x) => x == e));
          expect(r.height, greaterThanOrEqualTo(60));
          expect(r.width, kAndroidLook ? w - 32 : w);
        }
        // Title never "Untitled session"; fallback names the folder.
        expect(find.text('Untitled session'), findsNothing);
        expect(find.text('New session in snippet-mobile-all'), findsOneWidget);
        // Title after the state mark: gutter + 24 mark + 14 gap.
        expect(tester.getTopLeft(find.text('Wire the wake')).dx,
            (kAndroidLook ? 32 : MK.gutter) + 24 + 14);
        // Group label.
        expect(find.text('snippet-mobile-all'), findsNWidgets(2)); // group label + sub
        // Needs you row: amber word only; failed row carries the word.
        expect(find.text('Needs you'), findsOneWidget); // row; the chip is rich text
        expect(find.text('Failed - feat/wake'), findsOneWidget);
      });
    }
  }

  testWidgets('chip counts and filters', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(1, _screen(_sessions)));
    await tester.pump();
    expect(find.bySemanticsLabel('Working, 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Needs you, 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Done, 2'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Done, 2'));
    await tester.pump();
    expect(find.byType(SessionRowPhone), findsNWidgets(2));
  });

  testWidgets('empty states', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(1, _screen(const [])));
    await tester.pump();
    expect(find.text('No sessions'), findsOneWidget);
    expect(find.text('Start one from a folder on your Mac.'), findsOneWidget);
    await tester.pumpWidget(_wrap(1, _screen([_sessions[1]])));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Working, 0'));
    await tester.pump();
    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('No working sessions.'), findsOneWidget);
  });

  testWidgets('filter sheet persists group by folder', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(1, _screen(_sessions)));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Filter'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.text('Group by folder'), findsOneWidget);
    tester.widget<SpecSwitch>(find.byType(SpecSwitch)).onChanged!(false);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 400));
    // Grouping off: the folder label is gone, only the sub line remains.
    expect(find.text('snippet-mobile-all'), findsOneWidget);
  });
}
