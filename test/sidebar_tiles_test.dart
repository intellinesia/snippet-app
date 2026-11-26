import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/sidebar_tiles.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

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
                actions: [
                  SidebarSectionAction(
                      icon: 'search', tooltip: 'Search agents', onTap: (_) {}),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    await pump(false);
    expect(find.text('7'), findsOneWidget);
    final title = tester.widget<Text>(find.text('Agents'));
    expect(title.style?.fontSize, 13);
    expect(title.style?.fontWeight, W.label);
    expect(title.style?.color, AppColors.fg1);
    final action = tester.widget<AppIcon>(
        find.byWidgetPredicate((w) => w is AppIcon && w.name == 'search'));
    expect(action.size, 14);
    expect(action.color, AppColors.fg3);
    final expanded = tester.widget<Text>(find.text('7'));
    expect(expanded.style?.fontSize, 11.5);
    expect(expanded.style?.color, AppColors.fg3);

    await pump(true);
    expect(find.text('7'), findsOneWidget);
    // Reset inside the body: the binding checks debug vars before tear-down.
    debugDefaultTargetPlatformOverride = null;
  });
}
