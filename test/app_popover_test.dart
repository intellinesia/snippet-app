import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/menu_widgets.dart';

void main() {
  testWidgets('popover search filters rows and keyboard picks one',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    t.view.physicalSize = const Size(1200, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    String? picked;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => Center(
          child: TextButton(
            onPressed: () async => picked = await showAppMenu<String>(c,
                anchor: c,
                items: [
                  for (final n in 'a b c d e f g h'.split(' '))
                    appMenuItem<String>(value: n, label: 'Item $n'),
                ]),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await t.enterText(find.byType(TextField), 'item f');
    await t.pump();
    expect(find.text('Item a'), findsNothing);
    expect(find.text('Item f'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(picked, 'f');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('arrow keys move and wrap without search', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    String? picked;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () async => picked = await showAppMenu<String>(c,
              anchor: c, items: [
            appMenuItem<String>(value: 'x', label: 'X'),
            appMenuItem<String>(value: 'y', label: 'Y'),
          ]),
          child: const Text('open'),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(picked, 'y');
    debugDefaultTargetPlatformOverride = null;
  });
}
