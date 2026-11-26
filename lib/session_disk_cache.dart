import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

class SessionDiskCache {
  SessionDiskCache._();

  static const _version = 1;
  static const _maxEntries = 24;
  static const _maxBytes = 8 * 1024 * 1024;
  static const _debounce = Duration(seconds: 2);
  static final Map<String, Timer> _timers = {};
  static final Map<String, (HarnessState, int)> _pending = {};
  static Future<Directory>? _dirFuture;

  static Future<Directory> _dir() => _dirFuture ??= () async {
        final base = await getApplicationSupportDirectory();
        return Directory('${base.path}/session_cache').create(recursive: true);
      }();

  static String _name(String key) {
    var hash = 0xcbf29ce484222325;
    for (final b in utf8.encode(key)) {
      hash ^= b;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toUnsigned(64).toRadixString(16);
  }

  static Future<(HarnessState, int)?> load(String key) async {
    try {
      final file = File('${(await _dir()).path}/${_name(key)}.json');
      if (!await file.exists()) return null;
      final decoded = await compute(jsonDecode, await file.readAsString());
      if (decoded is! Map) return null;
      final j = decoded.cast<String, dynamic>();
      if (j['v'] != _version || j['key'] != key) return null;
      final state = HarnessState.fromJson(j);
      if (state.events.isEmpty) return null;
      return (state, (j['event_offset'] as num?)?.toInt() ?? 0);
    } catch (_) {
      return null;
    }
  }

  static void save(String key, HarnessState state, int start) {
    _pending[key] = (state, start);
    _timers[key]?.cancel();
    _timers[key] = Timer(_debounce, () => unawaited(_flush(key)));
  }

  static Future<void> _flush(String key) async {
    _timers.remove(key);
    final entry = _pending.remove(key);
    if (entry == null) return;
    final (state, start) = entry;
    try {
      final text = await compute(jsonEncode, <String, dynamic>{
        'v': _version,
        'key': key,
        'event_offset': start,
        'workspace': state.workspace,
        'title': state.title,
        'events': state.events,
      });
      final dir = await _dir();
      final file = File('${dir.path}/${_name(key)}.json');
      if (state.events.isEmpty || text.length > _maxBytes) {
        if (await file.exists()) await file.delete();
        return;
      }
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(file.path);
      await _prune(dir);
    } catch (_) {}
  }

  static Future<void> _prune(Directory dir) async {
    final files = <(DateTime, File)>[];
    await for (final e in dir.list()) {
      if (e is File && e.path.endsWith('.json')) {
        files.add((await e.lastModified(), e));
      }
    }
    if (files.length <= _maxEntries) return;
    files.sort((a, b) => b.$1.compareTo(a.$1));
    for (final (_, f) in files.skip(_maxEntries)) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }
}
