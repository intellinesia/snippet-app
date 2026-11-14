import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/settings_panel.dart';
import 'package:snippet/theme.dart';

import 'package:snippet/wake_models.dart';
import '../support/wake_fakes.dart';

class _Client extends FakeWakeClient {
  _Client()
      : super(
            wakeState: WakeSchedule.fromJson(wakeJson()),
            warmState: KeepWarmEntry.fromJson(keepWarmJson()));

  @override
  Future<ServerConfig> getConfig({bool force = false}) async =>
      ServerConfig.fromJson({
        'voice': {'enabled': true, 'max_seconds': 180}
      });

  @override
  Future<AmbientSettings> getAmbientSettings() async =>
      AmbientSettings.fromJson({
        'stt': 'assemblyai',
        'tts_provider': 'rime',
        'assemblyai_key_set': true,
        'rime_key_set': false,
        'rime_voice': 'cove',
        'wake_phrases': ['snippet', 'hey snippet'],
      });

  @override
  Future<Map<String, List<Account>>> getAccounts() async => {
        'chatgpt': [
          Account.fromJson({'id': 'a', 'label': 'Personal Plus', 'active': true}),
          Account.fromJson({'id': 'b', 'label': 'Work Pro', 'active': false}),
        ],
        'xai': [],
        'claude-code': [
          Account.fromJson({'id': 'c', 'label': 'Max 20x', 'active': true}),
        ],
      };
}

const _inst = Instance(name: 'mac', url: 'https://mac.tail1234.ts.net', token: 't');

Future<void> _show(WidgetTester t, Size size, bool mobile, Widget child) async {
  debugDefaultTargetPlatformOverride =
      mobile ? TargetPlatform.android : TargetPlatform.macOS;
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: Scaffold(backgroundColor: AppColors.bg, body: child),
  ));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 400));
  }
}

Widget _panel(SettingsPage? section, {bool mobile = true}) => SettingsPanel(
      client: _Client(),
      instances: const [_inst],
      active: _inst,
      onRemove: (_) {},
      onClose: () {},
      embedded: mobile,
      section: mobile ? section : null,
      initialPage: mobile ? null : section,
    );

Widget _specimen() {
  final ts = <String, TextStyle>{
    'pageTitle': TS.pageTitle(),
    'sectionTitle': TS.sectionTitle(),
    'rowTitle': TS.rowTitle(),
    'body': TS.body(),
    'reading': TS.reading(),
    'ui': TS.ui(),
    'label': TS.label(),
    'meta': TS.meta(),
    'caption': TS.caption(),
    'overline': TS.overline(),
    'code': TS.code(),
    'codeSmall': TS.codeSmall(),
  };
  final sizes = <double>[10, 10.5, 11, 11.5, 12, 12.5, 13, 13.5, 14, 15, 16, 17, 18, 20, 22, 24, 28];
  return ListView(padding: const EdgeInsets.all(16), children: [
    for (final e in ts.entries)
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
            '${e.key}  ${e.value.fontSize}/${e.value.height?.toStringAsFixed(2)} w${e.value.fontWeight?.value} ls${e.value.letterSpacing?.toStringAsFixed(2)}  Quick brown fox 0123',
            style: e.value),
      ),
    const SizedBox(height: 12),
    for (final s in sizes)
      Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text('sans($s) Settings Machine 0123 Quick brown fox',
            style: sans(s, color: AppColors.fg1)),
      ),
    const SizedBox(height: 12),
    for (final w in [W.body, W.label, W.strong, FontWeight.w700])
      Text('weight request w${w.value} -> renders w${weightFor(w).value}: Settings',
          style: sans(16, weight: w, color: AppColors.fg1)),
  ]);
}

void main() {
  SharedPreferences.setMockInitialValues({});
  final phone = const Size(390, 844);
  final desk = const Size(1280, 800);
  final pages = {
    'home': null,
    'appearance': SettingsPage.appearance,
    'voice': SettingsPage.voice,
    'accounts': SettingsPage.accounts,
    'wakes': SettingsPage.wakes,
    'general': SettingsPage.general,
    'usage': SettingsPage.usage,
  };
  for (final e in pages.entries) {
    testWidgets('phone ${e.key}', (t) async {
      await _show(t, phone, true, _panel(e.value));
      await expectLater(find.byType(Scaffold),
          matchesGoldenFile('goldens/settings/phone_${e.key}.png'));
      debugDefaultTargetPlatformOverride = null;
    });
    if (e.value == null) continue;
    testWidgets('desktop ${e.key}', (t) async {
      await _show(t, desk, false, _panel(e.value, mobile: false));
      await expectLater(find.byType(Scaffold),
          matchesGoldenFile('goldens/settings/desktop_${e.key}.png'));
      debugDefaultTargetPlatformOverride = null;
    });
  }
  testWidgets('specimen phone', (t) async {
    await _show(t, const Size(390, 900), true, Builder(builder: (_) => _specimen()));
    await expectLater(find.byType(Scaffold),
        matchesGoldenFile('goldens/settings/specimen_phone.png'));
      debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('specimen desktop', (t) async {
    await _show(t, const Size(900, 900), false, Builder(builder: (_) => _specimen()));
    await expectLater(find.byType(Scaffold),
        matchesGoldenFile('goldens/settings/specimen_desktop.png'));
      debugDefaultTargetPlatformOverride = null;
  });
}
