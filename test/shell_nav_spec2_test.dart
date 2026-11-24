import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/mobile_home/everyone_switcher.dart';
import 'package:snippet/screens/phone_tool_bar.dart';
import 'package:snippet/screens/shell_rail.dart' show ShellSection;
import 'package:snippet/screens/terminals_sidebar_panel.dart';
import 'package:snippet/screens/session.dart' show TerminalInfo;
import 'package:snippet/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:snippet/screens/file_tree_sidebar_panel.dart' show FileTreeRow;

Widget _wrap(double scale, Widget child) => MaterialApp(
      theme: buildAppTheme(),
      builder: (c, ch) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: ch!,
      ),
      home: Scaffold(body: child),
    );

CoordinationAgent _agent(int i) => CoordinationAgent.fromJson({
      'id': 'a$i',
      'display_name': i == 1 ? 'Ada review assistant' : 'Agent $i',
      'handle': 'a$i',
      'kind': 'agent',
      'status': 'active',
      'needs_you': i == 0 ? 1 : 0,
    });

void main() {
  for (final w in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 1.35, 2.0]) {
      testWidgets('tool header w=$w s=$scale', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(w, 852);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_wrap(
            scale,
            Column(children: [
              PhoneToolHeader(
                  section: ShellSection.files,
                  subtitle: 'snippet - main',
                  onSection: (_) {},
                  onMore: () {}),
            ])));
        expect(tester.takeException(), isNull);
        final back = tester.getRect(find.bySemanticsLabel('Back'));
        final chips = [
          for (final l in ['Files', 'Git', 'Terminals'])
            tester.getRect(find
                .ancestor(
                    of: find.descendant(
                        of: find.byType(PhoneToolChips),
                        matching: find.text(l)),
                    matching: find.byType(Container))
                .first)
        ];
        final title = tester.getTopLeft(find.text('Files').first);
        // ignore: avoid_print
        print('w=$w s=$scale back=${back.size}@${back.left} chips=${chips.map((c) => c.size).toList()} chipLeft=${chips.first.left}');
        expect(back.size, const Size(48, 48));
        expect(back.left, 0);
        for (final c in chips) {
          expect(c.height, 44);
        }
        expect(chips.first.left, 16);
        expect(chips[1].left - chips[0].right, 8);
        expect(title.dx, greaterThan(0));
      });
      testWidgets('file row w=$w s=$scale', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(w, 852);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_wrap(
            scale,
            Column(children: [
              FileTreeRow(
                  entry: FsEntry.fromJson({
                    'name': 'main.dart',
                    'path': '/p/main.dart',
                    'is_dir': false,
                    'git': true,
                    'git_status': 'modified',
                  }),
                  depth: 1,
                  expanded: false,
                  loading: false,
                  hasError: false,
                  onTap: () {}),
              FileTreeRow(
                  entry: FsEntry.fromJson(
                      {'name': 'lib', 'path': '/p/lib', 'is_dir': true}),
                  depth: 0,
                  expanded: false,
                  loading: false,
                  hasError: false,
                  onTap: () {}),
            ])));
        expect(tester.takeException(), isNull);
        final r = tester.getRect(find
            .ancestor(of: find.text('main.dart'), matching: find.byType(InkWell))
            .first);
        // ignore: avoid_print
        print('w=$w s=$scale fileRow=${r.size} M=${find.text('M').evaluate().length}');
        expect(r.width, w);
        expect(r.height, greaterThanOrEqualTo(48));
        expect(tester.getTopLeft(find.text('main.dart')).dx, 62);
        expect(find.text('M'), findsOneWidget);
        debugDefaultTargetPlatformOverride = null;
      });
      testWidgets('switcher w=$w s=$scale', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(w, 852);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_wrap(
            scale,
            SizedBox(
              height: 752,
              child: EveryoneSwitcher(
                agents: [for (var i = 0; i < 9; i++) _agent(i)],
                groups: const [],
                sessions: const [],
                onOpenAgent: (_) {},
                onOpenGroup: (_) {},
                onOpenSession: (_) {},
              ),
            )));
        await tester.pump();
        expect(tester.takeException(), isNull);
        final search = tester.getRect(find.byKey(const ValueKey('switcher-search')));
        expect(search.left, 16);
        expect(search.width, w - 32);
        expect(search.height, 44);
        final rows = find.byKey(const ValueKey('sw-agent-a1'));
        final r = tester.getRect(rows);
        // ignore: avoid_print
        print('w=$w s=$scale search=${search.size} row=${r.size}');
        expect(r.width, w);
        expect(r.height, greaterThanOrEqualTo(48));
        if (scale == 2.0) {
          expect(find.text('Search'), findsOneWidget);
          final hint = tester.getRect(find.text('Search'));
          expect(hint.right, lessThanOrEqualTo(search.right));
        }
        if (scale < 1.5) {
          final name = find.descendant(
              of: find.byKey(const ValueKey('sw-agent-a1')),
              matching: find.text('Ada review assistant'));
          final para = tester.renderObject<RenderParagraph>(name.first);
          expect(para.didExceedMaxLines, isFalse);
        }
        expect(find.text('Show all 9'), findsOneWidget);
        final fold = tester.getRect(find
            .ancestor(of: find.text('Show all 9'), matching: find.byType(InkWell))
            .first);
        expect(fold.height, greaterThanOrEqualTo(48));
        expect(fold.width, w);
        await tester.tap(find.text('Show all 9'));
        await tester.pump();
        expect(find.text('Show all 9'), findsNothing);
        expect(find.byKey(const ValueKey('sw-agent-a8')), findsOneWidget);
      });
      testWidgets('terminals w=$w s=$scale', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(w, 852);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_wrap(
            scale,
            TerminalsSidebarPanel(
              workspacePath: '/home/x/proj',
              terminals: [
                TerminalInfo(id: 't1', title: 'zsh', alive: true, live: true),
                TerminalInfo(id: 't2', title: 'dev', alive: false, live: false),
              ],
              focus: 0,
              onNewTerminal: () {},
              onOpenTerminal: (_) {},
              onCloseTerminal: (_) {},
              showHeader: false,
            )));
        expect(tester.takeException(), isNull);
        final row = tester.getRect(find
            .ancestor(of: find.text('zsh'), matching: find.byType(InkWell))
            .first);
        final btn = tester.getRect(find
            .ancestor(of: find.text('New terminal'), matching: find.byType(InkWell))
            .first);
        // ignore: avoid_print
        print('w=$w s=$scale termRow=${row.size} newBtn=${btn.size}@${btn.left}');
        expect(row.width, w);
        expect(row.height, greaterThanOrEqualTo(64));
        expect(btn.left, 16);
        expect(btn.width, w - 32);
        expect(btn.height, greaterThanOrEqualTo(48));
        expect(find.textContaining('running'), findsOneWidget);
        expect(find.textContaining('stopped'), findsOneWidget);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
