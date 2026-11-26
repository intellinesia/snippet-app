import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import 'highlight.dart';
import 'chat/desktop_rich_cards.dart';
import 'screens/artifact_viewer.dart' show MermaidDiagram, canRenderMermaid;
import 'platform.dart';
import 'theme.dart';
import 'widgets.dart';

class ThinkingMarkdown extends StatelessWidget {
  final String data;
  const ThinkingMarkdown({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final text = data.trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return MarkdownBody(
      data: unwrapCodedLinks(text),
      selectable: false,
      styleSheet: thinkingMarkdownStyle(context),
      builders: {'pre': PreBlockBuilder()},
      onTapLink: (txt, href, title) => openMarkdownLink(href, context, txt),
    );
  }
}

/// A compact, clipped text preview for summaries shown in lane cards and notices.
/// MarkdownBody uses a Column internally, so constraining it to a fixed preview
/// height can overflow for long lists or code blocks. A native Text preview keeps
/// its line limit under the parent constraints.
class MarkdownPreview extends StatelessWidget {
  final String data;
  final int maxLines;
  final TextStyle? style;

  const MarkdownPreview({
    super.key,
    required this.data,
    this.maxLines = 2,
    this.style,
  });

  static String plain(String md) {
    var t = md.replaceAll(RegExp(r'```[a-zA-Z0-9_-]*'), '');
    t = t.replaceAllMapped(
        RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1) ?? '');
    t = t.replaceAllMapped(RegExp(r'^\s{0,3}#{1,6}\s+(.*)$', multiLine: true),
        (m) => '${m.group(1)!.trim()} · ');
    t = t.replaceAll(RegExp(r'^\s{0,3}>\s?', multiLine: true), '');
    t = t.replaceAll(RegExp(r'^\s*([-*+]|\d+\.)\s+', multiLine: true), '• ');
    t = t.replaceAllMapped(RegExp(r'(\*\*|__)(.+?)\1'), (m) => m.group(2)!);
    t = t.replaceAllMapped(
        RegExp(r'(?<![\w*])[*_]([^*_\n]+)[*_](?![\w*])'), (m) => m.group(1)!);
    t = t.replaceAll('`', '');
    return t
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s*·$'), '');
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      plain(data),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: style ?? sans(12, height: 1.35, color: AppColors.fg3),
    );
  }
}

/// Fenced ``` blocks — highlighted text only, no boxed chrome.
class PreBlockBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(BuildContext context, md.Element element,
      TextStyle? preferredStyle, TextStyle? parentStyle) {
    var code = element.textContent;
    if (code.endsWith('\n')) code = code.substring(0, code.length - 1);
    var lang = '';
    for (final child in element.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'code') {
        final cls = child.attributes['class'] ?? '';
        if (cls.startsWith('language-')) lang = cls.substring(9);
        break;
      }
    }
    final lower = lang.trim().toLowerCase();
    if (lower == 'mermaid' && canRenderMermaid) {
      return MermaidDiagram(code: code);
    }
    if (lower == 'diff' ||
        lower == 'patch' ||
        (lower.isEmpty &&
            (code.startsWith('diff --git ') ||
                (code.startsWith('--- ') && code.contains('\n+++ '))))) {
      return _MdDiffBlock(code: code);
    }
    return _MdCodeBlock(code: code, language: lang);
  }
}

enum _MdDiffKind { hunk, meta, add, del, ctx }

class _MdDiffLine {
  final _MdDiffKind kind;
  final int? oldNum;
  final int? newNum;
  final String text;
  const _MdDiffLine(this.kind, this.text, {this.oldNum, this.newNum});
}

class _MdDiffBlock extends StatefulWidget {
  final String code;
  const _MdDiffBlock({required this.code});

  @override
  State<_MdDiffBlock> createState() => _MdDiffBlockState();
}

class _MdDiffBlockState extends State<_MdDiffBlock> {
  static const int _initialCap = 42;
  static const _headers = [
    'diff --git ',
    'index ',
    '--- ',
    '+++ ',
    'new file mode',
    'deleted file mode',
    'similarity index',
    'rename from ',
    'rename to ',
  ];
  static final _hunkRe = RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@(.*)');

  bool _wrap = true;
  bool _expanded = false;

  ({
    String? file,
    List<_MdDiffLine> lines,
    int adds,
    int dels,
    int maxLineNum,
  }) _parse() {
    String? file;
    final out = <_MdDiffLine>[];
    var oldN = 0;
    var newN = 0;
    var adds = 0;
    var dels = 0;
    var maxNum = 0;
    var inHunk = false;
    var rawNum = 1;

    for (final raw in widget.code.split('\n')) {
      if (raw.startsWith('\\')) continue;
      if (file == null && raw.startsWith('diff --git ')) {
        final parts = raw.split(' b/');
        if (parts.length > 1) file = parts.last.trim();
      } else if (file == null && raw.startsWith('+++ b/')) {
        file = raw.substring(6).trim();
      }
      final m = _hunkRe.firstMatch(raw);
      if (m != null) {
        oldN = int.parse(m.group(1)!);
        newN = int.parse(m.group(2)!);
        final ctx = m.group(3)!.trim();
        out.add(_MdDiffLine(
          _MdDiffKind.hunk,
          ctx.isEmpty ? raw : '@@ -${m.group(1)} +${m.group(2)} @@  $ctx',
        ));
        inHunk = true;
        continue;
      }
      if (raw.startsWith('diff --git ')) {
        inHunk = false;
        final nextFile = raw.split(' b/').last.trim();
        if (out.isNotEmpty && nextFile.isNotEmpty) {
          out.add(_MdDiffLine(_MdDiffKind.meta, nextFile));
        }
        continue;
      }
      if (!inHunk && _headers.any(raw.startsWith)) continue;
      if (raw.startsWith('+')) {
        adds++;
        final n = inHunk ? newN++ : rawNum++;
        if (n > maxNum) maxNum = n;
        out.add(_MdDiffLine(_MdDiffKind.add, raw.substring(1), newNum: n));
      } else if (raw.startsWith('-')) {
        dels++;
        final n = inHunk ? oldN++ : rawNum++;
        if (n > maxNum) maxNum = n;
        out.add(_MdDiffLine(_MdDiffKind.del, raw.substring(1), oldNum: n));
      } else if (raw.startsWith(' ')) {
        final o = inHunk ? oldN++ : null;
        final n = inHunk ? newN++ : rawNum++;
        if (n > maxNum) maxNum = n;
        out.add(_MdDiffLine(_MdDiffKind.ctx, raw.substring(1),
            oldNum: o, newNum: n));
      } else {
        final n = inHunk ? newN++ : rawNum++;
        if (n > maxNum) maxNum = n;
        out.add(_MdDiffLine(_MdDiffKind.ctx, raw, newNum: n));
      }
    }
    return (
      file: file,
      lines: out,
      adds: adds,
      dels: dels,
      maxLineNum: maxNum,
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final parsed = _parse();
    final all = parsed.lines;
    final canCollapse = all.length > _initialCap + 8;
    final shown =
        canCollapse && !_expanded ? all.take(_initialCap).toList() : all;
    final hiddenCount = all.length - shown.length;
    final gutterW =
        (parsed.maxLineNum.toString().length.clamp(2, 5) * 7.5) + 6.0;
    final label = parsed.file == null || parsed.file!.isEmpty
        ? 'diff'
        : parsed.file!.split('/').last;

    if (kMobile && !_expanded) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: S.s8),
        child: Material(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _expanded = true),
            child: SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  AppIcon('file-code', size: 14, color: AppColors.fg2),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13,
                            weight: FontWeight.w500, color: AppColors.fg1)),
                  ),
                  Text('+${parsed.adds} -${parsed.dels}',
                      style: codeMono(13, color: AppColors.fg2)),
                  const SizedBox(width: 10),
                  AppIcon('chevron-down', size: 14, color: AppColors.fg2),
                ]),
              ),
            ),
          ),
        ),
      );
    }

    Widget buildRows({required bool wrapped}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final l in shown) _buildLine(l, gutterW, wrapped: wrapped),
        ],
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: S.s8),
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: kMobile ? AppColors.surface2 : AppColors.surface1,
          borderRadius: BorderRadius.circular(8),
          border: null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: kMobile
                  ? EdgeInsets.fromLTRB(S.s12, S.s6, S.s6, S.s6)
                  : EdgeInsets.fromLTRB(S.s12, S.of(7), S.s6, S.of(7)),
              child: Row(children: [
                AppIcon('file-code', size: 13, color: AppColors.fg3),
                SizedBox(width: S.s6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: codeMono(12, color: AppColors.fg2),
                  ),
                ),
                if (parsed.adds > 0) ...[
                  SizedBox(width: S.s6),
                  Text('+${parsed.adds}',
                      style: codeMono(11,
                          weight: FontWeight.w600, color: AppColors.fg2)),
                ],
                if (parsed.dels > 0) ...[
                  SizedBox(width: S.s6),
                  Text('-${parsed.dels}',
                      style: codeMono(11,
                          weight: FontWeight.w600, color: AppColors.fg2)),
                ],
                SizedBox(width: S.s6),
                IconBtn(
                  'wrap',
                  size: 28,
                  iconSize: 13,
                  active: _wrap,
                  tooltip: _wrap ? 'Unwrap lines' : 'Wrap lines',
                  onTap: () => setState(() => _wrap = !_wrap),
                ),
                SizedBox(width: S.s2),
                IconBtn(
                  'copy',
                  size: 28,
                  iconSize: 13,
                  tooltip: 'Copy diff',
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: widget.code));
                    toast(context, 'Diff copied');
                  },
                ),
              ]),
            ),
            Divider(
                height: 1, color: kMobile ? AppColors.line : AppColors.border),
            if (_wrap)
              Padding(
                padding: EdgeInsets.symmetric(vertical: S.s4),
                child: buildRows(wrapped: true),
              )
            else
              NotificationListener<ScrollNotification>(
                onNotification: (_) => true,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(vertical: S.s4),
                  child: IntrinsicWidth(child: buildRows(wrapped: false)),
                ),
              ),
            if (canCollapse) ...[
              Divider(
                  height: 1,
                  color: kMobile ? AppColors.line : AppColors.border),
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: S.s12, vertical: S.s8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AppIcon(_expanded ? 'chevron-up' : 'chevron-down',
                          size: 13, color: AppColors.accent),
                      SizedBox(width: S.s6),
                      Text(
                        _expanded
                            ? 'Show less'
                            : 'Show $hiddenCount more lines',
                        style: sans(12,
                            weight: FontWeight.w500, color: AppColors.accent),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLine(_MdDiffLine l, double gutterW, {required bool wrapped}) {
    if (l.kind == _MdDiffKind.hunk || l.kind == _MdDiffKind.meta) {
      return Container(
        color: kMobile ? AppColors.surface3 : AppColors.surface2,
        padding: EdgeInsets.symmetric(horizontal: S.of(10), vertical: S.of(3)),
        child: Text(
          l.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: codeMono(11, height: 1.4, color: AppColors.fg4),
        ),
      );
    }
    final (Color? bg, Color fg, Color numColor, String sign) = switch (l.kind) {
      _MdDiffKind.add when kMobile => (
          AppColors.surface3,
          AppColors.fg1,
          AppColors.fg3,
          '+'
        ),
      _MdDiffKind.del when kMobile => (
          AppColors.bg,
          AppColors.fg3,
          AppColors.fg3,
          '-'
        ),
      _MdDiffKind.add => (
          AppColors.surface2,
          AppColors.fg1,
          AppColors.fg3,
          '+'
        ),
      _MdDiffKind.del => (
          null,
          AppColors.fg3,
          AppColors.fg4,
          '-'
        ),
      _ => (null, AppColors.fg2, AppColors.fg4, ' '),
    };
    final numStr = (l.newNum ?? l.oldNum)?.toString() ?? '';
    final textWidget = Text(
      l.text.isEmpty ? ' ' : l.text,
      softWrap: wrapped,
      style: codeMono(12, height: 1.45, color: fg),
    );
    return Container(
      color: bg,
      padding: EdgeInsets.fromLTRB(S.s6, S.of(1.5), S.of(10), S.of(1.5)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: gutterW,
            child: Text(
              numStr,
              textAlign: TextAlign.right,
              style: codeMono(11, height: 1.55, color: numColor),
            ),
          ),
          SizedBox(
            width: 16,
            child: Text(
              sign,
              textAlign: TextAlign.center,
              style: codeMono(12,
                  height: 1.45, weight: FontWeight.w600, color: fg),
            ),
          ),
          if (wrapped) Expanded(child: textWidget) else textWidget,
        ],
      ),
    );
  }
}

class _MdCodeBlock extends StatefulWidget {
  final String code;
  final String language;
  const _MdCodeBlock({required this.code, this.language = ''});

  @override
  State<_MdCodeBlock> createState() => _MdCodeBlockState();
}

class _MdCodeBlockState extends State<_MdCodeBlock> {
  bool _expanded = false;
  late bool _wrap = const {'md', 'markdown', 'mdx', 'text', 'txt'}
      .contains(widget.language.trim().toLowerCase());

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final lines = widget.code.split('\n');
    final lang =
        widget.language.trim().isEmpty ? 'code' : widget.language.trim();
    if (!kMobile) {
      return _desktop(lines, lang, () => setState(() => _wrap = !_wrap));
    }
    // Phone RC-12: surface2 radius 8, 12 px language header, hairline, and
    // two visible code lines before the expand row.
    final visible = _expanded ? lines : lines.take(2).toList();
    final hidden = lines.length - visible.length;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: S.s8),
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 36,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, right: 4),
                child: Row(children: [
                  Text(lang,
                      style: sans(12,
                          weight: FontWeight.w500, color: AppColors.fg3)),
                  const Spacer(),
                  IconBtn(
                    'copy',
                    size: 36,
                    iconSize: 14,
                    tooltip: 'Copy',
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: widget.code));
                      toast(context, 'Copied');
                    },
                  ),
                ]),
              ),
            ),
            Container(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
              child: NotificationListener<ScrollNotification>(
                onNotification: (_) => true,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SelectableText.rich(highlightedCodeSpan(
                      visible.join('\n'),
                      language: widget.language,
                      fontSize: 12,
                      height: 18 / 12)),
                ),
              ),
            ),
            if (hidden > 0 || _expanded) ...[
              Container(height: 1, color: AppColors.border),
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: SizedBox(
                  height: 44,
                  child: Center(
                    child: Text(
                      _expanded ? 'Collapse' : 'Show $hidden more lines',
                      style: sans(13, color: AppColors.fg2),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

extension on _MdCodeBlockState {
  /// Desktop RC-12: a quiet surface-one block, language header and 28-point
  /// wrap/copy affordances.
  Widget _desktop(List<String> lines, String lang, VoidCallback toggleWrap) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 12),
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(8),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
            child: Row(children: [
              Text(lang, style: sans(11, color: AppColors.fg3)),
              const Spacer(),
              DesktopCardIconButton('wrap',
                  tooltip: _wrap ? 'Unwrap lines' : 'Wrap lines',
                  active: _wrap,
                  onTap: toggleWrap),
              DesktopCardIconButton('copy', tooltip: 'Copy', onTap: () {
                Clipboard.setData(ClipboardData(text: widget.code));
                toast(context, 'Copied');
              }),
            ]),
          ),
          Container(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: _wrap
                ? SelectableText.rich(highlightedCodeSpan(widget.code,
                    language: widget.language,
                    fontSize: 12.5,
                    height: 20 / 12.5))
                : NotificationListener<ScrollNotification>(
                    onNotification: (_) => true,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText.rich(highlightedCodeSpan(
                          widget.code,
                          language: widget.language,
                          fontSize: 12.5,
                          height: 20 / 12.5)),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}

class _HoverTools extends StatefulWidget {
  const _HoverTools(
      {required this.code,
      required this.wrap,
      required this.onWrap,
      required this.child});
  final String code;
  final bool wrap;
  final VoidCallback onWrap;
  final Widget child;

  @override
  State<_HoverTools> createState() => _HoverToolsState();
}

class _HoverToolsState extends State<_HoverTools> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 12),
          child: Stack(children: [
            widget.child,
            Positioned(
              top: 4,
              right: 4,
              child: AnimatedOpacity(
                opacity: _hover ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: IgnorePointer(
                  ignoring: !_hover,
                  child: Row(children: [
                    IconBtn('wrap',
                        size: 26,
                        iconSize: 13,
                        active: widget.wrap,
                        tooltip: widget.wrap ? 'Unwrap lines' : 'Wrap lines',
                        onTap: widget.onWrap),
                    IconBtn('copy', size: 26, iconSize: 13, tooltip: 'Copy',
                        onTap: () {
                      Clipboard.setData(ClipboardData(text: widget.code));
                      toast(context, 'Copied');
                    }),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      );
}
