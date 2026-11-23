import 'app_icons.dart';
import 'dart:async';
import 'desktop_look.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
export 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';

import 'platform.dart';
import 'shell_panel.dart' show openSessionInTab;
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'gesture_physics.dart';
import 'api.dart';
import 'chat_links.dart';
import 'media_views.dart';
import 'theme.dart';
import 'components.dart';
import 'dialog_widgets.dart';
import 'markdown_widgets.dart';
import 'menu_widgets.dart';
import 'chat/chat_style.dart' show ChatBubble, ChatBubbleRow, chatMarkdownStyle;
import 'screens/artifact_viewer.dart' show openArtifact;
import 'screens/file_viewer.dart' show openFileForViewing, presentFileOnDesktop;
import 'screens/session.dart' show SessionScreen;
import 'panel.dart' show presentScreen;
import 'screens/mobile_chrome.dart';
import 'tap_detector.dart';

export 'components.dart';
export 'dialog_widgets.dart';
export 'markdown_widgets.dart';
export 'menu_widgets.dart';

class AppLoading extends StatelessWidget {
  const AppLoading({super.key, this.label = 'Loading'});
  final String label;

  @override
  Widget build(BuildContext context) => PageLoader(label: label);
}

/// Phone-only haptics: light for taps, selection for toggles and tabs,
/// medium for long-press menus. No-ops elsewhere.
void tapHaptic() {
  if (kMobile) HapticFeedback.lightImpact();
}

void pickHaptic() {
  if (kMobile) HapticFeedback.selectionClick();
}

void holdHaptic() {
  if (kMobile) HapticFeedback.mediumImpact();
}

/// [onSelect] null disables the whole row (e.g. a locked field).
class Pills<T> extends StatelessWidget {
  final List<(T, String)> items;
  final T selected;
  final ValueChanged<T>? onSelect;
  final String? Function(T)? iconFor;
  const Pills(
      {super.key,
      required this.items,
      required this.selected,
      this.onSelect,
      this.iconFor});

  Widget _label(T val, String label, TextStyle style) {
    final icon = iconFor?.call(val);
    final text = Text(label, style: style);
    if (icon == null) return text;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      AppIcon(icon, size: (style.fontSize ?? 13) + 1, color: style.color),
      SizedBox(width: S.s6),
      text,
    ]);
  }

  Widget _segmented() => Container(
        padding: EdgeInsets.all(S.s4),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(R.of(22)),
          boxShadow: [
            BoxShadow(
                color: AppColors.fg1.withValues(alpha: 0.08), spreadRadius: 1),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final (val, label) in items)
              TapDetector(
                onTap: onSelect == null
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        onSelect!(val);
                      },
                child: AnimatedContainer(
                  duration: Motion.quick,
                  padding: EdgeInsets.symmetric(
                      horizontal: S.of(13), vertical: S.s8),
                  decoration: BoxDecoration(
                    color: selected == val
                        ? AppColors.surface3
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(R.of(18)),
                  ),
                  child: _label(
                      val,
                      label,
                      sans(14,
                          color:
                              selected == val ? AppColors.fg1 : AppColors.fg3)),
                ),
              ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => kMobile
      ? _segmented()
      : Wrap(spacing: 7, runSpacing: 7, children: [
          for (final (val, label) in items)
            Pressable(
              enabled: onSelect != null,
              child: TapDetector(
                onTap: onSelect == null
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        onSelect!(val);
                      },
                child: Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: S.of(10), vertical: S.s4),
                  decoration: BoxDecoration(
                    // Selection is a NEUTRAL surface step, not the accent. The
                    // accent is reserved for STATE (running, needs-attention), so
                    // an accent-filled chip reads as an alert rather than "this is
                    // on" — and it collides with the same hue already meaning
                    // status elsewhere. Matches IconBtn.active and the nav rows.
                    color: selected == val
                        ? AppColors.surface3
                        : AppColors.surface2,
                    borderRadius: BorderRadius.circular(R.sm),
                    border: Border.all(
                        color: selected == val
                            ? AppColors.border2
                            : AppColors.border),
                  ),
                  child: _label(
                      val,
                      label,
                      sans(12,
                          weight: W.label,
                          color:
                              selected == val ? AppColors.fg1 : AppColors.fg2)),
                ),
              ),
            ),
        ]);
}

const _linkColor = Color(0xFF8AB4FF);

final _codedLink = RegExp(
    r'`(\[[^\]`]+\]\((?:session|artifact|agent|thread|task):[^)\s`]+\))`');
final _diffFenceOpenRe = RegExp(r'^([ \t]{0,3})(`{3,})(diff|patch)\s*$');
final _innerBacktickLineRe = RegExp(r'^[ +\-]?[ \t]*`{3,}');

String unwrapCodedLinks(String md) => _widenDiffFences(
    md.replaceAllMapped(_codedLink, (m) => m.group(1)!));

/// Unified diffs of Markdown files often contain unchanged context lines like
/// ` ``` ` (1 leading space + 3 backticks), which CommonMark treats as closing
/// an outer 3-backtick ```diff fence mid-diff. Widening the outer diff fence
/// to outrank any inner backtick run keeps the entire diff inside one block.
String _widenDiffFences(String text) {
  if (!text.contains('```diff') && !text.contains('```patch')) return text;
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final open = _diffFenceOpenRe.firstMatch(lines[i]);
    if (open == null) continue;
    final indent = open.group(1)!;
    final fence = open.group(2)!;
    final lang = open.group(3)!;
    int? closeIdx;
    var maxInnerTicks = fence.length;
    for (var j = i + 1; j < lines.length; j++) {
      final line = lines[j];
      final trimmed = line.trim();
      // A true closing fence has no diff prefix ('+', '-', or context space paired with diff lines)
      // and matches the outer fence at the end of the diff section, or before a blank line + heading/prose.
      if (RegExp('^\\s*`{${fence.length},}\\s*\$').hasMatch(line) &&
          !line.startsWith(' ') &&
          !line.startsWith('+') &&
          !line.startsWith('-')) {
        final nextNonEmpty = lines
            .skip(j + 1)
            .map((l) => l.trimRight())
            .firstWhere((l) => l.isNotEmpty, orElse: () => '');
        final looksLikeMoreDiff = nextNonEmpty.startsWith('@@ ') ||
            nextNonEmpty.startsWith('diff --git ') ||
            nextNonEmpty.startsWith('+') ||
            nextNonEmpty.startsWith('-');
        if (!looksLikeMoreDiff) {
          closeIdx = j;
          break;
        }
      }
      if (_innerBacktickLineRe.hasMatch(line) || trimmed.startsWith('```')) {
        for (final m in RegExp(r'`{3,}').allMatches(line)) {
          if (m.group(0)!.length >= maxInnerTicks) {
            maxInnerTicks = m.group(0)!.length + 1;
          }
        }
      }
    }
    if (closeIdx != null && maxInnerTicks > fence.length) {
      final wider = '`' * maxInnerTicks;
      lines[i] = '$indent$wider$lang';
      lines[closeIdx] = '$indent$wider';
      i = closeIdx;
    }
  }
  return lines.join('\n');
}

void openMarkdownLink(String? href, [BuildContext? context, String? text]) {
  if (href == null || href.isEmpty) return;
  if (parseChatLink(href) case final link?) {
    if (context == null) return;
    final client = DaemonScope.maybeOf(context) ?? DaemonScope.current;
    if (client == null) {
      toast(context, 'Connect to the machine to open this link.',
          danger: true);
      return;
    }
    openChatLink(context, client, link, text);
    return;
  }
  final uri = Uri.tryParse(href);
  if (uri == null) return;
  if (uri.scheme == 'artifact') {
    if (context != null) _openArtifactLink(context, uri);
    return;
  }
  if (uri.scheme == 'session') {
    if (context != null) _openSessionLink(context, uri, text);
    return;
  }
  if (uri.scheme.isEmpty || uri.scheme == 'file') {
    if (context != null) _openFileLink(context, uri);
    return;
  }
  launchUrl(uri, mode: LaunchMode.externalApplication);
}

void _openFileLink(BuildContext context, Uri uri) {
  final raw =
      uri.scheme == 'file' ? uri.toFilePath() : Uri.decodeComponent(uri.path);
  if (raw.isEmpty) return;
  final client = DaemonScope.maybeOf(context) ?? DaemonScope.current;
  if (client == null) {
    toast(context, 'Connect to the machine to open this file.', danger: true);
    return;
  }
  final scope = DaemonScope.scopeOf(context);
  final ws = scope?.workspace ?? '';
  final path = raw.startsWith('/') || ws.isEmpty
      ? raw
      : '${ws.endsWith('/') ? ws : '$ws/'}$raw';
  final name = raw.split('/').last;
  if (openFileForViewing(context, client: client, path: path, name: name)) {
    return;
  }
  final open = scope?.onOpenFile;
  if (open != null) {
    open(path, name);
  } else {
    presentFileOnDesktop(context, client: client, path: path, name: name);
  }
}

void _openSessionLink(BuildContext context, Uri uri, String? text) {
  final id = Uri.decodeComponent(uri.path).trim();
  final client = DaemonScope.maybeOf(context) ?? DaemonScope.current;
  if (client == null || id.isEmpty) {
    toast(context, 'Connect to the machine to open this session.',
        danger: true);
    return;
  }
  final title = (text ?? '').trim();
  final open =
      context.findAncestorWidgetOfExactType<SessionScreen>()?.onOpenSession;
  if (open != null) {
    open(id, title, null);
    return;
  }
  final tab = openSessionInTab;
  if (!kMobile && tab != null) {
    tab(client, id, title);
    return;
  }
  presentScreen(context,
      builder: (_, close) => SessionScreen(
          client: client, sessionId: id, title: title, onMenu: close));
}

void _openArtifactLink(BuildContext context, Uri uri) {
  final path = Uri.decodeComponent(uri.path);
  final cut = path.lastIndexOf('/');
  if (cut <= 0) return;
  final session = path.substring(0, cut);
  final tail = path.substring(cut + 1);
  final at = tail.lastIndexOf('@');
  final id = at > 0 ? tail.substring(0, at) : tail;
  final version = at > 0 ? int.tryParse(tail.substring(at + 1)) : null;
  final client = DaemonScope.maybeOf(context) ?? DaemonScope.current;
  if (client == null || id.isEmpty) {
    toast(context, 'Connect to the machine to open this artifact.',
        danger: true);
    return;
  }
  openArtifact(context,
      client: client, session: session, id: id, version: version);
}

/// Themed markdown stylesheet for agent messages.
/// Cached per-process to avoid rebuilding the full stylesheet on every Bubble
/// rebuild — the stylesheet is pure allocation and identical across the session
/// lifetime when the theme doesn't change.
MarkdownStyleSheet? _cachedMarkdownStyle;
int? _cachedMarkdownThemeIndex;

MarkdownStyleSheet markdownStyle(BuildContext context) {
  final themeIndex = ThemeManager.instance.index * 2 + (kMobile ? 1 : 0);
  if (_cachedMarkdownStyle != null && _cachedMarkdownThemeIndex == themeIndex) {
    return _cachedMarkdownStyle!;
  }
  _cachedMarkdownThemeIndex = themeIndex;
  _cachedMarkdownStyle =
      MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    p: TS.body(),
    pPadding: EdgeInsets.zero,
    strong: TS.body(AppColors.fg1).copyWith(fontWeight: weightFor(W.strong)),
    em: TS.body().copyWith(fontStyle: FontStyle.italic),
    a: TS.body(_linkColor).copyWith(
        decoration: TextDecoration.underline,
        decorationColor: _linkColor.withValues(alpha: 0.5)),
    h1: TS.sectionTitle(),
    h1Padding: EdgeInsets.only(top: S.s12, bottom: S.s4),
    h2: TS.rowTitle().copyWith(fontWeight: weightFor(W.strong)),
    h2Padding: EdgeInsets.only(top: S.s12, bottom: S.s4),
    h3: TS.rowTitle(),
    h3Padding: EdgeInsets.only(top: S.s8, bottom: S.s2),
    listIndent: 20,
    listBulletPadding: EdgeInsets.only(right: S.s6),
    code: TS.code(AppColors.fg1).copyWith(
        fontSize: kMobile ? 14 : 13, backgroundColor: AppColors.hover),
    codeblockPadding: EdgeInsets.zero,
    codeblockDecoration: const BoxDecoration(),
    blockquote: TS.body(AppColors.fg3),
    blockquotePadding: EdgeInsets.fromLTRB(S.s12, S.s2, 0, S.s2),
    blockquoteDecoration: BoxDecoration(
      border: Border(left: BorderSide(color: AppColors.lineStrong, width: 2)),
    ),
    listBullet: TS.body(AppColors.fg3),
    tableBody: TS.ui(),
    tableHead: TS.ui(AppColors.fg1).copyWith(fontWeight: weightFor(W.label)),
    // FlexColumnWidth stretches every markdown table to the full message width.
    // Intrinsic columns keep phone tables content-sized; the markdown package
    // supplies horizontal scrolling when a long URL or code value needs it.
    tableColumnWidth:
        kMobile ? const IntrinsicColumnWidth() : const FlexColumnWidth(),
    horizontalRuleDecoration:
        BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
  );
  return _cachedMarkdownStyle!;
}

/// The agent's replies: [markdownStyle] with the reading serif for prose on a
/// phone. Headings, code and tables keep the interface faces.
MarkdownStyleSheet? _cachedAgentMarkdownStyle;
int? _cachedAgentMarkdownThemeIndex;

MarkdownStyleSheet agentMarkdownStyle(BuildContext context) {
  final base = markdownStyle(context);
  final themeIndex = ThemeManager.instance.index;
  if (_cachedAgentMarkdownStyle != null &&
      _cachedAgentMarkdownThemeIndex == themeIndex) {
    return _cachedAgentMarkdownStyle!;
  }
  _cachedAgentMarkdownThemeIndex = themeIndex;
  final reading = TS.reading();
  // Desktop transcript: 13 on a 1.5 line, per the reference session.
  final prose = kMobile
      ? reading
      : reading.copyWith(fontSize: reading.fontSize! * 13 / 14, height: 1.5);
  _cachedAgentMarkdownStyle = base.copyWith(
    p: prose,
    strong: prose.copyWith(fontWeight: weightFor(W.strong)),
    em: prose.copyWith(fontStyle: FontStyle.italic),
    a: prose.copyWith(
        color: _linkColor,
        decoration: TextDecoration.underline,
        decorationColor: _linkColor.withValues(alpha: 0.5)),
    listBullet: prose.copyWith(color: AppColors.fg3),
    blockquote:
        prose.copyWith(color: AppColors.fg3, fontStyle: FontStyle.italic),
    code: kMobile
        ? TS
            .code(Color.lerp(AppColors.fg1, AppColors.run, 0.3))
            .copyWith(fontSize: 13, backgroundColor: AppColors.surface2)
        : TS
            .code(AppColors.fg1)
            .copyWith(fontSize: 13, backgroundColor: AppColors.surface1),
  );
  return _cachedAgentMarkdownStyle!;
}

/// The reading styles with a document heading scale, for whole markdown files.
MarkdownStyleSheet documentMarkdownStyle(BuildContext context) =>
    agentMarkdownStyle(context).copyWith(
      h1: sans(26, height: 32 / 26, spacing: -0.5, color: AppColors.fg1),
      h1Padding: EdgeInsets.only(top: S.s4, bottom: S.s6),
      h2: sans(20, height: 26 / 20, spacing: -0.3, color: AppColors.fg1),
      h2Padding: EdgeInsets.only(top: S.of(18), bottom: S.s4),
      h3: sans(17, height: 23 / 17, color: AppColors.fg1),
      h3Padding: EdgeInsets.only(top: S.of(14), bottom: S.s2),
      h4: sans(15, height: 20 / 15, color: AppColors.fg2),
    );

/// Dimmed markdown for live model thinking/reasoning — same structure as
/// [markdownStyle], quieter palette so it reads as an aside, not the answer.
MarkdownStyleSheet? _cachedThinkingMarkdownStyle;
int? _cachedThinkingMarkdownThemeIndex;

MarkdownStyleSheet thinkingMarkdownStyle(BuildContext context) {
  final themeIndex = ThemeManager.instance.index;
  if (_cachedThinkingMarkdownStyle != null &&
      _cachedThinkingMarkdownThemeIndex == themeIndex) {
    return _cachedThinkingMarkdownStyle!;
  }
  _cachedThinkingMarkdownThemeIndex = themeIndex;
  final dim = AppColors.fg3;
  final dim2 = AppColors.fg4;
  _cachedThinkingMarkdownStyle =
      MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    p: sans(13, height: 1.45, color: dim),
    pPadding: EdgeInsets.zero,
    em: sans(13, height: 1.45, color: dim)
        .copyWith(fontStyle: FontStyle.italic),
    strong: sans(13, height: 1.45, color: dim, weight: W.label),
    a: sans(13, height: 1.45, color: _linkColor).copyWith(
        decoration: TextDecoration.underline,
        decorationColor: _linkColor.withValues(alpha: 0.5)),
    h1: sans(kMobile ? 16 : 14, weight: W.label, height: 1.3, color: dim),
    h1Padding: EdgeInsets.only(top: S.s4, bottom: S.s2),
    h2: sans(kMobile ? 14 : 13, weight: W.label, height: 1.3, color: dim),
    h2Padding: EdgeInsets.only(top: S.s4, bottom: S.s2),
    h3: sans(kMobile ? 14 : 13, weight: W.label, height: 1.3, color: dim),
    h3Padding: EdgeInsets.only(top: S.s2, bottom: S.of(1)),
    code: mono(12, color: dim2),
    codeblockPadding: EdgeInsets.zero,
    codeblockDecoration: const BoxDecoration(),
    blockquote: sans(13, height: 1.45, color: dim2),
    blockquoteDecoration: BoxDecoration(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(R.xs),
      border: Border(left: BorderSide(color: AppColors.border, width: 2)),
    ),
    listBullet: sans(13, height: 1.45, color: dim),
    tableBody: sans(12, color: dim),
    tableColumnWidth:
        kMobile ? const IntrinsicColumnWidth() : const FlexColumnWidth(),
    horizontalRuleDecoration:
        BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
  );
  return _cachedThinkingMarkdownStyle!;
}

/// Live thinking/reasoning stream — full markdown, dimmed.

/// Phosphor glyphs use 224 of their 256 grid, so a small lift keeps the ink
/// level with the text beside it at 16 to 24 pt.
const double _iconOptical = 1.08;

/// One icon set (Phosphor) drawn from the bundled Phosphor fonts, in an explicit
/// square so glyphs never push their neighbours around.
class AppIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;

  /// Optical size correction for a glyph that over- or under-fills its box.
  final double visualScale;

  /// Fill weight for selected or active states.
  final bool filled;
  const AppIcon(this.name,
      {super.key,
      this.size = 18,
      this.color,
      this.visualScale = 1.0,
      this.filled = false});

  @override
  Widget build(BuildContext context) {
    if (name.startsWith('provider:')) {
      return ProviderLogo(name.substring(9), size: size * visualScale);
    }
    return SizedBox.square(
      dimension: size,
      child: Center(
        child: Icon(
            (filled ? appIconsFilled[name] : null) ??
                appIcons[name] ??
                appIcons['circle']!,
            size: size * visualScale * _iconOptical,
            color: color ?? AppColors.fg2),
      ),
    );
  }
}

/// Glowing status dot.
class StatusDot extends StatefulWidget {
  final String status; // online | running | offline | checking
  final double size;
  final Color? color;
  const StatusDot(
      {super.key, this.status = 'online', this.size = 9, this.color});
  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
  /// Assigned in initState, NOT as a lazy `late final` initialiser.
  ///
  /// A lazy initialiser is evaluated on FIRST ACCESS, and for a static status
  /// ('online'/'offline') `build` never reads it — so `dispose` became the first
  /// access and constructed an AnimationController on an element that was
  /// already unmounting, throwing "the widget's element tree is no longer
  /// stable". Creating it eagerly removes the ordering dependency entirely.
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
  }

  /// Reduced motion stops the breath but keeps the lit dot: the state is still
  /// readable from colour alone, so nothing is lost by holding it steady.
  bool get _pulses => widget.status == 'checking' || widget.status == 'running';

  void _sync() {
    if (!_pulses || reduceMotion(context)) {
      if (_c.isAnimating) _c.stop();
      _c.value = 1;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Color get _color =>
      widget.color ??
      switch (widget.status) {
        'online' => AppColors.ok,
        'running' => AppColors.run,
        'offline' => AppColors.danger,
        _ => AppColors.fg3,
      };

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final c = _color;
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        boxShadow: widget.status == 'offline'
            ? null
            : [
                BoxShadow(
                    color: c.withValues(alpha: 0.6),
                    blurRadius: 8,
                    spreadRadius: 1)
              ],
      ),
    );
    if (_pulses) {
      return RepaintBoundary(
        child: FadeTransition(
            opacity: Tween(begin: 0.45, end: 1.0).animate(_c), child: dot),
      );
    }
    return dot;
  }
}

/// Surface-1 card with a hairline border.
class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  const AppCard({super.key, required this.child, this.onTap, this.padding});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Pressable(
      enabled: onTap != null,
      kind: PressKind.card,
      radius: R.card,
      child: Material(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.card),
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  tapHaptic();
                  onTap!();
                },
          borderRadius: BorderRadius.circular(R.card),
          child: Padding(
              padding: padding ?? EdgeInsets.all(S.of(14)), child: child),
        ),
      ),
    );
  }
}

enum BtnVariant {
  primary,
  secondary,

  /// A surface STEP, no border.
  ///
  /// The design language has no borders and reserves the accent hue for state,
  /// so neither [primary] (accent fill) nor [secondary] (hairline) is right for
  /// a plain action. This is the doc's chip/active ladder doing the work.
  surface,
  outline,
  ghost,
  danger,
}

class Btn extends StatelessWidget {
  final String label;
  final BtnVariant variant;
  final bool small;
  final bool full;
  final bool disabled;
  final String? icon;
  final String? iconRight;
  final VoidCallback? onTap;
  const Btn(this.label,
      {super.key,
      this.variant = BtnVariant.primary,
      this.small = false,
      this.full = false,
      this.disabled = false,
      this.icon,
      this.iconRight,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final (Color bg, Color fg, Color? bd) = switch (variant) {
      BtnVariant.primary => (AppColors.accentFill, AppColors.accentFg, null),
      BtnVariant.secondary => (
          AppColors.surface2,
          AppColors.fg1,
          AppColors.border
        ),
      // Ladder, not a line: the fill is the separation.
      BtnVariant.surface => (AppColors.surface3, AppColors.fg2, null),
      BtnVariant.outline => (
          Colors.transparent,
          AppColors.fg1,
          AppColors.border
        ),
      BtnVariant.ghost => (Colors.transparent, AppColors.fg2, null),
      BtnVariant.danger => (
          AppColors.dangerBg,
          AppColors.danger,
          AppColors.danger.withValues(alpha: 0.3)
        ),
    };
    // Compact on desktop (mouse), roomy touch targets on mobile.
    // 44 on mobile for BOTH variants. `small` was 34 — under Apple's 44pt and
    // Material's 48dp floors — and it is the primary action of the agent thread
    // composer and every dialog footer. Desktop keeps the compact 28/34 so a
    // mouse-sized toolbar does not grow.
    final h = small ? (kMobile ? 36.0 : 28.0) : (kMobile ? 46.0 : 28.0);
    final radius = kMobile ? R.pill : (small ? R.sm : R.md);
    final child = Row(
      mainAxisSize: full ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          AppIcon(icon!, size: small ? 15 : 17, color: fg),
          SizedBox(width: S.s8)
        ],
        Text(label,
            style: kMobile
                ? sans(small ? 13 : 15, weight: W.strong, color: fg)
                : sans(small ? 12 : 13, weight: W.label, color: fg)),
        if (iconRight != null) ...[
          SizedBox(width: S.s8),
          AppIcon(iconRight!, size: small ? 15 : 17, color: fg)
        ],
      ],
    );
    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: Pressable(
        enabled: !disabled && onTap != null,
        child: Tactile(
          radius: BorderRadius.circular(radius),
          enabled:
              variant == BtnVariant.primary || variant == BtnVariant.secondary,
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(radius),
            child: InkWell(
              onTap: disabled || onTap == null
                  ? null
                  : () {
                      tapHaptic();
                      onTap!();
                    },
              borderRadius: BorderRadius.circular(radius),
              child: Container(
                height: h,
                width: full ? double.infinity : null,
                padding:
                    EdgeInsets.symmetric(horizontal: small ? S.s12 : S.s16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: bd != null &&
                          !(kMobile && variant == BtnVariant.secondary)
                      ? Border.all(color: bd)
                      : null,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Accent pill action (Claude-style primary affordance).
class PillBtn extends StatelessWidget {
  final String label;
  final String? icon;
  final VoidCallback? onTap;
  const PillBtn(this.label, {super.key, this.icon, this.onTap});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Pressable(
        enabled: onTap != null,
        child: Material(
          color: AppColors.accentFill,
          borderRadius: BorderRadius.circular(kMobile ? R.pill : R.md),
          child: InkWell(
            onTap: onTap == null
                ? null
                : () {
                    tapHaptic();
                    onTap!();
                  },
            borderRadius: BorderRadius.circular(kMobile ? R.pill : R.md),
            child: Container(
              height: kMobile ? 48 : 28,
              padding:
                  EdgeInsets.symmetric(horizontal: kMobile ? S.s20 : S.s12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[
                  AppIcon(icon!,
                      size: kMobile ? 18 : 16, color: AppColors.accentFg),
                  SizedBox(width: S.s8),
                ],
                Text(label,
                    style: sans(kMobile ? 14 : 13,
                        weight: W.label, color: AppColors.accentFg)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// How a surface answers a press: buttons shrink most, cards a little with a
/// surface lift, rows only tint (a scaling full-width row looks wrong).
enum PressKind { button, card, row }

/// Tactile press feedback shared by buttons, cards, tiles and rows.
///
/// A `Listener` observes the pointer without joining the gesture arena, so the
/// child's own tap, ripple and long-press are untouched. Press-in is a fast
/// ease-out; release springs back with a hint of overshoot. Dragging past touch
/// slop (a scroll) releases it. Reduced motion drops the scale, keeps the tint.
class Pressable extends StatefulWidget {
  final Widget child;

  /// Off for inert controls, and for a surface where motion would distract.
  final bool enabled;
  final PressKind kind;

  /// Pressed scale; defaults by [kind] and platform.
  final double? scale;

  /// Corner radius of the press tint. Cards and rows tint, buttons do not.
  final double radius;

  /// Fires a selection click on press-in (phone only).
  final bool haptic;

  /// Hold time before the press shows; for long-press targets, so a tap or
  /// the start of a scroll never flinches.
  final Duration delay;

  /// Long-press targets: a still hold lifts the surface before the menu opens.
  final bool lift;

  const Pressable({
    super.key,
    required this.child,
    this.enabled = true,
    this.kind = PressKind.button,
    this.scale,
    this.radius = 0,
    this.haptic = false,
    this.delay = Duration.zero,
    this.lift = false,
  });

  static const _pressIn = Duration(milliseconds: 90);
  static const _pressOut = Duration(milliseconds: 220);
  static const _down = SpringDescription(mass: 1, stiffness: 1100, damping: 66);
  static const _spring =
      SpringDescription(mass: 1, stiffness: 600, damping: 40);
  static const _liftSpring =
      SpringDescription(mass: 1, stiffness: 520, damping: 36);
  static const _liftDelay = Duration(milliseconds: 420);
  static const liftScale = 1.03;

  static double scaleFor(PressKind kind) => switch (kind) {
        PressKind.button => 0.98,
        PressKind.card => 0.98,
        // Desktop rows only tint; a pointer click should not shrink a list.
        PressKind.row => kMobile ? 0.98 : 1.0,
      };

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> with TickerProviderStateMixin {
  late final AnimationController _scale;
  late final AnimationController _tint;
  Offset? _origin;
  Timer? _hold;
  Timer? _liftTimer;
  bool _down = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _scale = AnimationController(
        vsync: this, value: 1, lowerBound: 0.5, upperBound: 1.5);
    _tint = AnimationController(
        vsync: this,
        duration: Pressable._pressIn,
        reverseDuration: Pressable._pressOut,
        upperBound: 2);
  }

  // Phone rows keep the press scale but no square tint (radius 0 showed a rectangle).
  bool get _tints =>
      widget.kind != PressKind.button &&
      !(kMobile && widget.kind == PressKind.row);

  void _press(PointerDownEvent e) {
    if (_disposed || !mounted || !widget.enabled || _down) return;
    _down = true;
    _origin = e.position;
    if (widget.delay == Duration.zero) {
      _show();
    } else {
      _hold = Timer(widget.delay, () {
        if (!_disposed && mounted && _down) _show();
      });
    }
    if (widget.lift && kMobile) {
      _liftTimer = Timer(Pressable._liftDelay, () {
        if (!_disposed && mounted && _down) _lift();
      });
    }
  }

  void _lift() {
    if (_disposed || !mounted) return;
    if (!reduceMotion(context)) {
      springTo(_scale, Pressable.liftScale, _scale.velocity,
          spring: Pressable._liftSpring, epsilon: 0.001);
    }
    if (_tints) _tint.animateTo(2, duration: Pressable._pressIn);
  }

  void _show() {
    if (_disposed || !mounted) return;
    if (widget.haptic && kMobile) HapticFeedback.selectionClick();
    final to = widget.scale ?? Pressable.scaleFor(widget.kind);
    if (!reduceMotion(context) && to < 1) {
      springTo(_scale, to, 0, spring: Pressable._down, epsilon: 0.001);
    }
    if (_tints) _tint.animateTo(1, duration: Pressable._pressIn);
  }

  void _release() {
    _hold?.cancel();
    _liftTimer?.cancel();
    if (!_down) return;
    _down = false;
    _origin = null;
    if (_disposed || !mounted) return;
    if (_scale.value != 1) {
      final v = _scale.velocity;
      springTo(_scale, 1, v, spring: Pressable._spring, epsilon: 0.001);
    }
    if (_tints) _tint.animateBack(0, duration: Pressable._pressOut);
  }

  void _move(PointerMoveEvent e) {
    if (_disposed || !mounted) return;
    final o = _origin;
    if (_down && o != null && (e.position - o).distance > kTouchSlop) {
      _release();
    }
  }

  @override
  void didUpdateWidget(Pressable old) {
    super.didUpdateWidget(old);
    if (!widget.enabled) _release();
  }

  @override
  void dispose() {
    _disposed = true;
    _down = false;
    _origin = null;
    _hold?.cancel();
    _liftTimer?.cancel();
    _scale.dispose();
    _tint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget out = widget.child;
    if (_tints) {
      out = Stack(fit: StackFit.passthrough, children: [
        out,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _tint,
              builder: (_, __) => DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.fg1.withValues(alpha: 0.05 * _tint.value),
                  borderRadius: BorderRadius.circular(widget.radius),
                ),
              ),
            ),
          ),
        ),
      ]);
    }
    return Listener(
      onPointerDown: _press,
      onPointerMove: _move,
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: AnimatedBuilder(
        animation: _scale,
        child: out,
        // Always wrapped: adding the Transform on press remounted the child
        // and dropped the tap in flight.
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
      ),
    );
  }
}

/// Opens [child] downward on a spring with the top edge fixed. Content stays
/// hidden for the first quarter of the growth, then fades in; on collapse it
/// fades by the square of the height so it is gone before the box closes.
class SpringExpand extends StatefulWidget {
  const SpringExpand({super.key, required this.open, required this.child});

  final bool open;
  final Widget child;

  static const spring = SpringDescription(mass: 1, stiffness: 320, damping: 34);

  @override
  State<SpringExpand> createState() => _SpringExpandState();
}

class _SpringExpandState extends State<SpringExpand>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController.unbounded(vsync: this, value: widget.open ? 1 : 0);

  @override
  void didUpdateWidget(SpringExpand old) {
    super.didUpdateWidget(old);
    if (old.open == widget.open) return;
    final to = widget.open ? 1.0 : 0.0;
    if (reduceMotion(context)) {
      _c.value = to;
    } else {
      springTo(_c, to, _c.velocity,
          spring: SpringExpand.spring, epsilon: 0.001);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          final h = _c.value.clamp(0.0, 1.0);
          if (h == 0 && !widget.open) {
            return const SizedBox(width: double.infinity);
          }
          final fade =
              widget.open ? ((h - 0.25) / 0.75).clamp(0.0, 1.0) : h * h;
          return ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: h,
              child: Opacity(
                opacity: fade,
                child: Transform.translate(
                  offset: Offset(0, widget.open ? -4 * (1 - fade) : 0),
                  child: child,
                ),
              ),
            ),
          );
        },
      );
}

/// Grows and shrinks [child] with its content visible while the size eases.
/// The child leaves the tree once the collapse has finished.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.show, required this.child});

  final bool show;
  final Widget child;

  @override
  State<Reveal> createState() => _RevealState();
}

const _revealSize = Duration(milliseconds: 340);

class _RevealState extends State<Reveal> {
  late bool _mounted = widget.show;
  Timer? _unmount;

  @override
  void didUpdateWidget(Reveal old) {
    super.didUpdateWidget(old);
    if (widget.show == old.show) return;
    _unmount?.cancel();
    if (widget.show) {
      _mounted = true;
    } else {
      _unmount = Timer(_revealSize + const Duration(milliseconds: 40), () {
        if (mounted && !widget.show) setState(() => _mounted = false);
      });
    }
  }

  @override
  void dispose() {
    _unmount?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dur = reduceMotion(context) ? Duration.zero : _revealSize;
    return AnimatedSize(
      duration: dur,
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: widget.show ? 1 : 0,
        child: !_mounted
            ? const SizedBox(width: double.infinity)
            : IgnorePointer(
                ignoring: !widget.show,
                child: AnimatedOpacity(
                  opacity: widget.show ? 1 : 0,
                  duration: dur == Duration.zero ? dur : Motion.base,
                  curve: Curves.easeOut,
                  child: widget.child,
                ),
              ),
      ),
    );
  }
}

/// A tappable row or tile whose fill eases between rest, hover and selected,
/// so pointer movement over a list reads as one smooth sweep.
class HoverSurface extends StatefulWidget {
  const HoverSurface({
    super.key,
    required this.child,
    this.onTap,
    this.onSecondaryTapDown,
    this.onLongPress,
    this.radius = 8,
    this.selected = false,
    this.rest,
    this.selectedColor,
    this.hoverColor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final VoidCallback? onLongPress;
  final double radius;
  final bool selected;
  final Color? rest;
  final Color? selectedColor;
  final Color? hoverColor;

  @override
  State<HoverSurface> createState() => _HoverSurfaceState();
}

class _HoverSurfaceState extends State<HoverSurface> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final rest = widget.rest ?? Colors.transparent;
    final color = widget.selected
        ? (widget.selectedColor ?? AppColors.surface2)
        : _hover && widget.onTap != null
            ? (widget.hoverColor ?? AppColors.surface1)
            : rest;
    final r = BorderRadius.circular(widget.radius);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Pressable(
        kind: PressKind.row,
        radius: widget.radius,
        lift: widget.onLongPress != null,
        enabled: widget.onTap != null || widget.onLongPress != null,
        child: Tactile(
          radius: r,
          enabled: widget.selected,
          child: AnimatedContainer(
            duration: reduceMotion(context) ? Duration.zero : Motion.quick,
            curve: Curves.easeOut,
            decoration: BoxDecoration(color: color, borderRadius: r),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: r,
                hoverColor: Colors.transparent,
                onTap: widget.onTap == null
                    ? null
                    : () {
                        tapHaptic();
                        widget.onTap!();
                      },
                onLongPress: widget.onLongPress == null
                    ? null
                    : () {
                        holdHaptic();
                        widget.onLongPress!();
                      },
                onSecondaryTapDown: widget.onSecondaryTapDown,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class IconBtn extends StatelessWidget {
  final String name;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final bool active;
  final String? tooltip;
  const IconBtn(this.name,
      {super.key,
      this.onTap,
      this.size = 38,
      this.iconSize = 19,
      this.active = false,
      this.tooltip});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    if (ShellPanelRoot.hides(context, name, tooltip)) {
      return const SizedBox.shrink();
    }
    // A touch target may not be smaller than a fingertip just because the ink
    // is small: on a phone the layout box grows to [M.minTarget] while the glyph
    // keeps its size, so a 22px clear button is still comfortably tappable. On
    // desktop the pointer is precise, so `size` is taken at its word.
    final box = kMobile
        ? (onTap != null && size < M.minTarget ? M.minTarget : size)
        : (size > 28 ? 28.0 : size);
    if (!kMobile) {
      final btn = _DesktopIconBtn(
        name: name,
        onTap: onTap,
        box: box,
        ink: box < iconSize + 10 ? box : (iconSize + 10).clamp(24.0, 30.0),
        iconSize: iconSize,
        active: active,
      );
      return tooltip != null ? Tooltip(message: tooltip!, child: btn) : btn;
    }
    final btn = Pressable(
      enabled: onTap != null,
      child: Material(
        // Selection is surface-only, matching the sidebar/rail selection
        // language. The accent is reserved for state, not for "this is on".
        color: active ? AppColors.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  tapHaptic();
                  onTap!();
                },
          borderRadius: BorderRadius.circular(R.md),
          child: SizedBox(
            width: box,
            height: box,
            child: Center(
              child: AppIcon(name,
                  size: iconSize,
                  color: active ? AppColors.fg1 : AppColors.fg2),
            ),
          ),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: btn) : btn;
  }
}

class _DesktopIconBtn extends StatefulWidget {
  const _DesktopIconBtn({
    required this.name,
    required this.onTap,
    required this.box,
    required this.ink,
    required this.iconSize,
    required this.active,
  });
  final String name;
  final VoidCallback? onTap;
  final double box;
  final double ink;
  final double iconSize;
  final bool active;

  @override
  State<_DesktopIconBtn> createState() => _DesktopIconBtnState();
}

class _DesktopIconBtnState extends State<_DesktopIconBtn> {
  bool _hover = false;
  bool _focus = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final fill = _down
        ? AppColors.surface3
        : widget.active || ((_hover || _focus) && enabled)
            ? AppColors.surface2
            : Colors.transparent;
    final lit = widget.active || (_hover && enabled);
    return FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => widget.onTap?.call()),
      },
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) => setState(() => _focus = v),
      child: Semantics(
        button: true,
        enabled: enabled,
        child: Pressable(
          enabled: enabled,
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onTapDown: enabled ? (_) => setState(() => _down = true) : null,
            onTapUp: enabled ? (_) => setState(() => _down = false) : null,
            onTapCancel: enabled ? () => setState(() => _down = false) : null,
            child: SizedBox(
              width: widget.box,
              height: widget.box,
              child: Center(
                child: AnimatedContainer(
                  duration: Motion.quick,
                  width: widget.ink,
                  height: widget.ink,
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(R.sm),
                  ),
                  child: Center(
                    child: AppIcon(widget.name,
                        size: widget.iconSize,
                        color: lit ? AppColors.fg1 : AppColors.fg2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Internal attachment and transcription markers are agent-facing metadata, not
/// user-facing chat text.
final RegExp _attachMarkerRe =
    RegExp(r'\[attached (image|file) —([^\]]*)\]', multiLine: true);
final RegExp _audioTranscriptHeaderRe = RegExp(
  r'\[Audio transcript for ([^\]\r\n]+)\]\r?\n',
  multiLine: true,
);
final RegExp _audioUnavailableRe = RegExp(
  r'\[Audio transcription unavailable: ([^\]\r\n]*)\]',
  multiLine: true,
);

class AudioTranscriptItem {
  final String text;
  final bool unavailable;
  const AudioTranscriptItem(this.text, {this.unavailable = false});
}

/// Extract the daemon's audio transcript block(s) without exposing its internal
/// attachment path. A message may contain more than one audio attachment.
List<AudioTranscriptItem> audioTranscriptItems(String raw) {
  final headers = _audioTranscriptHeaderRe.allMatches(raw).toList();
  final items = <AudioTranscriptItem>[];
  for (var i = 0; i < headers.length; i++) {
    final start = headers[i].end;
    final end = i + 1 < headers.length ? headers[i + 1].start : raw.length;
    final text = raw.substring(start, end).trim();
    if (text.isNotEmpty) items.add(AudioTranscriptItem(text));
  }
  for (final match in _audioUnavailableRe.allMatches(raw)) {
    final error = match.group(1)?.trim() ?? 'unknown error';
    items.add(AudioTranscriptItem(error, unavailable: true));
  }
  return items;
}

bool isAudioAttachmentPath(String value) {
  final path = value.trim().toLowerCase();
  return const [
    '.aac',
    '.flac',
    '.m4a',
    '.mp3',
    '.oga',
    '.ogg',
    '.opus',
    '.wav',
    '.webm',
  ].any(path.endsWith);
}

/// Remove internal attachment/transcription metadata from the message body while
/// leaving the audio transcript available to the dedicated transcript card.
String hideAttachmentMarkers(String raw) {
  var shown = splitPastedBlocks(raw).$2;
  final headers = _audioTranscriptHeaderRe.allMatches(shown).toList();
  for (var i = headers.length - 1; i >= 0; i--) {
    final start = headers[i].start;
    final end = i + 1 < headers.length ? headers[i + 1].start : shown.length;
    shown = shown.replaceRange(start, end, '');
  }
  return shown
      .replaceAll(_audioUnavailableRe, '')
      .replaceAll(_attachMarkerRe, '')
      .trim();
}

/// Read-only attachment summary on a sent message — icon + count, no emoji.
/// Images and files each get their own compact pill (matches desktop).
class AttachmentPill extends StatelessWidget {
  final int audio, images, files;
  const AttachmentPill({
    super.key,
    required this.audio,
    required this.images,
    required this.files,
  });
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    Widget pill(String icon, String label, {bool isAudio = false}) => Container(
          padding: EdgeInsets.symmetric(horizontal: S.s8, vertical: S.of(3)),
          decoration: BoxDecoration(
            color: isAudio ? AppColors.accentBg : AppColors.surface2,
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(
                color: isAudio ? AppColors.accentLine : AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon(icon,
                size: 11, color: isAudio ? AppColors.accent : AppColors.fg3),
            SizedBox(width: S.s4),
            Text(label,
                style: sans(11,
                    color: isAudio ? AppColors.accent : AppColors.fg2)),
          ]),
        );
    final pills = <Widget>[];
    if (audio > 0) {
      pills.add(
          pill('mic', audio == 1 ? 'audio' : '$audio audio', isAudio: true));
    }
    if (images > 0) {
      pills.add(pill('image', images == 1 ? 'image' : '$images images'));
    }
    if (files > 0) {
      pills.add(pill('file', files == 1 ? 'file' : '$files files'));
    }
    if (pills.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 6, children: pills);
  }
}

/// A compact, readable transcript attached to the audio pill. It is collapsed by
/// default so the conversation stays compact, but can be expanded without hiding
/// the original audio attachment.
class AudioTranscriptCard extends StatefulWidget {
  final List<AudioTranscriptItem> items;
  const AudioTranscriptCard({super.key, required this.items});

  @override
  State<AudioTranscriptCard> createState() => _AudioTranscriptCardState();
}

class _AudioTranscriptCardState extends State<AudioTranscriptCard> {
  bool _expanded = false;

  String _lineFor(AudioTranscriptItem item) => item.unavailable
      ? 'Could not transcribe this audio: ${item.text}'
      : item.text;

  String get _preview {
    final first = widget.items.isEmpty ? '' : _lineFor(widget.items.first);
    return first.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool get _canExpand {
    if (widget.items.length > 1) return true;
    if (widget.items.isEmpty) return false;
    return _lineFor(widget.items.first).contains('\n') || _preview.length > 110;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: S.s4),
      child: InkWell(
        onTap: _canExpand ? () => setState(() => _expanded = !_expanded) : null,
        borderRadius: BorderRadius.circular(R.sm),
        child: AnimatedSize(
          duration: Motion.base,
          curve: Motion.enter,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_expanded)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text(
                      _preview.isEmpty ? 'Transcript' : _preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: kMobile
                          ? sans(13, height: 18 / 12.5, color: AppColors.fg2)
                          : sans(12, height: 1.4, color: AppColors.fg2),
                    ),
                  ),
                  if (_canExpand) ...[
                    SizedBox(width: S.s8),
                    AppIcon('chevron-down', size: 13, color: AppColors.fg4),
                  ],
                ])
              else ...[
                for (var i = 0; i < widget.items.length; i++) ...[
                  if (i > 0) SizedBox(height: S.s6),
                  Text(
                    _lineFor(widget.items[i]),
                    style: sans(kMobile ? 13 : 12,
                        height: kMobile ? 19 / 13 : 1.4,
                        color: widget.items[i].unavailable
                            ? AppColors.fg3
                            : AppColors.fg2),
                  ),
                ],
                SizedBox(height: S.s4),
                Row(children: [
                  const Spacer(),
                  AppIcon('chevron-up', size: 13, color: AppColors.fg4),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One chat message — flat (no bubble/box). YOUR messages get a left accent bar
/// + label; the agent's are plain full-width markdown under a dim label. The bar
/// vs no-bar is the primary you/agent distinction.
/// A reply's long-press sheet on phones: copy it whole, or open it to select.
void _messageActions(BuildContext context, String text) {
  final preview = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  showAppSheet(context,
      title: 'Message',
      subtitle:
          preview.length > 60 ? '${preview.substring(0, 60)}\u2026' : preview,
      child: SheetActions([
        SheetAction('clipboard', 'Copy', () {
          Navigator.pop(context);
          Clipboard.setData(ClipboardData(text: text));
          toast(context, 'Copied');
        }, detail: 'Copy the whole message'),
        SheetAction('edit', 'Select text', () {
          Navigator.pop(context);
          showAppSheet(context,
              title: 'Select text',
              maxWidth: 620,
              maxHeight: 640,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: S.s4),
                child: SelectionArea(
                  child: MarkdownBody(
                    data: unwrapCodedLinks(text),
                    styleSheet: markdownStyle(context),
                    builders: {'pre': PreBlockBuilder()},
                  ),
                ),
              ));
        }, detail: 'Open it to select part of the text'),
      ]));
}

/// Draws a transcript's replies and sent messages as chat bubbles, the way
/// agent chat does (Lead).
class ChatBubbleScope extends InheritedWidget {
  const ChatBubbleScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatBubbleScope>() != null;

  @override
  bool updateShouldNotify(ChatBubbleScope oldWidget) => false;
}

class Bubble extends StatelessWidget {
  final bool mine;
  final String text;

  /// Live bubbles are intentionally not selectable while their text is changing.
  /// Set this to false for streaming/optimistic content; durable transcript
  /// bubbles use the default per-message selection container.
  final bool selectable;

  /// Override the built-in mobile/desktop long-press copy affordance when a
  /// caller supplies its own message action bar.
  final VoidCallback? onLongPress;

  /// When given, a sent message's attachments render as real media (image
  /// thumbnails, file cards, playable voice notes) instead of count pills.
  final DaemonClient? client;
  const Bubble({
    super.key,
    required this.mine,
    required this.text,
    this.selectable = true,
    this.onLongPress,
    this.client,
  });
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final (pasted, body) = splitPastedBlocks(text);
    final matches = _attachMarkerRe.allMatches(body).toList();
    final transcripts = audioTranscriptItems(body);
    final shown = hideAttachmentMarkers(body);
    final pastedCards = [
      for (final block in pasted)
        Padding(
          padding: EdgeInsets.only(top: S.s6),
          child: PastedTextCard(text: block),
        ),
    ];
    final audio =
        matches.where((m) => isAudioAttachmentPath(m.group(2) ?? '')).length;
    final images = matches.where((m) => m.group(1) == 'image').length;
    final files = matches.length - images - audio;
    final textBody = shown.isNotEmpty
        ? MarkdownBody(
            data: unwrapCodedLinks(shown),
            selectable: false,
            styleSheet: markdownStyle(context),
            builders: {'pre': PreBlockBuilder()},
            onTapLink: (txt, href, title) =>
                openMarkdownLink(href, context, txt),
          )
        : null;
    final voice = <Widget>[
      if (audio > 0) AttachmentPill(audio: audio, images: 0, files: 0),
      if (transcripts.isNotEmpty) AudioTranscriptCard(items: transcripts),
      if (audio > 0 && transcripts.isEmpty)
        Row(mainAxisSize: MainAxisSize.min, children: [
          AppIcon('activity', size: 12, color: AppColors.fg3),
          SizedBox(width: S.s6),
          Text('Transcribing audio…', style: TS.meta()),
        ]),
    ];
    final extras = <Widget>[
      if (images > 0 || files > 0)
        AttachmentPill(audio: 0, images: images, files: files),
    ];
    final media =
        client == null ? null : _sentMedia(context, client!, transcripts);
    final mineText = textBody == null
        ? const SizedBox.shrink()
        : (selectable ? SelectionArea(child: textBody) : textBody);
    final agentContent = MarkdownBody(
      data: unwrapCodedLinks(shown),
      selectable: false,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      styleSheet: agentMarkdownStyle(context),
      builders: {'pre': PreBlockBuilder()},
      onTapLink: (txt, href, title) => openMarkdownLink(href, context, txt),
    );

    final agent =
        selectable ? SelectionArea(child: agentContent) : agentContent;

    final chatBubbles = ChatBubbleScope.of(context);
    if (chatBubbles && !mine && shown.isNotEmpty) {
      final reply = MarkdownBody(
        data: unwrapCodedLinks(shown),
        selectable: false,
        extensionSet: md.ExtensionSet.gitHubFlavored,
        styleSheet: chatMarkdownStyle(context, mine: false),
        builders: {'pre': PreBlockBuilder()},
        onTapLink: (txt, href, title) => openMarkdownLink(href, context, txt),
      );
      final body = selectable && !kMobile ? SelectionArea(child: reply) : reply;
      final bubble = ChatBubbleRow(
          mine: false, child: ChatBubble(mine: false, child: body));
      return Padding(
        padding: EdgeInsets.symmetric(vertical: S.s2),
        child: onLongPress != null
            ? GestureDetector(onLongPress: onLongPress, child: bubble)
            : (selectable
                ? _LongPressCopy(text: shown, child: bubble)
                : bubble),
      );
    }

    if (!mine && kMobile && selectable) {
      // Phones: no Copy row under every reply. Long-press offers copying the
      // whole message or selecting within it (a long-press can't do both).
      return Padding(
        padding: EdgeInsets.only(right: S.s8, top: S.s4, bottom: S.s4),
        child: Pressable(
          enabled: shown.isNotEmpty || onLongPress != null,
          scale: 0.98,
          delay: const Duration(milliseconds: 160),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: onLongPress != null
                ? () {
                    holdHaptic();
                    onLongPress!();
                  }
                : (shown.isEmpty
                    ? null
                    : () {
                        holdHaptic();
                        _messageActions(context, shown);
                      }),
            child: agentContent,
          ),
        ),
      );
    }

    if (!mine) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.only(right: S.s8, top: S.s4, bottom: S.s4),
          child: onLongPress != null
              ? GestureDetector(onLongPress: onLongPress, child: agent)
              : (selectable && shown.isNotEmpty
                  ? _LongPressCopy(text: shown, child: agent)
                  : agent),
        ),
      );
    }

    return LayoutBuilder(builder: (context, box) {
      final inset = kMobile
          ? 48.0
          : (box.maxWidth.isFinite ? box.maxWidth * 0.18 : 140.0)
              .clamp(24.0, 140.0);
      return Padding(
        padding: EdgeInsets.only(left: inset, top: S.s4, bottom: S.s4),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
            if (media != null)
              for (final m in media) ...[
                m,
                SizedBox(height: S.s6),
              ],
            if (shown.isNotEmpty && chatBubbles)
              ChatBubble(
                mine: true,
                child: MarkdownBody(
                  data: unwrapCodedLinks(shown),
                  selectable: false,
                  styleSheet: chatMarkdownStyle(context, mine: true),
                  builders: {'pre': PreBlockBuilder()},
                  onTapLink: (txt, href, title) =>
                      openMarkdownLink(href, context, txt),
                ),
              )
            else if (shown.isNotEmpty)
              Container(
                padding: kMobile
                    ? EdgeInsets.fromLTRB(
                        S.of(15), S.of(10), S.of(15), S.of(11))
                    : const EdgeInsets.fromLTRB(11, 7, 11, 7),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: kMobile
                      ? BorderRadius.only(
                          topLeft: Radius.circular(R.of(20)),
                          topRight: Radius.circular(R.of(20)),
                          bottomLeft: Radius.circular(R.of(20)),
                          bottomRight: Radius.circular(R.sm),
                        )
                      : BorderRadius.circular(R.of(8)),
                ),
                child: DefaultTextStyle.merge(
                  textWidthBasis: TextWidthBasis.longestLine,
                  child: mineText,
                ),
              ),
            if (media == null || media.isEmpty) ...[
              for (final v in voice) ...[
                SizedBox(height: S.s6),
                v,
              ],
              for (final extra in extras) ...[
                SizedBox(height: S.s6),
                extra,
              ],
            ],
            ...pastedCards,
          ],
          ),
        ),
      );
    });
  }
}

extension on Bubble {
  /// The attachments of a sent message as media, in the order images, files,
  /// voice notes; empty when the message has none.
  List<Widget> _sentMedia(BuildContext context, DaemonClient client,
      List<AudioTranscriptItem> transcripts) {
    final attachments = parseSentAttachments(text);
    if (attachments.isEmpty) return const [];
    final images = [
      for (final a in attachments)
        if (a.kind == MediaKind.image) a.path
    ];
    final audio = [
      for (final a in attachments)
        if (a.kind == MediaKind.audio) a.path
    ];
    final files = [
      for (final a in attachments)
        if (a.kind != MediaKind.image && a.kind != MediaKind.audio) a.path
    ];
    final maxWidth =
        (MediaQuery.sizeOf(context).width - 32).clamp(160.0, 280.0);
    Widget card(Widget child) => Container(
          constraints: BoxConstraints(maxWidth: kMobile ? 272 : 340),
          padding: kMobile
              ? EdgeInsets.fromLTRB(S.s8, S.s8, S.s12, S.of(10))
              : EdgeInsets.fromLTRB(S.s8, S.s8, S.s12, S.of(10)),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(kMobile ? 16 : R.card),
          ),
          child: child,
        );
    final out = <Widget>[];
    void add(Widget w) {
      if (out.isNotEmpty) out.add(SizedBox(height: S.s6));
      out.add(w);
    }

    if (images.isNotEmpty) {
      add(ImageGallery(client: client, paths: images, maxWidth: maxWidth));
    }
    if (files.isNotEmpty) {
      add(SizedBox(
        width: maxWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < files.length; i++) ...[
              if (i > 0) SizedBox(height: S.s6),
              FileChip(client: client, path: files[i]),
            ],
          ],
        ),
      ));
    }
    for (var i = 0; i < audio.length; i++) {
      final transcript = i < transcripts.length
          ? AudioTranscriptCard(items: [transcripts[i]])
          : (transcripts.isEmpty
              ? Text('Transcribing…', style: TS.meta())
              : null);
      add(card(
          VoiceNote(client: client, path: audio[i], transcript: transcript)));
    }
    return out;
  }
}

class _LongPressCopy extends StatefulWidget {
  const _LongPressCopy({required this.text, required this.child});
  final String text;
  final Widget child;

  @override
  State<_LongPressCopy> createState() => _LongPressCopyState();
}

class _LongPressCopyState extends State<_LongPressCopy> {
  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.text));
    toast(context, 'Copied');
  }

  @override
  Widget build(BuildContext context) =>
      GestureDetector(onLongPress: _copy, child: widget.child);
}

/// Dim note / error card (labelled, danger-tinted).
class NoteLine extends StatelessWidget {
  final String text;
  final bool error;
  final String? icon;

  /// What went wrong, as the card's header (errors only).
  final String? label;
  final int count;
  const NoteLine(this.text,
      {super.key, this.error = false, this.icon, this.label, this.count = 1});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    if (!error) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: S.of(3)),
        child: icon == null
            ? Text(text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style:
                    sans(kMobile ? 13 : 13, height: 1.4, color: AppColors.fg3))
            : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: S.of(2.5)),
                    child: AppIcon(icon!, size: 13, color: AppColors.fg3),
                  ),
                  SizedBox(width: S.of(7)),
                  Flexible(
                    child: Text(text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: sans(kMobile ? 13 : 13,
                            height: 1.4, color: AppColors.fg3)),
                  ),
                ],
              ),
      );
    }
    final limit = text.toLowerCase().contains('session limit') ||
        text.toLowerCase().contains('usage limit') ||
        text.toLowerCase().contains('rate limit');
    final tone = limit ? AppColors.run : AppColors.danger;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: S.s4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: S.s12, vertical: S.s8),
          decoration: BoxDecoration(
            color: Color.lerp(AppColors.surface1, tone, 0.11),
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: S.s2),
                child: AppIcon(limit ? 'clock' : 'alert-triangle',
                    size: 13, color: tone),
              ),
              SizedBox(width: S.s8),
              Flexible(
                child: SelectableText.rich(
                    TextSpan(children: [
                      if (label != null)
                        TextSpan(
                            text: '$label  ',
                            style: TextStyle(
                                color: AppColors.fg1,
                                fontWeight: weightFor(W.label))),
                      TextSpan(text: text),
                    ]),
                    minLines: 1,
                    maxLines: 5,
                    style: sans(kMobile ? 13 : 13,
                        height: 1.4, color: AppColors.fg2)),
              ),
              if (count > 1) ...[
                SizedBox(width: S.s8),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: S.s6, vertical: S.of(1)),
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(R.pill),
                  ),
                  child: Text('×$count',
                      style: mono(11, weight: W.label, color: tone)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class Progress extends StatelessWidget {
  final double pct; // 0..100
  final Color? color;
  final double height;
  const Progress({super.key, required this.pct, this.color, this.height = 7});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return ClipRRect(
      borderRadius: BorderRadius.circular(R.pill),
      child: LinearProgressIndicator(
        value: (pct / 100).clamp(0, 1),
        minHeight: height,
        backgroundColor: AppColors.surface2,
        valueColor: AlwaysStoppedAnimation(color ?? AppColors.accent),
      ),
    );
  }
}

class WarnChip extends StatelessWidget {
  final String label;
  const WarnChip({super.key, this.label = 'No key'});
  @override
  Widget build(BuildContext context) =>
      Tag(label, tone: Tone.run, icon: 'alert-triangle');
}

/// A section label above a group of rows.
///
/// `fg2` at weight 500, matching BOTH other section-header treatments in the app
/// (`ShellSectionHeader` in the sidebar, `_StatusHeader` on the task board).
/// This rendered at `fg4` — the placeholder/disabled rung — which measured
/// 2.98:1 against the panel background, below the 4.5 AA floor, and read as
/// disabled chrome rather than a label. `shell_nav.dart` had already documented
/// and fixed exactly this mistake for its own header; this one was missed.
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s2),
        child: Text(text.toUpperCase(), style: TS.overline()),
      );
}

class EmptyState extends StatelessWidget {
  final String icon;
  final String title;
  final String? body;
  final Widget? action;
  const EmptyState(
      {super.key,
      required this.icon,
      required this.title,
      this.body,
      this.action});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    // Fills the box it is handed and centers inside it. Call sites give this the
    // whole body of a pane or an `Expanded`, and a shrink-wrapping child there
    // aligns to the top-left instead of the middle — so the centering has to
    // live here rather than be repeated at every call site.
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: S.of(44), horizontal: S.of(28)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              // Separation by surface step, not a hairline — the design
              // language's first rule. surface2 is the ladder's "quiet raised
              // content" step, which is what this tile is; the border was
              // standing in for a step that already existed.
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(R.md),
            ),
            child: AppIcon(icon, size: 24, color: AppColors.fg3),
          ),
          SizedBox(height: S.s12),
          Text(title, style: TS.sectionTitle()),
          if (body != null) ...[
            SizedBox(height: S.s8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(body!, textAlign: TextAlign.center, style: TS.meta()),
            ),
          ],
          if (action != null) ...[SizedBox(height: S.s16), action!],
        ]),
      ),
    );
  }
}

/// Custom app bar matching the handoff (back + title/mono-subtitle + right + ⋯).
/// A page header's primary action: a labelled button on desktop, an icon
/// button on phones, where a filled text button crowded the title.
class HeaderAction extends StatelessWidget {
  final String label;
  final String icon;
  final VoidCallback? onTap;
  const HeaderAction(this.label,
      {super.key, this.icon = 'plus', required this.onTap});

  @override
  Widget build(BuildContext context) => kMobile
      ? RoundBtn(
          icon: icon, size: 34, iconSize: 15, tooltip: label, onTap: onTap)
      : Btn(label,
          icon: icon, small: true, variant: BtnVariant.secondary, onTap: onTap);
}

class ShellPanelRoot extends InheritedWidget {
  const ShellPanelRoot({super.key, this.label = '', required super.child});

  final String label;

  static ShellPanelRoot? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellPanelRoot>();

  static bool inPanel(BuildContext context) => !kMobile && of(context) != null;

  static bool isRoot(BuildContext context) {
    if (of(context) == null) return false;
    final route = ModalRoute.of(context);
    return route != null ? route.isFirst : !Navigator.of(context).canPop();
  }

  static bool repeatsLabel(BuildContext context, String title) {
    final label = of(context)?.label.trim().toLowerCase() ?? '';
    return !kMobile &&
        label.isNotEmpty &&
        title.trim().toLowerCase() == label &&
        isRoot(context);
  }

  static bool hides(BuildContext context, String name, String? tooltip) =>
      !kMobile && of(context) != null && name == 'x' && tooltip == 'Close';

  @override
  bool updateShouldNotify(ShellPanelRoot old) => false;
}

class SnAppBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final bool keepBack;
  final Widget? leading;
  final List<Widget> actions;
  final double? titleSize;
  final bool compact;

  /// Which surface the bar sits on. Defaults to the ambient scaffold colour,
  /// which is what the desktop panels re-theme.
  final Color? background;

  /// Draws the 1px bottom hairline.
  ///
  /// The design language uses NO borders — separation comes from the surface
  /// ladder — so a page that pairs a chrome bar with a canvas body passes
  /// `false` and lets the step do the work. Defaulted to true rather than
  /// flipped globally: the existing call sites share the scaffold's own colour,
  /// where the hairline is currently the only separation they have. Removing it
  /// for them is a follow-up, not something to fold into one page's fix.
  final bool bordered;
  const SnAppBar(
      {super.key,
      required this.title,
      this.subtitle,
      this.onBack,
      this.keepBack = false,
      this.leading,
      this.actions = const [],
      this.titleSize,
      this.compact = false,
      this.background,
      this.bordered = true});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final onBack =
        this.onBack != null && !kMobile && ShellPanelRoot.isRoot(context)
            ? null
            : this.onBack;
    final actions = ShellPanelRoot.inPanel(context)
        ? this
            .actions
            .where((a) => !(a is IconBtn &&
                ShellPanelRoot.hides(context, a.name, a.tooltip)))
            .toList()
        : this.actions;
    final repeats = subtitle == null &&
        onBack == null &&
        leading == null &&
        ShellPanelRoot.repeatsLabel(context, title);
    if (repeats && actions.isEmpty) return const SizedBox.shrink();
    if (kMobile && onBack != null && leading == null) {
      return MobileBackBar(
        title: title,
        subtitle: subtitle,
        onBack: onBack,
        keepBack: keepBack,
        trailing: [
          for (final a in actions)
            if (a is IconBtn)
              Padding(
                padding: EdgeInsets.only(left: S.s8),
                child: RoundBtn(
                    icon: a.name, tooltip: a.tooltip ?? a.name, onTap: a.onTap),
              )
            else
              a,
        ],
      );
    }
    return Container(
      height: repeats ? 44 : (compact ? 52 : 64),
      padding: EdgeInsets.fromLTRB(
          onBack != null || leading != null
              ? (kMobile ? S.s6 : S.s4)
              : (kMobile ? M.gutter : S.s12),
          0,
          kMobile ? S.of(10) : S.s8,
          0),
      decoration: BoxDecoration(
        // Follows the ambient shell surface — desktop panels re-theme this to
        // surface1 so the bar never reads as a darker strip (mobile: still bg).
        color: background ?? Theme.of(context).scaffoldBackgroundColor,
        border: bordered && !kMobile
            ? Border(bottom: BorderSide(color: AppColors.border))
            : null,
      ),
      child: Row(children: [
        if (leading != null)
          leading!
        else if (onBack != null)
          IconBtn('chevron-left',
              size: kMobile ? M.minTarget : 36,
              iconSize: kMobile ? 22 : 20,
              tooltip: 'Back',
              onTap: onBack),
        if (leading != null || onBack != null) SizedBox(width: S.s2),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!repeats)
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kMobile && (titleSize ?? 0) >= 22
                          ? TS.pageTitle()
                          : kMobile
                              ? sans(titleSize ?? 18,
                                  spacing: -0.3, color: AppColors.fg1)
                              : display((titleSize ?? 15).clamp(0, 15).toDouble())),
                if (subtitle != null)
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kMobile
                          ? sans(12, color: AppColors.fg3)
                          : TS.codeSmall()),
              ]),
        ),
        ...actions,
      ]),
    );
  }
}

/// Labeled input: focus → accent border + ring.

class AppSwitch extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChanged;

  /// Whole-track size. The thumb and its inset derive from this, so the
  /// proportions hold at any size.
  final double width;
  final double height;
  final double thumb;

  const AppSwitch({
    super.key,
    required this.on,
    required this.onChanged,
    this.width = 44,
    this.height = 26,
    this.thumb = 20,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    const inset = 3.0;
    return Semantics(
      toggled: on,
      child: TapDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!on);
        },
        // The visible track is small; this keeps the tappable area comfortable
        // without scaling the drawing.
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: width,
          height: height + 12,
          child: Center(
            child: AnimatedContainer(
              duration: Motion.fast,
              curve: Motion.enter,
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: on ? AppColors.accentFill : AppColors.surface3,
                borderRadius: BorderRadius.circular(height / 2),
              ),
              child: AnimatedAlign(
                duration: Motion.fast,
                curve: Motion.enter,
                alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: inset),
                  child: Container(
                    width: thumb,
                    height: thumb,
                    decoration: BoxDecoration(
                        color: on
                            ? AppColors.accentFg
                            : (kMobile ? AppColors.fg4 : Colors.white),
                        shape: BoxShape.circle),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppToggle extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChanged;
  final String label;
  final String? sub;

  /// A row inside a grouped card, without a card of its own.
  final bool flat;
  const AppToggle(
      {super.key,
      required this.on,
      required this.onChanged,
      required this.label,
      this.sub,
      this.flat = false});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Pressable(
      kind: PressKind.row,
      radius: R.md,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!on);
        },
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          padding: flat
              ? EdgeInsets.symmetric(vertical: S.of(10))
              : kMobile
                  ? EdgeInsets.symmetric(horizontal: S.s4, vertical: S.s12)
                  : EdgeInsets.symmetric(horizontal: S.of(14), vertical: S.s12),
          decoration: flat || kMobile
              ? null
              : BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(R.md),
                ),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: kMobile
                            ? sans(15, height: 20 / 15, color: AppColors.fg1)
                            : TS.label(AppColors.fg1)),
                    if (sub != null) ...[
                      SizedBox(height: S.of(3)),
                      Text(sub!,
                          style: kMobile
                              ? sans(13, height: 18 / 13, color: AppColors.fg3)
                              : TS.caption())
                    ],
                  ]),
            ),
            SizedBox(width: S.s12),
            AppSwitch(on: on, onChanged: onChanged),
          ]),
        ),
      ),
    );
  }
}

String? providerLogoAsset(String? provider) {
  final p = (provider ?? '').toLowerCase();
  final key = switch (p) {
    'claude-code' || 'claude' => 'claude',
    'anthropic' || 'anthropic-compatible' => 'anthropic',
    'openai' || 'chatgpt' || 'codex' || 'openai-compatible' => 'openai',
    'gemini' || 'google' => 'gemini',
    'antigravity' => 'antigravity',
    'devin' || 'windsurf' => 'devin',
    'xai' || 'grok' => 'xai',
    'openrouter' => 'openrouter',
    'opencode-zen' || 'opencode-go' || 'opencode' => 'opencode',
    _ => null,
  };
  if (key == null) return null;
  return 'assets/providers/$key.${key == 'antigravity' ? 'png' : 'svg'}';
}

/// Marks that ship in their own colours; the rest are single-colour and follow the theme.
bool providerLogoIsColour(String? provider) {
  final a = providerLogoAsset(provider) ?? '';
  return a.endsWith('claude.svg') ||
      a.endsWith('gemini.svg') ||
      a.endsWith('antigravity.png');
}

class ProviderLogo extends StatelessWidget {
  const ProviderLogo(this.provider, {super.key, this.size = 16, this.color});

  final String? provider;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final asset = providerLogoAsset(provider);
    final tint = color ?? AppColors.fg1;
    if (asset == null) return AppIcon('cpu', size: size, color: tint);
    final inner = size * 0.86;
    if (color == null && providerLogoIsColour(provider)) {
      return SizedBox.square(
        dimension: size,
        child: Center(
          child: asset.endsWith('.png')
              ? Image.asset(asset,
                  width: inner,
                  height: inner,
                  filterQuality: FilterQuality.high)
              : SvgPicture.asset(asset, width: inner, height: inner),
        ),
      );
    }
    return SizedBox.square(
      dimension: size,
      child: Center(
        child: SvgPicture.asset(
          asset,
          width: size * 0.86,
          height: size * 0.86,
          colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
        ),
      ),
    );
  }
}

/// Short git status letter and token colour for a file-browser / tree entry.
({String letter, Color color})? fsGitStatusMeta(String? status) =>
    switch (status) {
      'modified' => (letter: 'M', color: AppColors.run),
      'added' => (letter: 'A', color: AppColors.ok),
      'untracked' => (letter: 'U', color: AppColors.fg4),
      'deleted' => (letter: 'D', color: AppColors.danger),
      'renamed' => (letter: 'R', color: AppColors.accent),
      _ => null,
    };

class FsGitStatusLabel extends StatelessWidget {
  final String? status;
  const FsGitStatusLabel(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final meta = fsGitStatusMeta(status);
    if (meta == null) return const SizedBox.shrink();
    return Text(
      meta.letter,
      style: mono(11, weight: W.label, color: meta.color),
    );
  }
}
