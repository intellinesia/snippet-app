import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/sidebar_tiles.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('section count shows only once collapsed, as in Capy',
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
    expect(find.text('7'), findsNothing);
    final title = tester.widget<Text>(find.text('Agents'));
    expect(title.style?.fontSize, 13);
    expect(title.style?.fontWeight, W.label);
    expect(title.style?.color, Color.lerp(AppColors.fg1, AppColors.fg2, 0.3));
    final action = tester.widget<AppIcon>(
        find.byWidgetPredicate((w) => w is AppIcon && w.name == 'search'));
    expect(action.size, 14);
    expect(action.color, AppColors.fg3);

    await pump(true);
    expect(find.text('7'), findsOneWidget);
    final count = tester.widget<Text>(find.text('7'));
    expect(count.style?.fontSize, 11.5);
    expect(count.style?.color, AppColors.fg3);
    // Reset inside the body: the binding checks debug vars before tear-down.
    debugDefaultTargetPlatformOverride = null;
  });
}
