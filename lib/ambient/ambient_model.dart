import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../swr.dart';
import '../theme.dart';
import 'capture.dart';
import 'controller.dart';
import 'voice.dart';

Color ambientModeColor(String mode) =>
    mode == 'active' ? AppColors.accent : AppColors.ok;

Color ambientStateColor(AmbientSettings? s, AmbientStatus st) {
  if (s != null && s.enabled && st.error != null) return AppColors.danger;
  return ambientModeColor(s?.shownMode ?? 'passive');
}

String ambientStatusText({
  required AmbientSettings? settings,
  required AmbientStatus status,
  required AmbientStateEvent? event,
  bool elsewhere = false,
  bool busy = false,
  bool? liveOverride,
}) {
  if (kIsWeb) return 'Unavailable in browser';
  if (elsewhere) {
    return 'On ${settings?.listeningDevice ?? 'another device'}';
  }
  if (status.displaced) return 'Paused here';
  final live = liveOverride ?? ((settings?.enabled ?? false) && status.running);
  if (busy) return live ? 'Stopping…' : 'Starting…';
  if (!live) return 'Off';
  if (event != null) {
    if (event.sub == 'speaking') return 'Speaking';
    if (event.sub == 'thinking') return 'Thinking';
    if (event.mode == 'active') return 'In conversation';
  }
  if (status.assistantSpeaking) return 'Speaking';
  if (settings?.conversationOpen ?? false) return 'In conversation';
  if (status.speaking) return 'Hearing you';
  return 'Listening';
}

String ambientModeLabel(AmbientSettings? settings) {
  final m = settings?.shownMode.trim() ?? '';
  if (m.isEmpty) return 'Listening';
  if (m == 'active') return 'Active';
  if (m == 'passive') return 'Passive';
  return m[0].toUpperCase() + m.substring(1);
}

List<AmbientEvent> filterAmbientEvents(List<AmbientEvent> events) => events
    .where((e) =>
        e.status == 'done' &&
        e.kept &&
        e.text.trim().isNotEmpty &&
        !const {'media', 'noise', 'background', 'echo'}.contains(e.verdict))
    .toList();

class AmbientModel extends ChangeNotifier {
  AmbientModel(
    this.client, {
    AmbientControl? ambient,
    AmbientSettings? initialSettings,
  })  : ambient = ambient ?? AmbientController.instance,
        settings = initialSettings {
    this.ambient.addListener(_onAmbient);
    if (client != null) {
      this.ambient.bind();
      this.ambient.deviceId.then((v) {
        if (_disposed) return;
        selfId = v;
        notifyListeners();
      });
      load();
      _live = Revalidator(
          client: client!,
          on: (e) => e['kind'] == 'ambient_state' || e['kind'] == 'config',
          debounce: const Duration(seconds: 1),
          onRevalidate: ({required bool force}) => load());
    }
  }

  final DaemonClient? client;
  final AmbientControl ambient;
  AmbientSettings? settings;
  String selfId = '';
  String? error;
  bool busy = false;
  Revalidator? _live;
  bool _disposed = false;

  void _onAmbient() {
    if (!_disposed) notifyListeners();
  }

  AmbientStatus get status => ambient.status;
  bool get on => settings?.enabled ?? false;
  bool get listening => on && status.running;
  bool get liveOrRunning => (settings?.enabled ?? status.running) && status.running;

  Future<void> load() async {
    final c = client;
    if (c == null) return;
    try {
      settings = await c.getAmbientSettings();
      if (!_disposed) notifyListeners();
    } catch (_) {}
  }

  bool get elsewhere {
    final id = settings?.listeningId;
    return id != null && selfId.isNotEmpty && id != selfId;
  }

  Future<void> press() async {
    final c = client;
    if (c == null) return;
    if (on && listening) return toggle(false);
    if (on) {
      if (busy) return;
      busy = true;
      notifyListeners();
      error = await ambient.start(c);
      busy = false;
      if (!_disposed) notifyListeners();
      load();
      return;
    }
    return toggle(true);
  }

  Future<void> toggle(bool value) async {
    final c = client;
    if (c == null || busy) return;
    busy = true;
    error = null;
    notifyListeners();
    final (saved, err) = await ambient.setEnabled(c, value);
    if (saved != null) settings = saved;
    error = err;
    busy = false;
    if (!_disposed) notifyListeners();
    if (value && err == null && !await ambient.ignoringBattery) {
      await ambient.requestBatteryExemption();
    }
  }

  Future<void> shiftMode(int dir) =>
      setMode(dir > 0 ? 'active' : 'passive');

  Future<void> setMode(String mode) async {
    final c = client;
    final before = settings;
    if (c == null ||
        before == null ||
        (before.mode == mode && before.shownMode == mode)) {
      return;
    }
    settings = before.withMode(mode);
    notifyListeners();
    try {
      final saved = await c.setAmbientSettings(mode: mode);
      settings = saved.withMode(mode);
    } catch (e) {
      settings = before;
      error = '$e';
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _live?.dispose();
    ambient.removeListener(_onAmbient);
    super.dispose();
  }
}
