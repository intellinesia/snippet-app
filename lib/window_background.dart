import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'platform.dart';
import 'theme.dart';

class WindowBackgroundStore {
  WindowBackgroundStore._();
  static final WindowBackgroundStore instance = WindowBackgroundStore._();

  static const prefsKey = 'desktop_bg_image';
  static const _channel = MethodChannel('snippet/window_state');

  final ValueNotifier<String?> path = ValueNotifier<String?>(null);
  bool _loaded = false;

  Future<void> init() async {
    if (kMobile || _loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(prefsKey);
    if (saved != null && File(saved).existsSync()) {
      path.value = saved;
    }
    await _syncNative();
  }

  /// Copies [source] into app support so the original can move or vanish.
  Future<void> setFromFile(String source) async {
    final dir = await getApplicationSupportDirectory();
    final dot = source.lastIndexOf('.');
    final ext = dot > source.lastIndexOf(Platform.pathSeparator) && dot >= 0
        ? source.substring(dot)
        : '.img';
    final dest = File(
        '${dir.path}${Platform.pathSeparator}window_bg_${DateTime.now().millisecondsSinceEpoch}$ext');
    await dest.parent.create(recursive: true);
    await File(source).copy(dest.path);
    final old = path.value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, dest.path);
    path.value = dest.path;
    if (old != null && old != dest.path) _deleteQuietly(old);
    await _syncNative();
  }

  Future<void> clear() async {
    final old = path.value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
    path.value = null;
    if (old != null) _deleteQuietly(old);
    await _syncNative();
  }

  void _deleteQuietly(String p) {
    try {
      File(p).deleteSync();
    } catch (_) {}
  }

  Future<void> _syncNative() async {
    if (!kMacOS) return;
    try {
      await _channel.invokeMethod(
          'setBackgroundImageMode', path.value != null);
    } catch (_) {}
  }
}

class WindowBackground extends StatelessWidget {
  const WindowBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (kMobile) return child;
    return ValueListenableBuilder<String?>(
      valueListenable: WindowBackgroundStore.instance.path,
      builder: (context, p, _) {
        if (p == null) return child;
        return Stack(fit: StackFit.expand, children: [
          Positioned.fill(
            child: Image.file(File(p),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) =>
                    ColoredBox(color: AppColors.bg)),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(color: AppColors.bg.withValues(alpha: 0.35)),
            ),
          ),
          child,
        ]);
      },
    );
  }
}
