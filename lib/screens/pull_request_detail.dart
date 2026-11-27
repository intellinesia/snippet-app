import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../github_models.dart';
import '../highlight.dart';
import '../platform.dart';
import '../settings_form.dart' show Grouped;
import '../theme.dart';
import '../widgets.dart';
import 'mobile_chrome.dart';
import 'pane_add_menu.dart';
import '../tap_detector.dart';

part 'pull_request_desktop.dart';

// ---------------------------------------------------------------------------
// Shared pieces
// ---------------------------------------------------------------------------

String prAgo(String iso) {
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  return relativeTime(t.millisecondsSinceEpoch ~/ 1000);
}

List<PrSummary> appendPrs(List<PrSummary>? have, List<PrSummary> page) {
  final seen = {for (final p in have ?? const <PrSummary>[]) p.number};
  return [...?have, ...page.where((p) => seen.add(p.number))];
}

// Unbuilt files only have an estimated offset, so the first jump lands near and
// the second, once they are laid out, lands exactly.
void prReveal(GlobalKey? key) {
  final ctx = key?.currentContext;
  if (ctx == null) return;
  Scrollable.ensureVisible(ctx);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final again = key?.currentContext;
    if (again != null) Scrollable.ensureVisible(again);
  });
}

bool prNearEnd(ScrollNotification n, VoidCallback load) {
  if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 600) load();
  return false;
}

Widget prLoadMore(bool busy, VoidCallback onTap) => SizedBox(
      height: 56,
      child: Center(
        child: busy
            ? Spinner(size: 16, color: AppColors.fg3)
            : TextButton(
                onPressed: onTap,
                child: Text('Load more',
                    style: sans(13, weight: W.label, color: AppColors.accent)),
              ),
      ),
    );

Widget prMessage(String text) => Center(
      child: Padding(
        padding: EdgeInsets.all(S.s24),
        child: Text(text,
            textAlign: TextAlign.center,
            style: sans(13, height: 1.5, color: AppColors.fg3)),
      ),
    );

Widget prSize(int add, int del, {double size = 12}) => Text.rich(TextSpan(children: [
      TextSpan(text: '+$add', style: sans(size, color: AppColors.ok)),
      TextSpan(text: ' −$del', style: sans(size, color: AppColors.danger)),
    ]));

/// A small tinted status label, as on the pull request list and detail.
Widget prPill(String text, Color tone) => Container(
      padding: EdgeInsets.symmetric(
          horizontal: kMobile ? S.s8 : S.s6, vertical: kMobile ? S.s4 : S.s2),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: kMobile ? 0.14 : 0.10),
        borderRadius: BorderRadius.circular(kMobile ? R.sm : R.of(5)),
      ),
      child: Text(text,
          maxLines: 1, style: sans(kMobile ? 12 : 11.5, color: tone)),
    );

Widget prAvatar(String login, {double size = 22}) {
  const tints = [0xFF7C8CF8, 0xFF5BC0A0, 0xFFE0A050, 0xFFD27AA8, 0xFF62A8E0, 0xFFB59A6A];
  final tint = Color(tints[login.codeUnits.fold<int>(0, (a, b) => a + b) % tints.length]);
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: tint.withValues(alpha: 0.2), shape: BoxShape.circle),
    child: Text(login.isEmpty ? '?' : login[0].toUpperCase(),
        style: sans(size * 0.48, weight: W.strong, color: tint)),
  );
}

Widget prHeader(
  BuildContext context, {
  required String title,
  String subtitle = '',
  VoidCallback? onBack,
  VoidCallback? onClose,
  List<Widget> actions = const [],
}) {
  if (kMobile) {
    return MobileBackBar(
      title: title,
      subtitle: subtitle.isEmpty ? null : subtitle,
      onBack: onBack ?? onClose ?? () => Navigator.maybePop(context),
      trailing: actions,
    );
  }
  return Container(
    padding: EdgeInsets.fromLTRB(onBack == null ? S.s16 : S.s6, kMobile ? S.s8 : S.of(10), S.s6, S.of(10)),
    child: Row(children: [
      if (onBack != null)
        IconBtn('chevron-left',
            size: kMobile ? M.minTarget : 32, iconSize: 18, tooltip: 'Back', onTap: onBack),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(kMobile ? 17 : 15, weight: W.strong, color: AppColors.fg1)),
            if (subtitle.isNotEmpty)
              Text(subtitle,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TS.meta(AppColors.fg3)),
          ],
        ),
      ),
      ...actions,
      if (onClose != null)
        IconBtn('x', size: kMobile ? M.minTarget : 32, iconSize: 16, tooltip: 'Close', onTap: onClose),
    ]),
  );
}

/// GitHub comments carry HTML that the markdown renderer would print raw:
/// keep the readable parts (bold, code, links, line breaks) and drop the rest.
String _cleanBody(String body) {
  var s = body.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  s = s.replaceAll(RegExp(r'<picture>.*?</picture>', dotAll: true), '');
  s = s.replaceAllMapped(RegExp(r'<(strong|b)>(.*?)</(strong|b)>', dotAll: true), (m) => '**${m[2]!.trim()}**');
  s = s.replaceAllMapped(RegExp(r'<(em|i)>(.*?)</(em|i)>', dotAll: true), (m) => '_${m[2]!.trim()}_');
  s = s.replaceAllMapped(RegExp(r'<code>(.*?)</code>', dotAll: true), (m) => '`${m[1]}`');
  s = s.replaceAllMapped(RegExp(r'<a [^>]*href="([^"]+)"[^>]*>(.*?)</a>', dotAll: true),
      (m) => '[${m[2]!.replaceAll(RegExp(r'<[^>]+>'), '').trim()}](${m[1]})');
  s = s.replaceAll(RegExp(r'<br\s*/?>'), '\n');
  s = s.replaceAll(RegExp(r'</?[a-zA-Z][^>]*>'), '');
  s = s.replaceAll('&nbsp;', ' ').replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&amp;', '&');
  return s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

/// Split a body into plain text and top-level `<details>` blocks (nesting
/// counted), so collapsed sections stay collapsed as they do on GitHub.
List<({String text, String? summary})> _segments(String body) {
  final out = <({String text, String? summary})>[];
  final open = RegExp(r'<details[^>]*>');
  var rest = body.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  while (true) {
    final m = open.firstMatch(rest);
    if (m == null) break;
    if (m.start > 0) out.add((text: rest.substring(0, m.start), summary: null));
    var depth = 1;
    var i = m.end;
    while (depth > 0 && i < rest.length) {
      final nextOpen = rest.indexOf(open, i);
      final nextClose = rest.indexOf('</details>', i);
      if (nextClose < 0) {
        i = rest.length;
        break;
      }
      if (nextOpen >= 0 && nextOpen < nextClose) {
        depth++;
        i = rest.indexOf('>', nextOpen) + 1;
      } else {
        depth--;
        i = nextClose + '</details>'.length;
      }
    }
    final inner = rest.substring(m.end, depth == 0 ? i - '</details>'.length : rest.length);
    final sum = RegExp(r'<summary>(.*?)</summary>', dotAll: true).firstMatch(inner);
    final summary = sum == null
        ? 'Details'
        : _cleanBody(sum[1]!).replaceAll('\n', ' ').replaceAll('**', '').replaceAll('`', '').trim();
    final content = sum == null ? inner : inner.replaceRange(sum.start, sum.end, '');
    out.add((text: content, summary: summary.isEmpty ? 'Details' : summary));
    rest = rest.substring(i);
  }
  if (rest.trim().isNotEmpty) out.add((text: rest, summary: null));
  return out;
}

MarkdownStyleSheet _compactMarkdown(BuildContext context) {
  final text = sans(kMobile ? 14 : 13, height: 1.55, color: AppColors.fg2);
  return markdownStyle(context).copyWith(
    p: text,
    listBullet: text,
    strong: text.copyWith(color: AppColors.fg1, fontWeight: weightFor(W.strong)),
    em: text.copyWith(fontStyle: FontStyle.italic),
    a: text.copyWith(color: AppColors.accent),
    h1: sans(17, weight: W.strong, color: AppColors.fg1),
    h2: sans(15, weight: W.strong, color: AppColors.fg1),
    h3: sans(14, weight: W.strong, color: AppColors.fg1),
    code: codeMono(12, color: AppColors.fg1).copyWith(backgroundColor: AppColors.tint2),
    blockSpacing: 8,
  );
}

/// A comment body: markdown, with ```suggestion blocks shown as the change
/// they propose and `<details>` sections collapsed until tapped.
class PrCommentBody extends StatelessWidget {
  const PrCommentBody(this.body, {super.key});
  final String body;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final seg in _segments(body)) {
      if (seg.summary != null) {
        children.add(_Collapsible(summary: seg.summary!, body: seg.text));
      } else {
        children.addAll(_markdown(context, _cleanBody(seg.text)));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: S.s8),
          children[i],
        ],
      ],
    );
  }

  List<Widget> _markdown(BuildContext context, String clean) {
    final parts = clean.split(RegExp(r'```suggestion[^\n]*\n'));
    final out = <Widget>[];
    for (var i = 0; i < parts.length; i++) {
      var part = parts[i];
      if (i > 0) {
        final end = part.indexOf('```');
        final code = end < 0 ? part : part.substring(0, end);
        part = end < 0 ? '' : part.substring(end + 3);
        out.add(_suggestion(code.trimRight()));
      }
      if (part.trim().isNotEmpty) {
        out.add(MarkdownBody(
          data: part.trim(),
          styleSheet: _compactMarkdown(context),
          onTapLink: (_, href, __) => openMarkdownLink(href, context),
        ));
      }
    }
    return out;
  }

  Widget _suggestion(String code) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(R.md),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: AppColors.tint2,
            padding: EdgeInsets.symmetric(horizontal: S.of(10), vertical: S.s6),
            child: Text('Suggested change', style: TS.meta(AppColors.fg2)),
          ),
          for (final line in code.split('\n'))
            Container(
              color: AppColors.diffAddBg,
              padding: EdgeInsets.symmetric(horizontal: S.of(10), vertical: S.of(1)),
              child: Text('+ $line', style: codeMono(12, height: 1.5, color: AppColors.fg1)),
            ),
        ]),
      );
}

class _Collapsible extends StatefulWidget {
  const _Collapsible({required this.summary, required this.body});
  final String summary;
  final String body;

  @override
  State<_Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<_Collapsible> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        onTap: () => setState(() => _open = !_open),
        borderRadius: BorderRadius.circular(R.sm),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: S.of(3)),
          child: Row(children: [
            AppIcon(_open ? 'chevron-down' : 'chevron-right', size: 13, color: AppColors.fg3),
            SizedBox(width: S.s6),
            Expanded(
              child: Text(widget.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, weight: W.label, color: AppColors.fg1)),
            ),
          ]),
        ),
      ),
      if (_open)
        Padding(
          padding: EdgeInsets.fromLTRB(S.of(19), S.s6, 0, S.s4),
          child: PrCommentBody(widget.body),
        ),
    ]);
  }
}

/// A markdown comment editor in GitHub's shape: Write and Preview tabs, a
/// formatting toolbar that wraps the selection, and a footer for actions.
class PrMarkdownComposer extends StatefulWidget {
  const PrMarkdownComposer({
    super.key,
    required this.controller,
    this.hint = 'Leave a comment',
    this.minLines = 3,
    this.autofocus = false,
    this.extraTools = const [],
    this.footer,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final int minLines;
  final bool autofocus;
  final List<Widget> extraTools;
  final Widget? footer;
  final VoidCallback? onChanged;

  @override
  State<PrMarkdownComposer> createState() => _PrMarkdownComposerState();
}

class _PrMarkdownComposerState extends State<PrMarkdownComposer> {
  final _focus = FocusNode();
  bool _preview = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    widget.onChanged?.call();
    setState(() {});
  }

  void _wrap(String before, [String? after]) {
    final c = widget.controller;
    final text = c.text;
    final sel = c.selection.isValid ? c.selection : TextSelection.collapsed(offset: text.length);
    final picked = sel.textInside(text);
    final close = after ?? before;
    final replaced = '$before${picked.isEmpty ? 'text' : picked}$close';
    c.value = TextEditingValue(
      text: sel.textBefore(text) + replaced + sel.textAfter(text),
      selection: picked.isEmpty
          ? TextSelection(
              baseOffset: sel.start + before.length, extentOffset: sel.start + before.length + 4)
          : TextSelection.collapsed(offset: sel.start + replaced.length),
    );
    _focus.requestFocus();
    _changed();
  }

  void _prefixLines(String prefix) {
    final c = widget.controller;
    final text = c.text;
    final sel = c.selection.isValid ? c.selection : TextSelection.collapsed(offset: text.length);
    final start = text.lastIndexOf('\n', sel.start == 0 ? 0 : sel.start - 1) + 1;
    final endBreak = text.indexOf('\n', sel.end);
    final end = endBreak < 0 ? text.length : endBreak;
    final block = text.substring(start, end).split('\n').map((l) => '$prefix$l').join('\n');
    c.value = TextEditingValue(
      text: text.replaceRange(start, end, block),
      selection: TextSelection.collapsed(offset: start + block.length),
    );
    _focus.requestFocus();
    _changed();
  }

  void _code() {
    final c = widget.controller;
    final picked = c.selection.isValid ? c.selection.textInside(c.text) : '';
    if (picked.contains('\n')) {
      _wrap('```\n', '\n```');
    } else {
      _wrap('`');
    }
  }

  Widget _tab(String label, bool selected, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: S.of(10), vertical: S.of(5)),
          decoration: BoxDecoration(
            color: selected
                ? (kMobile ? AppColors.tint2 : PaneRow.plate)
                : Colors.transparent,
            borderRadius:
                BorderRadius.circular(kMobile ? R.sm : PaneRow.radius),
          ),
          child: Text(label,
              style: sans(kMobile ? 13 : 12.5,
                  weight: W.label,
                  color: selected
                      ? (kMobile ? AppColors.fg1 : PaneRow.labelOn)
                      : (kMobile ? AppColors.fg3 : PaneRow.labelOff))),
        ),
      );

  Widget _tool({String? icon, String? glyph, TextStyle? style, required String tip, required VoidCallback onTap}) =>
      Tooltip(
        message: tip,
        child: InkWell(
          onTap: _preview ? null : onTap,
          borderRadius: BorderRadius.circular(R.sm),
          child: SizedBox(
            width: 30,
            height: 28,
            child: Center(
              child: icon != null
                  ? AppIcon(icon, size: 14, color: _preview ? AppColors.fg4 : (kMobile ? AppColors.fg2 : AppColors.fg3))
                  : Text(glyph!, style: (style ?? sans(14)).copyWith(color: _preview ? AppColors.fg4 : (kMobile ? AppColors.fg2 : AppColors.fg3))),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    final text = widget.controller.text;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      decoration: BoxDecoration(
        color: kMobile ? AppColors.tint2 : Grouped.card,
        borderRadius: BorderRadius.circular(kMobile ? R.lg : R.of(9)),
        border: Border.all(
            color: focused
                ? (kMobile ? AppColors.accent : AppColors.accentLine)
                : (kMobile ? Colors.transparent : Grouped.cardBorder),
            width: kMobile ? 1.4 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(S.s6, S.s6, S.s4, S.s2),
          child: Row(children: [
            _tab('Write', !_preview, () => setState(() => _preview = false)),
            SizedBox(width: S.s2),
            _tab('Preview', _preview, () => setState(() => _preview = true)),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    ...widget.extraTools,
                    _tool(glyph: 'B', style: sans(14, weight: W.strong), tip: 'Bold', onTap: () => _wrap('**')),
                    _tool(glyph: 'I', style: sans(14).copyWith(fontStyle: FontStyle.italic), tip: 'Italic', onTap: () => _wrap('_')),
                    _tool(icon: 'code', tip: 'Code', onTap: _code),
                    _tool(glyph: '\u2022', style: sans(18, weight: W.strong), tip: 'List', onTap: () => _prefixLines('- ')),
                    _tool(glyph: '>', style: mono(15, weight: W.strong), tip: 'Quote', onTap: () => _prefixLines('> ')),
                  ]),
                ),
              ),
            ),
          ]),
        ),
        Container(height: 1, color: kMobile ? AppColors.border : AppColors.paneLine),
        if (_preview)
          Container(
            constraints: BoxConstraints(minHeight: widget.minLines * 22.0 + 20),
            padding: EdgeInsets.fromLTRB(S.s12, S.of(10), S.s12, S.of(10)),
            child: text.trim().isEmpty
                ? Text('Nothing to preview', style: TS.meta(AppColors.fg4))
                : PrCommentBody(text),
          )
        else
          TextField(
            controller: widget.controller,
            focusNode: _focus,
            autofocus: widget.autofocus,
            minLines: widget.minLines,
            maxLines: 14,
            onChanged: (_) => _changed(),
            style: TS.body(AppColors.fg1),
            cursorColor: AppColors.accent,
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: TS.body(AppColors.fg4),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.fromLTRB(S.s12, S.of(10), S.s12, S.of(10)),
            ),
          ),
        if (widget.footer != null) ...[
          Container(height: 1, color: kMobile ? AppColors.border : AppColors.paneLine),
          Padding(padding: EdgeInsets.fromLTRB(S.s8, S.s6, S.s8, S.s6), child: widget.footer),
        ] else
          Padding(
            padding: EdgeInsets.fromLTRB(S.s12, 0, S.s12, S.s8),
            child: Text('Markdown supported', style: TS.meta(AppColors.fg4)),
          ),
      ]),
    );
  }
}

/// A sheet for writing a conversation comment.
Future<String?> showPrCommentSheet(BuildContext context, {required String title, String action = 'Comment'}) {
  return showAppSheet<String>(context,
      title: title, maxWidth: 520, maxHeight: 640, child: _CommentSheet(action: action));
}

class _CommentSheet extends StatefulWidget {
  const _CommentSheet({required this.action});
  final String action;

  @override
  State<_CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<_CommentSheet> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _text.text.trim().isNotEmpty;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PrMarkdownComposer(
          controller: _text,
          autofocus: true,
          minLines: 5,
          onChanged: () => setState(() {}),
          footer: Row(children: [
            Text('Markdown supported', style: TS.meta(AppColors.fg4)),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TS.label(AppColors.fg3)),
            ),
            SizedBox(width: S.s4),
            FilledButton(
              onPressed: ready ? () => Navigator.of(context).pop(_text.text.trim()) : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentFill,
                foregroundColor: AppColors.accentFg,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kMobile ? R.pill : R.sm)),
              ),
              child: Text(widget.action, style: TS.label(AppColors.accentFg)),
            ),
          ]),
        ),
    ]);
  }
}

/// The push between pull request pages: the new page slides in from the
/// right over the old one, which drifts left and dims, and back reverses it.
class PrRoute<T> extends PageRoute<T> {
  PrRoute({required this.builder});
  final WidgetBuilder builder;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 320);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 260);
  @override
  bool get opaque => true;
  @override
  bool get maintainState => true;
  @override
  Color? get barrierColor => null;
  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      builder(context);

  @override
  Widget buildTransitions(
      BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final secondary = secondaryAnimation;
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    final incoming = CurvedAnimation(
        parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    final outgoing = CurvedAnimation(
        parent: secondary, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return SlideTransition(
      position: Tween(begin: Offset.zero, end: const Offset(-0.25, 0)).animate(outgoing),
      child: AnimatedBuilder(
        animation: outgoing,
        builder: (context, page) => Stack(children: [
          page!,
          if (outgoing.value > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.28 * outgoing.value)),
              ),
            ),
        ]),
        child: SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(incoming),
          child: DecoratedBox(
            decoration: BoxDecoration(boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24),
            ]),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// True once the page's push transition has had time to finish, so a heavy
/// body can wait for it and the slide stays smooth.
mixin _AfterTransition<W extends StatefulWidget> on State<W> {
  bool settled = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 340), () {
      if (mounted) setState(() => settled = true);
    });
  }
}

Widget _diffPlaceholder() => ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(S.s12, S.of(14), S.s12, 0),
      children: [
        for (var i = 0; i < 3; i++) ...[
          Container(
            height: 34,
            decoration: BoxDecoration(color: AppColors.tint1, borderRadius: BorderRadius.circular(R.sm)),
          ),
          SizedBox(height: S.s8),
          for (final w in const [0.7, 0.5, 0.85, 0.4, 0.6])
            Padding(
              padding: EdgeInsets.only(bottom: S.s8, left: S.of(46)),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: w,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(color: AppColors.tint1, borderRadius: BorderRadius.circular(R.of(3))),
                ),
              ),
            ),
          SizedBox(height: S.of(14)),
        ],
      ],
    );

/// Pending review comments and viewed files, kept for the life of the app so
/// leaving a pull request doesn't lose them.
final Map<String, List<PendingComment>> _pendingByPr = {};
final Map<String, Set<String>> _viewedByPr = {};

// ---------------------------------------------------------------------------
// Overview
// ---------------------------------------------------------------------------

class PullRequestScreen extends StatefulWidget {
  const PullRequestScreen({
    super.key,
    required this.client,
    required this.session,
    required this.number,
    required this.status,
  });

  final DaemonClient client;
  final String session;
  final int number;
  final GithubStatus status;

  @override
  State<PullRequestScreen> createState() => _PullRequestScreenState();
}

class _PullRequestScreenState extends State<PullRequestScreen> {
  PrDetail? _pr;
  late Future<String?> _diff = _fetchDiff();
  String? _diffOid;
  String? _error;
  bool _busy = false;
  bool _bodyOpen = false;
  bool _checksOpen = false;
  int _loadGen = 0;

  String get _key => '${widget.client.baseUrl}|${widget.session}|${widget.number}';
  List<PendingComment> get _pending => _pendingByPr.putIfAbsent(_key, () => []);
  Set<String> get _viewed => _viewedByPr.putIfAbsent(_key, () => {});

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String?> _fetchDiff() => widget.client
      .githubPrDiff(widget.session, widget.number)
      .then<String?>((d) => d)
      .catchError((_) => null);

  Future<void> _load() async {
    _diff;
    final gen = ++_loadGen;
    try {
      final pr = await widget.client.githubPr(widget.session, widget.number);
      if (!mounted || gen != _loadGen) return;
      setState(() {
        if (_diffOid != null && _diffOid != pr.headOid) _diff = _fetchDiff();
        _diffOid = pr.headOid;
        _pr = pr;
        _error = null;
      });
    } catch (e) {
      if (mounted && gen == _loadGen) setState(() => _error = '$e');
    }
  }

  bool get _open => _pr?.summary.state == 'OPEN';
  bool get _isAuthor => _pr?.summary.author == widget.status.viewer;

  Future<void> _openFiles({String? path}) async {
    final pr = _pr;
    if (pr == null) return;
    await Navigator.of(context).push(PrRoute<void>(
      builder: (_) => PrFilesScreen(
        client: widget.client,
        session: widget.session,
        number: widget.number,
        files: pr.files,
        diff: _diff,
        threads: pr.threads,
        pending: _pending,
        viewed: _viewed,
        canComment: _open,
        isAuthor: _isAuthor,
        onChanged: _load,
        scrollTo: path,
      ),
    ));
    if (mounted) setState(() {});
  }

  Future<void> _openCommits() async {
    final pr = _pr;
    if (pr == null) return;
    await Navigator.of(context).push(PrRoute<void>(
      builder: (_) => PrCommitsScreen(client: widget.client, session: widget.session, commits: pr.commits),
    ));
  }

  Future<void> _comment() async {
    final text = await showPrCommentSheet(context, title: 'Comment on #${widget.number}');
    if (text == null || text.trim().isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.client.commentOnPr(widget.session, widget.number, text.trim());
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review() async {
    final submitted = await submitPrReviewFlow(context,
        client: widget.client,
        session: widget.session,
        number: widget.number,
        pending: _pending,
        isAuthor: _isAuthor);
    if (submitted && mounted) {
      setState(() {});
      await _load();
    }
  }

  Future<void> _menu(BuildContext anchor) async {
    final s = _pr!.summary;
    final open = s.state == 'OPEN';
    final action = await showAppMenu<String>(
      context,
      anchor: anchor,
      minWidth: 230,
      items: [
        if (open && !s.draft)
          appMenuRow<String>(value: 'draft', icon: 'git-branch', label: 'Convert to draft'),
        if (open && s.draft)
          appMenuRow<String>(value: 'ready', icon: 'eye', label: 'Ready for review'),
        if (open) appMenuRow<String>(value: 'close', icon: 'x-circle', label: 'Close pull request'),
        if (s.state == 'CLOSED')
          appMenuRow<String>(value: 'reopen', icon: 'refresh', label: 'Reopen pull request'),
        appMenuRow<String>(value: 'github', icon: 'globe', label: 'Open on GitHub'),
      ],
    );
    if (action == null || !mounted) return;
    if (action == 'github') {
      launchUrl(Uri.parse(s.url), mode: LaunchMode.externalApplication);
      return;
    }
    if (action == 'close') {
      final ok = await confirmAction(context,
          title: 'Close #${s.number}?',
          body: 'It can be reopened later; the branch stays.',
          confirmLabel: 'Close pull request');
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await widget.client.prState(widget.session, widget.number, action);
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _stateBadge(PrSummary s) {
    final (label, icon, bg) = switch (s.state) {
      'MERGED' => ('Merged', 'git-commit', AppColors.accent),
      'CLOSED' => ('Closed', 'x-circle', AppColors.danger),
      _ => s.draft ? ('Draft', 'git-branch', AppColors.fg4) : ('Open', 'git-branch', AppColors.ok),
    };
    if (kMobile) {
      return Container(
        height: 28,
        padding: EdgeInsets.fromLTRB(S.of(9), 0, S.s12, 0),
        decoration: BoxDecoration(
            color: bg.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(R.pill)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AppIcon(icon, size: 13, color: bg),
          SizedBox(width: S.of(5)),
          Text(label, style: sans(13, color: bg)),
        ]),
      );
    }
    return Container(
      padding: EdgeInsets.fromLTRB(S.of(9), S.s4, S.of(11), S.s4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(R.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AppIcon(icon, size: 13, color: Colors.white),
        SizedBox(width: S.of(5)),
        Text(label, style: sans(13, weight: W.label, color: Colors.white)),
      ]),
    );
  }

  Widget _branch(String name) => kMobile
      ? Container(
          height: 28,
          padding: EdgeInsets.symmetric(horizontal: S.of(11)),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(R.pill),
          ),
          child: Center(
              widthFactor: 1,
              child: Text(name, style: mono(12, color: AppColors.fg2))),
        )
      : Container(
        padding: EdgeInsets.symmetric(horizontal: S.s8, vertical: S.of(3)),
        decoration: BoxDecoration(
          color: AppColors.accentBg,
          borderRadius: BorderRadius.circular(R.sm),
        ),
        child: Text(name, style: mono(12, color: AppColors.accent)),
      );

  Widget _section(String label) => kMobile
      ? Padding(
          padding: EdgeInsets.fromLTRB(S.s20, S.s24, S.s16, S.s8),
          child: Text(label, style: sans(13, weight: W.label, color: AppColors.fg3)),
        )
      : Container(
        width: double.infinity,
        margin: EdgeInsets.only(top: S.of(22)),
        padding: EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, S.s6),
        child: Text(label, style: sans(15, weight: W.strong, color: AppColors.fg1)),
      );

  Widget _row({
    String? icon,
    required Color ink,
    required String label,
    String detail = '',
    Widget? trailing,
    VoidCallback? onTap,
  }) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: S.s16, vertical: kMobile ? S.s8 : S.s12),
          child: Row(children: [
            if (icon == null)
              const SizedBox.shrink()
            else if (kMobile)
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: ink == AppColors.fg2 || ink == AppColors.fg3
                        ? AppColors.surface3
                        : ink.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(R.of(10))),
                child: AppIcon(icon, size: 16, color: ink),
              )
            else
              AppIcon(icon, size: 17, color: ink),
            if (icon != null) SizedBox(width: S.s12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: sans(kMobile ? 15 : 14, weight: W.label, color: AppColors.fg1)),
                if (detail.isNotEmpty) Text(detail, style: TS.meta(AppColors.fg3)),
              ]),
            ),
            if (trailing != null) trailing,
            if (trailing == null && onTap != null && kMobile)
              AppIcon('chevron-right', size: 14, color: AppColors.fg3),
          ]),
        ),
      );

  Widget _group(List<Widget> children) => kMobile
      ? Padding(
          padding: EdgeInsets.symmetric(horizontal: S.s16),
          child: CardGroupScope(child: ListGroup(children: children)),
        )
      : Column(children: children);

  List<Widget> _status(PrDetail pr) {
    final s = pr.summary;
    final reviewers = {
      for (final e in pr.timeline.where((e) => e.kind == PrEventKind.review)) e.author: e.reviewState
    };
    final approved = reviewers.entries.where((e) => e.value == 'APPROVED').map((e) => e.key).toList();
    final changes = reviewers.entries.where((e) => e.value == 'CHANGES_REQUESTED').map((e) => e.key).toList();
    final review = switch (s.reviewDecision) {
      'APPROVED' => ('check-circle', AppColors.ok, 'Approved', approved.isEmpty ? '' : 'by ${approved.join(', ')}'),
      'CHANGES_REQUESTED' => ('alert-circle', AppColors.danger, 'Changes requested', changes.isEmpty ? '' : 'by ${changes.join(', ')}'),
      'REVIEW_REQUIRED' => ('eye', AppColors.run, 'Review required', s.reviewers.isEmpty ? '' : 'Requested from ${s.reviewers.join(', ')}'),
      _ => ('eye', AppColors.fg3, reviewers.isEmpty ? 'No reviews yet' : '${reviewers.length} review${reviewers.length == 1 ? '' : 's'}', ''),
    };
    final checks = s.checks;
    final failing = checks.where((c) => c.state == ChecksState.failing).length;
    final pending = checks.where((c) => c.state == ChecksState.pending).length;
    final check = switch (rollup(checks)) {
      ChecksState.failing => ('x-circle', AppColors.danger, '$failing failing check${failing == 1 ? '' : 's'}'),
      ChecksState.pending => ('clock', AppColors.run, '$pending check${pending == 1 ? '' : 's'} running'),
      ChecksState.passing => ('check-circle', AppColors.ok, 'All checks have passed'),
      ChecksState.none => ('check-circle', AppColors.fg4, 'No checks'),
    };
    final merge = switch (pr.mergeState) {
      'CLEAN' || 'HAS_HOOKS' => ('check-circle', AppColors.ok, 'Ready to merge', 'No conflicts with ${s.base}'),
      'DIRTY' => ('alert-triangle', AppColors.danger, 'This branch has conflicts', 'Resolve them before merging'),
      'BEHIND' => ('alert-triangle', AppColors.run, 'Branch is out of date', 'Update it with ${s.base}'),
      'BLOCKED' => ('x-circle', AppColors.danger, 'Merging is blocked', 'Required reviews or checks are missing'),
      'UNSTABLE' => ('alert-triangle', AppColors.run, 'Some checks failed', 'It can still be merged'),
      'DRAFT' => ('git-branch', AppColors.fg3, 'Draft', 'Mark it ready before merging'),
      _ => ('clock', AppColors.fg3, 'Checking mergeability', ''),
    };
    return [
      if (_open && pr.autoMergeMethod.isEmpty && !s.draft)
        _row(icon: merge.$1, ink: merge.$2, label: merge.$3, detail: merge.$4),
      _row(
        icon: check.$1,
        ink: check.$2,
        label: check.$3,
        trailing: checks.isEmpty
            ? null
            : AppIcon(_checksOpen ? 'chevron-up' : (kMobile ? 'chevron-right' : 'chevron-down'), size: 14, color: AppColors.fg4),
        onTap: checks.isEmpty ? null : () => setState(() => _checksOpen = !_checksOpen),
      ),
      if (_checksOpen)
        for (final c in checks)
          InkWell(
            onTap: c.url.isEmpty
                ? null
                : () => launchUrl(Uri.parse(c.url), mode: LaunchMode.externalApplication),
            child: Padding(
              padding: EdgeInsets.fromLTRB(S.of(45), S.s6, S.s16, S.s6),
              child: Row(children: [
                AppIcon(
                    switch (c.state) {
                      ChecksState.failing => 'x-circle',
                      ChecksState.pending => 'clock',
                      _ => 'check-circle',
                    },
                    size: 13,
                    color: switch (c.state) {
                      ChecksState.failing => AppColors.danger,
                      ChecksState.pending => AppColors.run,
                      _ => AppColors.ok,
                    }),
                SizedBox(width: S.s8),
                Expanded(
                  child: Text(c.workflow.isEmpty ? c.name : '${c.workflow} / ${c.name}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TS.ui(AppColors.fg2)),
                ),
              ]),
            ),
          ),
      _row(icon: review.$1, ink: review.$2, label: review.$3, detail: review.$4),
    ];
  }

  Widget _mergeBox(PrDetail pr) => PrMergeBox(
        client: widget.client,
        session: widget.session,
        pr: pr,
        status: widget.status,
        onDone: _load,
      );

  Widget _timeline(PrDetail pr) {
    final threadsByReview = <String, List<PrThread>>{};
    for (final t in pr.threads) {
      final id = t.comments.isEmpty ? '' : t.comments.first.reviewId;
      if (id.isNotEmpty) threadsByReview.putIfAbsent(id, () => []).add(t);
    }
    final items = <Widget>[];
    for (final e in pr.timeline) {
      switch (e.kind) {
        case PrEventKind.commit:
          items.add(_node(
            icon: 'git-commit',
            child: Row(children: [
              prAvatar(e.author, size: 18),
              SizedBox(width: S.s8),
              Expanded(
                child: Text(e.body,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(12, color: AppColors.fg2)),
              ),
              SizedBox(width: S.s8),
              Text(e.sha.length > 7 ? e.sha.substring(0, 7) : e.sha, style: mono(11, color: AppColors.fg4)),
            ]),
          ));
        case PrEventKind.review:
          final (verb, icon, ink) = switch (e.reviewState) {
            'APPROVED' => ('approved these changes', 'check-circle', AppColors.ok),
            'CHANGES_REQUESTED' => ('requested changes', 'alert-circle', AppColors.danger),
            'DISMISSED' => ('had a review dismissed', 'x-circle', AppColors.fg4),
            _ => ('reviewed these changes', 'eye', AppColors.fg3),
          };
          final threads = threadsByReview[e.reviewId] ?? const [];
          items.add(_node(
            icon: icon,
            ink: ink,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: e.author, style: sans(13, weight: W.label, color: AppColors.fg1)),
                TextSpan(text: ' $verb', style: sans(13, color: AppColors.fg2)),
                TextSpan(text: ' · ${prAgo(e.at)}', style: TS.meta(AppColors.fg4)),
              ])),
              if (e.body.trim().isNotEmpty) ...[
                SizedBox(height: S.s8),
                _card(PrCommentBody(e.body)),
              ],
              if (threads.isNotEmpty) ...[
                SizedBox(height: S.s8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => _openFiles(path: threads.first.path),
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.tint1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kMobile ? R.pill : R.sm)),
                    ),
                    child: Text('${threads.length} comment${threads.length == 1 ? '' : 's'}',
                        style: sans(13, weight: W.label, color: AppColors.accent)),
                  ),
                ),
              ],
            ]),
          ));
        case PrEventKind.comment:
          items.add(_node(
            avatar: e.author,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: e.author, style: sans(13, weight: W.label, color: AppColors.fg1)),
                TextSpan(text: ' · ${prAgo(e.at)}', style: TS.meta(AppColors.fg4)),
              ])),
              SizedBox(height: S.s6),
              _card(PrCommentBody(e.body)),
            ]),
          ));
      }
    }
    if (items.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(S.s16, S.s4, S.s16, S.s8),
        child: Text('No activity yet.', style: TS.meta(AppColors.fg4)),
      );
    }
    return Column(children: items);
  }

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: EdgeInsets.only(top: S.s2),
        child: child,
      );

  Widget _node({String? icon, Color? ink, String? avatar, required Widget child}) {
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 44,
          child: Stack(alignment: Alignment.topCenter, children: [
            Positioned.fill(
              child: Center(child: Container(width: 1.5, color: AppColors.border)),
            ),
            Padding(
              padding: EdgeInsets.only(top: S.of(10)),
              child: avatar != null
                  ? prAvatar(avatar, size: 24)
                  : Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.tint2,
                        shape: BoxShape.circle,
                      ),
                      child: AppIcon(icon ?? 'git-commit', size: 12, color: ink ?? AppColors.fg3),
                    ),
            ),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(S.s4, S.s12, S.s16, S.of(10)),
            child: child,
          ),
        ),
      ]),
    );
  }

  Widget _body(PrDetail pr) {
    final text = pr.body.trim();
    if (text.isEmpty) return Text('No description provided.', style: TS.meta(AppColors.fg4));
    final long = text.length > 700 || '\n'.allMatches(text).length > 14;
    final content = PrCommentBody(text);
    if (!long || _bodyOpen) return content;
    return Stack(children: [
      SizedBox(height: 220, child: ClipRect(child: OverflowBox(
        alignment: Alignment.topCenter,
        maxHeight: double.infinity,
        child: content,
      ))),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: 90,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.paneBg.withValues(alpha: 0), AppColors.paneBg],
            ),
          ),
          alignment: Alignment.bottomCenter,
          child: TextButton.icon(
            onPressed: () => setState(() => _bodyOpen = true),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.tint2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.pill)),
            ),
            icon: AppIcon('chevron-down', size: 14, color: AppColors.fg1),
            label: Text('Read more', style: sans(13, weight: W.label, color: AppColors.fg1)),
          ),
        ),
      ),
    ]);
  }

  Widget _overview(PrDetail pr) {
    final s = pr.summary;
    final lastCommit = pr.commits.isEmpty ? '' : prAgo(pr.commits.last.date);
    final openedBy = Row(children: [
      prAvatar(s.author, size: kMobile ? 28 : 32),
      SizedBox(width: S.of(10)),
      Expanded(
        child: Text.rich(TextSpan(children: [
          TextSpan(text: s.author, style: sans(14, weight: W.label, color: AppColors.fg1)),
          TextSpan(
              text: kMobile ? ' opened this · ${prAgo(pr.createdAt)}' : ' · opened ${prAgo(pr.createdAt)}',
              style: TS.meta(AppColors.fg3)),
        ])),
      ),
    ]);
    // The phone's Changes card reads as plain rows, as the mockup draws it.
    final files = _row(
      icon: kMobile ? null : 'file-code',
      ink: AppColors.fg2,
      label: '${pr.files.length} file${pr.files.length == 1 ? '' : 's'}${kMobile ? '' : ' changed'}',
      detail: [
        if (kMobile) '+${s.additions} −${s.deletions}',
        if (_pending.isNotEmpty) '${_pending.length} pending comment${_pending.length == 1 ? '' : 's'}',
      ].join(' · '),
      trailing: kMobile ? null : prSize(s.additions, s.deletions, size: 13),
      onTap: _openFiles,
    );
    final commits = _row(
      icon: kMobile ? null : 'git-commit',
      ink: AppColors.fg2,
      label: '${pr.commits.length} commit${pr.commits.length == 1 ? '' : 's'}',
      trailing: kMobile ? null : Text(lastCommit, style: TS.meta(AppColors.fg3)),
      onTap: _openCommits,
    );
    return ListView(
      padding: EdgeInsets.only(bottom: kMobile ? S.s24 : 96),
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(S.s16, S.s16, S.s16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.title,
                style: sans(kMobile ? 17 : 20, weight: W.strong, height: 1.25, color: AppColors.fg1)),
            SizedBox(height: S.s12),
            if (kMobile)
              Row(children: [
                _stateBadge(s),
                SizedBox(width: S.s8),
                Expanded(
                  child: Text('${s.head} → ${s.base}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: codeMono(12, color: AppColors.fg3)),
                ),
              ])
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _stateBadge(s),
                  _branch(s.head),
                  AppIcon('arrow-right', size: 14, color: AppColors.fg4),
                  _branch(s.base),
                ],
              ),
              SizedBox(height: S.of(18)),
              openedBy,
              SizedBox(height: S.s12),
              _body(pr),
            ],
          ]),
        ),
        if (kMobile) ...[
          _section('Status'),
          _group(_status(pr)),
          if (_open) _mergeBox(pr),
          _section('Changes'),
          _group([files, commits]),
          _section('Conversation'),
          Padding(
            padding: EdgeInsets.fromLTRB(S.s16, 0, S.s16, S.s8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              openedBy,
              SizedBox(height: S.s8),
              Container(
                width: double.infinity,
                margin: EdgeInsets.only(left: S.of(38)),
                padding: EdgeInsets.all(S.s12),
                decoration: BoxDecoration(
                  color: AppColors.surface1,
                  borderRadius: BorderRadius.circular(R.of(14)),
                  border: Border.all(color: AppColors.line),
                ),
                child: _body(pr),
              ),
            ]),
          ),
          _timeline(pr),
        ] else ...[
          _section('Changes'),
          files,
          commits,
          _section('Status'),
          ..._status(pr),
          if (_open) _mergeBox(pr),
          _section('Conversation'),
          _timeline(pr),
        ],
      ],
    );
  }

  Widget _dockedBar() {
    final pending = _pending.length;
    return Container(
      color: AppColors.paneBg,
      padding: EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, S.of(10 ) + MediaQuery.of(context).padding.bottom),
      child: Row(children: [
        Expanded(
          child: Btn('Comment',
              icon: 'message',
              variant: BtnVariant.surface,
              full: true,
              disabled: _busy,
              onTap: _comment),
        ),
        SizedBox(width: S.of(10)),
        Expanded(
          child: Btn(pending == 0 ? 'Review' : 'Finish review ($pending)',
              icon: 'check-circle',
              full: true,
              disabled: _busy,
              onTap: _review),
        ),
      ]),
    );
  }

  Widget _floatingBar() {
    final pending = _pending.length;
    return Positioned(
      right: 16,
      bottom: 16 + MediaQuery.of(context).padding.bottom,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _pill(
          icon: 'message',
          label: 'Comment',
          onTap: _busy ? null : _comment,
        ),
        SizedBox(width: S.s8),
        _pill(
          icon: 'check-circle',
          label: pending == 0 ? 'Review' : 'Finish review ($pending)',
          primary: true,
          onTap: _busy ? null : _review,
        ),
      ]),
    );
  }

  Widget _pill({required String icon, required String label, VoidCallback? onTap, bool primary = false}) =>
      Material(
        color: primary ? AppColors.accentFill : AppColors.tint2,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.pill),
          side: primary ? BorderSide.none : BorderSide(color: AppColors.border2),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.pill)),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: S.s16, vertical: S.of(11)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon(icon, size: 15, color: primary ? AppColors.accentFg : AppColors.fg1),
              SizedBox(width: S.of(7)),
              Text(label,
                  style: sans(13, weight: W.label, color: primary ? AppColors.accentFg : AppColors.fg1)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final pr = _pr;
    return Material(
      color: AppColors.paneBg,
      child: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (kMobile)
            MobileBackBar(
              title: '#${widget.number}',
              onBack: () => Navigator.maybePop(context),
              trailing: [
                Builder(
                  builder: (anchor) => RoundBtn(
                      icon: 'more-horizontal',
                      tooltip: 'More',
                      onTap: pr == null || _busy ? null : () => _menu(anchor)),
                ),
              ],
            )
          else
          prHeader(context,
              title: '#${widget.number}',
              subtitle: pr?.summary.title ?? '',
              actions: [
                if (pr != null)
                  Builder(
                    builder: (anchor) => IconBtn('more-horizontal',
                        size: kMobile ? M.minTarget : 32,
                        iconSize: 16,
                        tooltip: 'More',
                        onTap: _busy ? null : () => _menu(anchor)),
                  ),
              ]),
          Expanded(
            child: _error != null
                ? prMessage(_error!)
                : pr == null
                    ? Center(child: Spinner(size: 16, color: AppColors.fg3))
                    : kMobile
                        ? RefreshIndicator(onRefresh: _load, child: _overview(pr))
                        : Stack(children: [
                            Positioned.fill(
                              child: RefreshIndicator(onRefresh: _load, child: _overview(pr)),
                            ),
                            if (_open) _floatingBar(),
                          ]),
          ),
          if (kMobile && pr != null && _open) _dockedBar(),
        ]),
      ),
    );
  }
}

/// GitHub's merge box: the methods the repo allows as a split button, a
/// confirm step with the commit title and message and branch deletion,
/// auto-merge when requirements aren't met yet, an admin bypass, updating an
/// out-of-date branch, and marking a draft ready.
class PrMergeBox extends StatefulWidget {
  const PrMergeBox({
    super.key,
    required this.client,
    required this.session,
    required this.pr,
    required this.status,
    required this.onDone,
    this.padding ,
  });

  final EdgeInsets ? padding;
  final DaemonClient client;
  final String session;
  final PrDetail pr;
  final GithubStatus status;
  final Future<void> Function() onDone;

  @override
  State<PrMergeBox> createState() => _PrMergeBoxState();
}

class _PrMergeBoxState extends State<PrMergeBox> {
  static const _order = ['merge', 'squash', 'rebase'];
  late String _method = _order.firstWhere(widget.status.mergeMethods.contains, orElse: () => 'merge');
  bool _confirming = false;
  bool _admin = false;
  bool _busy = false;
  late bool _deleteBranch = widget.status.deleteBranchOnMerge;
  final _subject = TextEditingController();
  final _body = TextEditingController();

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  PrSummary get _s => widget.pr.summary;

  String _label(String m) => switch (m) {
        'squash' => 'Squash and merge',
        'rebase' => 'Rebase and merge',
        _ => 'Create a merge commit',
      };

  String _short(String m) => switch (m) {
        'squash' => 'squash',
        'rebase' => 'rebase',
        _ => 'merge commit',
      };

  bool get _ready => const {'CLEAN', 'HAS_HOOKS', 'UNSTABLE'}.contains(widget.pr.mergeState);

  void _prefill() {
    final owner = widget.status.repo.split('/').first;
    switch (_method) {
      case 'squash':
        _subject.text = '${_s.title} (#${_s.number})';
        _body.text = [for (final c in widget.pr.commits) '* ${c.headline}'].join('\n');
      case 'merge':
        _subject.text = 'Merge pull request #${_s.number} from $owner/${_s.head}';
        _body.text = _s.title;
      default:
        _subject.clear();
        _body.clear();
    }
  }

  Future<void> _pickMethod(BuildContext anchor) async {
    final picked = await showAppMenu<String>(
      context,
      anchor: anchor,
      minWidth: 300,
      items: [
        for (final m in _order)
          if (widget.status.mergeMethods.contains(m))
            appMenuRow<String>(
              value: m,
              icon: switch (m) {
                'squash' => 'minimize',
                'rebase' => 'git-branch',
                _ => 'git-commit',
              },
              label: _label(m),
              description: switch (m) {
                'squash' => 'The ${widget.pr.commits.length} commits are combined into one on ${_s.base}',
                'rebase' => 'The commits are rebased and added to ${_s.base}',
                _ => 'All commits are added to ${_s.base} with a merge commit',
              },
              selected: m == _method,
            ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() {
      _method = picked;
      if (_confirming) _prefill();
    });
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      toast(context, done);
      setState(() => _confirming = false);
      await widget.onDone();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _merge() => _run(
        () => widget.client.mergePr(widget.session, _s.number,
            method: _method,
            subject: _method == 'rebase' ? null : _subject.text,
            body: _method == 'rebase' ? null : _body.text,
            head: widget.pr.headOid.isEmpty ? null : widget.pr.headOid,
            admin: _admin && !_ready,
            deleteBranch: _deleteBranch,
            branch: _s.head),
        'Merged #${_s.number}',
      );

  Future<void> _enableAuto() => _run(
        () => widget.client.mergePr(widget.session, _s.number,
            method: _method,
            subject: _method == 'rebase' ? null : _subject.text,
            body: _method == 'rebase' ? null : _body.text,
            head: widget.pr.headOid.isEmpty ? null : widget.pr.headOid,
            auto: true),
        'Auto-merge enabled',
      );

  Future<void> _update(BuildContext anchor) async {
    final how = await showAppMenu<String>(
      context,
      anchor: anchor,
      minWidth: 260,
      items: [
        appMenuRow<String>(
            value: 'update', icon: 'git-commit', label: 'Update with merge commit', description: 'Merge ${_s.base} into ${_s.head}'),
        appMenuRow<String>(
            value: 'update_rebase', icon: 'git-branch', label: 'Update with rebase', description: 'Rebase ${_s.head} onto ${_s.base}'),
      ],
    );
    if (how == null || !mounted) return;
    await _run(() => widget.client.prState(widget.session, _s.number, how), 'Branch updated');
  }

  Widget _mergeButton({required String label, required VoidCallback? onTap}) {
    final enabled = onTap != null && !_busy;
    if (widget.status.mergeMethods.length > 1) {
      final r = Radius.circular(kMobile ? R.of(12) : R.md);
      final h = kMobile ? 40.0 : 32.0;
      return Builder(
        builder: (anchor) => Row(children: [
          Expanded(
            child: Material(
              color: enabled ? AppColors.accentFill : AppColors.tint2,
              borderRadius: BorderRadius.horizontal(left: r),
              child: InkWell(
                onTap: enabled ? onTap : null,
                child: Container(
                  height: h,
                  alignment: Alignment.center,
                  child: Text(label,
                      style: sans(14, weight: W.label, color: enabled ? AppColors.accentFg : AppColors.fg4)),
                ),
              ),
            ),
          ),
          SizedBox(width: S.of(2)),
          Material(
            color: enabled ? AppColors.accentFill : AppColors.tint2,
            borderRadius: BorderRadius.horizontal(right: r),
            child: InkWell(
              onTap: _busy ? null : () => _pickMethod(anchor),
              child: SizedBox(
                width: kMobile ? 44 : 32,
                height: h,
                child: Center(
                    child: AppIcon('chevron-down',
                        size: 16, color: enabled ? AppColors.accentFg : AppColors.fg4)),
              ),
            ),
          ),
        ]),
      );
    }
    return Builder(
      builder: (anchor) => GestureDetector(
        onSecondaryTap: _busy ? null : () => _pickMethod(anchor),
        child: Material(
          color: enabled ? AppColors.accentFill : AppColors.tint2,
          borderRadius: BorderRadius.circular(kMobile ? R.pill : R.md),
          child: InkWell(
            onTap: enabled ? onTap : null,
            onLongPress: _busy
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    _pickMethod(anchor);
                  },
            borderRadius: BorderRadius.circular(kMobile ? R.pill : R.md),
            child: Container(
              height: kMobile ? 44 : 32,
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(horizontal: S.of(14)),
              child: Text(label,
                  style: sans(14, weight: W.strong, color: enabled ? AppColors.accentFg : AppColors.fg4)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, {int lines = 1}) => TextField(
        controller: c,
        minLines: lines,
        maxLines: lines == 1 ? 1 : 10,
        style: lines == 1 ? sans(14, weight: W.label, color: AppColors.fg1) : mono(13, height: 1.5, color: AppColors.fg1),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TS.body(AppColors.fg4),
          isDense: true,
          filled: true,
          fillColor: AppColors.tint2,
          contentPadding: EdgeInsets.fromLTRB(S.s12, S.of(10), S.s12, S.of(10)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.border2)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.border2)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.accent)),
        ),
      );

  Widget _check(bool value, String label, ValueChanged<bool> onChanged) => InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: S.s4),
          child: Row(children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: AppColors.accent,
                side: BorderSide(color: AppColors.fg4, width: 1.5),
              ),
            ),
            SizedBox(width: S.s8),
            Expanded(child: Text(label, style: sans(13, color: AppColors.fg2))),
          ]),
        ),
      );

  Widget _notice(String icon, Color ink, String title, String detail, {List<Widget> actions = const []}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AppIcon(icon, size: 17, color: ink),
            SizedBox(width: S.of(10)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: sans(14, weight: W.label, color: AppColors.fg1)),
                if (detail.isNotEmpty) ...[
                  SizedBox(height: S.s2),
                  Text(detail, style: sans(13, height: 1.4, color: AppColors.fg3)),
                ],
              ]),
            ),
          ]),
          if (actions.isNotEmpty) ...[
            SizedBox(height: S.s12),
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) SizedBox(height: S.s8),
              actions[i],
            ],
          ],
        ],
      );

  Widget _secondary(String label, VoidCallback? onTap) => TextButton(
        onPressed: _busy ? null : onTap,
        style: TextButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          backgroundColor: AppColors.tint2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kMobile ? R.pill : R.md)),
          padding: EdgeInsets.symmetric(horizontal: S.of(14)),
        ),
        child: Text(label, style: sans(13, weight: W.label, color: AppColors.fg1)),
      );

  Widget _content() {
    final pr = widget.pr;
    if (pr.autoMergeMethod.isNotEmpty) {
      final how = switch (pr.autoMergeMethod) {
        'SQUASH' => 'squash',
        'REBASE' => 'rebase',
        _ => 'merge commit',
      };
      return _notice('git-commit', AppColors.accent, 'Auto-merge enabled',
          'Merges with a $how once every requirement is met${pr.autoMergeBy.isEmpty ? '' : ' · enabled by ${pr.autoMergeBy}'}',
          actions: [
            _secondary('Disable auto-merge',
                () => _run(() => widget.client.mergePr(widget.session, _s.number, disableAuto: true), 'Auto-merge disabled')),
          ]);
    }
    if (_s.draft) {
      return _notice('git-branch', AppColors.fg3, 'This pull request is still a draft',
          'It can be merged once it is marked ready for review.',
          actions: [
            _secondary('Ready for review',
                () => _run(() => widget.client.prState(widget.session, _s.number, 'ready'), 'Marked ready for review')),
          ]);
    }
    if (pr.mergeState == 'DIRTY') {
      return _notice('alert-triangle', AppColors.danger, 'This branch has conflicts that must be resolved',
          'Resolve them locally or on GitHub, then push.',
          actions: [
            _secondary('Resolve on GitHub',
                () => launchUrl(Uri.parse('${_s.url}/conflicts'), mode: LaunchMode.externalApplication)),
          ]);
    }
    final children = <Widget>[];
    if (pr.mergeState == 'BEHIND') {
      children.add(_notice('alert-triangle', AppColors.run, 'This branch is out of date with ${_s.base}',
          'Update it so the merge uses the latest ${_s.base}.',
          actions: [Builder(builder: (anchor) => _secondary('Update branch', () => _update(anchor)))]));
      children.add(SizedBox(height: S.of(14)));
    }
    final blocked = !_ready;
    if (_confirming) {
      children.addAll([
        Text(_label(_method), style: sans(14, weight: W.strong, color: AppColors.fg1)),
        SizedBox(height: S.of(10)),
        if (_method == 'rebase')
          Text('The ${pr.commits.length} commit${pr.commits.length == 1 ? '' : 's'} from ${_s.head} will be rebased onto ${_s.base}.',
              style: sans(13, height: 1.4, color: AppColors.fg3))
        else ...[
          _field(_subject, 'Commit message'),
          SizedBox(height: S.s8),
          _field(_body, 'Extended description', lines: 4),
        ],
        SizedBox(height: S.s8),
        _check(_deleteBranch, 'Delete ${_s.head} after merging', (v) => setState(() => _deleteBranch = v)),
        if (blocked && widget.status.isAdmin)
          _check(_admin, 'Merge without waiting for requirements to be met (bypass branch protections)',
              (v) => setState(() => _admin = v)),
        SizedBox(height: S.s12),
        if (blocked && widget.status.autoMerge && !_admin)
          FilledButton(
            onPressed: _busy ? null : _enableAuto,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              backgroundColor: AppColors.accentFill,
              foregroundColor: AppColors.accentFg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kMobile ? R.pill : R.md)),
            ),
            child: Text('Enable auto-merge', style: sans(14, weight: W.label, color: AppColors.accentFg)),
          )
        else
          FilledButton(
            onPressed: _busy || (blocked && !_admin) ? null : _merge,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              backgroundColor: AppColors.accentFill,
              foregroundColor: AppColors.accentFg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kMobile ? R.pill : R.md)),
            ),
            child: Text('Confirm ${_short(_method)}', style: sans(14, weight: W.label, color: AppColors.accentFg)),
          ),
        SizedBox(height: S.s6),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(40)),
          onPressed: _busy ? null : () => setState(() => _confirming = false),
          child: Text('Cancel', style: sans(13, weight: W.label, color: AppColors.fg3)),
        ),
      ]);
    } else {
      final canMerge = _ready || widget.status.isAdmin;
      final canAuto = blocked && widget.status.autoMerge;
      children.add(_mergeButton(
        label: canAuto && !widget.status.isAdmin ? 'Enable auto-merge' : _label(_method),
        onTap: canMerge || canAuto
            ? () => setState(() {
                  _prefill();
                  _confirming = true;
                })
            : null,
      ));
      children.add(SizedBox(height: S.s8));
      children.add(Text(
        blocked
            ? (widget.status.isAdmin
                ? 'Requirements aren\'t met; as an admin you can still merge. Long-press to choose the method.'
                : canAuto
                    ? 'It will merge with a ${_short(_method)} once requirements are met.'
                    : 'Merging is disabled until requirements are met.')
            : 'Merges with a ${_short(_method)} into ${_s.base}.${''}',
        style: TS.meta(AppColors.fg4),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding?? EdgeInsets.fromLTRB(S.s16, S.s6, S.s16, S.of(10)),
      child: _content(),
    );
  }
}

/// Review submission shared by the overview and the files page.
Future<bool> submitPrReviewFlow(
  BuildContext context, {
  required DaemonClient client,
  required String session,
  required int number,
  required List<PendingComment> pending,
  required bool isAuthor,
}) async {
  final result = await showAppSheet<(String, String)>(context,
      title: 'Finish your review',
      maxWidth: 520,
      maxHeight: 700,
      child: _ReviewSheet(pendingCount: pending.length, isAuthor: isAuthor));
  if (result == null || !context.mounted) return false;
  try {
    await client.submitPrReview(session, number,
        event: result.$1, body: result.$2, comments: List.of(pending));
    pending.clear();
    if (context.mounted) toast(context, 'Review submitted');
    return true;
  } catch (e) {
    if (context.mounted) toast(context, '$e', danger: true);
    return false;
  }
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.pendingCount, required this.isAuthor});
  final int pendingCount;
  final bool isAuthor;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  final _body = TextEditingController();
  String _event = 'COMMENT';

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  bool get _canSubmit => _event == 'APPROVE' || _body.text.trim().isNotEmpty || widget.pendingCount > 0;

  Widget _option(String event, String label, String detail, {bool enabled = true}) {
    final selected = _event == event;
    return InkWell(
      onTap: enabled ? () => setState(() => _event = event) : null,
      borderRadius: BorderRadius.circular(R.card),
      child: Container(
        margin: EdgeInsets.only(bottom: S.s8),
        padding: EdgeInsets.fromLTRB(S.s12, S.of(10), S.s12, S.of(10)),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentBg : Colors.transparent,
          borderRadius: BorderRadius.circular(R.card),
        ),
        child: Row(children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: selected ? AppColors.accent : AppColors.fg4, width: selected ? 5 : 1.5),
            ),
          ),
          SizedBox(width: S.s12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TS.rowTitle(enabled ? AppColors.fg1 : AppColors.fg4)),
              Text(detail, style: TS.meta(AppColors.fg3)),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.pendingCount > 0) ...[
            Text('${widget.pendingCount} line comment${widget.pendingCount == 1 ? '' : 's'} will be posted with it',
                style: TS.meta(AppColors.accent)),
            SizedBox(height: S.of(14)),
          ],
          PrMarkdownComposer(
            controller: _body,
            hint: 'Leave a summary',
            onChanged: () => setState(() {}),
          ),
          SizedBox(height: S.of(14)),
          _option('COMMENT', 'Comment', 'Feedback without approving'),
          _option('APPROVE', 'Approve',
              widget.isAuthor ? "You can't approve your own pull request" : 'Approve these changes',
              enabled: !widget.isAuthor),
          _option('REQUEST_CHANGES', 'Request changes',
              widget.isAuthor ? "You can't request changes on your own pull request" : 'Feedback that must be addressed',
              enabled: !widget.isAuthor),
          SizedBox(height: S.s6),
          FilledButton(
            onPressed: _canSubmit ? () => Navigator.of(context).pop((_event, _body.text.trim())) : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              backgroundColor: AppColors.accentFill,
              foregroundColor: AppColors.accentFg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kMobile ? R.pill : R.sm)),
            ),
            child: Text('Submit review', style: TS.label(AppColors.accentFg)),
          ),
        ],
    );
  }
}

// ---------------------------------------------------------------------------
// Files changed
// ---------------------------------------------------------------------------

class PrFilesScreen extends StatefulWidget {
  const PrFilesScreen({
    super.key,
    required this.client,
    required this.session,
    required this.number,
    required this.files,
    required this.diff,
    required this.threads,
    required this.pending,
    required this.viewed,
    required this.canComment,
    required this.isAuthor,
    required this.onChanged,
    this.scrollTo,
  });

  final DaemonClient client;
  final String session;
  final int number;
  final List<PrFile> files;
  final Future<String?> diff;
  final List<PrThread> threads;
  final List<PendingComment> pending;
  final Set<String> viewed;
  final bool canComment;
  final bool isAuthor;
  final Future<void> Function() onChanged;
  final String? scrollTo;

  @override
  State<PrFilesScreen> createState() => _PrFilesScreenState();
}

class _PrFilesScreenState extends State<PrFilesScreen> with _AfterTransition {
  Map<String, List<DiffLine>>? _parsed;
  bool _diffFailed = false;
  late List<PrThread> _threads = widget.threads;
  final Map<String, GlobalKey> _fileKeys = {};

  bool get _ready => settled && _parsed != null;

  @override
  void initState() {
    super.initState();
    widget.diff.then((d) {
      if (!mounted) return;
      setState(() {
        _parsed = parseUnifiedDiff(d ?? '');
        _diffFailed = d == null;
      });
    });
  }

  @override
  void setState(VoidCallback fn) {
    final wasReady = _ready;
    super.setState(fn);
    if (!wasReady && _ready && widget.scrollTo != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jump(widget.scrollTo!));
    }
  }

  void _jump(String path) {
    prReveal(_fileKeys[path]);
  }

  Future<void> _refreshThreads() async {
    await widget.onChanged();
    try {
      final pr = await widget.client.githubPr(widget.session, widget.number);
      if (mounted) setState(() => _threads = pr.threads);
    } catch (_) {}
  }

  Future<void> _finish() async {
    final submitted = await submitPrReviewFlow(context,
        client: widget.client,
        session: widget.session,
        number: widget.number,
        pending: widget.pending,
        isAuthor: widget.isAuthor);
    if (submitted && mounted) {
      setState(() {});
      await _refreshThreads();
    }
  }

  Future<void> _jumpMenu(BuildContext anchor) async {
    final path = await showAppMenu<String>(
      context,
      anchor: anchor,
      minWidth: 280,
      items: [
        appMenuHeading<String>('Jump to file'),
        for (final f in widget.files)
          appMenuRow<String>(
            value: f.path,
            icon: widget.viewed.contains(f.path) ? 'check-circle' : 'file-code',
            label: f.path.split('/').last,
            description: f.path,
          ),
      ],
    );
    if (path != null) _jump(path);
  }

  Widget _statsPill(int adds, int dels, int viewed) {
    final total = widget.files.length;
    final progress = total == 0 ? 0.0 : viewed / total;
    final done = viewed == total && total > 0;
    final pending = widget.pending.length;
    return Center(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.pill),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: Material(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.pill),
          clipBehavior: Clip.antiAlias,
          child: Padding(
              padding: EdgeInsets.fromLTRB(S.s16, S.of(5), pending > 0 ? S.of(5 ) : S.s16, S.of(5)),
              child: Row(mainAxisSize: pending > 0 ? MainAxisSize.max : MainAxisSize.min, children: [
                prSize(adds, dels, size: 13),
                Container(
                  width: 1,
                  height: 14,
                  margin: EdgeInsets.symmetric(horizontal: S.of(10)),
                  color: AppColors.fg4.withValues(alpha: 0.5),
                ),
                if (done)
                  AppIcon('check-circle', size: 15, color: AppColors.ok)
                else
                  SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 2.2,
                      color: AppColors.accent,
                      backgroundColor: AppColors.fg4.withValues(alpha: 0.35),
                    ),
                  ),
                SizedBox(width: S.of(7)),
                if (pending > 0)
                  Expanded(
                    child: Text('$viewed/$total viewed',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(13, weight: W.label, color: AppColors.fg2)),
                  )
                else
                  Text('$viewed/$total viewed', style: sans(13, weight: W.label, color: AppColors.fg2)),
                if (pending > 0)
                  Material(
                    color: AppColors.accentFill,
                    borderRadius: BorderRadius.circular(R.pill),
                    child: InkWell(
                      onTap: _finish,
                      borderRadius: BorderRadius.circular(R.pill),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: S.of(14), vertical: S.of(9)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          AppIcon('check-circle', size: 14, color: AppColors.accentFg),
                          SizedBox(width: S.s6),
                          Text('Finish review ($pending)',
                              style: sans(13, weight: W.label, color: AppColors.accentFg)),
                        ]),
                      ),
                    ),
                  )
                else
                  SizedBox(height: S.of(36)),
              ]),
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _fileTree() {
    return ListView(padding: EdgeInsets.symmetric(vertical: S.s6), children: [
      for (final f in widget.files)
        InkWell(
          onTap: () => _jump(f.path),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: S.s12, vertical: S.of(7)),
            child: Row(children: [
              AppIcon(widget.viewed.contains(f.path) ? 'check-circle' : 'file-code',
                  size: 13, color: widget.viewed.contains(f.path) ? AppColors.ok : AppColors.fg3),
              SizedBox(width: S.s8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.path.split('/').last,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(12, color: AppColors.fg1)),
                  if (f.path.contains('/'))
                    Text(f.path.substring(0, f.path.lastIndexOf('/')),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TS.meta(AppColors.fg4)),
                ]),
              ),
              if (widget.pending.any((c) => c.path == f.path)) ...[
                AppIcon('message', size: 11, color: AppColors.accent),
                SizedBox(width: S.s6),
              ],
              prSize(f.additions, f.deletions, size: 11),
            ]),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final adds = widget.files.fold<int>(0, (a, f) => a + f.additions);
    final dels = widget.files.fold<int>(0, (a, f) => a + f.deletions);
    final viewed = widget.files.where((f) => widget.viewed.contains(f.path)).length;
    final diff = CustomScrollView(
      slivers: [
        if (_diffFailed)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(S.s16),
              child: Text("Couldn't load the diff for this pull request.",
                  style: sans(13, color: AppColors.fg3)),
            ),
          ),
        for (final f in widget.files)
          KeyedSubtree(
            key: _fileKeys.putIfAbsent(f.path, () => GlobalKey()),
            child: PrFileDiff(
              file: f,
              lines: _parsed?[f.path] ?? const [],
              startCollapsed: prStartCollapsed(widget.files) &&
                  f.path != widget.scrollTo,
              threads: _threads.where((t) => t.path == f.path).toList(),
              pending: widget.pending,
              viewed: widget.viewed.contains(f.path),
              onViewed: (v) => setState(() => v ? widget.viewed.add(f.path) : widget.viewed.remove(f.path)),
              canComment: widget.canComment,
              client: widget.client,
              session: widget.session,
              number: widget.number,
              onPendingChanged: () => setState(() {}),
              onThreadsChanged: _refreshThreads,
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
    return Material(
      color: AppColors.paneBg,
      child: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          prHeader(context,
              title: 'Files changed',
              actions: [
                if (kMobile)
                  Builder(
                    builder: (anchor) => RoundBtn(
                        icon: 'folder-open', tooltip: 'Jump to file', onTap: () => _jumpMenu(anchor)),
                  ),
              ]),
          Expanded(
            child: Stack(children: [
              Positioned.fill(
                child: kMobile
                    ? (_ready ? diff : _diffPlaceholder())
                    : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        SizedBox(width: 260, child: _fileTree()),
                        Container(width: 1, color: AppColors.border),
                        Expanded(child: _ready ? diff : _diffPlaceholder()),
                      ]),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16 + MediaQuery.of(context).padding.bottom,
                child: _statsPill(adds, dels, viewed),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// One file of a diff: a collapsible header with a Viewed box, its hunks with
/// syntax highlighting, threads under their lines, and line selection for new
/// comments (tap a line, then shift-click or long-press another to extend).
// Scrolling past a file lays out all its rows, so a jump through a big PR only
// stays quick if most of it starts closed.
bool prStartCollapsed(List<PrFile> files) =>
    files.length > 40 ||
    files.fold<int>(0, (n, f) => n + f.additions + f.deletions) > 3000;

class PrFileDiff extends StatefulWidget {
  const PrFileDiff({
    super.key,
    required this.file,
    required this.lines,
    this.startCollapsed = false,
    required this.threads,
    required this.pending,
    required this.viewed,
    required this.onViewed,
    required this.canComment,
    required this.client,
    required this.session,
    required this.number,
    required this.onPendingChanged,
    required this.onThreadsChanged,
  });

  final PrFile file;
  final List<DiffLine> lines;
  final bool startCollapsed;
  final List<PrThread> threads;
  final List<PendingComment> pending;
  final bool viewed;
  final ValueChanged<bool>? onViewed;
  final bool canComment;
  final DaemonClient client;
  final String session;
  final int number;
  final VoidCallback onPendingChanged;
  final Future<void> Function() onThreadsChanged;

  @override
  State<PrFileDiff> createState() => _PrFileDiffState();
}

class _PrFileDiffState extends State<PrFileDiff> {
  static const _bigFile = 400;
  late bool _collapsed =
      widget.viewed || widget.startCollapsed || widget.lines.length > _bigFile;
  int? _selStart;
  int? _selEnd;
  final _composer = TextEditingController();
  bool _posting = false;
  final Map<int, TextSpan> _spans = {};

  @override
  void didUpdateWidget(PrFileDiff old) {
    super.didUpdateWidget(old);
    if (widget.viewed && !old.viewed) _collapsed = true;
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  String get _ext {
    final name = widget.file.path.split('/').last;
    return name.contains('.') ? name.split('.').last : name;
  }

  TextSpan _span(int index, String text) => _spans.putIfAbsent(
      index,
      () => highlightedCodeSpan(text.isEmpty ? ' ' : text,
          language: _ext, fontSize: kMobile ? 12 : 13, height: 1.5));

  (int, int)? get _range {
    if (_selStart == null) return null;
    final a = _selStart!, b = _selEnd ?? _selStart!;
    return a <= b ? (a, b) : (b, a);
  }

  bool _extending() =>
      HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
      HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);

  void _tap(int index) {
    if (!widget.canComment || widget.lines[index].anchor == null) return;
    setState(() {
      if (_selStart != null && _extending()) {
        _selEnd = index;
      } else if (_selStart == index && _selEnd == null && _composer.text.isEmpty) {
        _selStart = null;
      } else {
        _selStart = index;
        _selEnd = null;
      }
    });
  }

  void _extend(int index) {
    if (!widget.canComment || widget.lines[index].anchor == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selStart ??= index;
      _selEnd = index;
    });
  }

  void _clear() => setState(() {
        _selStart = null;
        _selEnd = null;
        _composer.clear();
      });

  PendingComment? _draft() {
    final r = _range;
    final text = _composer.text.trim();
    if (r == null || text.isEmpty) return null;
    final start = widget.lines[r.$1].anchor!;
    final end = widget.lines[r.$2].anchor!;
    final multi = r.$1 != r.$2;
    return PendingComment(
      path: widget.file.path,
      line: end.$2,
      side: end.$1,
      startLine: multi ? start.$2 : null,
      startSide: multi ? start.$1 : null,
      body: text,
    );
  }

  void _addToReview() {
    final draft = _draft();
    if (draft == null) return;
    widget.pending.add(draft);
    _clear();
    widget.onPendingChanged();
  }

  Future<void> _commentNow() async {
    final draft = _draft();
    if (draft == null) return;
    setState(() => _posting = true);
    try {
      await widget.client.submitPrReview(widget.session, widget.number,
          event: 'COMMENT', body: '', comments: [draft]);
      _clear();
      await widget.onThreadsChanged();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  void _suggest() {
    final r = _range;
    if (r == null) return;
    final lines = [
      for (var i = r.$1; i <= r.$2; i++)
        if (widget.lines[i].kind != DiffKind.del) widget.lines[i].text,
    ];
    final block = '```suggestion\n${lines.join('\n')}\n```';
    final text = _composer.text;
    _composer.text = text.isEmpty ? block : '$text\n$block';
    _composer.selection = TextSelection.collapsed(offset: _composer.text.length);
    setState(() {});
  }

  bool _matches(DiffLine line, int lineNo, String side) {
    final a = line.anchor;
    return a != null && a.$1 == side && a.$2 == lineNo;
  }

  // Deep paths would otherwise ellipsize away the only part that differs.
  Widget _fileName(String path) {
    final slash = path.lastIndexOf('/');
    if (!kMobile || slash < 0) {
      return Text(path,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: mono(13, color: AppColors.fg1));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(path.substring(slash + 1),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: mono(13, color: AppColors.fg1)),
      Text(path.substring(0, slash),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: mono(11, color: AppColors.fg4)),
    ]);
  }

  Widget _header() {
    final f = widget.file;
    return Material(
      color: AppColors.tint1,
      child: InkWell(
        onTap: () => setState(() => _collapsed = !_collapsed),
        child: Container(
          margin: EdgeInsets.only(top: S.s8),
          padding: EdgeInsets.fromLTRB(S.s8, S.s6, S.s8, S.s6),
          child: Row(children: [
            AppIcon(_collapsed ? 'chevron-right' : 'chevron-down', size: 14, color: AppColors.fg3),
            SizedBox(width: S.s6),
            Expanded(child: _fileName(f.path)),
            SizedBox(width: S.s8),
            prSize(f.additions, f.deletions, size: 11.5),
            if (widget.onViewed != null) ...[
              SizedBox(width: S.s6),
              Tooltip(
                message: 'Viewed',
                child: kMobile
                    ? TapDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onViewed!(!widget.viewed),
                        child: Padding(
                          padding: EdgeInsets.all(S.s8),
                          child: SelectCheck(widget.viewed, size: 20),
                        ),
                      )
                    : Checkbox(
                  value: widget.viewed,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  activeColor: AppColors.accent,
                  side: BorderSide(color: AppColors.fg4, width: 1.5),
                  onChanged: (v) => widget.onViewed!(v ?? false),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _line(int index) {
    final line = widget.lines[index];
    final r = _range;
    final selected = r != null && index >= r.$1 && index <= r.$2;
    if (line.kind == DiffKind.hunk) {
      return Container(
        color: AppColors.accentBg,
        padding: EdgeInsets.symmetric(horizontal: S.of(10), vertical: S.of(5)),
        child: Text(line.text, style: codeMono(12, color: AppColors.accent)),
      );
    }
    final bg = selected
        ? AppColors.accent.withValues(alpha: 0.22)
        : switch (line.kind) {
            DiffKind.add => AppColors.diffAddBg,
            DiffKind.del => AppColors.diffDelBg,
            _ => Colors.transparent,
          };
    final number = line.newLine ?? line.oldLine;
    final sign = switch (line.kind) {
      DiffKind.add => '+',
      DiffKind.del => '−',
      _ => ' ',
    };
    return Material(
      color: bg,
      child: InkWell(
        onTap: () => _tap(index),
        onLongPress: kMobile ? () => _extend(index) : null,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: kMobile ? 40 : 46,
            padding: EdgeInsets.only(right: S.s6),
            color: selected ? AppColors.accent.withValues(alpha: 0.3) : null,
            child: Text('${number ?? ''}',
                textAlign: TextAlign.right,
                style: codeMono(11, height: 1.75, color: selected ? AppColors.fg1 : AppColors.fg4)),
          ),
          SizedBox(
            width: 16,
            child: Text(sign, style: codeMono(12, height: 1.5, color: AppColors.fg3)),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: S.of(10)),
              child: Text.rich(_span(index, line.text)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _composerBox() {
    final r = _range!;
    final start = widget.lines[r.$1].anchor!.$2;
    final end = widget.lines[r.$2].anchor!.$2;
    final label = r.$1 == r.$2 ? 'Line $end' : 'Lines $start–$end';
    final canSuggest = [for (var i = r.$1; i <= r.$2; i++) widget.lines[i]].any((l) => l.kind != DiffKind.del);
    final ready = _composer.text.trim().isNotEmpty && !_posting;
    return Padding(
      padding: EdgeInsets.fromLTRB(S.s12, S.s8, S.s12, S.of(10)),
      child: PrMarkdownComposer(
        controller: _composer,
        autofocus: true,
        onChanged: () => setState(() {}),
        extraTools: [
          if (canSuggest)
            Tooltip(
              message: 'Suggest a change to ${label.toLowerCase()}',
              child: InkWell(
                onTap: _suggest,
                borderRadius: BorderRadius.circular(R.sm),
                child: Container(
                  height: 28,
                  padding: EdgeInsets.symmetric(horizontal: S.s8),
                  margin: EdgeInsets.only(right: S.s4),
                  decoration: BoxDecoration(
                    color: AppColors.accentBg,
                    borderRadius: BorderRadius.circular(R.sm),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    AppIcon('file-plus', size: 13, color: AppColors.accent),
                    SizedBox(width: S.of(5)),
                    Text('Suggest', style: sans(12, weight: W.label, color: AppColors.accent)),
                  ]),
                ),
              ),
            ),
        ],
        footer: Row(children: [
          Text(label, style: TS.meta(AppColors.fg3)),
          const Spacer(),
          TextButton(
            onPressed: _clear,
            style: TextButton.styleFrom(minimumSize: const Size(0, 32), padding: EdgeInsets.symmetric(horizontal: S.of(10))),
            child: Text('Cancel', style: sans(13, weight: W.label, color: AppColors.fg3)),
          ),
          TextButton(
            onPressed: ready ? _commentNow : null,
            style: TextButton.styleFrom(minimumSize: const Size(0, 32), padding: EdgeInsets.symmetric(horizontal: S.of(10))),
            child: Text('Comment now', style: sans(13, weight: W.label, color: ready ? AppColors.fg1 : AppColors.fg4)),
          ),
          SizedBox(width: S.s4),
          FilledButton(
            onPressed: ready ? _addToReview : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 32),
              backgroundColor: AppColors.accentFill,
              foregroundColor: AppColors.accentFg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kMobile ? R.pill : R.sm)),
            ),
            child: Text(widget.pending.isEmpty ? 'Start a review' : 'Add to review',
                style: sans(13, weight: W.label, color: AppColors.accentFg)),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget Function()>[_header];
    if (!_collapsed) {
      if (widget.lines.isEmpty) {
        rows.add(() => Padding(
              padding: EdgeInsets.all(S.of(14)),
              child: Text('No textual changes (binary, renamed or too large to show).',
                  style: TS.meta(AppColors.fg4)),
            ));
      }
      final r = _range;
      final notes = widget.threads.isNotEmpty || widget.pending.isNotEmpty;
      for (var i = 0; i < widget.lines.length; i++) {
        final line = widget.lines[i];
        rows.add(() => _line(i));
        if (notes && line.anchor != null) {
          for (final t in widget.threads.where((t) => _matches(line, t.line, t.side))) {
            rows.add(() => PrThreadBox(
                  key: ValueKey(t.id),
                  thread: t,
                  client: widget.client,
                  session: widget.session,
                  number: widget.number,
                  onChanged: widget.onThreadsChanged,
                ));
          }
          for (final p in widget.pending.where((p) => p.path == widget.file.path && _matches(line, p.line, p.side))) {
            rows.add(() => _PendingBox(
                  comment: p,
                  onRemove: () {
                    widget.pending.remove(p);
                    widget.onPendingChanged();
                    setState(() {});
                  },
                ));
          }
        }
        if (r != null && i == r.$2) rows.add(_composerBox);
      }
    }
    return SliverList.builder(
      itemCount: rows.length,
      itemBuilder: (_, i) => rows[i](),
    );
  }
}

class _PendingBox extends StatelessWidget {
  const _PendingBox({required this.comment, required this.onRemove});
  final PendingComment comment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final range = comment.startLine == null ? 'line ${comment.line}' : 'lines ${comment.startLine}–${comment.line}';
    return Container(
      margin: EdgeInsets.fromLTRB(S.s12, S.s6, S.s12, S.s8),
      padding: EdgeInsets.fromLTRB(S.s12, S.s8, S.s6, S.of(10)),
      decoration: BoxDecoration(
        color: AppColors.accentBg,
        borderRadius: BorderRadius.circular(R.card),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: S.of(7), vertical: S.s2),
            decoration: BoxDecoration(color: AppColors.accentBg, borderRadius: BorderRadius.circular(R.pill)),
            child: Text('Pending', style: sans(11, weight: W.label, color: AppColors.accent)),
          ),
          SizedBox(width: S.s8),
          Expanded(child: Text('You · $range', style: TS.meta(AppColors.fg3))),
          IconBtn('trash', size: 26, iconSize: 13, tooltip: 'Remove', onTap: onRemove),
        ]),
        SizedBox(height: S.s6),
        PrCommentBody(comment.body),
      ]),
    );
  }
}

/// A review thread as GitHub shows it: comments with avatars, a reply box, and
/// resolve. Resolved threads start collapsed.
class PrThreadBox extends StatefulWidget {
  const PrThreadBox({
    super.key,
    required this.thread,
    required this.client,
    required this.session,
    required this.number,
    required this.onChanged,
  });

  final PrThread thread;
  final DaemonClient client;
  final String session;
  final int number;
  final Future<void> Function() onChanged;

  @override
  State<PrThreadBox> createState() => _PrThreadBoxState();
}

class _PrThreadBoxState extends State<PrThreadBox>
    with AutomaticKeepAliveClientMixin {
  // A half-typed reply has to survive scrolling out of the lazy list.
  @override
  bool get wantKeepAlive => true;

  late bool _open = !widget.thread.resolved;
  bool _replying = false;
  bool _busy = false;
  final _reply = TextEditingController();

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _sendReply() async {
    final text = _reply.text.trim();
    final root = widget.thread.comments.isEmpty ? null : widget.thread.comments.first;
    if (text.isEmpty || root == null) return;
    setState(() => _busy = true);
    try {
      await widget.client.replyToThread(widget.session, widget.number, root.id, text);
      _reply.clear();
      _replying = false;
      await widget.onChanged();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolve() async {
    setState(() => _busy = true);
    try {
      await widget.client.resolveThread(widget.session, widget.thread.id, !widget.thread.resolved);
      await widget.onChanged();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _comment(PrThreadComment c, {bool first = false}) => Padding(
        padding: EdgeInsets.fromLTRB(S.s12, first ? S.of(10 ) : S.s12, S.s12, 0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          prAvatar(c.author, size: 24),
          SizedBox(width: S.of(10)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: c.author, style: sans(13, weight: W.label, color: AppColors.fg1)),
                TextSpan(text: ' · ${prAgo(c.at)}', style: TS.meta(AppColors.fg4)),
              ])),
              SizedBox(height: S.s4),
              PrCommentBody(c.body),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = widget.thread;
    final first = t.comments.isEmpty ? null : t.comments.first;
    return Container(
      margin: EdgeInsets.fromLTRB(S.s12, S.s6, S.s12, S.of(10)),
      decoration: BoxDecoration(
        color: AppColors.tint1,
        borderRadius: BorderRadius.circular(R.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: EdgeInsets.fromLTRB(S.s12, S.s8, S.s8, S.s8),
            child: Row(children: [
              if (t.resolved) ...[
                AppIcon('check-circle', size: 13, color: AppColors.ok),
                SizedBox(width: S.s6),
              ],
              Expanded(
                child: Text(
                    [
                      if (t.resolved) 'Resolved',
                      if (t.outdated) 'Outdated',
                      t.startLine != null && t.startLine != t.line
                          ? 'Lines ${t.startLine}–${t.line}'
                          : 'Line ${t.line}',
                      '${t.comments.length} comment${t.comments.length == 1 ? '' : 's'}',
                      if (!_open && first != null) first.author,
                    ].join(' · '),
                    style: TS.meta(AppColors.fg3)),
              ),
              AppIcon(_open ? 'chevron-up' : 'chevron-down', size: 13, color: AppColors.fg4),
            ]),
          ),
        ),
        if (_open) ...[
          Container(height: 1, color: kMobile ? AppColors.border : AppColors.paneLine),
          for (var i = 0; i < t.comments.length; i++) _comment(t.comments[i], first: i == 0),
          SizedBox(height: S.of(10)),
          Container(height: 1, color: kMobile ? AppColors.border : AppColors.paneLine),
          if (_replying)
            Padding(
              padding: EdgeInsets.all(S.of(10)),
              child: PrMarkdownComposer(
                controller: _reply,
                hint: 'Reply',
                minLines: 2,
                autofocus: true,
                onChanged: () => setState(() {}),
                footer: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(
                    onPressed: () => setState(() {
                      _replying = false;
                      _reply.clear();
                    }),
                    child: Text('Cancel', style: sans(13, weight: W.label, color: AppColors.fg3)),
                  ),
                  SizedBox(width: S.s4),
                  FilledButton(
                    onPressed: _busy || _reply.text.trim().isEmpty ? null : _sendReply,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      backgroundColor: AppColors.accentFill,
                      foregroundColor: AppColors.accentFg,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kMobile ? R.pill : R.sm)),
                    ),
                    child: Text('Reply', style: sans(13, weight: W.label, color: AppColors.accentFg)),
                  ),
                ]),
              ),
            )
          else
            Row(children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _replying = true),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(S.s12, S.of(10), S.s12, S.of(10)),
                    child: Text('Reply…', style: sans(13, color: AppColors.fg4)),
                  ),
                ),
              ),
              TextButton(
                onPressed: _busy ? null : _resolve,
                child: Text(t.resolved ? 'Unresolve' : 'Resolve conversation',
                    style: sans(13, weight: W.label, color: AppColors.fg2)),
              ),
              SizedBox(width: S.s4),
            ]),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Commits
// ---------------------------------------------------------------------------

class PrCommitsScreen extends StatelessWidget {
  const PrCommitsScreen({super.key, required this.client, required this.session, required this.commits});

  final DaemonClient client;
  final String session;
  final List<PrCommit> commits;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String _day(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return 'Unknown date';
    return '${_months[t.month - 1]} ${t.day}, ${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<PrCommit>>{};
    for (final c in commits.reversed) {
      groups.putIfAbsent(_day(c.date), () => []).add(c);
    }
    return Material(
      color: AppColors.paneBg,
      child: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          prHeader(context,
              title: 'Commits',
              subtitle: '${commits.length} commit${commits.length == 1 ? '' : 's'}'),
          Expanded(
            child: ListView(padding: EdgeInsets.only(bottom: S.s32), children: [
              for (final entry in groups.entries) ...[
                Padding(
                  padding: EdgeInsets.fromLTRB(S.s16, S.of(18), S.s16, S.s8),
                  child: Row(children: [
                    AppIcon('git-commit', size: 14, color: AppColors.fg3),
                    SizedBox(width: S.s8),
                    Text('Commits on ${entry.key}', style: sans(13, weight: W.label, color: AppColors.fg2)),
                  ]),
                ),
                for (final c in entry.value)
                  Padding(
                    padding: EdgeInsets.only(left: S.s4),
                    child: _CommitRow(commit: c, client: client, session: session),
                  ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

class _CommitRow extends StatefulWidget {
  const _CommitRow({required this.commit, required this.client, required this.session});
  final PrCommit commit;
  final DaemonClient client;
  final String session;

  @override
  State<_CommitRow> createState() => _CommitRowState();
}

class _CommitRowState extends State<_CommitRow> {
  bool _body = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.commit;
    final short = c.oid.length > 7 ? c.oid.substring(0, 7) : c.oid;
    return InkWell(
      onTap: () => Navigator.of(context).push(PrRoute<void>(
        builder: (_) => CommitDiffScreen(client: widget.client, session: widget.session, commit: c),
      )),
      child: Padding(
        padding: EdgeInsets.fromLTRB(S.s12, S.of(11), S.s8, S.of(11)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: c.headline, style: sans(14, weight: W.label, height: 1.4, color: AppColors.fg1)),
                  if (c.body.trim().isNotEmpty)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: TapDetector(
                        onTap: () => setState(() => _body = !_body),
                        child: Container(
                          margin: EdgeInsets.only(left: S.s6),
                          padding: EdgeInsets.symmetric(horizontal: S.of(5)),
                          decoration: BoxDecoration(
                            color: AppColors.tint2,
                            borderRadius: BorderRadius.circular(R.xs),
                          ),
                          child: Text('…', style: sans(12, weight: W.strong, color: AppColors.fg2)),
                        ),
                      ),
                    ),
                ]),
              ),
              if (_body) ...[
                SizedBox(height: S.s6),
                Text(c.body.trim(), style: codeMono(12, height: 1.5, color: AppColors.fg2)),
              ],
              SizedBox(height: S.s6),
              Row(children: [
                prAvatar(c.author, size: 18),
                SizedBox(width: S.s6),
                Flexible(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: c.author, style: sans(13, weight: W.label, color: AppColors.fg2)),
                      TextSpan(text: ' committed ${prAgo(c.date)}', style: TS.meta(AppColors.fg3)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ]),
          ),
          SizedBox(width: S.s8),
          Container(
            padding: EdgeInsets.symmetric(horizontal: S.of(7), vertical: S.of(3)),
            decoration: BoxDecoration(
              color: AppColors.tint2,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Text(short, style: mono(12, color: AppColors.fg2)),
          ),
          IconBtn('copy', size: 28, iconSize: 13, tooltip: 'Copy SHA', onTap: () {
            Clipboard.setData(ClipboardData(text: c.oid));
            toast(context, 'Copied $short');
          }),
        ]),
      ),
    );
  }
}

class CommitDiffScreen extends StatefulWidget {
  const CommitDiffScreen({super.key, required this.client, required this.session, required this.commit});
  final DaemonClient client;
  final String session;
  final PrCommit commit;

  @override
  State<CommitDiffScreen> createState() => _CommitDiffScreenState();
}

class _CommitDiffScreenState extends State<CommitDiffScreen> with _AfterTransition {
  Map<String, List<DiffLine>>? _files;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.client.githubCommitDiff(widget.session, widget.commit.oid).then((d) {
      if (mounted) setState(() => _files = parseUnifiedDiff(d));
    }).catchError((Object e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final files = _files;
    final c = widget.commit;
    return Material(
      color: AppColors.paneBg,
      child: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          prHeader(context,
              title: c.headline,
              subtitle: '${c.oid.length > 7 ? c.oid.substring(0, 7) : c.oid} · ${c.author} · ${prAgo(c.date)}'),
          Expanded(
            child: _error != null
                ? prMessage(_error!)
                : files == null || !settled
                    ? _diffPlaceholder()
                    : CustomScrollView(slivers: [
                        for (final e in files.entries)
                          PrFileDiff(
                            file: PrFile(
                              path: e.key,
                              additions: e.value.where((l) => l.kind == DiffKind.add).length,
                              deletions: e.value.where((l) => l.kind == DiffKind.del).length,
                              changeType: '',
                            ),
                            lines: e.value,
                            threads: const [],
                            pending: const [],
                            viewed: false,
                            onViewed: null,
                            canComment: false,
                            client: widget.client,
                            session: widget.session,
                            number: 0,
                            onPendingChanged: () {},
                            onThreadsChanged: () async {},
                          ),
                        SliverToBoxAdapter(child: SizedBox(height: S.s32)),
                      ]),
          ),
        ]),
      ),
    );
  }
}
