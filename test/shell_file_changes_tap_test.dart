import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/screens/shell_pane_view.dart';
import 'package:snippet/theme.dart';

void main() {
  testWidgets('tapping a shell-changed file opens it by absolute path',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(420, 900);
    addTearDown(t.view.reset);
    final state = HarnessState.fromJson({
      'status': 'idle',
      'workspace': '/work/app',
      'events': [
        {
          'kind': 'turn_changes',
          'files': [
            {'path': 'lib/main.dart', 'add': 3, 'del': 1}
          ]
        }
      ],
    });
    final opened = <(String, String)>[];
    await t.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: RightTabBody(
          tab: RightTab.panel(RightPanel.checkpoints),
          state: state,
          controls: null,
          client: DaemonClient('http://x', 't'),
          activeSessionId: 's1',
          onOpenFile: (p, n) => opened.add((p, n)),
        ),
      ),
    ));
    await t.pump();
    await t.tap(find.text('main.dart'));
    await t.pump();
    expect(opened, [('/work/app/lib/main.dart', 'main.dart')]);
    debugDefaultTargetPlatformOverride = null;
  });
}
