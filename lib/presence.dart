import 'dart:async';

import 'package:flutter/foundation.dart';

import 'device_events.dart';
import 'models.dart';
import 'swr.dart';

class Presence {
  const Presence({required this.state, this.detail = '', this.since = 0});
  final String state;
  final String detail;
  final int since;

  bool get active => state != 'idle' && state.isNotEmpty;
}

class PresenceStore extends ChangeNotifier {
  PresenceStore([Stream<DeviceEventFrame>? events, DateTime Function()? clock])
      : _events = events,
        _now = clock ?? DateTime.now;

  final Stream<DeviceEventFrame>? _events;

  static const staleAfter = Duration(minutes: 10);

  final DateTime Function() _now;
  StreamSubscription<DeviceEventFrame>? _sub;
  final Map<String, Presence> _bySession = {};
  final Map<String, String> _agentOf = {};

  void handle(DeviceEventFrame frame) {
    final kind = frame['kind'];
    if (kind == DeviceEventHub.reconnected) {
      if (_bySession.isEmpty) return;
      _bySession.clear();
      _agentOf.clear();
      notifyListeners();
      return;
    }
    if (kind != 'agent_presence') return;
    final e = DeviceEvent.fromJson(frame);
    if (e.session.isEmpty) return;
    _bySession[e.session] =
        Presence(state: e.state, detail: e.detail, since: e.since);
    if (e.agent.isNotEmpty) _agentOf[e.session] = e.agent;
    notifyListeners();
  }

  Presence? forSession(String session) => _live(_bySession[session]);

  Presence? _live(Presence? p) {
    if (p == null || !p.active) return null;
    final stale = p.state == 'thinking' || p.state == 'typing' || p.state == 'tool';
    if (stale && p.since > 0) {
      final age = _now().millisecondsSinceEpoch ~/ 1000 - p.since;
      if (age > staleAfter.inSeconds) return null;
    }
    return p;
  }

  Presence? presenceForAgent(String agentId, Iterable<SessionInfo> sessions) {
    Presence? best;
    for (final s in sessions) {
      final owner = s.displayAgentId;
      if (owner != agentId && _agentOf[s.id] != agentId) continue;
      final p = forSession(s.id);
      if (p != null && (best == null || p.since > best.since)) best = p;
    }
    return best;
  }

  /// Latest live presence among sessions the service tagged with [agentId].
  Presence? presenceForAgentId(String agentId) {
    Presence? best;
    for (final e in _agentOf.entries) {
      if (e.value != agentId) continue;
      final p = forSession(e.key);
      if (p != null && (best == null || p.since > best.since)) best = p;
    }
    return best;
  }

  /// Lower-case status word for a header: thinking, running bash, ...
  static String word(Presence p) => switch (p.state) {
        'tool' => p.detail.isEmpty ? 'running' : 'running ${p.detail}',
        'waiting' => p.detail.isEmpty || p.detail == 'user'
            ? 'waiting on you'
            : 'waiting on ${p.detail}',
        final s => s,
      };

  // Hold the shared socket only while something is watching presence.
  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _sub ??= _events?.listen(handle);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _sub?.cancel();
      _sub = null;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
