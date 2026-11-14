import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Pins extends ChangeNotifier {
  Pins._();
  static final Pins instance = Pins._();

  static const session = 'session';
  static const agent = 'agent';
  static const group = 'group';

  static const _prefix = 'pins:';

  final Map<String, Map<String, int>> _pins = {};
  int _seq = 0;

  static String _normHost(String? host) {
    final h = (host ?? '').trim();
    if (h.isEmpty) return '';
    return h.endsWith('/') ? h.substring(0, h.length - 1) : h;
  }

  static String _bucketKey(String kind, [String? host]) {
    final h = _normHost(host);
    return h.isEmpty ? kind : '$h|$kind';
  }

  static String _prefKey(String bucket) => '$_prefix$bucket';

  Future<void> init() => load();

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _pins.clear();
      _seq = 0;
      for (final k in prefs.getKeys()) {
        if (!k.startsWith(_prefix)) continue;
        final bucket = k.substring(_prefix.length);
        final raw = prefs.getString(k);
        if (raw == null) continue;
        final map = _decode(raw);
        if (map != null && map.isNotEmpty) {
          _pins[bucket] = map;
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  static Map<String, int>? _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final out = <String, int>{};
        for (final entry in decoded.entries) {
          final v = entry.value;
          if (v is num) out['${entry.key}'] = v.toInt();
        }
        return out;
      }
      if (decoded is List) {
        final out = <String, int>{};
        var ts = decoded.length;
        for (final id in decoded) {
          if (id is String && id.isNotEmpty) out[id] = ts--;
        }
        return out;
      }
    } catch (_) {}
    return null;
  }

  int? pinnedAt(String kind, String id, {String? host}) {
    final h = _normHost(host);
    if (h.isNotEmpty) {
      final scoped = _pins[_bucketKey(kind, h)]?[id];
      if (scoped != null) return scoped;
    }
    return _pins[kind]?[id];
  }

  bool isPinned(String kind, String id, {String? host}) =>
      pinnedAt(kind, id, host: host) != null;

  List<String> ids(String kind, {String? host}) {
    final merged = <String, int>{
      ...?_pins[kind],
      if (_normHost(host).isNotEmpty) ...?_pins[_bucketKey(kind, host)],
    };
    final list = merged.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in list) e.key];
  }

  Future<bool> toggle(String kind, String id, {String? host}) async {
    final h = _normHost(host);
    final bucket = _bucketKey(kind, h);
    final currentlyPinned = isPinned(kind, id, host: h);
    if (currentlyPinned) {
      _pins[bucket]?.remove(id);
      if (_pins[bucket]?.isEmpty ?? false) _pins.remove(bucket);
      if (h.isNotEmpty) {
        _pins[kind]?.remove(id);
        if (_pins[kind]?.isEmpty ?? false) _pins.remove(kind);
      }
      notifyListeners();
      await _write(bucket);
      if (h.isNotEmpty) await _write(kind);
      return false;
    }
    final now = DateTime.now().microsecondsSinceEpoch * 1000 + (++_seq % 1000);
    (_pins[bucket] ??= <String, int>{})[id] = now;
    notifyListeners();
    await _write(bucket);
    return true;
  }

  Future<void> _write(String bucket) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = _pins[bucket];
      if (map == null || map.isEmpty) {
        await prefs.remove(_prefKey(bucket));
      } else {
        await prefs.setString(_prefKey(bucket), jsonEncode(map));
      }
    } catch (_) {}
  }

  @visibleForTesting
  void clear() {
    _pins.clear();
    _seq = 0;
    notifyListeners();
  }
}
