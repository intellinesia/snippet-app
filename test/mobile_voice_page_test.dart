import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/mobile_home/agents_home.dart' show BarIcon;
import 'package:snippet/ambient/capture.dart';
import 'package:snippet/ambient/controller.dart';
import 'package:snippet/ambient/voice.dart';
import 'package:snippet/api.dart';
import 'package:snippet/mochi.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/mobile_chrome.dart';
import 'package:snippet/screens/mobile_voice_page.dart';
import 'package:snippet/theme.dart';

class _FakeAmbientController extends ChangeNotifier implements AmbientControl {
  _FakeAmbientController({
    AmbientStatus status = const AmbientStatus(running: true),
    this.supportsMute = false,
    bool muted = false,
  })  : _status = status,
        _muted = muted;

  AmbientStatus _status;
  @override
  AmbientStatus get status => _status;
  set status(AmbientStatus value) {
    _status = value;
    notifyListeners();
  }

  @override
  bool get running => _status.running;

  @override
  final bool supportsMute;

  bool _muted;
  @override
  bool get muted => _muted;

  final ValueNotifier<AmbientVoice?> _voice = ValueNotifier(null);
  @override
  ValueListenable<AmbientVoice?> get voice => _voice;

  final ValueNotifier<AmbientStateEvent?> stateNotifier = ValueNotifier(null);
  @override
  ValueListenable<AmbientStateEvent?>? get stateListenable => stateNotifier;

  int stopCalls = 0;

  @override
  Future<void> toggleMute() async {
    _muted = !_muted;
    notifyListeners();
  }

  @override
  Future<void> bind() async {}

  @override
  Future<String> get deviceId async => 'phone-1';

  @override
  Future<String?> start(DaemonClient client) async => null;

  @override
  Future<void> stop() async {
    stopCalls++;
    _status = const AmbientStatus(running: false);
    notifyListeners();
  }

  @override
  Future<bool> get ignoringBattery async => true;

  @override
  Future<void> requestBatteryExemption() async {}

  @override
  Future<(AmbientSettings?, String?)> setEnabled(
          DaemonClient client, bool on) async =>
      (null, null);

  @override
  void dispose() {
    _voice.dispose();
    stateNotifier.dispose();
    super.dispose();
  }
}

void main() {
  testWidgets(
      'MobileVoicePage renders idle controller state and chevron-down pops',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    try {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => openMobileVoicePage(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(MobileVoicePage), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('Listening'), findsNothing);
      expect(find.byKey(const ValueKey('ambient-circles')), findsOneWidget);
      expect(find.byType(BarIcon).first, findsOneWidget);
      expect(find.byTooltip('End'), findsOneWidget);
      expect(find.byTooltip('Mute'), findsNothing);
      expect(find.byTooltip('Unmute'), findsNothing);

      await tester.tap(find.byType(BarIcon).first);
      await tester.pumpAndSettle();

      expect(find.byType(MobileVoicePage), findsNothing);
      expect(find.text('Open'), findsOneWidget);
    } finally {
      tester.view.reset();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'MobileVoicePage renders status transitions, heard quote, reply, mute toggle, and end stops controller',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    final controller = _FakeAmbientController(
      status: const AmbientStatus(running: true),
      supportsMute: true,
    );
    try {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => MobileVoicePage(
                      controller: controller,
                      initialSettings:
                          const AmbientSettings(enabled: true, mode: 'active'),
                      initialEvents: [
                        AmbientEvent.fromJson({
                          'id': 'ev-1',
                          'device': 'phone-1',
                          'started_at': '2026-11-13T02:00:00Z',
                          'duration_ms': 1200,
                          'status': 'done',
                          'text': 'Check the build status',
                          'kept': true,
                        }),
                      ],
                      replyText: 'Checking the latest build now.',
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Active'), findsOneWidget);
      expect(find.text('Listening'), findsOneWidget);
      expect(find.text('Check the build status'), findsOneWidget);
      expect(find.text('Checking the latest build now.'), findsOneWidget);
      expect(find.byTooltip('Mute'), findsOneWidget);

      await tester.tap(find.byTooltip('Mute'));
      await tester.pump();
      expect(controller.muted, isTrue);
      expect(find.byTooltip('Unmute'), findsOneWidget);

      controller.status = const AmbientStatus(running: true, speaking: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Hearing you'), findsOneWidget);

      controller.stateNotifier.value =
          const AmbientStateEvent(mode: 'active', sub: 'thinking');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Thinking'), findsOneWidget);

      controller.stateNotifier.value =
          const AmbientStateEvent(mode: 'active', sub: 'speaking');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Speaking'), findsOneWidget);

      await tester.tap(find.byTooltip('End'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(controller.stopCalls, 1);
      expect(find.byType(MobileVoicePage), findsNothing);
    } finally {
      controller.dispose();
      tester.view.reset();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('ListeningPill in MobileHomeHeader opens MobileVoicePage on tap',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    try {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: MobileHomeHeader(
            title: 'Sessions',
            listening: true,
          ),
        ),
      ));

      await tester.tap(find.byType(ListeningPill));
      await tester.pumpAndSettle();

      expect(find.byType(MobileVoicePage), findsOneWidget);

      await tester.tap(find.byType(BarIcon).first);
      await tester.pumpAndSettle();

      expect(find.byType(MobileVoicePage), findsNothing);
    } finally {
      tester.view.reset();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  for (final w in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 1.35, 2.0]) {
      testWidgets('ambient circles and card at $w x $scale', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(w, 1400);
        final controller = _FakeAmbientController(
            status: const AmbientStatus(running: true), supportsMute: true);
        try {
          await tester.pumpWidget(MaterialApp(
            theme: buildAppTheme(),
            builder: (c, ch) => MediaQuery(
                data: MediaQuery.of(c)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: ch!),
            home: MobileVoicePage(
              controller: controller,
              initialSettings:
                  const AmbientSettings(enabled: true, mode: 'active'),
              initialEvents: const [],
            ),
          ));
          await tester.pump(const Duration(milliseconds: 300));
          final circles =
              tester.getSize(find.byKey(const ValueKey('ambient-circles')));
          expect(circles, const Size(180, 180));
          final card = tester.getSize(find.byKey(const ValueKey('last-heard')));
          expect(card.width, closeTo(w - 32, 0.6));
          expect(card.height, greaterThanOrEqualTo(116));
          final mute = tester.getSize(find.byTooltip('Mute'));
          final end = tester.getSize(find.byTooltip('End'));
          expect(mute.width, greaterThanOrEqualTo(56));
          expect(end.height, greaterThanOrEqualTo(56));
          // ignore: avoid_print
          print('HM10 ambient w=$w s=$scale circles=$circles card=$card mute=$mute');
        } finally {
          controller.dispose();
          tester.view.reset();
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
}
