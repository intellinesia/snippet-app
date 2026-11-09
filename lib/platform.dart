import 'package:flutter/foundation.dart';

/// True on phones/tablets (Android/iOS). Desktop (macOS/Linux/Windows) and web
/// are false. Used to guard mobile-only plugins (foreground task, camera
/// permissions) that have no desktop support, and to pick the layout.
bool get kMobile =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Desktop platforms with native notification plugin support.
bool get kDesktopNotify =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

/// True wherever the recorder can capture voice input. macOS uses the native
/// record_macos plugin and requests permission through AudioRecorder itself.
bool get kCanRecord => kMobile || kMacOS;

/// True wherever we can deliver session notifications at all.
///
/// MOBILE ONLY. The desktop shell has no notification surface: there is no bell
/// in the window chrome and no inbox, so the only control was the Settings >
/// Alerts toggle. Removing just that toggle would strand anyone who had already
/// enabled watching — with the setting on and no way to turn it off — so the
/// delivery gate is narrowed too. Hiding both together is what keeps the UI and
/// the machinery from disagreeing.
bool get kCanNotify => kMobile;

/// macOS specifically — the window draws full-size content, so the traffic-light
/// controls overlay the top-left; the shell insets its top to clear them.
bool get kMacOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

/// Windows desktop. The runner builds and core features work, but a few
/// plugins have no Windows implementation (video_player, open_filex) — call
/// sites guard on this to fall back instead of throwing MissingPluginException.
bool get kWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

/// Height reserved for the macOS traffic lights when the sidebar has to clear
/// the native window chrome (narrow layout, drawer).
///
/// This is AppKit's own titlebar height: the lights are positioned natively and
/// are NOT moved by the app.
const double kMacTitlebar = 28.0;

/// The desktop layout (sidebar + panes) kicks in at/above this logical width.
const double kDesktopBreakpoint = 900;

/// Below this shell width the persistent sidebar collapses into a drawer (the
/// desktop shell stays native — it never falls back to the phone UI).
const double kShellCompact = 720;
