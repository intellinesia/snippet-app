import 'dart:math' as math;
import 'dart:convert';
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ambient_loop.dart';
import 'theme.dart';

enum AgentCharacterState { idle, working, waiting, done, needs, sleeping }

@immutable
class CharacterEyeAnchor {
  const CharacterEyeAnchor({
    required this.x,
    required this.y,
    required this.rx,
    required this.ry,
  });

  factory CharacterEyeAnchor.fromJson(Map<String, dynamic> j) =>
      CharacterEyeAnchor(
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        rx: (j['rx'] as num).toDouble(),
        ry: (j['ry'] as num).toDouble(),
      );

  final double x;
  final double y;
  final double rx;
  final double ry;
}

@immutable
class CharacterShadowSpec {
  const CharacterShadowSpec({
    required this.file,
    required this.file256,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  factory CharacterShadowSpec.fromJson(Map<String, dynamic> j) =>
      CharacterShadowSpec(
        file: j['file'] as String,
        file256: j['file_256'] as String,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        w: (j['w'] as num).toDouble(),
        h: (j['h'] as num).toDouble(),
      );

  final String file;
  final String file256;
  final double x;
  final double y;
  final double w;
  final double h;
}

@immutable
class CharacterSpec {
  const CharacterSpec({
    required this.id,
    required this.shape,
    required this.colour,
    required this.colorHex,
    required this.eyeStyle,
    required this.eyes,
    required this.shadow,
    required this.body,
    required this.body256,
    this.over,
    this.over256,
    this.bodyTop = 0,
  });

  factory CharacterSpec.fromJson(Map<String, dynamic> j) {
    final p = j['plate'] as Map<String, dynamic>;
    return CharacterSpec(
      id: j['id'] as String,
      shape: j['shape'] as String? ?? '',
      colour: j['colour'] as String? ?? '',
      colorHex: j['color'] as String? ?? '#EDEDED',
      eyeStyle: p['eye_style'] as String,
      eyes: [
        for (final e in (p['eyes'] as List))
          CharacterEyeAnchor.fromJson(e as Map<String, dynamic>),
      ],
      shadow: CharacterShadowSpec.fromJson(p['shadow'] as Map<String, dynamic>),
      body: p['body'] as String,
      body256: p['body_256'] as String,
      over: p['over'] as String?,
      over256: p['over_256'] as String?,
      bodyTop: (p['body_top'] as num?)?.toDouble() ?? 0,
    );
  }

  final String id;
  final String shape;
  final String colour;
  final String colorHex;

  Color get color {
    final hex = colorHex.replaceFirst('#', '');
    return Color(int.tryParse('FF$hex', radix: 16) ?? 0xFFEDEDED);
  }

  final String eyeStyle;
  final List<CharacterEyeAnchor> eyes;
  final CharacterShadowSpec shadow;
  final String body;
  final String body256;
  final String? over;
  final String? over256;

  /// Top of the body's opaque area as a fraction of the plate height.
  final double bodyTop;
}

@immutable
class EyeStyleSpec {
  const EyeStyleSpec({
    required this.style,
    required this.openHFrac,
    required this.files,
  });

  factory EyeStyleSpec.fromJson(Map<String, dynamic> j) => EyeStyleSpec(
        style: j['style'] as String,
        openHFrac: (j['open_h_frac'] as num).toDouble(),
        files: {
          for (final e in (j['files'] as Map<String, dynamic>).entries)
            e.key: e.value as String,
        },
      );

  final String style;
  final double openHFrac;
  final Map<String, String> files;
}

class CharacterRoster {
  CharacterRoster({
    required Map<String, CharacterSpec> characters,
    required Map<String, EyeStyleSpec> eyeStyles,
  })  : characters = Map.unmodifiable(characters),
        eyeStyles = Map.unmodifiable(eyeStyles);

  factory CharacterRoster.parse(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final chars = <String, CharacterSpec>{};
    for (final entry in (j['characters'] as List)) {
      final spec = CharacterSpec.fromJson(entry as Map<String, dynamic>);
      chars[spec.id] = spec;
    }
    final styles = <String, EyeStyleSpec>{};
    for (final entry in (j['eye_styles'] as Map<String, dynamic>).entries) {
      styles[entry.key] =
          EyeStyleSpec.fromJson(entry.value as Map<String, dynamic>);
    }
    return CharacterRoster(characters: chars, eyeStyles: styles);
  }

  static const _assetRoot = 'assets/avatars/';
  static final _pngSuffix = RegExp(r'\.png$');

  static CharacterRoster? current;
  static Future<CharacterRoster>? _pending;

  static Future<CharacterRoster> load() {
    final ready = current;
    if (ready != null) return SynchronousFuture(ready);
    return _pending ??=
        rootBundle.loadString('${_assetRoot}roster.json').then((raw) {
      final parsed = CharacterRoster.parse(raw);
      current = parsed;
      return parsed;
    }).catchError((Object e) {
      _pending = null;
      throw e;
    });
  }

  final Map<String, CharacterSpec> characters;
  final Map<String, EyeStyleSpec> eyeStyles;

  CharacterSpec? character(String id) =>
      characters[id] ?? characters['01'] ?? characters.values.firstOrNull;

  EyeStyleSpec? eyeStyle(String style) => eyeStyles[style];

  static String plateAsset(String characterId, String filename) =>
      '$_assetRoot$characterId/${filename.replaceFirst(_pngSuffix, '.webp')}';

  static String eyeAsset(String filename) =>
      '$_assetRoot${filename.replaceFirst(_pngSuffix, '.webp')}';
}

@immutable
class CharacterPose {
  const CharacterPose({
    this.bodyDy = 0,
    this.bodyScaleX = 1,
    this.bodyScaleY = 1,
    this.shadowScale = 1,
    this.shadowOpacity = 1,
    this.glanceX = 0,
    this.blinkClosedOpacity = 0,
    this.eyeState = 'open',
  });

  final double bodyDy;
  final double bodyScaleX;
  final double bodyScaleY;
  final double shadowScale;
  final double shadowOpacity;
  final double glanceX;
  final double blinkClosedOpacity;
  final String eyeState;
}

/// Composited agent mascot driven by [CharacterRoster] and a single shared
/// [AmbientClock].
class AgentCharacter extends StatefulWidget {
  const AgentCharacter(
    this.characterId, {
    super.key,
    this.size = 24,
    this.state = AgentCharacterState.idle,
    this.staggerKey,
    this.badge,
    this.sleepMarks = true,
  });

  final String characterId;
  final double size;
  final AgentCharacterState state;
  final String? staggerKey;

  /// Short mark (usually '?') shown top-right in the character's colour.
  final String? badge;

  /// Draw the drifting 'z' when sleeping; off where a stage draws its own.
  final bool sleepMarks;

  static bool useHighRes(double logicalSize, double devicePixelRatio) =>
      logicalSize * devicePixelRatio > 256.0;

  static int staggerMs(String key) {
    var h = 7;
    for (final code in key.codeUnits) {
      h = (h * 31 + code) & 0xFFFFFFFF;
    }
    return h % 4000;
  }

  static const _hopCurve = Cubic(0.3, 0.7, 0.4, 1.0);

  static CharacterPose poseForState(
    AgentCharacterState state,
    double size,
    double timeSec, {
    bool reducedMotion = false,
  }) {
    final baseEye = switch (state) {
      AgentCharacterState.done => 'happy',
      AgentCharacterState.needs => 'wide',
      AgentCharacterState.sleeping => 'closed',
      _ => 'open',
    };
    if (reducedMotion ||
        state == AgentCharacterState.idle ||
        state == AgentCharacterState.done) {
      return CharacterPose(eyeState: baseEye);
    }

    switch (state) {
      case AgentCharacterState.working:
        final p = (timeSec % 1.8) / 1.8;
        double dy = 0, sx = 1, sy = 1, shScale = 1, shOpacity = 1;
        if (p < 0.10) {
          final k = _hopCurve.transform(p / 0.10);
          sx = lerpDouble(1.0, 1.05, k)!;
          sy = lerpDouble(1.0, 0.94, k)!;
        } else if (p < 0.26) {
          final k = _hopCurve.transform((p - 0.10) / 0.16);
          dy = lerpDouble(0.0, -0.10 * size, k)!;
          sx = lerpDouble(1.05, 0.97, k)!;
          sy = lerpDouble(0.94, 1.04, k)!;
          shScale = lerpDouble(1.0, 0.8, k)!;
          shOpacity = lerpDouble(1.0, 0.6, k)!;
        } else if (p < 0.42) {
          final k = _hopCurve.transform((p - 0.26) / 0.16);
          dy = lerpDouble(-0.10 * size, 0.0, k)!;
          sx = lerpDouble(0.97, 1.05, k)!;
          sy = lerpDouble(1.04, 0.94, k)!;
          shScale = lerpDouble(0.8, 1.0, k)!;
          shOpacity = lerpDouble(0.6, 1.0, k)!;
        } else if (p < 0.50) {
          final k = _hopCurve.transform((p - 0.42) / 0.08);
          sx = lerpDouble(1.05, 1.0, k)!;
          sy = lerpDouble(0.94, 1.0, k)!;
        }
        return CharacterPose(
          bodyDy: dy,
          bodyScaleX: sx,
          bodyScaleY: sy,
          shadowScale: shScale,
          shadowOpacity: shOpacity,
          glanceX: _glanceOffset(timeSec, size),
          eyeState: 'open',
        );
      case AgentCharacterState.waiting:
        final b = (timeSec % 4.2) / 4.2;
        var closed = 0.0;
        if (b >= 0.88 && b < 0.89) {
          closed = (b - 0.88) / 0.01;
        } else if (b >= 0.89 && b < 0.94) {
          closed = 1.0;
        } else if (b >= 0.94 && b < 0.95) {
          closed = 1.0 - (b - 0.94) / 0.01;
        }
        return CharacterPose(
          glanceX: _glanceOffset(timeSec, size),
          blinkClosedOpacity: closed,
          eyeState: 'open',
        );
      case AgentCharacterState.needs:
        final p = (timeSec % 3.2) / 3.2;
        var dy = 0.0;
        if (p >= 0.78 && p < 0.84) {
          dy = lerpDouble(0.0, -0.05 * size,
              Curves.easeInOut.transform((p - 0.78) / 0.06))!;
        } else if (p >= 0.84 && p < 0.90) {
          dy = lerpDouble(-0.05 * size, 0.0,
              Curves.easeInOut.transform((p - 0.84) / 0.06))!;
        }
        return CharacterPose(bodyDy: dy, eyeState: 'wide');
      case AgentCharacterState.sleeping:
        // Slow breath: a gentle squash on a 4 s cycle.
        final k = (1 - math.cos((timeSec % 4.0) / 4.0 * 2 * math.pi)) / 2;
        return CharacterPose(
          bodyScaleX: 1 + 0.025 * k,
          bodyScaleY: 1 - 0.035 * k,
          shadowScale: 1 + 0.04 * k,
          eyeState: 'closed',
        );
      case AgentCharacterState.idle:
      case AgentCharacterState.done:
        return CharacterPose(eyeState: baseEye);
    }
  }

  static double _glanceOffset(double timeSec, double size) {
    final g = (timeSec % 6.0) / 6.0;
    if (g < 0.28) return 0.0;
    if (g < 0.34) {
      return lerpDouble(
          0.0, 0.04 * size, Curves.easeInOut.transform((g - 0.28) / 0.06))!;
    }
    if (g < 0.56) return 0.04 * size;
    if (g < 0.62) {
      return lerpDouble(0.04 * size, -0.03 * size,
          Curves.easeInOut.transform((g - 0.56) / 0.06))!;
    }
    if (g < 0.80) return -0.03 * size;
    if (g < 0.86) {
      return lerpDouble(-0.03 * size, 0.0,
          Curves.easeInOut.transform((g - 0.80) / 0.06))!;
    }
    return 0.0;
  }

  @override
  State<AgentCharacter> createState() => _AgentCharacterState();
}

class _AgentCharacterState extends State<AgentCharacter> {
  CharacterRoster? _roster = CharacterRoster.current;
  ValueListenable<TickerModeData>? _tickerMode;
  bool _tickerEnabled = true;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    if (_roster == null) {
      CharacterRoster.load().then((r) {
        if (!mounted) return;
        setState(() => _roster = r);
        _syncTicking();
      }).catchError((_) {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mode = TickerMode.getValuesNotifier(context);
    if (mode != _tickerMode) {
      _tickerMode?.removeListener(_modeChanged);
      _tickerMode = mode..addListener(_modeChanged);
      _tickerEnabled = mode.value.enabled;
    }
    _syncTicking();
  }

  @override
  void didUpdateWidget(AgentCharacter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _syncTicking();
  }

  void _modeChanged() {
    final enabled = _tickerMode?.value.enabled ?? true;
    if (enabled == _tickerEnabled) return;
    _tickerEnabled = enabled;
    _syncTicking();
  }

  bool get _animatedState =>
      widget.state == AgentCharacterState.working ||
      widget.state == AgentCharacterState.waiting ||
      widget.state == AgentCharacterState.needs ||
      widget.state == AgentCharacterState.sleeping;

  void _syncTicking() {
    final want = mounted &&
        _roster != null &&
        _animatedState &&
        _tickerEnabled &&
        !reduceMotion(context);
    if (want == _listening) return;
    _listening = want;
    if (want) {
      AmbientClock.instance.addListener(_onTick);
    } else {
      AmbientClock.instance.removeListener(_onTick);
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tickerMode?.removeListener(_modeChanged);
    _tickerMode = null;
    if (_listening) {
      AmbientClock.instance.removeListener(_onTick);
      _listening = false;
    }
    super.dispose();
  }

  Widget _assetImage(String asset, {double? width, double? height}) =>
      Image.asset(
        asset,
        width: width,
        height: height,
        fit: BoxFit.fill,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );

  /// A small "z" that rises from the head and fades, 3 s a cycle.
  Widget _sleepLayer(double size, double bodyTop, double timeSec) {
    final p = (timeSec % 3.0) / 3.0;
    final fade = p < 0.2 ? p / 0.2 : (1 - p) / 0.8;
    final font = (size * 0.22).clamp(9.0, 16.0);
    return Positioned(
      right: -size * 0.02 - p * size * 0.08,
      top: bodyTop * size - font * 0.4 - p * size * 0.18,
      child: IgnorePointer(
        child: Opacity(
          opacity: fade.clamp(0.0, 1.0) * 0.8,
          child: Text('z',
              textScaler: TextScaler.noScaling,
              style: sans(font * (0.85 + 0.3 * p),
                      weight: FontWeight.w600, color: AppColors.fg3)
                  .copyWith(height: 1)),
        ),
      ),
    );
  }

  Widget _badgeLayer(Color fill, double size, double bodyTop) {
    // Matches the mockup: 11px at sidebar size up to 20px on the stage.
    final d = (size * 0.34).clamp(11.0, 20.0);
    final ring = d < 14 ? 1.0 : 1.5;
    final ink = fill.computeLuminance() > 0.4
        ? const Color(0xFF121110)
        : const Color(0xFFFFFFFF);
    final edge = d < 14 ? -3.0 : -2.0;
    return Positioned(
      right: edge,
      // Low shapes such as the dome would otherwise float the badge in air.
      top: bodyTop * size + edge,
      child: Container(
        width: d,
        height: d,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.bg, width: ring),
        ),
        child: Text(
          widget.badge!,
          textScaler: TextScaler.noScaling,
          style: sans(d * 0.58, weight: FontWeight.w700, color: ink)
              .copyWith(height: 1),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final roster = _roster;
    final spec = roster?.character(widget.characterId);
    final eyeStyle = spec == null ? null : roster?.eyeStyle(spec.eyeStyle);
    if (spec == null || eyeStyle == null) {
      return SizedBox.square(dimension: size);
    }

    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final hi = AgentCharacter.useHighRes(size, dpr);
    final reduced = reduceMotion(context);
    final staggerSec =
        AgentCharacter.staggerMs(widget.staggerKey ?? widget.characterId) /
            1000.0;
    final timeSec =
        _listening ? AmbientClock.instance.seconds + staggerSec : 0.0;
    final pose = AgentCharacter.poseForState(
      widget.state,
      size,
      timeSec,
      reducedMotion: reduced,
    );

    final shadowAsset = CharacterRoster.plateAsset(
      spec.id,
      hi ? spec.shadow.file : spec.shadow.file256,
    );
    final bodyAsset = CharacterRoster.plateAsset(
      spec.id,
      hi ? spec.body : spec.body256,
    );
    final overName = hi ? spec.over : spec.over256;
    final overAsset =
        overName == null ? null : CharacterRoster.plateAsset(spec.id, overName);
    final openEyeFile = eyeStyle.files[pose.eyeState] ?? eyeStyle.files['open']!;
    final openEyeAsset = CharacterRoster.eyeAsset(openEyeFile);
    final closedEyeAsset = widget.state == AgentCharacterState.waiting &&
            pose.blinkClosedOpacity > 0 &&
            eyeStyle.files.containsKey('closed')
        ? CharacterRoster.eyeAsset(eyeStyle.files['closed']!)
        : null;

    final sh = spec.shadow;
    final shWidget = _assetImage(shadowAsset);
    final shadowLayer = Positioned(
      left: sh.x * size,
      top: sh.y * size,
      width: sh.w * size,
      height: sh.h * size,
      child: pose.shadowScale == 1.0 && pose.shadowOpacity == 1.0
          ? shWidget
          : Opacity(
              opacity: pose.shadowOpacity,
              child: Transform.scale(
                scale: pose.shadowScale,
                alignment: Alignment.center,
                child: shWidget,
              ),
            ),
    );

    final eyesChildren = <Widget>[
      for (final eye in spec.eyes)
        () {
          final box = 2.0 * eye.ry / eyeStyle.openHFrac * size;
          Widget img = _assetImage(openEyeAsset, width: box, height: box);
          if (closedEyeAsset != null) {
            final c = pose.blinkClosedOpacity;
            if (c >= 1.0) {
              img = _assetImage(closedEyeAsset, width: box, height: box);
            } else if (c > 0.0) {
              img = Stack(
                fit: StackFit.expand,
                children: [
                  Opacity(opacity: 1.0 - c, child: img),
                  Opacity(
                    opacity: c,
                    child: _assetImage(closedEyeAsset, width: box, height: box),
                  ),
                ],
              );
            }
          }
          return Positioned(
            left: (eye.x - (eye.ry / eyeStyle.openHFrac)) * size,
            top: (eye.y - (eye.ry / eyeStyle.openHFrac)) * size,
            width: box,
            height: box,
            child: img,
          );
        }(),
    ];

    Widget eyesLayer = Stack(clipBehavior: Clip.none, children: eyesChildren);
    if (pose.glanceX != 0.0) {
      eyesLayer = Transform.translate(
        offset: Offset(pose.glanceX, 0),
        child: eyesLayer,
      );
    }

    Widget bodyGroup = Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: _assetImage(bodyAsset)),
        Positioned.fill(child: eyesLayer),
        if (overAsset != null) Positioned.fill(child: _assetImage(overAsset)),
      ],
    );

    if (pose.bodyScaleX != 1.0 || pose.bodyScaleY != 1.0) {
      bodyGroup = Transform(
        alignment: Alignment.bottomCenter,
        transform: Matrix4.diagonal3Values(pose.bodyScaleX, pose.bodyScaleY, 1),
        child: bodyGroup,
      );
    }
    if (pose.bodyDy != 0.0) {
      bodyGroup = Transform.translate(
        offset: Offset(0, pose.bodyDy),
        child: bodyGroup,
      );
    }

    final stack = SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          shadowLayer,
          Positioned.fill(child: bodyGroup),
          if (widget.badge != null && widget.badge!.isNotEmpty)
            _badgeLayer(spec.color, size, spec.bodyTop),
          if (widget.state == AgentCharacterState.sleeping &&
              widget.sleepMarks &&
              size >= 24)
            _sleepLayer(size, spec.bodyTop, reduced ? 0.35 : timeSec),
        ],
      ),
    );

    return _animatedState ? RepaintBoundary(child: stack) : stack;
  }
}
