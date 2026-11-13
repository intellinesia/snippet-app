import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/command_palette.dart';
import 'package:snippet/glass.dart';

PaletteItem _i(String id, PaletteKind k, String title, {String sub = ''}) =>
    PaletteItem(id: id, kind: k, icon: 'search', title: title, subtitle: sub, run: () {});

void main() {
  testWidgets('desktop palette groups and footer', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    Glass.enabled = false;
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final items = [
      _i('a', PaletteKind.command, 'Review settings'),
      _i('b', PaletteKind.agent, 'Review bot', sub: 'idle'),
      _i('c', PaletteKind.task, 'Review task'),
      _i('d', PaletteKind.session, 'Review session', sub: 'repo'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => TextButton(
            onPressed: () => showCommandPalette(c, items: items),
            child: const Text('go')),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'review');
    await tester.pumpAndSettle();
    final ys = [
      for (final h in ['Sessions', 'Tasks', 'Agents', 'Actions'])
        tester.getTopLeft(find.text(h)).dy
    ];
    expect([...ys]..sort(), ys);
    expect(find.textContaining('↑↓'), findsOneWidget);
    expect(find.textContaining('repo', findRichText: true), findsOneWidget);
    expect(find.textContaining('esc'), findsOneWidget);
    expect(find.textContaining('new tab'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
