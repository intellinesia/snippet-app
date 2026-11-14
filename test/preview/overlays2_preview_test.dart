import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/crew_widgets.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/mobile_chrome.dart';
import 'package:snippet/screens/pull_request_detail.dart';
import 'package:snippet/screens/shell_card_tab_strip.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/settings_form.dart';
import 'package:snippet/dialog_widgets.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

class _Client extends DaemonClient {
  _Client() : super('https://daemon.invalid', 'test');
}

Widget _app(Widget Function(BuildContext) open) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
                key: const Key('open'),
                onPressed: () => open(ctx),
                child: const Text('Open')),
          ),
        ),
      ),
    );

List<PopupMenuEntry<String>> _items() => [
      appMenuHeading<String>('Approval'),
      appMenuRow<String>(
          value: 'ask',
          label: 'Ask every time',
          description: 'Confirm each tool call before it runs',
          selected: true),
      appMenuRow<String>(
          value: 'auto',
          icon: 'zap',
          label: 'Auto-approve edits',
          description: 'Only shell commands need a confirmation'),
      const PopupMenuDivider(),
      appMenuItem<String>(value: 'rename', icon: 'edit', label: 'Rename'),
      appMenuItem<String>(
          value: 'detail', icon: 'copy', label: 'Copy link', detail: 'Cmd C'),
      appMenuItem<String>(
          value: 'delete', icon: 'trash', label: 'Delete', danger: true),
    ];

final _agent = CoordinationAgent.fromJson({
  'id': 'ada',
  'display_name': 'Ada',
  'role': 'Code reviewer',
});

Future<void> _shot(WidgetTester t, String name,
    Widget Function(BuildContext) open, Size size, bool phone) async {
  debugDefaultTargetPlatformOverride =
      phone ? TargetPlatform.android : TargetPlatform.macOS;
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(_app(open));
  await t.tap(find.byKey(const Key('open')));
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
  await expectLater(find.byType(MaterialApp),
      matchesGoldenFile('goldens/overlays2/$name.png'));
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  const phone = Size(390, 844);
  const desk = Size(1280, 800);

  {
    final cases = <String, (Widget Function(BuildContext), Size, bool)>{
      'menu_phone': ((c) {
        showAppMenu<String>(c, items: _items(), anchor: c);
        return const SizedBox();
      }, phone, true),
      'menu_desktop': ((c) {
        showAppMenu<String>(c,
            items: _items(), anchor: c, below: true);
        return const SizedBox();
      }, desk, false),
      'confirm_phone': ((c) {
        confirmAction(c,
            title: 'Delete Ada?',
            body:
                "This removes the agent, its identity and its notes. This can't be undone.",
            confirmLabel: 'Delete agent');
        return const SizedBox();
      }, phone, true),
      'confirm_normal_phone': ((c) {
        confirmAction(c,
            title: 'Discard draft?',
            body: 'The message you started will be lost.',
            confirmLabel: 'Discard',
            danger: false);
        return const SizedBox();
      }, phone, true),
      'confirm_desktop': ((c) {
        confirmAction(c,
            title: 'Delete Ada?',
            body:
                "This removes the agent, its identity and its notes. This can't be undone.",
            confirmLabel: 'Delete agent');
        return const SizedBox();
      }, desk, false),
      'prompt_phone': ((c) {
        promptText(c, title: 'Rename session', initial: 'Review auth flow');
        return const SizedBox();
      }, phone, true),
      'prompt_desktop': ((c) {
        promptText(c, title: 'Rename session', initial: 'Review auth flow');
        return const SizedBox();
      }, desk, false),
      'app_sheet_phone': ((c) {
        showAppSheet<void>(c,
            title: 'Machines',
            child: Column(children: [
              for (final n in ['studio.local', 'build-box', 'raspberry-pi'])
                ListTile(title: Text(n), subtitle: const Text('Online')),
            ]));
        return const SizedBox();
      }, phone, true),
      'mobile_menu_phone': ((c) {
        showMobileMenu(c,
            client: null,
            newSessionSubtitle: 'on studio.local',
            onPick: (_) {},
            onAgent: (_) {});
        return const SizedBox();
      }, phone, true),
      'crew_menu_phone': ((c) {
        showCrewAgentMenu(c, client: _Client(), agent: _agent);
        return const SizedBox();
      }, phone, true),
      'crew_menu_desktop': ((c) {
        showCrewAgentMenu(c,
            client: _Client(), agent: _agent, point: const Offset(600, 300));
        return const SizedBox();
      }, desk, false),
      'tab_menu_phone': ((c) {
        showTabContextMenu(
            context: c,
            tab: ShellTab.session(
                client: _Client(),
                instanceUrl: 'http://m',
                sessionId: 's1',
                title: 'Review authentication flow'),
            index: 1,
            hasNonMissionControlTabs: true,
            onCloseTab: () {},
            onCloseOthers: () {},
            onCloseAll: () {});
        return const SizedBox();
      }, phone, true),
      'settings_popup_phone': ((c) {
        showAppMenu<String>(c, items: [
          for (final m in ['Claude Sonnet 5.5', 'GPT-5 Codex with an extremely long display name that overflows', 'Gemini 3 Pro'])
            appMenuItem<String>(value: m, label: m, selected: m == 'Gemini 3 Pro'),
        ]);
        return const SizedBox();
      }, phone, true),
      'menu_narrow_phone': ((c) {
        showAppMenu<String>(c, items: _items(), anchor: c);
        return const SizedBox();
      }, const Size(320, 690), true),
      'pr_review_sheet_phone': ((c) {
        submitPrReviewFlow(c,
            client: _Client(), session: 's', number: 12, pending: [], isAuthor: false);
        return const SizedBox();
      }, phone, true),
      'popover_desktop': ((c) {
        showPointPopover<void>(c,
            point: const Offset(500, 300),
            width: 240,
            maxHeight: 120,
            child: const Padding(padding: EdgeInsets.all(16), child: Text('Popover')));
        return const SizedBox();
      }, desk, false),
      'pr_comment_sheet_phone': ((c) {
        showPrCommentSheet(c, title: 'Add a comment');
        return const SizedBox();
      }, phone, true),
    };
    for (final e in cases.entries) {
      testWidgets(e.key, (t) async {
        await _shot(t, e.key, e.value.$1, e.value.$2, e.value.$3);
      });
    }
  }
}
