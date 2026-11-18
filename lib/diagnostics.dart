// On-device diagnostics: crashes, UI stalls and slow steps are written to a
// local log and sent to the daemon, so a freeze or crash can be read later.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'media_views.dart' show DaemonScope;

class Diag {
  static const _channel = MethodChannel('snippet/diag');
  static const _maxBytes = 400 * 1024;
  static const _stallMs = 400;

  static final _ring = <String>[];
  static RandomAccessFile? _file;
  static String? _dir;
  static Timer? _beat;
  static Timer? _upload;
  static DateTime _last = DateTime.now();
  static bool _uploading = false;
  static String _preTail = '';

  static bool get _on => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Future<void> init() async {
    if (!_on) return;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/diag')..createSync(recursive: true);
      _dir = dir.path;
      final log = File('${dir.path}/events.log');
      if (log.existsSync() && log.lengthSync() > _maxBytes) {
        final old = File('${dir.path}/events.log.1');
        if (old.existsSync()) old.deleteSync();
        log.renameSync(old.path);
        File('${dir.path}/uploaded.txt').writeAsStringSync('0');
      }
      // What the previous run was doing last, kept in case it died.
      if (log.existsSync() && log.lengthSync() > 0) {
        final raf = log.openSync();
        final len = raf.lengthSync();
        final from = len > 12000 ? len - 12000 : 0;
        raf.setPositionSync(from);
        _preTail = utf8.decode(raf.readSync(len - from), allowMalformed: true);
        raf.closeSync();
      }
      _file = log.openSync(mode: FileMode.append);
    } catch (_) {
      return;
    }
    _write('launch', 'debug=$kDebugMode os=${Platform.operatingSystemVersion}');

    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      _write('flutter-error', '${d.exceptionAsString()}\n${d.stack}');
      prev?.call(d);
    };
    ui.PlatformDispatcher.instance.onError = (e, s) {
      _write('uncaught', '$e\n$s');
      return false;
    };

    _beat = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final now = DateTime.now();
      final late = now.difference(_last).inMilliseconds - 100;
      _last = now;
      if (late > _stallMs) _write('ui-stall', '${late}ms');
    });
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final t in timings) {
        final ms = t.totalSpan.inMilliseconds;
        if (ms > 250) {
          _write('slow-frame',
              '${ms}ms build=${t.buildDuration.inMilliseconds} raster=${t.rasterDuration.inMilliseconds}');
        }
      }
    });

    unawaited(_readNative());
    _upload = Timer.periodic(const Duration(seconds: 90), (_) => flush());
    Timer(const Duration(seconds: 15), flush);
  }

  /// A short note kept with the next crash or stall for context.
  static void crumb(String message) {
    _ring.add('${_stamp()} $message');
    if (_ring.length > 40) _ring.removeAt(0);
    _write('crumb', message, ring: false);
  }

  static void lifecycle(AppLifecycleState state) {
    _last = DateTime.now();
    crumb('lifecycle ${state.name}');
    if (state == AppLifecycleState.resumed) unawaited(flush());
  }

  /// Times [body]; slow ones are logged.
  static Future<T> span<T>(String name, Future<T> Function() body) async {
    final sw = Stopwatch()..start();
    crumb('$name begin');
    try {
      return await body();
    } catch (e) {
      crumb('$name threw $e');
      rethrow;
    } finally {
      final ms = sw.elapsedMilliseconds;
      crumb('$name end ${ms}ms');
      if (ms > 300) _write('slow-step', '$name ${ms}ms');
    }
  }

  static String _stamp() => DateTime.now().toIso8601String().substring(11, 23);

  static void _write(String kind, String text, {bool ring = true}) {
    final f = _file;
    if (f == null) return;
    try {
      final recent =
          ring && kind != 'launch' && _ring.isNotEmpty ? '\n  recent: ${_ring.reversed.take(12).toList().reversed.join(' | ')}' : '';
      f.writeStringSync('${_stamp()} [$kind] $text$recent\n');
      if (kind != 'crumb') f.flushSync();
    } catch (_) {}
  }

  /// Reasons the previous processes ended, and a Java crash if one was caught.
  static Future<void> _readNative() async {
    if (!Platform.isAndroid) return;
    try {
      final raw = await _channel.invokeMethod<String>('previousExits');
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List;
      final seen = File('$_dir/exit_seen.txt');
      final since =
          seen.existsSync() ? int.tryParse(seen.readAsStringSync()) ?? 0 : 0;
      var newest = since;
      var contextWritten = false;
      for (final e in list.whereType<Map>()) {
        final at = (e['timestamp'] as num?)?.toInt() ?? 0;
        if (at <= since) continue;
        if (at > newest) newest = at;
        _write('previous-exit', jsonEncode(e), ring: false);
        final r = '${e['reason']}';
        if (!contextWritten && (r.startsWith('CRASH') || r == 'ANR')) {
          contextWritten = true;
          _write('pre-crash-context', _preTail, ring: false);
        }
      }
      seen.writeAsStringSync('$newest');
    } catch (_) {}
    try {
      final crash = File('$_dir/native-crash.log');
      if (crash.existsSync()) {
        _write('java-crash', crash.readAsStringSync(), ring: false);
        crash.deleteSync();
      }
    } catch (_) {}
  }

  /// Sends what has been written since the last upload to the daemon.
  static Future<void> flush() async {
    final dir = _dir;
    final client = DaemonScope.current;
    if (dir == null || client == null || _uploading) return;
    _uploading = true;
    try {
      final log = File('$dir/events.log');
      if (!log.existsSync()) return;
      final mark = File('$dir/uploaded.txt');
      final from =
          mark.existsSync() ? int.tryParse(mark.readAsStringSync()) ?? 0 : 0;
      final all = log.readAsBytesSync();
      if (all.length <= from) return;
      final chunk = all.sublist(from);
      // Crumbs alone are noise: only send when something worth reading is in it.
      final text = utf8.decode(chunk, allowMalformed: true);
      if (!RegExp(r'\[(ui-stall|slow-frame|slow-step|flutter-error|uncaught|previous-exit|java-crash|pre-crash-context)\]')
          .hasMatch(text)) {
        mark.writeAsStringSync('${all.length}');
        return;
      }
      final name =
          'snippet-diag-${DateTime.now().millisecondsSinceEpoch}.log';
      // The lines just before it say what led up to it.
      final ctx = from > 3000 ? from - 3000 : 0;
      await client.uploadFile(all.sublist(ctx),
          name: name, dir: '/tmp/snippet-diag');
      mark.writeAsStringSync('${all.length}');
    } catch (_) {
    } finally {
      _uploading = false;
    }
  }

  static void dispose() {
    _beat?.cancel();
    _upload?.cancel();
  }
}
