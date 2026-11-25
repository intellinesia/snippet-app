import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/shell_frame.dart';

void main() {
  testWidgets('desktop shell uses the revised 40/36 top chrome density',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 600,
        child: Column(children: [
          ShellTitleRow(
            onToggleSidebar: () {},
            canNavigateBack: false,
            canNavigateForward: false,
            onNavigateBack: () {},
            onNavigateForward: () {},
          ),
          const ShellTabStripFrame(
            tabs: SizedBox(
              key: ValueKey('density-tab-child'),
              width: 120,
              height: 32,
            ),
          ),
        ]),
      ),
    ));

    final title = tester.getRect(find.byKey(const ValueKey('shell-title-row')));
    final strip = tester.getRect(find.byKey(const ValueKey('shell-tab-strip')));
    final tab = tester.getRect(find.byKey(const ValueKey('density-tab-child')));

    expect(title.height, kShellTitleRowHeight);
    expect(title.height, 40);
    expect(strip.height, kShellTabStripHeight);
    expect(strip.height, 36);
    expect(tab.top - strip.top, closeTo(2, 1));
    expect(tab.height, 32);
  });
}
