import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'platform.dart';
import 'theme.dart';

/// Desktop-only finish: tactile surfaces and the chat wallpaper.
class DesktopLook extends ChangeNotifier {
  @override
  void notifyListeners() {
    AppColors.solidChrome = hasWallpaper;
    super.notifyListeners();
  }

  DesktopLook._();
  static final DesktopLook instance = DesktopLook._();

  static const _tactileKey = 'desktop_tactile';
  static const _wallKey = 'desktop_chat_wallpaper';
  static const _wallImageKey = 'desktop_chat_wallpaper_image';
  static const _wallStrengthKey = 'desktop_chat_wallpaper_strength';

  static const none = 'none';
  static const image = 'image';

  bool _tactile = true;
  String _wallpaper = none;
  String? _imagePath;
  double _strength = 0.7;
  bool _loaded = false;

  bool get tactile => !kMobile && _tactile;
  String get wallpaper => _wallpaper;
  String? get imagePath => _imagePath;
  double get strength => _strength;
  bool get hasWallpaper =>
      !kMobile && _wallpaper == image && _imagePath != null;

  Future<void> init() async {
    if (kMobile || _loaded) return;
    _loaded = true;
    final p = await SharedPreferences.getInstance();
    _tactile = p.getBool(_tactileKey) ?? true;
    _wallpaper = p.getString(_wallKey) ?? none;
    final img = p.getString(_wallImageKey);
    _imagePath = img != null && File(img).existsSync() ? img : null;
    _strength = (p.getDouble(_wallStrengthKey) ?? 0.7).clamp(0.0, 1.0);
    if (_wallpaper != image || _imagePath == null) _wallpaper = none;
    notifyListeners();
  }

  Future<void> setTactile(bool on) async {
    if (on == _tactile) return;
    _tactile = on;
    notifyListeners();
    try {
      (await SharedPreferences.getInstance()).setBool(_tactileKey, on);
    } catch (_) {}
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
  void debugSet(
      {bool? tactile, String? wallpaper, String? imagePath, double? strength}) {
    if (tactile != null) _tactile = tactile;
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

enum TactileKind { raised, inset }

/// Quiet physical cues on desktop: a top highlight and soft lower shade on
/// raised surfaces, an inner shadow on wells. A no-op on phones or when off.
class Tactile extends StatelessWidget {
  const Tactile({
    super.key,
    required this.child,
    required this.radius,
    this.kind = TactileKind.raised,
    this.enabled = true,
  });

  final Widget child;
  final BorderRadius radius;
  final TactileKind kind;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (kMobile || !enabled) return child;
    return ListenableBuilder(
      listenable: DesktopLook.instance,
      builder: (context, child) => DesktopLook.instance.tactile
          ? CustomPaint(
              foregroundPainter: TactilePainter(radius, kind),
              child: child)
          : child!,
      child: child,
    );
  }
}

class TactilePainter extends CustomPainter {
  const TactilePainter(this.radius, this.kind);
  final BorderRadius radius;
  final TactileKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect);
    if (kind == TactileKind.raised) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0),
              Colors.black.withValues(alpha: 0.12),
            ],
            stops: const [0.5, 1],
          ).createShader(rect),
      );
      canvas.drawRRect(
        radius.toRRect(rect.deflate(0.5)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.10),
              Colors.white.withValues(alpha: 0),
            ],
            stops: [0, (12 / size.height).clamp(0.2, 0.6)],
          ).createShader(rect),
      );
      return;
    }
    canvas.save();
    canvas.clipRRect(rrect);
    final shade = (7 / size.height).clamp(0.05, 0.5);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.38),
            Colors.black.withValues(alpha: 0),
          ],
          stops: [0, shade],
        ).createShader(rect),
    );
    canvas.restore();
    canvas.drawRRect(
      radius.toRRect(rect.deflate(0.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.05),
          ],
          stops: const [0.6, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(TactilePainter old) =>
      old.radius != radius || old.kind != kind;
}
