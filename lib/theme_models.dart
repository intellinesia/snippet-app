import 'package:flutter/material.dart';

import 'chat_scene.dart';
import 'platform.dart';
import 'theme.dart';

/// Parses `#RRGGBB` or `#AARRGGBB` into a [Color]. Returns null when invalid.
Color? parseThemeColor(dynamic raw) {
  if (raw is! String) return null;
  final h = raw.trim().replaceFirst('#', '');
  if (h.length != 6 && h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  if (v == null) return null;
  return Color(h.length == 6 ? (0xFF000000 | v) : v);
}

String formatThemeColor(Color c) {
  final argb = c.toARGB32();
  if ((argb >> 24) & 0xFF == 0xFF) {
    return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
  return '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}

double _numOr(dynamic raw, double fallback) =>
    raw is num ? raw.toDouble() : fallback;

int _intOr(dynamic raw, int fallback) => raw is num ? raw.round() : fallback;

bool _boolOr(dynamic raw, bool fallback) => raw is bool ? raw : fallback;

String _strOr(dynamic raw, String fallback) =>
    raw is String && raw.isNotEmpty ? raw : fallback;

Map<String, dynamic> _mapOrEmpty(dynamic raw) =>
    raw is Map<String, dynamic>
        ? raw
        : (raw is Map ? raw.cast<String, dynamic>() : const {});

/// A numeric token that may be a single value or `{phone, desktop}`.
class ResponsiveNum {
  final double phone;
  final double desktop;

  const ResponsiveNum(this.phone, this.desktop);
  const ResponsiveNum.all(double v)
      : phone = v,
        desktop = v;

  factory ResponsiveNum.fromJson(dynamic raw, ResponsiveNum fallback) {
    if (raw is num) return ResponsiveNum.all(raw.toDouble());
    if (raw is Map) {
      return ResponsiveNum(
        _numOr(raw['phone'], fallback.phone),
        _numOr(raw['desktop'], fallback.desktop),
      );
    }
    return fallback;
  }

  double resolve({required bool mobile}) => mobile ? phone : desktop;
  double get current => resolve(mobile: kMobile);

  dynamic toJson() =>
      phone == desktop ? phone : {'phone': phone, 'desktop': desktop};
}

class ThemeChatTokens {
  final String sentRaw;
  final Color? sentColor;
  final String sentTextRaw;
  final Color? sentTextColor;
  final Color received;
  final Color receivedText;
  final Color card;
  final Color cardButton;
  final Color meta;
  final Color glass;
  final ResponsiveNum fontSize;
  final ResponsiveNum bubbleRadius;
  final double runGap;
  final double groupGap;
  final ResponsiveNum maxShare;
  final ResponsiveNum avatarSize;
  final String agentReplies;
  final String longReplies;

  const ThemeChatTokens({
    this.sentRaw = '#3A3A3C',
    this.sentColor = const Color(0xFF3A3A3C),
    this.sentTextRaw = '#FFFFFF',
    this.sentTextColor = const Color(0xFFFFFFFF),
    this.received = const Color(0xFF26262A),
    this.receivedText = const Color(0xFFFFFFFF),
    this.card = const Color(0xFF1C1C1E),
    this.cardButton = const Color(0xFF2C2C2E),
    this.meta = const Color(0xFF8E8E93),
    this.glass = const Color(0xCC2C2C2E),
    this.fontSize = const ResponsiveNum(16, 13.5),
    this.bubbleRadius = const ResponsiveNum(18, 16),
    this.runGap = 2.0,
    this.groupGap = 10.0,
    this.maxShare = const ResponsiveNum(0.78, 0.66),
    this.avatarSize = const ResponsiveNum(28, 24),
    this.agentReplies = 'bubble',
    this.longReplies = 'bubble',
  });

  static const defaults = ThemeChatTokens();

  factory ThemeChatTokens.fromJson(Map<String, dynamic> j,
      [ThemeChatTokens fallback = defaults]) {
    final rawSent = j['sent'];
    String sentRaw = fallback.sentRaw;
    Color? sentColor = fallback.sentColor;
    if (rawSent is String && rawSent.isNotEmpty) {
      if (rawSent == 'agent' || rawSent == 'accent') {
        sentRaw = rawSent;
        sentColor = null;
      } else if (rawSent == 'grey') {
        sentRaw = rawSent;
        sentColor = const Color(0xFF3A3A3C);
      } else {
        final parsed = parseThemeColor(rawSent);
        if (parsed != null) {
          sentRaw = rawSent;
          sentColor = parsed;
        }
      }
    }

    final rawSentText = j['sentText'];
    String sentTextRaw = fallback.sentTextRaw;
    Color? sentTextColor = fallback.sentTextColor;
    if (rawSentText is String && rawSentText.isNotEmpty) {
      if (rawSentText == 'auto') {
        sentTextRaw = 'auto';
        sentTextColor = null;
      } else {
        final parsed = parseThemeColor(rawSentText);
        if (parsed != null) {
          sentTextRaw = rawSentText;
          sentTextColor = parsed;
        }
      }
    }

    return ThemeChatTokens(
      sentRaw: sentRaw,
      sentColor: sentColor,
      sentTextRaw: sentTextRaw,
      sentTextColor: sentTextColor,
      received: parseThemeColor(j['received']) ?? fallback.received,
      receivedText: parseThemeColor(j['receivedText']) ?? fallback.receivedText,
      card: parseThemeColor(j['card']) ?? fallback.card,
      cardButton: parseThemeColor(j['cardButton']) ?? fallback.cardButton,
      meta: parseThemeColor(j['meta']) ?? fallback.meta,
      glass: parseThemeColor(j['glass']) ?? fallback.glass,
      fontSize: ResponsiveNum.fromJson(j['fontSize'], fallback.fontSize),
      bubbleRadius:
          ResponsiveNum.fromJson(j['bubbleRadius'], fallback.bubbleRadius),
      runGap: _numOr(j['runGap'], fallback.runGap),
      groupGap: _numOr(j['groupGap'], fallback.groupGap),
      maxShare: ResponsiveNum.fromJson(j['maxShare'], fallback.maxShare),
      avatarSize: ResponsiveNum.fromJson(j['avatarSize'], fallback.avatarSize),
      agentReplies: _strOr(j['agentReplies'], fallback.agentReplies),
      longReplies: _strOr(j['longReplies'], fallback.longReplies),
    );
  }

  Map<String, dynamic> toJson() => {
        'sent': sentRaw,
        'sentText': sentTextRaw,
        'received': formatThemeColor(received),
        'receivedText': formatThemeColor(receivedText),
        'card': formatThemeColor(card),
        'cardButton': formatThemeColor(cardButton),
        'meta': formatThemeColor(meta),
        'glass': formatThemeColor(glass),
        'fontSize': fontSize.toJson(),
        'bubbleRadius': bubbleRadius.toJson(),
        'runGap': runGap,
        'groupGap': groupGap,
        'maxShare': maxShare.toJson(),
        'avatarSize': avatarSize.toJson(),
        'agentReplies': agentReplies,
        'longReplies': longReplies,
      };
}

class ThemeTypeWeights {
  final int body;
  final int label;
  final int title;
  final int strong;

  const ThemeTypeWeights({
    this.body = 400,
    this.label = 500,
    this.title = 500,
    this.strong = 500,
  });

  static const defaults = ThemeTypeWeights();

  factory ThemeTypeWeights.fromJson(Map<String, dynamic> j,
          [ThemeTypeWeights fallback = defaults]) =>
      ThemeTypeWeights(
        body: _intOr(j['body'], fallback.body),
        label: _intOr(j['label'], fallback.label),
        title: _intOr(j['title'], fallback.title),
        strong: _intOr(j['strong'], fallback.strong),
      );

  Map<String, dynamic> toJson() => {
        'body': body,
        'label': label,
        'title': title,
        'strong': strong,
      };
}

class ThemeTypeStyle {
  final ResponsiveNum size;
  final int weight;
  final double height;
  final double tracking;

  const ThemeTypeStyle({
    required this.size,
    required this.weight,
    required this.height,
    required this.tracking,
  });

  factory ThemeTypeStyle.fromJson(
          Map<String, dynamic> j, ThemeTypeStyle fallback) =>
      ThemeTypeStyle(
        size: ResponsiveNum.fromJson(j['size'], fallback.size),
        weight: _intOr(j['weight'], fallback.weight),
        height: _numOr(j['height'], fallback.height),
        tracking: _numOr(j['tracking'], fallback.tracking),
      );

  Map<String, dynamic> toJson() => {
        'size': size.toJson(),
        'weight': weight,
        'height': height,
        'tracking': tracking,
      };
}

class ThemeTypeTokens {
  final String uiFont;
  final String codeFont;
  final double scale;
  final ThemeTypeWeights weights;
  final Map<String, ThemeTypeStyle> styles;

  const ThemeTypeTokens({
    this.uiFont = ThemeManager.defaultFont,
    this.codeFont = ThemeManager.defaultMonoFont,
    this.scale = 1.0,
    this.weights = ThemeTypeWeights.defaults,
    this.styles = defaultStyles,
  });

  static const Map<String, ThemeTypeStyle> defaultStyles = {
    'pageTitle': ThemeTypeStyle(
        size: ResponsiveNum(28, 20), weight: 500, height: 1.3, tracking: -0.08),
    'sectionTitle': ThemeTypeStyle(
        size: ResponsiveNum(20, 16), weight: 500, height: 1.375, tracking: 0.0),
    'rowTitle': ThemeTypeStyle(
        size: ResponsiveNum(16, 13), weight: 500, height: 1.385, tracking: 0.0),
    'body': ThemeTypeStyle(
        size: ResponsiveNum(16, 14), weight: 400, height: 1.571, tracking: 0.0),
    'ui': ThemeTypeStyle(
        size: ResponsiveNum(14, 13), weight: 400, height: 1.385, tracking: 0.0),
    'label': ThemeTypeStyle(
        size: ResponsiveNum(13, 12), weight: 500, height: 1.333, tracking: 0.0),
    'meta': ThemeTypeStyle(
        size: ResponsiveNum(13, 12), weight: 400, height: 1.333, tracking: 0.0),
    'caption': ThemeTypeStyle(
        size: ResponsiveNum(12, 11), weight: 400, height: 1.273, tracking: 0.0),
    'overline': ThemeTypeStyle(
        size: ResponsiveNum(12, 11),
        weight: 500,
        height: 1.273,
        tracking: 0.66),
    'reading': ThemeTypeStyle(
        size: ResponsiveNum(16, 14), weight: 400, height: 1.571, tracking: 0.0),
    'code': ThemeTypeStyle(
        size: ResponsiveNum(13, 12), weight: 400, height: 1.5, tracking: 0.0),
    'codeSmall': ThemeTypeStyle(
        size: ResponsiveNum.all(12), weight: 400, height: 1.333, tracking: 0.0),
  };

  static const defaults = ThemeTypeTokens();

  ThemeTypeTokens copyWith({String? uiFont, String? codeFont}) =>
      ThemeTypeTokens(
        uiFont: uiFont ?? this.uiFont,
        codeFont: codeFont ?? this.codeFont,
        scale: scale,
        weights: weights,
        styles: styles,
      );

  factory ThemeTypeTokens.fromJson(Map<String, dynamic> j,
      [ThemeTypeTokens fallback = defaults]) {
    final rawStyles = _mapOrEmpty(j['styles']);
    final parsedStyles = <String, ThemeTypeStyle>{};
    for (final e in fallback.styles.entries) {
      final s = _mapOrEmpty(rawStyles[e.key]);
      parsedStyles[e.key] =
          s.isEmpty ? e.value : ThemeTypeStyle.fromJson(s, e.value);
    }
    return ThemeTypeTokens(
      uiFont: _strOr(j['uiFont'], fallback.uiFont),
      codeFont: _strOr(j['codeFont'], fallback.codeFont),
      scale: _numOr(j['scale'], fallback.scale),
      weights: ThemeTypeWeights.fromJson(
          _mapOrEmpty(j['weights']), fallback.weights),
      styles: parsedStyles,
    );
  }

  Map<String, dynamic> toJson() => {
        'uiFont': uiFont,
        'codeFont': codeFont,
        'scale': scale,
        'weights': weights.toJson(),
        'styles': {
          for (final e in styles.entries) e.key: e.value.toJson(),
        },
      };
}

class ThemeShapeRadii {
  final double xs;
  final double sm;
  final double chip;
  final double md;
  final double card;
  final double lg;
  final double sheetTop;
  final double pill;

  const ThemeShapeRadii({
    this.xs = R.xs,
    this.sm = R.sm,
    this.chip = R.chip,
    this.md = R.md,
    this.card = R.card,
    this.lg = R.lg,
    this.sheetTop = R.sheetTop,
    this.pill = R.pill,
  });

  static const defaults = ThemeShapeRadii();

  factory ThemeShapeRadii.fromJson(Map<String, dynamic> j,
          [ThemeShapeRadii fallback = defaults]) =>
      ThemeShapeRadii(
        xs: _numOr(j['xs'], fallback.xs),
        sm: _numOr(j['sm'], fallback.sm),
        chip: _numOr(j['chip'], fallback.chip),
        md: _numOr(j['md'], fallback.md),
        card: _numOr(j['card'], fallback.card),
        lg: _numOr(j['lg'], fallback.lg),
        sheetTop: _numOr(j['sheetTop'], fallback.sheetTop),
        pill: _numOr(j['pill'], fallback.pill),
      );

  Map<String, dynamic> toJson() => {
        'xs': xs,
        'sm': sm,
        'chip': chip,
        'md': md,
        'card': card,
        'lg': lg,
        'sheetTop': sheetTop,
        'pill': pill,
      };
}

class ThemeShapeTokens {
  final double radiusScale;
  final ThemeShapeRadii radii;
  final String avatar;

  const ThemeShapeTokens({
    this.radiusScale = 1.0,
    this.radii = ThemeShapeRadii.defaults,
    this.avatar = 'circle',
  });

  static const defaults = ThemeShapeTokens();

  factory ThemeShapeTokens.fromJson(Map<String, dynamic> j,
          [ThemeShapeTokens fallback = defaults]) =>
      ThemeShapeTokens(
        radiusScale: _numOr(j['radiusScale'], fallback.radiusScale),
        radii: ThemeShapeRadii.fromJson(_mapOrEmpty(j['radii']), fallback.radii),
        avatar: _strOr(j['avatar'], fallback.avatar),
      );

  Map<String, dynamic> toJson() => {
        'radiusScale': radiusScale,
        'radii': radii.toJson(),
        'avatar': avatar,
      };
}

class ThemeBorderTokens {
  final double width;
  final double hairline;
  final bool cards;
  final double glassEdgeAlpha;

  const ThemeBorderTokens({
    this.width = 1.0,
    this.hairline = 1.0,
    this.cards = true,
    this.glassEdgeAlpha = 0.08,
  });

  static const defaults = ThemeBorderTokens();

  factory ThemeBorderTokens.fromJson(Map<String, dynamic> j,
          [ThemeBorderTokens fallback = defaults]) =>
      ThemeBorderTokens(
        width: _numOr(j['width'], fallback.width),
        hairline: _numOr(j['hairline'], fallback.hairline),
        cards: _boolOr(j['cards'], fallback.cards),
        glassEdgeAlpha: _numOr(j['glassEdgeAlpha'], fallback.glassEdgeAlpha),
      );

  Map<String, dynamic> toJson() => {
        'width': width,
        'hairline': hairline,
        'cards': cards,
        'glassEdgeAlpha': glassEdgeAlpha,
      };
}

class ThemeTranslucencyTokens {
  final ResponsiveNum canvasAlpha;
  final double windowTint;
  final ResponsiveNum glassFill;
  final double glassBlur;
  final bool edgeBlur;
  final double scrim;
  final double glassScrim;
  final double modalScrim;
  final bool enabled;

  const ThemeTranslucencyTokens({
    this.canvasAlpha = const ResponsiveNum(1.0, 0.78),
    this.windowTint = 0.35,
    this.glassFill = const ResponsiveNum.all(0.62),
    this.glassBlur = 24.0,
    this.edgeBlur = true,
    this.scrim = 0.6,
    this.glassScrim = 0.35,
    this.modalScrim = 0.38,
    this.enabled = true,
  });

  static const defaults = ThemeTranslucencyTokens();

  factory ThemeTranslucencyTokens.fromJson(Map<String, dynamic> j,
          [ThemeTranslucencyTokens fallback = defaults]) =>
      ThemeTranslucencyTokens(
        canvasAlpha:
            ResponsiveNum.fromJson(j['canvasAlpha'], fallback.canvasAlpha),
        windowTint: _numOr(j['windowTint'], fallback.windowTint),
        glassFill: ResponsiveNum.fromJson(j['glassFill'], fallback.glassFill),
        glassBlur: _numOr(j['glassBlur'], fallback.glassBlur),
        edgeBlur: _boolOr(j['edgeBlur'], fallback.edgeBlur),
        scrim: _numOr(j['scrim'], fallback.scrim),
        glassScrim: _numOr(j['glassScrim'], fallback.glassScrim),
        modalScrim: _numOr(j['modalScrim'], fallback.modalScrim),
        enabled: _boolOr(j['enabled'], fallback.enabled),
      );

  Map<String, dynamic> toJson() => {
        'canvasAlpha': canvasAlpha.toJson(),
        'windowTint': windowTint,
        'glassFill': glassFill.toJson(),
        'glassBlur': glassBlur,
        'edgeBlur': edgeBlur,
        'scrim': scrim,
        'glassScrim': glassScrim,
        'modalScrim': modalScrim,
        'enabled': enabled,
      };
}

class ThemeSpaceScale {
  final double s2;
  final double s4;
  final double s6;
  final double s8;
  final double s12;
  final double s16;
  final double s20;
  final double s24;
  final double s32;
  final double s40;

  const ThemeSpaceScale({
    this.s2 = S.s2,
    this.s4 = S.s4,
    this.s6 = S.s6,
    this.s8 = S.s8,
    this.s12 = S.s12,
    this.s16 = S.s16,
    this.s20 = S.s20,
    this.s24 = S.s24,
    this.s32 = S.s32,
    this.s40 = S.s40,
  });

  static const defaults = ThemeSpaceScale();

  factory ThemeSpaceScale.fromJson(Map<String, dynamic> j,
          [ThemeSpaceScale fallback = defaults]) =>
      ThemeSpaceScale(
        s2: _numOr(j['s2'], fallback.s2),
        s4: _numOr(j['s4'], fallback.s4),
        s6: _numOr(j['s6'], fallback.s6),
        s8: _numOr(j['s8'], fallback.s8),
        s12: _numOr(j['s12'], fallback.s12),
        s16: _numOr(j['s16'], fallback.s16),
        s20: _numOr(j['s20'], fallback.s20),
        s24: _numOr(j['s24'], fallback.s24),
        s32: _numOr(j['s32'], fallback.s32),
        s40: _numOr(j['s40'], fallback.s40),
      );

  Map<String, dynamic> toJson() => {
        's2': s2,
        's4': s4,
        's6': s6,
        's8': s8,
        's12': s12,
        's16': s16,
        's20': s20,
        's24': s24,
        's32': s32,
        's40': s40,
      };
}

class ThemeSpaceMetrics {
  final ResponsiveNum gutter;
  final ResponsiveNum navRow;
  final ResponsiveNum minTarget;
  final ResponsiveNum appBarHeight;
  final ResponsiveNum rowHeight;
  final ResponsiveNum rowPadH;
  final ResponsiveNum tabStripHeight;
  final ResponsiveNum tabIconSize;
  final ResponsiveNum tabActionSize;

  const ThemeSpaceMetrics({
    this.gutter = const ResponsiveNum.all(M.gutter),
    this.navRow = const ResponsiveNum.all(M.navRow),
    this.minTarget = const ResponsiveNum.all(M.minTarget),
    this.appBarHeight = const ResponsiveNum.all(M.appBarHeight),
    this.rowHeight = const ResponsiveNum.all(M.rowHeight),
    this.rowPadH = const ResponsiveNum.all(M.rowPadH),
    this.tabStripHeight = const ResponsiveNum.all(M.tabStripHeight),
    this.tabIconSize = const ResponsiveNum.all(M.tabIconSize),
    this.tabActionSize = const ResponsiveNum.all(M.tabActionSize),
  });

  static const defaults = ThemeSpaceMetrics();

  factory ThemeSpaceMetrics.fromJson(Map<String, dynamic> j,
          [ThemeSpaceMetrics fallback = defaults]) =>
      ThemeSpaceMetrics(
        gutter: ResponsiveNum.fromJson(j['gutter'], fallback.gutter),
        navRow: ResponsiveNum.fromJson(j['navRow'], fallback.navRow),
        minTarget: ResponsiveNum.fromJson(j['minTarget'], fallback.minTarget),
        appBarHeight:
            ResponsiveNum.fromJson(j['appBarHeight'], fallback.appBarHeight),
        rowHeight: ResponsiveNum.fromJson(j['rowHeight'], fallback.rowHeight),
        rowPadH: ResponsiveNum.fromJson(j['rowPadH'], fallback.rowPadH),
        tabStripHeight: ResponsiveNum.fromJson(
            j['tabStripHeight'], fallback.tabStripHeight),
        tabIconSize:
            ResponsiveNum.fromJson(j['tabIconSize'], fallback.tabIconSize),
        tabActionSize:
            ResponsiveNum.fromJson(j['tabActionSize'], fallback.tabActionSize),
      );

  Map<String, dynamic> toJson() => {
        'gutter': gutter.toJson(),
        'navRow': navRow.toJson(),
        'minTarget': minTarget.toJson(),
        'appBarHeight': appBarHeight.toJson(),
        'rowHeight': rowHeight.toJson(),
        'rowPadH': rowPadH.toJson(),
        'tabStripHeight': tabStripHeight.toJson(),
        'tabIconSize': tabIconSize.toJson(),
        'tabActionSize': tabActionSize.toJson(),
      };
}

class ThemeSpaceTokens {
  final double density;
  final ThemeSpaceScale scale;
  final ThemeSpaceMetrics metrics;

  const ThemeSpaceTokens({
    this.density = 1.0,
    this.scale = ThemeSpaceScale.defaults,
    this.metrics = ThemeSpaceMetrics.defaults,
  });

  static const defaults = ThemeSpaceTokens();

  factory ThemeSpaceTokens.fromJson(Map<String, dynamic> j,
          [ThemeSpaceTokens fallback = defaults]) =>
      ThemeSpaceTokens(
        density: _numOr(j['density'], fallback.density),
        scale: ThemeSpaceScale.fromJson(_mapOrEmpty(j['scale']), fallback.scale),
        metrics: ThemeSpaceMetrics.fromJson(
            _mapOrEmpty(j['metrics']), fallback.metrics),
      );

  Map<String, dynamic> toJson() => {
        'density': density,
        'scale': scale.toJson(),
        'metrics': metrics.toJson(),
      };
}

class ThemeMotionDurations {
  final int press;
  final int quick;
  final int fast;
  final int base;
  final int open;
  final int close;
  final int page;
  final int slow;
  final int pulse;

  const ThemeMotionDurations({
    this.press = 100,
    this.quick = 150,
    this.fast = 180,
    this.base = 220,
    this.open = 240,
    this.close = 180,
    this.page = 260,
    this.slow = 300,
    this.pulse = 1150,
  });

  static const defaults = ThemeMotionDurations();

  factory ThemeMotionDurations.fromJson(Map<String, dynamic> j,
          [ThemeMotionDurations fallback = defaults]) =>
      ThemeMotionDurations(
        press: _intOr(j['press'], fallback.press),
        quick: _intOr(j['quick'], fallback.quick),
        fast: _intOr(j['fast'], fallback.fast),
        base: _intOr(j['base'], fallback.base),
        open: _intOr(j['open'], fallback.open),
        close: _intOr(j['close'], fallback.close),
        page: _intOr(j['page'], fallback.page),
        slow: _intOr(j['slow'], fallback.slow),
        pulse: _intOr(j['pulse'], fallback.pulse),
      );

  Map<String, dynamic> toJson() => {
        'press': press,
        'quick': quick,
        'fast': fast,
        'base': base,
        'open': open,
        'close': close,
        'page': page,
        'slow': slow,
        'pulse': pulse,
      };
}

class ThemeMotionCurves {
  final List<double> enter;
  final List<double> exit;

  const ThemeMotionCurves({
    this.enter = const [0.32, 0.72, 0.0, 1.0],
    this.exit = const [0.23, 1.0, 0.32, 1.0],
  });

  static const defaults = ThemeMotionCurves();

  static List<double> _parseCurve(dynamic raw, List<double> fallback) {
    if (raw is List && raw.length == 4 && raw.every((e) => e is num)) {
      return [for (final n in raw) (n as num).toDouble()];
    }
    return fallback;
  }

  factory ThemeMotionCurves.fromJson(Map<String, dynamic> j,
          [ThemeMotionCurves fallback = defaults]) =>
      ThemeMotionCurves(
        enter: _parseCurve(j['enter'], fallback.enter),
        exit: _parseCurve(j['exit'], fallback.exit),
      );

  Map<String, dynamic> toJson() => {
        'enter': enter,
        'exit': exit,
      };
}

class ThemeMotionTokens {
  final double speed;
  final ThemeMotionDurations durations;
  final ThemeMotionCurves curves;

  const ThemeMotionTokens({
    this.speed = 1.0,
    this.durations = ThemeMotionDurations.defaults,
    this.curves = ThemeMotionCurves.defaults,
  });

  static const defaults = ThemeMotionTokens();

  factory ThemeMotionTokens.fromJson(Map<String, dynamic> j,
          [ThemeMotionTokens fallback = defaults]) =>
      ThemeMotionTokens(
        speed: _numOr(j['speed'], fallback.speed),
        durations: ThemeMotionDurations.fromJson(
            _mapOrEmpty(j['durations']), fallback.durations),
        curves: ThemeMotionCurves.fromJson(
            _mapOrEmpty(j['curves']), fallback.curves),
      );

  Map<String, dynamic> toJson() => {
        'speed': speed,
        'durations': durations.toJson(),
        'curves': curves.toJson(),
      };
}

class ThemeBackdropTokens {
  final String scene;
  final Map<String, dynamic> params;

  const ThemeBackdropTokens({
    this.scene = ChatScene.none,
    this.params = const {},
  });

  static const defaults = ThemeBackdropTokens();

  factory ThemeBackdropTokens.fromJson(Map<String, dynamic> j,
          [ThemeBackdropTokens fallback = defaults]) =>
      ThemeBackdropTokens(
        scene: _strOr(j['scene'], fallback.scene),
        params: _mapOrEmpty(j['params']),
      );

  Map<String, dynamic> toJson() => {
        'scene': scene,
        'params': params,
      };
}

class ThemeTerminalTokens {
  final List<Color> ansi;

  const ThemeTerminalTokens({
    this.ansi = defaultAnsi,
  });

  static const List<Color> defaultAnsi = [
    Color(0xFF1B1917),
    Color(0xFFE5745F),
    Color(0xFF7FB88F),
    Color(0xFFD4923C),
    Color(0xFF9DB0FF),
    Color(0xFFC79BD8),
    Color(0xFF7FC4C0),
    Color(0xFFCFC8BC),
    Color(0xFF7A7368),
    Color(0xFFEE9583),
    Color(0xFF9DCCA9),
    Color(0xFFE3A85A),
    Color(0xFFB4C3FF),
    Color(0xFFD8B4E6),
    Color(0xFF9FD6D2),
    Color(0xFFEDE7DD),
  ];

  static const defaults = ThemeTerminalTokens();

  factory ThemeTerminalTokens.fromJson(Map<String, dynamic> j,
      [ThemeTerminalTokens fallback = defaults]) {
    final raw = j['ansi'];
    if (raw is List && raw.length == 16) {
      final parsed = <Color>[];
      for (var i = 0; i < 16; i++) {
        parsed.add(parseThemeColor(raw[i]) ?? fallback.ansi[i]);
      }
      return ThemeTerminalTokens(ansi: parsed);
    }
    return fallback;
  }

  Map<String, dynamic> toJson() => {
        'ansi': [for (final c in ansi) formatThemeColor(c)],
      };
}

/// Complete resolved schema-1 theme document.
class ResolvedTheme {
  final int schema;
  final String id;
  final String name;
  final String? base;
  final String? description;
  final String? author;
  final String? accentName;
  final bool? activeSet;
  final ThemePreset colorPreset;
  final ThemeChatTokens chat;
  final ThemeTypeTokens type;
  final ThemeShapeTokens shape;
  final ThemeBorderTokens border;
  final ThemeTranslucencyTokens translucency;
  final ThemeSpaceTokens space;
  final ThemeMotionTokens motion;
  final ThemeBackdropTokens backdrop;
  final ThemeTerminalTokens terminal;
  final Map<String, Color> syntax;

  const ResolvedTheme({
    this.schema = 1,
    required this.id,
    required this.name,
    this.base,
    this.description,
    this.author,
    this.accentName,
    this.activeSet,
    required this.colorPreset,
    this.chat = ThemeChatTokens.defaults,
    this.type = ThemeTypeTokens.defaults,
    this.shape = ThemeShapeTokens.defaults,
    this.border = ThemeBorderTokens.defaults,
    this.translucency = ThemeTranslucencyTokens.defaults,
    this.space = ThemeSpaceTokens.defaults,
    this.motion = ThemeMotionTokens.defaults,
    this.backdrop = ThemeBackdropTokens.defaults,
    this.terminal = ThemeTerminalTokens.defaults,
    this.syntax = const {},
  });

  /// Color preset with top-level [accentName] override applied when present.
  ThemePreset get effectivePreset {
    if (accentName == null || accentName!.isEmpty) return colorPreset;
    final override =
        allAccents.where((a) => a.name == accentName).firstOrNull;
    return override == null
        ? colorPreset
        : colorPreset.withAccentOverride(override);
  }

  factory ResolvedTheme.fromPreset(
    ThemePreset preset, {
    String? accentName,
    String uiFont = ThemeManager.defaultFont,
    String codeFont = ThemeManager.defaultMonoFont,
  }) =>
      ResolvedTheme(
        id: preset.name,
        name: preset.label,
        author: 'builtin',
        accentName: accentName,
        colorPreset: preset,
        type: ThemeTypeTokens.defaults.copyWith(
          uiFont: uiFont,
          codeFont: codeFont,
        ),
      );

  factory ResolvedTheme.fromJson(
    Map<String, dynamic> raw, {
    ThemePreset? fallbackPreset,
  }) {
    final activeSet = raw['active_set'] is bool ? raw['active_set'] as bool : null;
    final j = raw['resolved'] is Map
        ? (raw['resolved'] as Map).cast<String, dynamic>()
        : raw;

    final rawAccent = j['accent'];
    final accentName =
        rawAccent is String && rawAccent.isNotEmpty ? rawAccent : null;
    final preset = ThemePreset.fromJson(j, fallback: fallbackPreset);

    final rawSyntax = _mapOrEmpty(j['syntax']);
    final syntax = <String, Color>{};
    for (final e in rawSyntax.entries) {
      final c = parseThemeColor(e.value);
      if (c != null) syntax[e.key] = c;
    }

    return ResolvedTheme(
      schema: _intOr(j['schema'], 1),
      id: preset.name,
      name: preset.label,
      base: j['base'] is String && (j['base'] as String).isNotEmpty
          ? j['base'] as String
          : null,
      description: j['description'] as String?,
      author: j['author'] as String?,
      accentName: accentName,
      activeSet: activeSet,
      colorPreset: preset,
      chat: ThemeChatTokens.fromJson(_mapOrEmpty(j['chat'])),
      type: ThemeTypeTokens.fromJson(_mapOrEmpty(j['type'])),
      shape: ThemeShapeTokens.fromJson(_mapOrEmpty(j['shape'])),
      border: ThemeBorderTokens.fromJson(_mapOrEmpty(j['border'])),
      translucency:
          ThemeTranslucencyTokens.fromJson(_mapOrEmpty(j['translucency'])),
      space: ThemeSpaceTokens.fromJson(_mapOrEmpty(j['space'])),
      motion: ThemeMotionTokens.fromJson(_mapOrEmpty(j['motion'])),
      backdrop: ThemeBackdropTokens.fromJson(_mapOrEmpty(j['backdrop'])),
      terminal: ThemeTerminalTokens.fromJson(_mapOrEmpty(j['terminal'])),
      syntax: syntax,
    );
  }

  ResolvedTheme copyWith({
    String? id,
    String? name,
    String? base,
    String? author,
    Object? accentName = _unset,
    ThemePreset? colorPreset,
    ThemeTypeTokens? type,
  }) =>
      ResolvedTheme(
        schema: schema,
        id: id ?? this.id,
        name: name ?? this.name,
        base: base ?? this.base,
        description: description,
        author: author ?? this.author,
        accentName:
            identical(accentName, _unset) ? this.accentName : accentName as String?,
        activeSet: activeSet,
        colorPreset: colorPreset ?? this.colorPreset,
        chat: chat,
        type: type ?? this.type,
        shape: shape,
        border: border,
        translucency: translucency,
        space: space,
        motion: motion,
        backdrop: backdrop,
        terminal: terminal,
        syntax: syntax,
      );

  Map<String, dynamic> toJson() => {
        'schema': schema,
        'id': id,
        'name': name,
        if (base != null) 'base': base,
        if (description != null) 'description': description,
        if (author != null) 'author': author,
        'accent': accentName,
        'color': colorPreset.toColorJson(),
        'chat': chat.toJson(),
        'type': type.toJson(),
        'shape': shape.toJson(),
        'border': border.toJson(),
        'translucency': translucency.toJson(),
        'space': space.toJson(),
        'motion': motion.toJson(),
        'backdrop': backdrop.toJson(),
        'terminal': terminal.toJson(),
        'syntax': {
          for (final e in syntax.entries) e.key: formatThemeColor(e.value),
        },
      };
}

const _unset = Object();

class ThemePreview {
  final Color bg;
  final Color surface1;
  final Color fg1;
  final Color accent;

  const ThemePreview({
    required this.bg,
    required this.surface1,
    required this.fg1,
    required this.accent,
  });

  factory ThemePreview.fromJson(Map<String, dynamic> j) => ThemePreview(
        bg: parseThemeColor(j['bg']) ?? const Color(0xFF000000),
        surface1: parseThemeColor(j['surface1']) ?? const Color(0xFF0F0F0F),
        fg1: parseThemeColor(j['fg1']) ?? const Color(0xFFFAFAFA),
        accent: parseThemeColor(j['accent']) ?? const Color(0xFFFAFAFA),
      );
}

class ThemeSummary {
  final String id;
  final String name;
  final String author;
  final bool builtin;
  final String? base;
  final String? updatedAt;
  final ThemePreview preview;

  const ThemeSummary({
    required this.id,
    required this.name,
    required this.author,
    required this.builtin,
    this.base,
    this.updatedAt,
    required this.preview,
  });

  bool get isAgent => author.startsWith('agent:');
  String get agentId => isAgent ? author.substring('agent:'.length) : '';
  bool get isUser => !builtin && !isAgent;

  factory ThemeSummary.fromJson(Map<String, dynamic> j) {
    final author = j['author'] as String? ?? '';
    final builtin = j['builtin'] is bool
        ? j['builtin'] as bool
        : author == 'builtin';
    return ThemeSummary(
      id: j['id'] is String ? j['id'] as String : '',
      name: j['name'] is String ? j['name'] as String : '',
      author: author.isEmpty && builtin ? 'builtin' : author,
      builtin: builtin,
      base: j['base'] is String ? j['base'] as String : null,
      updatedAt: j['updated_at'] == null ? null : '${j['updated_at']}',
      preview: ThemePreview.fromJson(_mapOrEmpty(j['preview'])),
    );
  }

  factory ThemeSummary.fromPreset(ThemePreset p) => ThemeSummary(
        id: p.name,
        name: p.label,
        author: 'builtin',
        builtin: true,
        preview: ThemePreview(
          bg: p.bg,
          surface1: p.surface1,
          fg1: p.fg1,
          accent: p.accent,
        ),
      );
}

class ThemeListResponse {
  final List<String> liveGroups;
  final List<ThemeSummary> themes;
  final String active;
  final bool activeSet;

  const ThemeListResponse({
    this.liveGroups = const [],
    this.themes = const [],
    this.active = ThemeManager.defaultTheme,
    this.activeSet = true,
  });

  factory ThemeListResponse.fromJson(Map<String, dynamic> j) {
    final rawThemes = (j['themes'] ?? j['items']) as List? ?? const [];
    return ThemeListResponse(
      liveGroups: [
        for (final g in (j['live_groups'] as List? ?? const [])) '$g',
      ],
      themes: [
        for (final t in rawThemes)
          if (t is Map) ThemeSummary.fromJson(t.cast<String, dynamic>()),
      ],
      active: (j['active'] as String?) ?? ThemeManager.defaultTheme,
      activeSet: j['active_set'] is bool ? j['active_set'] as bool : true,
    );
  }
}

class ThemeDetail {
  final Map<String, dynamic> document;
  final ResolvedTheme resolved;

  const ThemeDetail({required this.document, required this.resolved});

  factory ThemeDetail.fromJson(Map<String, dynamic> j) {
    final doc = _mapOrEmpty(j['document']).isNotEmpty
        ? _mapOrEmpty(j['document'])
        : Map<String, dynamic>.of(j)
      ..remove('resolved');
    final resolvedMap = _mapOrEmpty(j['resolved']).isNotEmpty
        ? _mapOrEmpty(j['resolved'])
        : j;
    return ThemeDetail(
      document: doc,
      resolved: ResolvedTheme.fromJson(resolvedMap),
    );
  }
}

class ThemeValidationResult {
  final bool valid;
  final List<String> problems;

  const ThemeValidationResult({required this.valid, this.problems = const []});

  factory ThemeValidationResult.fromJson(Map<String, dynamic> j,
      {required bool okStatus}) {
    final problems = [
      for (final p in (j['problems'] as List? ?? const [])) '$p',
    ];
    final valid = j['valid'] is bool
        ? j['valid'] as bool
        : (okStatus && problems.isEmpty && j['error'] == null);
    return ThemeValidationResult(valid: valid, problems: problems);
  }
}

class ThemeValidationException implements Exception {
  final String message;
  final List<String> problems;

  const ThemeValidationException(this.message, this.problems);

  @override
  String toString() =>
      problems.isEmpty ? message : '$message: ${problems.join('; ')}';
}
