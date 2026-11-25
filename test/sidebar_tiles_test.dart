import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/sidebar_tiles.dart';
import 'package:snippet/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('section count is visible when expanded and collapsed',
      (tester) async {
    Future<void> pump(bool collapsed) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 240,
              child: SidebarSectionHeader(
                'Agents',
                count: 7,
                collapsed: collapsed,
                onToggle: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pump(false);
    expect(find.text('7'), findsOneWidget);
    final expanded = tester.widget<Text>(find.text('7'));
    expect(expanded.style?.fontSize, 11);
    expect(expanded.style?.color, AppColors.fg3);

    await pump(true);
    expect(find.text('7'), findsOneWidget);
  });
}
