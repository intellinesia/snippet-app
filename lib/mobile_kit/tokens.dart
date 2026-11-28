// The phone design language: one set of parts every mobile panel builds on.
// iPhone puts translucent glass on the control layer only (tab bar, header
// buttons, composer, sheets); Android uses Material 3 Expressive tonal
// surfaces. Content sits on flat surfaces without outlines, and amber means
// only "needs you". Desktop never imports lib/mobile_kit.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

// Dev only: the Linux phone build with the Android look, for screen audits.
const _forceAndroid = bool.fromEnvironment('SNIPPET_FORCE_ANDROID');

/// True when phone parts should take their Material 3 Expressive form.
bool get kAndroidLook =>
    _forceAndroid ||
    (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

/// Fixed measurements from the approved board, in logical pixels.
class MK {
  static const double gutter = 20;
  static const double rowMin = 60;
  static const double rowAvatar = 40;
  static const double glassButton = 44;
  static const double pill = 40;
  static const double tabBar = 62;
  static const double fab = 62;
  static const double androidFab = 56;
  static const double androidNav = 80;
  static const double cardRadius = 24;
  static const double groupRadius = 22;

  /// The filter row under a large title, the same on every tab (board).
  static EdgeInsets get filterPad => kAndroidLook
      ? const EdgeInsets.fromLTRB(16, 6, 16, 0)
      : const EdgeInsets.fromLTRB(20, 10, 20, 0);

  /// Height of the full-width primary buttons.
  static double get bigButton => kAndroidLook ? 56 : 50;

  /// Space a scroll view leaves at the bottom so the floating bar never
  /// covers its last row. The shell's extendBody already folds the bar's
  /// height into the bottom padding.
  static double bottomClearance(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom + 12;

  /// Text and icons on the light primary fill.
  static Color get onPrimary => AppColors.bg;

  static Color get hairline => AppColors.fg1.withValues(alpha: 0.07);

  /// Selected tab inside the iPhone glass bar.
  static const Color selectedTab = Color(0x6B000000);

  /// iPhone glass fill and Android tonal indicator.
  static const Color glassFill = Color(0x85343431);
  static Color get tonal =>
      Color.lerp(AppColors.surface3, AppColors.fg1, 0.06)!;

  static Color get amber => AppColors.run;
}

/// Large page title: 32 semibold on iPhone, 34 on Android, tracked -2%.
TextStyle mkLargeTitle() {
  final size = kAndroidLook ? 34.0 : 32.0;
  return display(size, weight: FontWeight.w600, color: AppColors.fg1)
      .copyWith(letterSpacing: -0.02 * size);
}

/// Row title, 15.5 medium.
TextStyle mkRowTitle({Color? color}) =>
    sans(15.5, weight: W.label, height: 1.4, color: color ?? AppColors.fg1);

/// Row subtitle, 13.5 in the third ink.
TextStyle mkRowSub({Color? color}) =>
    sans(13.5, height: 1.4, color: color ?? AppColors.fg3);

/// Branches, paths and commands under a row: Geist Mono 12.
TextStyle mkMonoSub({Color? color}) =>
    mono(12, height: 1.4, color: color ?? AppColors.fg3);

/// Timestamps on the right of a row.
TextStyle mkTime() => sans(12.5, color: AppColors.fg4, tabular: true);

/// Asks and questions read as prose: Geist 500 at 18.5.
TextStyle mkAskProse({double size = 18.5}) => TextStyle(
      fontFamily: 'Geist',
      fontSize: size,
      fontWeight: weightFor(FontWeight.w500),
      height: 1.38,
      letterSpacing: -0.01 * size,
      color: AppColors.fg1,
    );
