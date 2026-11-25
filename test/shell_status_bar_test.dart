import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/shell_frame.dart';
import 'package:snippet/screens/shell_status_bar.dart';
import 'package:snippet/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpBar(WidgetTester tester, ShellStatusBar bar) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 200);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: Align(alignment: Alignment.topCenter, child: bar)),
      ),
    );
    await tester.pump();
  }

  testWidgets(
      'formats usage percents and applies the 91 percent warning threshold',
      (tester) async {
    await pumpBar(
      tester,
      const ShellStatusBar(usage: [
        ShellUsageItem(label: 'Claude', usedPercent: 42.4),
        ShellUsageItem(label: 'Codex', usedPercent: 17.5),
      ]),
    );
    expect(find.text('Claude 42%'), findsOneWidget);
    expect(find.text('Codex 18%'), findsOneWidget);

    await pumpBar(
      tester,
      ShellStatusBar(usage: [
        ShellUsageItem(
          label: 'Claude',
          usedPercent: 90.9,
          resetsAt: DateTime(2026, 1, 2, 17, 4),
        ),
      ]),
    );
    expect(find.textContaining('Near limit'), findsNothing);

    await pumpBar(
      tester,
      ShellStatusBar(usage: [
        ShellUsageItem(
          label: 'Claude',
          usedPercent: 91,
          resetsAt: DateTime(2026, 1, 2, 17, 4),
        ),
      ]),
    );
    const warningText = 'Near limit, resets 17:04';
    expect(find.text(warningText), findsOneWidget);
    final warning = tester.widget<Text>(find.text(warningText));
    expect(warning.style?.fontWeight, FontWeight.w500);
    final meter = tester.widget<Text>(find.text('Claude 91%'));
    expect(meter.style?.fontWeight, FontWeight.w500);
  });

  testWidgets(
      'uses the strong unplugged-hosts variant when any host is offline',
      (tester) async {
    await pumpBar(
      tester,
      const ShellStatusBar(hostsOnline: 1, hostsTotal: 2),
    );
    expect(find.text('1 of 2 hosts online'), findsOneWidget);
    final text = tester.widget<Text>(find.text('1 of 2 hosts online'));
    expect(text.style?.fontWeight, FontWeight.w500);
    expect(find.byKey(const ValueKey('shell-status-unplug-glyph')),
        findsOneWidget);

    await pumpBar(
      tester,
      const ShellStatusBar(hostsOnline: 2, hostsTotal: 2),
    );
    expect(find.text('2 hosts'), findsOneWidget);
  });

  testWidgets('daemon-down replaces the right group and wires retry',
      (tester) async {
    var retries = 0;
    await pumpBar(
      tester,
      ShellStatusBar(
        daemonDown: true,
        needsYouCount: 2,
        connected: false,
        hostsOnline: 1,
        hostsTotal: 2,
        onRetry: () => retries++,
      ),
    );
    expect(find.text('Reconnecting...'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('2 need you'), findsNothing);
    expect(find.text('Agent'), findsNothing);
    expect(find.text('1 of 2 hosts online'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(retries, 1);
  });

  testWidgets('usage hit target reaches above the bar', (tester) async {
    var opened = 0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 200);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Column(children: [
            const SizedBox(height: 50),
            ShellStatusBarFrame(
              child: ShellStatusBar(
                usage: const [ShellUsageItem(label: 'Claude', usedPercent: 42)],
                onOpenUsage: () => opened++,
              ),
            ),
          ]),
        ),
      ),
    );
    await tester.pump();
    final x = tester.getCenter(find.text('Claude 42%')).dx;
    await tester.tapAt(Offset(x, 49));
    await tester.pump();
    expect(opened, 1);
  });
}
