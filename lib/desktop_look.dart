import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'platform.dart';
import 'theme.dart';

/// Desktop-only finish: the chat wallpaper and chrome opacity.
class DesktopLook extends ChangeNotifier {
  @override
  void notifyListeners() {
    AppColors.solidChrome = hasWallpaper;
    AppColors.chromeAlpha = kMobile ? null : _chrome;
    super.notifyListeners();
  }

  DesktopLook._();
  static final DesktopLook instance = DesktopLook._();

  static const _wallKey = 'desktop_chat_wallpaper';
  static const _wallImageKey = 'desktop_chat_wallpaper_image';
  static const _wallStrengthKey = 'desktop_chat_wallpaper_strength';
  static const chromeKey = 'desktop_chrome_opacity';

  static const none = 'none';
  static const image = 'image';

  String _wallpaper = none;
  String? _imagePath;
  double _strength = 0.7;
  double? _chrome;
  bool _loaded = false;

  String get wallpaper => _wallpaper;
  String? get imagePath => _imagePath;
  double get strength => _strength;

  /// Opacity of the sidebar, title bar and right pane; null keeps the default.
  double? get chromeOpacity => _chrome;
  bool get hasWallpaper =>
      !kMobile && _wallpaper == image && _imagePath != null;

  Future<void> init() async {
    if (kMobile || _loaded) return;
    _loaded = true;
    final p = await SharedPreferences.getInstance();
    // The tactile finish was removed; drop its stale pref.
    p.remove('desktop_tactile');
    _wallpaper = p.getString(_wallKey) ?? none;
    final img = p.getString(_wallImageKey);
    _imagePath = img != null && File(img).existsSync() ? img : null;
    _strength = (p.getDouble(_wallStrengthKey) ?? 0.7).clamp(0.0, 1.0);
    _chrome = p.getDouble(chromeKey)?.clamp(0.0, 1.0);
    if (_wallpaper != image || _imagePath == null) _wallpaper = none;
    notifyListeners();
  }

  Future<void> clearWallpaper() async {
    final old = _imagePath;
    _wallpaper = none;
    _imagePath = null;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_wallKey, none);
      await p.remove(_wallImageKey);
    } catch (_) {}
    if (old != null) {
      try {
        File(old).deleteSync();
      } catch (_) {}
    }
  }

  Future<void> setChromeOpacity(double? v, {bool persist = true}) async {
    _chrome = v?.clamp(0.0, 1.0);
    notifyListeners();
    if (!persist) return;
    try {
      final p = await SharedPreferences.getInstance();
      final c = _chrome;
      c == null ? await p.remove(chromeKey) : await p.setDouble(chromeKey, c);
    } catch (_) {}
  }

  Future<void> setStrength(double v, {bool persist = true}) async {
    _strength = v.clamp(0.0, 1.0);
    notifyListeners();
    if (!persist) return;
    try {
      (await SharedPreferences.getInstance())
          .setDouble(_wallStrengthKey, _strength);
    } catch (_) {}
  }

  /// Copies [source] into app support so the original can move or vanish.
  Future<void> setImageFromFile(String source) async {
    final dir = await getApplicationSupportDirectory();
    final dot = source.lastIndexOf('.');
    final ext = dot > source.lastIndexOf(Platform.pathSeparator) && dot >= 0
        ? source.substring(dot)
        : '.img';
    final dest = File(
        '${dir.path}${Platform.pathSeparator}chat_wall_${DateTime.now().millisecondsSinceEpoch}$ext');
    await dest.parent.create(recursive: true);
    await File(source).copy(dest.path);
    final old = _imagePath;
    _imagePath = dest.path;
    _wallpaper = image;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_wallImageKey, dest.path);
    await p.setString(_wallKey, image);
    if (old != null && old != dest.path) {
      try {
        File(old).deleteSync();
      } catch (_) {}
    }
  }

  @visibleForTesting
  void debugSet({String? wallpaper, String? imagePath, double? strength}) {
    if (wallpaper != null) _wallpaper = wallpaper;
    if (imagePath != null) _imagePath = imagePath;
    if (strength != null) _strength = strength;
    notifyListeners();
  }
}

/// The chat column wallpaper: the user's image, fading into the
/// theme background so the transcript stays readable.
class ChatWallpaper extends StatelessWidget {
  const ChatWallpaper({super.key});

  @override
  Widget build(BuildContext context) {
    if (kMobile) return const SizedBox.shrink();
    final look = DesktopLook.instance;
    return ListenableBuilder(
      listenable: look,
      builder: (context, _) {
        if (!look.hasWallpaper) return const SizedBox.shrink();
        final s = look.strength;
        final bg = AppColors.bg;
        return IgnorePointer(
          child: RepaintBoundary(
            child: Stack(fit: StackFit.expand, children: [
              Image.file(File(look.imagePath!),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      bg.withValues(alpha: 1 - 0.7 * s),
                      bg.withValues(alpha: 1 - 0.25 * s),
                      bg,
                    ],
                    stops: const [0, 0.7, 1],
                  ),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}
