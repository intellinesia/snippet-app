import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api.dart';
import '../chat/chat_card.dart';
import '../chat/grouped_card.dart';
import '../markdown_preview.dart' show plainPreview;
import '../gesture_physics.dart';
import '../models.dart';
import '../panel.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'artifact_grid.dart';
import 'file_viewer.dart';
import 'mobile_chrome.dart';
import '../tap_detector.dart';

const _textExts = {
  'txt',
  'log',
  'md',
  'json',
  'yaml',
  'yml',
  'toml',
  'ini',
  'cfg',
  'conf',
  'env',
  'xml',
  'css',
  'scss',
  'js',
  'ts',
  'tsx',
  'jsx',
  'dart',
  'rs',
  'py',
  'go',
  'c',
  'h',
  'cpp',
  'hpp',
  'java',
  'kt',
  'swift',
  'rb',
  'lua',
  'sh',
  'sql',
  'diff',
  'patch',
  'lock',
  'vue',
  'svelte',
  'gradle',
  'properties',
};

const _webExts = {
  'html',
  'htm',
  'svg',
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'avif',
  'css',
  'js',
  'mjs',
  'json',
  'txt',
  'md',
  'woff',
  'woff2',
  'ttf',
  'otf',
  'ico',
};

String _ext(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
}

bool _isText(String entry) {
  final e = _ext(entry);
  return e.isEmpty || _textExts.contains(e);
}

const _maxTextChars = 200000;

bool get _canEmbedWeb =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

String artifactIcon(String kind) => switch (kind) {
      'html' => 'globe',
      'markdown' => 'file-text',
      'image' || 'svg' => 'image',
      'csv' => 'list',
      'pdf' => 'pdf',
      'code' => 'file-code',
      'collection' => 'layers',
      _ => 'file',
    };

/// A tall sheet on a phone, for the artifact viewer and the shared list.
Future<void> showArtifactSheet(
    BuildContext context, Widget Function(VoidCallback close) builder) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: false,
    backgroundColor: AppColors.bg,
    sheetAnimationStyle: sheetMotion,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheetTop)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (sheet) {
      void close() => Navigator.of(sheet).pop();
      return FractionallySizedBox(
        heightFactor: 0.94,
        child: _HeaderDragSheet(onClose: close, child: builder(close)),
      );
    },
  );
}

/// Lets the sheet be dragged down by its header only, so the page inside keeps
/// its own scrolling. Past a threshold or on a quick flick it closes.
class _HeaderDragSheet extends StatefulWidget {
  const _HeaderDragSheet({required this.onClose, required this.child});
  final VoidCallback onClose;
  final Widget child;

  @override
  State<_HeaderDragSheet> createState() => _HeaderDragSheetState();
}

class _HeaderDragSheetState extends State<_HeaderDragSheet>
    with SingleTickerProviderStateMixin {
  static const _headerHeight = 76.0;
  late final AnimationController _dy =
      AnimationController.unbounded(vsync: this)
        ..addListener(() => setState(() {}));
  double _raw = 0;

  @override
  void dispose() {
    _dy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return Transform.translate(
      offset: Offset(0, _dy.value),
      child: Stack(children: [
        Positioned.fill(child: widget.child),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: _headerHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: (_) {
              _dy.stop();
              _raw = _dy.value;
            },
            onVerticalDragUpdate: (d) {
              _raw += d.delta.dy;
              _dy.value = _raw >= 0 ? _raw : rubberBand(_raw, 80);
            },
            onVerticalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (dragDismisses(
                  distance: _dy.value,
                  velocity: v,
                  distanceThreshold: 140,
                  velocityThreshold: 700)) {
                HapticFeedback.lightImpact();
                widget.onClose();
                springTo(_dy, h, math.max(v, 0));
              } else {
                springTo(_dy, 0, v);
              }
            },
            onVerticalDragCancel: () => springTo(_dy, 0, 0),
          ),
        ),
      ]),
    );
  }
}

/// Open an artifact: a side-pane tab on desktop, a tall sheet on a phone.
Future<void> openArtifact(
  BuildContext context, {
  required DaemonClient client,
  required String session,
  required String id,
  int? version,
  String? title,
}) {
  if (kMobile) {
    return showArtifactSheet(
      context,
      (close) => ArtifactViewer(
          client: client,
          session: session,
          id: id,
          version: version,
          onClose: close),
    );
  }
  return presentScreen<void>(
    context,
    style: PanelStyle.drawer,
    maxWidth: 820,
    purpose: ShellPanelPurpose.artifact,
    panelId: id,
    title: title,
    originClient: client,
    originSessionId: session,
    builder: (_, close) => ArtifactViewer(
      client: client,
      session: session,
      id: id,
      version: version,
      onClose: close,
    ),
  );
}

String _artifactKindLabel(String kind) => switch (kind) {
      'html' => 'Web page',
      'markdown' => 'Document',
      'image' || 'svg' => 'Image',
      'csv' => 'Table',
      'pdf' => 'PDF',
      'code' => 'Code',
      'collection' => 'Collection',
      _ => 'File',
    };

/// An artifact in the transcript: a card with a preview and a footer.
class ArtifactRow extends StatefulWidget {
  const ArtifactRow({
    super.key,
    required this.client,
    required this.session,
    required this.id,
    required this.version,
    required this.title,
    required this.kind,
    required this.caption,
  });

  final DaemonClient client;
  final String session;
  final String id;
  final int version;
  final String title;
  final String kind;
  final String caption;

  @override
  State<ArtifactRow> createState() => _ArtifactRowState();
}

class _ArtifactRowState extends State<ArtifactRow> {
  static const _previewKinds = {'image', 'markdown', 'code', 'csv'};
  Future<_ArtifactPreview?>? _preview;

  @override
  void initState() {
    super.initState();
    if (_previewKinds.contains(widget.kind)) _preview = _load();
  }

  Future<_ArtifactPreview?> _load() async {
    final all = await widget.client.artifacts(widget.session);
    final a = all.where((a) => a.id == widget.id).firstOrNull;
    final v = a?.version(widget.version) ?? a?.latest;
    if (v == null) return null;
    if (widget.kind == 'image') {
      return _ArtifactPreview(uri: v.url);
    }
    final text = await widget.client.artifactText(v.url);
    return _ArtifactPreview(
        text: text.length > 600 ? text.substring(0, 600) : text);
  }

  void _open(BuildContext context) => openArtifact(context,
      client: widget.client,
      session: widget.session,
      id: widget.id,
      version: widget.version);

  String get _meta => '${_artifactKindLabel(widget.kind)} · v${widget.version}';

  Widget _header(BuildContext context) => GroupedCardHeader(
        icon: artifactIcon(widget.kind),
        title: widget.title,
        sub: _meta,
        trailing: GroupedCardHeader.chevron(),
        onTap: () => _open(context),
      );

  Widget _compact(BuildContext context, {String? text}) {
    final plain =
        plainPreview((text ?? '').trim().isNotEmpty ? text! : widget.caption);
    return GroupedCard(segments: [
      _header(context),
      if (plain.isNotEmpty)
        GroupedCardBody(text: plain, onTap: () => _open(context)),
    ]);
  }

  void _retryPreview() {
    setState(() {
      _preview = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = _preview;
    if (f == null) return _compact(context);
    final isImage = widget.kind == 'image';
    return FutureBuilder<_ArtifactPreview?>(
      future: f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          if (!isImage) {
            if (widget.caption.trim().isNotEmpty) return _compact(context);
            return GroupedCard(segments: [
              _header(context),
              const LoadingInline(label: 'Loading preview…'),
            ]);
          }
          return GroupedCard(segments: [
            _header(context),
            TapDetector(
              onTap: () => _open(context),
              child: const SizedBox(
                height: 150,
                width: double.infinity,
                child: LoadingBlock(spinner: true),
              ),
            ),
          ]);
        }
        if (snap.hasError) {
          if (!isImage && widget.caption.trim().isNotEmpty) {
            return _compact(context);
          }
          final fail = LoadFailed(
            message: 'Couldn’t load preview',
            onRetry: _retryPreview,
          );
          return GroupedCard(segments: [
            _header(context),
            if (isImage)
              SizedBox(height: 150, width: double.infinity, child: fail)
            else
              fail,
          ]);
        }
        final d = snap.data;
        if (d == null) return _compact(context);
        if (d.uri == null) return _compact(context, text: d.text);
        return GroupedCard(segments: [
          _header(context),
          TapDetector(
            onTap: () => _open(context),
            child: SizedBox(
              height: 150,
              width: double.infinity,
              child: ArtifactImage(client: widget.client, url: d.uri!),
            ),
          ),
        ]);
      },
    );
  }
}

class _ArtifactPreview {
  const _ArtifactPreview({this.uri, this.text});
  final String? uri;
  final String? text;
}

bool artifactShowsInline(String kind, String? display) {
  final wanted = display == 'inline' ||
      (display == null &&
          (kind == 'markdown' || kind == 'csv' || kind == 'image'));
  if (!wanted) return false;
  return switch (kind) {
    'markdown' || 'csv' || 'code' || 'image' => true,
    'html' || 'svg' => _canEmbedWeb,
    _ => false,
  };
}

class ArtifactInline extends StatefulWidget {
  const ArtifactInline({
    super.key,
    required this.client,
    required this.session,
    required this.id,
    required this.version,
    required this.title,
    required this.kind,
    required this.caption,
  });

  final DaemonClient client;
  final String session;
  final String id;
  final int version;
  final String title;
  final String kind;
  final String caption;

  @override
  State<ArtifactInline> createState() => _ArtifactInlineState();
}

class _ArtifactInlineState extends State<ArtifactInline>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late Future<ArtifactVersion?> _version = _load();
  Future<String>? _text;

  Future<ArtifactVersion?> _load() async {
    final all = await widget.client.artifacts(widget.session);
    final a = all.where((a) => a.id == widget.id).firstOrNull;
    return a?.version(widget.version) ?? a?.latest;
  }

  Future<String> _textOf(ArtifactVersion v) =>
      _text ??= widget.client.artifactText(v.url);

  Widget _loading() => widget.kind == 'image'
      ? LoadingBlock(height: 280, radius: R.card, spinner: true)
      : const LoadingInline();

  Widget _note(String text) => Padding(
        padding: EdgeInsets.symmetric(vertical: S.s8),
        child: Text(text, style: sans(13, color: AppColors.fg3)),
      );

  Widget _textBody(ArtifactVersion v, Widget Function(String) render) =>
      FutureBuilder<String>(
        future: _textOf(v),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return _loading();
          if (snap.hasError) {
            return SizedBox(
              height: 72,
              child: LoadFailed(onRetry: () => setState(() => _text = null)),
            );
          }
          if (!snap.hasData) return _loading();
          return render(snap.data!);
        },
      );

  Widget _body(ArtifactVersion v) {
    final uri = widget.client.artifactUri(v.url);
    switch (widget.kind) {
      case 'markdown':
        return _textBody(
            v,
            (text) => MarkdownBody(
                data: text,
                styleSheet: markdownStyle(context),
                builders: {'pre': PreBlockBuilder()}));
      case 'csv':
        return _textBody(
            v,
            (text) => MarkdownBody(
                data: _csvMarkdown(text),
                styleSheet: markdownStyle(context),
                builders: {'pre': PreBlockBuilder()}));
      case 'code':
        return _textBody(
            v,
            (text) => Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(S.s12),
                  decoration: BoxDecoration(
                    color: AppColors.tint1,
                    borderRadius: BorderRadius.circular(R.card),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(text,
                        style: codeMono(12, height: 1.5, color: AppColors.fg2)),
                  ),
                ));
      case 'image':
        // A fixed slot, so the card keeps its height while the image loads.
        return SizedBox(
          height: 280,
          child: ArtifactImage(
              client: widget.client,
              url: v.url,
              fit: BoxFit.contain,
              radius: R.card),
        );
      default:
        return _InlineWebPage(key: ValueKey(uri.toString()), uri: uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: S.s6),
      child: ChatCard(
        maxWidth: double.infinity,
        children: [
          Padding(
            padding: EdgeInsets.all(ChatCard.pad),
            child: FutureBuilder<ArtifactVersion?>(
              future: _version,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return _loading();
                }
                if (snap.hasError) {
                  return SizedBox(
                    height: 72,
                    child: LoadFailed(
                      onRetry: () {
                        setState(() {
                          _version = _load();
                        });
                      },
                    ),
                  );
                }
                final v = snap.data;
                if (v == null) {
                  return _note('This artifact is no longer available.');
                }
                return _body(v);
              },
            ),
          ),
          ChatCardFooter(
            title: widget.title,
            meta: [
              _artifactKindLabel(widget.kind),
              'v${widget.version}',
              if (widget.caption.isNotEmpty) widget.caption
            ].join(' · '),
            onTap: () => openArtifact(context,
                client: widget.client,
                session: widget.session,
                id: widget.id,
                version: widget.version),
          ),
        ],
      ),
    );
  }
}

String _csvMarkdown(String text) {
  final rows = _CsvTable(text: text)._rows().take(201).toList();
  if (rows.isEmpty) return '';
  final width = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
  String line(List<String> r) =>
      '| ${List.generate(width, (i) => (i < r.length ? r[i] : '').replaceAll('|', '\\|')).join(' | ')} |';
  return [
    line(rows.first),
    '|${List.filled(width, '---').join('|')}|',
    for (final r in rows.skip(1)) line(r),
  ].join('\n');
}

String _cssHex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

String _cssRgba(Color c) =>
    'rgba(${(c.r * 255).round()},${(c.g * 255).round()},${(c.b * 255).round()},${c.a.toStringAsFixed(3)})';

String snippetPageTheme(bool dark, String bg) {
  final vars = {
    '--sn-bg': bg,
    '--sn-surface': _cssHex(AppColors.surface1),
    '--sn-surface-2': _cssHex(AppColors.surface2),
    '--sn-surface-3': _cssHex(AppColors.surface3),
    '--sn-text': _cssHex(AppColors.fg1),
    '--sn-text-2': _cssHex(AppColors.fg2),
    '--sn-muted': _cssHex(AppColors.fg3),
    '--sn-faint': _cssHex(AppColors.fg4),
    '--sn-border': _cssHex(AppColors.border),
    '--sn-border-strong': _cssHex(AppColors.border2),
    '--sn-accent': _cssHex(AppColors.accent),
    '--sn-accent-text': _cssHex(AppColors.accentFg),
    '--sn-accent-bg': _cssRgba(AppColors.accentBg),
    '--sn-ok': _cssHex(AppColors.ok),
    '--sn-warn': _cssHex(AppColors.run),
    '--sn-danger': _cssHex(AppColors.danger),
    '--sn-radius': '12px',
    '--sn-font': "'Geist', -apple-system, system-ui, sans-serif",
    '--sn-mono': "'Geist Mono', ui-monospace, monospace",
  };
  final css =
      ':root{${vars.entries.map((e) => '${e.key}:${e.value}').join(';')}}';
  return '''
(function () {
  var d = document, h = d.head || d.documentElement;
  var v = d.createElement('style'); v.textContent = ${jsonEncode(css)}; h.insertBefore(v, h.firstChild);
  if (!d.querySelector('link[data-sn-fonts]')) {
    var l = d.createElement('link'); l.rel = 'stylesheet'; l.setAttribute('data-sn-fonts', '');
    l.href = 'https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600&family=Geist+Mono:wght@400;500&display=swap';
    h.appendChild(l);
  }
  var b = d.body; if (!b) return;
  var clear = function (c) { return c === 'rgba(0, 0, 0, 0)' || c === 'transparent'; };
  if (clear(getComputedStyle(b).backgroundColor) && clear(getComputedStyle(d.documentElement).backgroundColor)) {
    var s = d.createElement('style');
    s.textContent = ':root{color-scheme:${dark ? 'dark' : 'light'}}html,body{background:var(--sn-bg);color:var(--sn-text);margin:0}';
    h.appendChild(s);
  }
})();
''';
}

/// Stand-in while an artifact loads: quiet shimmer slot when filling a fixed
/// media container, or a compact inline spinner row otherwise.
class ArtifactSkeleton extends StatelessWidget {
  const ArtifactSkeleton({super.key, this.fill = false});

  /// Fill the slot it sits in; otherwise a compact inline row.
  final bool fill;

  @override
  Widget build(BuildContext context) =>
      fill ? const LoadingBlock(spinner: true) : const LoadingInline();
}

/// An artifact image that loads with a timeout, decodes at display size and
/// offers a retry when it fails.
class ArtifactImage extends StatefulWidget {
  const ArtifactImage({
    super.key,
    required this.client,
    required this.url,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.radius = 0,
    this.fullSize = false,
    this.fallback,
  });

  final DaemonClient client;

  /// The signed artifact path.
  final String url;
  final BoxFit fit;
  final Alignment alignment;
  final double radius;

  /// Decode at full resolution and show a spinner, for the zoomable viewer.
  final bool fullSize;

  /// Shown instead of the retry line when loading fails.
  final Widget? fallback;

  @override
  State<ArtifactImage> createState() => _ArtifactImageState();
}

class _ArtifactImageState extends State<ArtifactImage> {
  int _attempt = 0;

  void _retry(ImageProvider p) {
    p.evict();
    setState(() => _attempt++);
  }

  Widget _placeholder() => widget.fullSize
      ? const Center(child: Spinner(size: 20))
      : LoadingBlock(radius: widget.radius, spinner: true);

  @override
  Widget build(BuildContext context) {
    final source = widget.client.artifactImage(widget.url);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final fast = reduceMotion(context) ? Duration.zero : Motion.fast;
    return LayoutBuilder(builder: (context, c) {
      final w = c.hasBoundedWidth ? (c.maxWidth * dpr).round() : null;
      final image = widget.fullSize
          ? source
          : ResizeImage.resizeIfNeeded(w, null, source);
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: Image(
          key: ValueKey(_attempt),
          image: image,
          fit: widget.fit,
          alignment: widget.alignment,
          width: !widget.fullSize && c.hasBoundedWidth ? double.infinity : null,
          height:
              !widget.fullSize && c.hasBoundedHeight ? double.infinity : null,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, sync) {
            if (sync) return child;
            return AnimatedSwitcher(
              duration: fast,
              child: frame == null
                  ? KeyedSubtree(
                      key: const ValueKey('loading'), child: _placeholder())
                  : KeyedSubtree(key: const ValueKey('loaded'), child: child),
            );
          },
          errorBuilder: (_, __, ___) =>
              widget.fallback ??
              LoadFailed(
                  message: 'Couldn’t load image', onRetry: () => _retry(image)),
        ),
      );
    });
  }
}

bool get canRenderMermaid => _canEmbedWeb;

class MermaidDiagram extends StatelessWidget {
  const MermaidDiagram({super.key, required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final escaped = const HtmlEscape(HtmlEscapeMode.element).convert(code);
    final vars = jsonEncode({
      'darkMode': dark,
      'background': 'transparent',
      'fontFamily': "Geist, -apple-system, system-ui, sans-serif",
      'fontSize': '14px',
      'primaryColor': _cssHex(AppColors.surface2),
      'primaryTextColor': _cssHex(AppColors.fg1),
      'primaryBorderColor': _cssHex(AppColors.border2),
      'secondaryColor': _cssHex(AppColors.surface3),
      'tertiaryColor': _cssHex(AppColors.surface1),
      'lineColor': _cssHex(AppColors.fg3),
      'textColor': _cssHex(AppColors.fg2),
      'clusterBkg': _cssHex(AppColors.surface1),
      'clusterBorder': _cssHex(AppColors.border2),
      'edgeLabelBackground': _cssHex(AppColors.surface1),
      'noteBkgColor': _cssHex(AppColors.surface3),
      'noteTextColor': _cssHex(AppColors.fg1),
    });
    final html = '''<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;padding:0;background:transparent}
.mermaid{display:flex;justify-content:center;margin:0;padding:4px 0}
.mermaid svg{max-width:100%;height:auto}</style></head>
<body><pre class="mermaid">$escaped</pre>
<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
<script>mermaid.initialize({startOnLoad:true,securityLevel:'strict',theme:'base',themeVariables:$vars});</script>
</body></html>''';
    return _InlineWebPage(
        key: ValueKey('mermaid:${code.hashCode}'), html: html);
  }
}

class _InlineWebPage extends StatefulWidget {
  const _InlineWebPage({super.key, this.uri, this.html});
  final Uri? uri;
  final String? html;

  String get cacheKey => uri?.toString() ?? 'html:${html.hashCode}';

  @override
  State<_InlineWebPage> createState() => _InlineWebPageState();
}

class _InlineWebPageState extends State<_InlineWebPage> {
  static const _report = """
(function () {
  if (window.__snippetHeight) return;
  window.__snippetHeight = true;
  var last = 0;
  function send() {
    var d = document.documentElement, b = document.body;
    var h = Math.ceil(Math.max(d.scrollHeight, b ? b.scrollHeight : 0, d.offsetHeight));
    if (h !== last) { last = h; SnippetHeight.postMessage(String(h)); }
  }
  new ResizeObserver(send).observe(document.documentElement);
  if (document.body) new ResizeObserver(send).observe(document.body);
  window.addEventListener('load', send);
  send();
})();
""";

  static const _wheel = """
(function () {
  if (window.__snippetWheel) return;
  window.__snippetWheel = true;
  window.addEventListener('wheel', function (e) {
    var dy = e.deltaY;
    if (Math.abs(e.deltaX) > Math.abs(dy) || dy === 0) return;
    for (var el = e.target; el && el.nodeType === 1 && el !== document.body && el !== document.documentElement; el = el.parentElement) {
      var oy = getComputedStyle(el).overflowY;
      if ((oy === 'auto' || oy === 'scroll') && el.scrollHeight > el.clientHeight + 1) {
        if ((dy < 0 && el.scrollTop > 0) || (dy > 0 && el.scrollTop + el.clientHeight < el.scrollHeight - 1)) return;
      }
    }
    e.preventDefault();
    var k = e.deltaMode === 1 ? 16 : e.deltaMode === 2 ? window.innerHeight : 1;
    SnippetScroll.postMessage(String(dy * k));
  }, { passive: false });
})();
""";

  static final _knownHeights = <String, double>{};

  late double _height = _knownHeights[widget.cacheKey] ?? 180;
  bool _ready = false;
  bool _finished = false;
  bool _measured = false;
  Timer? _settle;
  Timer? _giveUp;
  Timer? _heightThrottle;
  double? _pendingHeight;
  bool _onScreen = true;
  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (!identical(position, _position)) {
      _position?.removeListener(_checkOnScreen);
      _position = position;
      _position?.addListener(_checkOnScreen);
    }
  }

  void _checkOnScreen() {
    final box = context.findRenderObject();
    final viewport = _position?.context.notificationContext?.findRenderObject();
    if (box is! RenderBox ||
        viewport is! RenderBox ||
        !box.attached ||
        !viewport.attached) {
      return;
    }
    final top = box.localToGlobal(Offset.zero).dy;
    final viewTop = viewport.localToGlobal(Offset.zero).dy;
    const margin = 600.0;
    final visible = top + box.size.height > viewTop - margin &&
        top < viewTop + viewport.size.height + margin;
    if (visible != _onScreen) setState(() => _onScreen = visible);
  }

  String _bg = '#000000';
  bool _dark = true;

  String get _theme => snippetPageTheme(_dark, _bg);

  late final WebViewController _controller = () {
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('SnippetHeight', onMessageReceived: (m) {
        final h = double.tryParse(m.message);
        if (h == null || !mounted) return;
        final next = h.clamp(40.0, 6000.0);
        _measured = true;
        _knownHeights[widget.cacheKey] = next;
        _pendingHeight = next;
        if (!_ready) {
          if ((next - _height).abs() > 1) setState(() => _height = next);
          _scheduleReveal();
          return;
        }
        _heightThrottle ??= Timer(const Duration(milliseconds: 250), () {
          _heightThrottle = null;
          final target = _pendingHeight;
          if (mounted && target != null && (target - _height).abs() > 1) {
            setState(() => _height = target);
          }
        });
      })
      ..addJavaScriptChannel('SnippetScroll', onMessageReceived: (m) {
        final dy = double.tryParse(m.message);
        final p = _position;
        if (dy == null || p == null || !p.hasPixels) return;
        final delta = p.axisDirection == AxisDirection.up ? -dy : dy;
        final next =
            (p.pixels + delta).clamp(p.minScrollExtent, p.maxScrollExtent);
        if (next != p.pixels) p.jumpTo(next);
      })
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) {
          if (!_finished || !r.isMainFrame) return NavigationDecision.navigate;
          final u = Uri.tryParse(r.url);
          if (u == null || u.scheme == 'about' || u.scheme == 'data') {
            return NavigationDecision.navigate;
          }
          final same = widget.uri != null &&
              u.replace(fragment: '').toString() ==
                  widget.uri!.replace(fragment: '').toString();
          if (same) return NavigationDecision.navigate;
          launchUrl(u, mode: LaunchMode.externalApplication);
          return NavigationDecision.prevent;
        },
        onPageFinished: (_) {
          _controller.runJavaScript(_theme);
          _controller.runJavaScript(_report);
          if (!kMobile) _controller.runJavaScript(_wheel);
          _finished = true;
          _giveUp ??= Timer(const Duration(milliseconds: 2500), _reveal);
          _scheduleReveal();
        },
      ));
    if (!kMacOS) c.setBackgroundColor(Colors.transparent);
    final html = widget.html;
    if (html != null) return c..loadHtmlString(html);
    return c..loadRequest(widget.uri!);
  }();

  void _scheduleReveal() {
    if (_ready || !_finished || !_measured) return;
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 250), _reveal);
  }

  void _reveal() {
    if (_ready || !mounted) return;
    _settle?.cancel();
    _giveUp?.cancel();
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    _settle?.cancel();
    _giveUp?.cancel();
    _heightThrottle?.cancel();
    _position?.removeListener(_checkOnScreen);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    _bg = _cssHex(theme.scaffoldBackgroundColor);
    _dark = theme.brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      height: _height,
      child: Stack(children: [
        if (_onScreen)
          Positioned.fill(child: WebViewWidget(controller: _controller)),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: _ready,
            child: AnimatedOpacity(
              opacity: _ready ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: ColoredBox(
                color: theme.scaffoldBackgroundColor,
                child: const ArtifactSkeleton(fill: true),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class ArtifactViewer extends StatefulWidget {
  const ArtifactViewer({
    super.key,
    required this.client,
    required this.session,
    required this.id,
    this.version,
    this.onClose,
  });

  final DaemonClient client;
  final String session;
  final String id;
  final int? version;
  final VoidCallback? onClose;

  @override
  State<ArtifactViewer> createState() => _ArtifactViewerState();
}

class _ArtifactViewerState extends State<ArtifactViewer> {
  ArtifactInfo? _artifact;
  int? _n;
  bool _source = false;
  String? _error;
  Future<String>? _text;
  String? _textFor;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _n = widget.version;
    _load();
    _poll =
        Timer.periodic(const Duration(seconds: 5), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool latest = false, bool quiet = false}) async {
    try {
      final all = await widget.client.artifacts(widget.session);
      final found = all.where((a) => a.id == widget.id).firstOrNull;
      if (!mounted) return;
      final before = _artifact?.latest?.n;
      final after = found?.latest?.n;
      if (quiet && found != null && before == after) return;
      final follow = latest || _n == null || _n == before;
      setState(() {
        _artifact = found;
        _error = found == null ? 'This artifact is no longer available.' : null;
        if (follow) _n = after;
        _textFor = null;
      });
    } catch (e) {
      if (mounted && !quiet) setState(() => _error = '$e');
    }
  }

  Future<void> _download() async {
    final a = _artifact;
    final v = _version;
    if (a == null || v == null) return;
    if (a.kind != 'html' && a.kind != 'collection' && v.source.isNotEmpty) {
      final name = v.source.split('/').last;
      try {
        final msg = await downloadRemoteFileWithCancel(context, widget.client,
            path: v.source, name: name);
        if (msg != null && mounted) toast(context, msg);
        return;
      } catch (_) {
        if (!mounted) return;
      }
    }
    try {
      if (!mounted) return;
      toast(context, 'Preparing ${a.title}…');
      final path =
          await widget.client.zipArtifact(widget.session, a.id, version: v.n);
      if (!mounted) return;
      final msg = await downloadRemoteFileWithCancel(context, widget.client,
          path: path, name: '${a.id}-v${v.n}.zip');
      if (msg != null && mounted) toast(context, msg);
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  ArtifactVersion? get _version => _artifact?.version(_n ?? 0);

  bool get _hasSource => switch (_artifact?.kind) {
        'html' || 'markdown' || 'csv' || 'code' || 'svg' => true,
        'file' => _isText(_version?.entry ?? ''),
        _ => false,
      };

  Future<String> _textOf(ArtifactVersion v) {
    if (_textFor != v.url || _text == null) {
      _textFor = v.url;
      _text = widget.client.artifactText(v.url).then((t) => t.length >
              _maxTextChars
          ? '${t.substring(0, _maxTextChars)}\n\n… truncated, download for the full file'
          : t);
    }
    return _text!;
  }

  Future<void> _pickVersion(BuildContext anchor) async {
    final a = _artifact;
    if (a == null || a.versions.length < 2) return;
    final picked = await showAppMenu<int>(
      context,
      anchor: anchor,
      minWidth: 200,
      items: [
        appMenuHeading<int>('Versions'),
        for (final v in a.versions.reversed)
          appMenuRow<int>(
            value: v.n,
            icon: 'history',
            label: kMobile
                ? 'Version ${v.n}'
                : 'v${v.n}${v.n == a.latest?.n ? ' \u00b7 Latest version' : ''}',
            description: _when(v.createdAt),
            selected: v.n == _n,
          ),
      ],
    );
    if (picked != null && mounted) setState(() => _n = picked);
  }

  String _when(int seconds) {
    if (seconds <= 0) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '${t.day}/${t.month} $hh:$mm';
  }

  void _openInBrowser() {
    final v = _version;
    if (v == null) return;
    launchUrl(widget.client.artifactUri(v.url),
        mode: LaunchMode.externalApplication);
  }

  Future<void> _more(BuildContext anchor) async {
    final picked = await showAppMenu<String>(
      context,
      anchor: anchor,
      minWidth: 220,
      items: [
        appMenuRow<String>(
            value: 'browser', icon: 'globe', label: 'Open in browser'),
        appMenuRow<String>(
            value: 'latest', icon: 'refresh', label: 'Latest version'),
        if (kMobile)
          appMenuRow<String>(
              value: 'download', icon: 'download', label: 'Download'),
        appMenuRow<String>(value: 'copy', icon: 'copy', label: 'Copy path'),
      ],
    );
    if (!mounted) return;
    switch (picked) {
      case 'copy':
        final v = _version;
        Clipboard.setData(ClipboardData(
            text: v == null || v.source.isEmpty ? widget.id : v.source));
        toast(context, 'Path copied');
      case 'browser':
        _openInBrowser();
      case 'latest':
        _load(latest: true);
      case 'download':
        _download();
    }
  }

  Widget _versionLabel() {
    final v = _version;
    if (v == null) return const SizedBox.shrink();
    final when = _when(v.createdAt);
    final multi = (_artifact?.versions.length ?? 0) > 1;
    final style = sans(13, color: AppColors.fg3);
    return Builder(
      builder: (anchor) => TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: multi ? () => _pickVersion(anchor) : null,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: S.s8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text('Version ${v.n}${when.isEmpty ? '' : ' · $when'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
            ),
            if (multi) ...[
              SizedBox(width: S.s4),
              AppIcon('chevron-down', size: 12, color: AppColors.fg3),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _sourceSeg() => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final (src, label) in [(false, 'Preview'), (true, 'Source')])
            TapDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _source = src),
              child: Container(
                height: kTapTarget - 6,
                padding: EdgeInsets.symmetric(horizontal: S.s16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _source == src ? AppColors.surface3 : null,
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Text(label,
                    style: sans(13,
                        weight: _source == src ? W.label : W.body,
                        color: _source == src ? AppColors.fg1 : AppColors.fg3)),
              ),
            ),
        ]),
      );

  Widget _subBar() {
    if (_version == null || !kMobile) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(
          kMobile ? M.gutter : S.s16, S.s4, kMobile ? M.gutter : S.s16, S.s4),
      child: Row(children: [
        if (_hasSource) ...[_sourceSeg(), SizedBox(width: S.s12)],
        Expanded(
          child:
              Align(alignment: Alignment.centerRight, child: _versionLabel()),
        ),
      ]),
    );
  }

  Widget _mobileHeader() {
    final a = _artifact;
    final v = _version;
    final sub = [
      if (a != null) _artifactKindLabel(a.kind),
      if (v != null) 'v${v.n}',
    ].join(' \u00b7 ');
    return Container(
      color: AppColors.bg,
      padding: EdgeInsets.fromLTRB(S.s8, S.s6, S.s8, S.s4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36,
          height: 4,
          margin: EdgeInsets.only(bottom: S.s6),
          decoration: BoxDecoration(
            color: AppColors.border2,
            borderRadius: BorderRadius.circular(R.pill),
          ),
        ),
        Row(children: [
          RoundBtn(
              icon: 'x',
              size: M.minTarget,
              iconSize: 20,
              tooltip: 'Close',
              onTap: widget.onClose),
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(a?.title ?? 'Artifact',
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: sans(15, weight: W.label, color: AppColors.fg1)),
              if (sub.isNotEmpty)
                Text(sub, maxLines: 1, style: sans(12, color: AppColors.fg2)),
            ]),
          ),
          Builder(
            builder: (anchor) => IconBtn('more-horizontal',
                size: M.minTarget,
                iconSize: 19,
                tooltip: 'More',
                onTap: () => _more(anchor)),
          ),
        ]),
      ]),
    );
  }

  Widget _header() {
    if (kMobile) return _mobileHeader();
    final a = _artifact;
    return Container(
      height: 52,
      padding: const EdgeInsets.fromLTRB(22, 0, 14, 0),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(children: [
        // Expanded, not Flexible + Spacer: that pair splits the row and strands the controls mid-way.
        Expanded(
          // A canvas pane is narrow: below this only the title stays.
          child: LayoutBuilder(
              builder: (context, box) => Row(children: [
                    Flexible(
                      child: Text(a?.title ?? 'Artifact',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              sans(14, weight: W.strong, color: AppColors.fg1)),
                    ),
                    if (a != null && box.maxWidth >= 260) ...[
                      const SizedBox(width: 8),
                      Container(
                        height: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: AppColors.surface3,
                            borderRadius: BorderRadius.circular(R.of(5))),
                        child: Text(_artifactKindLabel(a.kind),
                            style: sans(11.5, color: AppColors.fg2)),
                      ),
                    ],
                    if (box.maxWidth >= 260) ...[
                      const SizedBox(width: 8),
                      _versionButton(),
                    ],
                  ])),
        ),
        if (_hasSource) ...[_sourceSeg(), const SizedBox(width: 6)],
        _hit(
            IconBtn('external-link',
                size: 28,
                iconSize: 15,
                tooltip: 'Open in browser',
                onTap: _openInBrowser),
            _openInBrowser),
        _hit(
            IconBtn('download',
                size: 28, iconSize: 15, tooltip: 'Download', onTap: _download),
            _download),
        Builder(
          builder: (anchor) => _hit(
              IconBtn('more-horizontal',
                  size: 28,
                  iconSize: 15,
                  tooltip: 'More',
                  onTap: () => _more(anchor)),
              () => _more(anchor)),
        ),
        if (widget.onClose != null)
          _hit(
              IconBtn('x',
                  size: 28,
                  iconSize: 15,
                  tooltip: 'Close',
                  onTap: widget.onClose),
              widget.onClose),
      ]),
    );
  }

  /// Gives a small visual control a [kTapTarget] hit area without growing it.
  Widget _hit(Widget child, VoidCallback? onTap) => SizedBox(
        width: kTapTarget,
        height: kTapTarget,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(child: child),
        ),
      );

  Widget _versionButton() {
    final v = _version;
    final a = _artifact;
    if (v == null || a == null) return const SizedBox.shrink();
    final multi = a.versions.length > 1;
    final latest = v.n == a.latest?.n;
    return Builder(
      builder: (anchor) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(R.of(6)),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.of(6)),
          onTap: multi ? () => _pickVersion(anchor) : null,
          child: SizedBox(
            height: kTapTarget,
            child: Center(
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border2),
                  borderRadius: BorderRadius.circular(R.of(6)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  AppIcon('history', size: 13, color: AppColors.fg2),
                  const SizedBox(width: 6),
                  Text('v${v.n}${latest ? ' \u00b7 Latest version' : ''}',
                      style: sans(12, color: AppColors.fg2)),
                  if (multi) ...[
                    const SizedBox(width: 6),
                    AppIcon('chevron-down', size: 12, color: AppColors.fg2),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _centered(String text, {Widget? action}) => Center(
        child: Padding(
          padding: EdgeInsets.all(S.s24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(text,
                textAlign: TextAlign.center,
                style: sans(13, color: AppColors.fg3, height: 1.5)),
            if (action != null) ...[SizedBox(height: S.s12), action],
          ]),
        ),
      );

  Widget _fileCard(ArtifactInfo a, ArtifactVersion v) {
    final name = (v.source.isNotEmpty ? v.source : v.entry).split('/').last;
    final ext = _ext(name);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(S.of(28)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.tint2,
              borderRadius: BorderRadius.circular(R.of(20)),
            ),
            child: AppIcon(
                ext == 'pdf'
                    ? 'file-text'
                    : ext == 'apk' || ext == 'zip' || ext == 'gz'
                        ? 'file-archive'
                        : 'file',
                size: 28,
                color: AppColors.fg2),
          ),
          SizedBox(height: S.s16),
          Text(name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: sans(16, weight: W.label, color: AppColors.fg1)),
          SizedBox(height: S.s4),
          Text(ext.isEmpty ? 'File' : '${ext.toUpperCase()} file',
              style: sans(13, color: AppColors.fg3)),
          SizedBox(height: S.of(22)),
          Btn('Download', icon: 'download', onTap: _download),
          SizedBox(height: S.s8),
          Btn('Open in browser',
              icon: 'external-link',
              variant: BtnVariant.ghost,
              onTap: _openInBrowser),
        ]),
      ),
    );
  }

  Widget _textBody(ArtifactVersion v, Widget Function(String text) render) =>
      FutureBuilder<String>(
        future: _textOf(v),
        builder: (context, snap) {
          if (snap.hasError) return _centered('${snap.error}');
          if (!snap.hasData) {
            return Center(child: Spinner(size: 16, color: AppColors.fg3));
          }
          return render(snap.data!);
        },
      );

  Widget _sourceView(ArtifactVersion v) => _textBody(
        v,
        (text) => SingleChildScrollView(
          padding: EdgeInsets.all(S.s16),
          child: SelectableText(text,
              style: codeMono(12, height: 1.5, color: AppColors.fg2)),
        ),
      );

  Widget _preview(ArtifactInfo a, ArtifactVersion v) {
    final uri = widget.client.artifactUri(v.url);
    switch (a.kind) {
      case 'markdown':
        return _textBody(
          v,
          (text) => SingleChildScrollView(
            padding: kMobile
                ? EdgeInsets.fromLTRB(S.s20, S.s16, S.s20, S.s32)
                : const EdgeInsets.fromLTRB(28, 30, 28, 48),
            child: Center(
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: kMobile ? double.infinity : 720),
                child: SelectionArea(
                  child: MarkdownBody(
                      data: text,
                      styleSheet: kMobile
                          ? markdownStyle(context)
                          : documentMarkdownStyle(context),
                      builders: {'pre': PreBlockBuilder()},
                      onTapLink: (_, href, __) =>
                          openMarkdownLink(href, context)),
                ),
              ),
            ),
          ),
        );
      case 'image':
        return InteractiveViewer(
          maxScale: 6,
          child: Center(
              child: ArtifactImage(
                  client: widget.client,
                  url: v.url,
                  fit: BoxFit.contain,
                  fullSize: true)),
        );
      case 'csv':
        return _textBody(v, (text) => _CsvTable(text: text));
      case 'code':
        return _sourceView(v);
      case 'file':
        if (_isText(v.entry)) return _sourceView(v);
        return _fileCard(a, v);
      case 'pdf':
        if (defaultTargetPlatform == TargetPlatform.android) {
          return _fileCard(a, v);
        }
        continue web;
      web:
      default:
        if (!_canEmbedWeb) {
          return _centered('This page opens in your browser.',
              action: TextButton(
                  onPressed: _openInBrowser,
                  style: TextButton.styleFrom(
                      minimumSize: Size(kTapTarget, kTapTarget)),
                  child: const Text('Open in browser')));
        }
        final page = _WebPreview(key: ValueKey(v.url), uri: uri);
        return page;
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _artifact;
    final v = _version;
    return Material(
      color: kMobile ? AppColors.pageBg : Colors.transparent,
      child: SafeArea(
        bottom: false,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(),
          _subBar(),
          Expanded(
            child: _error != null
                ? _centered(_error!)
                : a == null || v == null
                    ? Center(child: Spinner(size: 16, color: AppColors.fg3))
                    : _source && _hasSource
                        ? _sourceView(v)
                        : _preview(a, v),
          ),
        ]),
      ),
    );
  }
}

class _WebPreview extends StatefulWidget {
  const _WebPreview({super.key, required this.uri});
  final Uri uri;

  @override
  State<_WebPreview> createState() => _WebPreviewState();
}

class _WebPreviewState extends State<_WebPreview> {
  String _page = '';
  int _progress = 0;
  String? _failed;
  Timer? _slow;
  late final WebViewController _controller = () {
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: _route,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onPageFinished: (_) {
          _slow?.cancel();
          if (mounted) setState(() => _progress = 100);
          _controller.runJavaScript(_page);
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == false || !mounted) return;
          setState(() => _failed = e.description);
        },
      ));
    if (!kMacOS) c.setBackgroundColor(Colors.white);
    return c..loadRequest(widget.uri);
  }();

  @override
  void initState() {
    super.initState();
    _slow = Timer(const Duration(seconds: 20), () {
      if (mounted && _progress < 100) {
        setState(() => _failed = 'This page is taking too long to load.');
      }
    });
  }

  @override
  void dispose() {
    _slow?.cancel();
    super.dispose();
  }

  NavigationDecision _route(NavigationRequest r) {
    final u = Uri.tryParse(r.url);
    if (u == null) return NavigationDecision.prevent;
    if (u.scheme == 'about' || u.scheme == 'data' || u.scheme == 'blob') {
      return NavigationDecision.navigate;
    }
    final sameOrigin = u.scheme == widget.uri.scheme &&
        u.host == widget.uri.host &&
        u.port == widget.uri.port;
    final ext = _ext(u.path);
    if (sameOrigin && (ext.isEmpty || _webExts.contains(ext))) {
      return NavigationDecision.navigate;
    }
    if (!r.isMainFrame) return NavigationDecision.navigate;
    launchUrl(u, mode: LaunchMode.externalApplication);
    return NavigationDecision.prevent;
  }

  // Scrolls that reach Flutter instead of the native view are passed to the page.
  void _scrollPage(Offset at, Offset d) {
    if (d == Offset.zero) return;
    _controller.runJavaScript('''(function(x,y,dx,dy){
  var el=document.elementFromPoint(x,y);
  for(;el&&el.nodeType===1&&el!==document.body&&el!==document.documentElement;el=el.parentElement){
    var s=getComputedStyle(el);
    if((s.overflowY==='auto'||s.overflowY==='scroll')&&el.scrollHeight>el.clientHeight+1){el.scrollBy(dx,dy);return;}
  }
  (document.scrollingElement||document.documentElement).scrollBy(dx,dy);
})(${at.dx},${at.dy},${d.dx},${d.dy})''');
  }

  void _retry() {
    setState(() {
      _failed = null;
      _progress = 0;
    });
    _controller.loadRequest(widget.uri);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    _page = snippetPageTheme(theme.brightness == Brightness.dark,
        _cssHex(theme.scaffoldBackgroundColor));
    if (_failed != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(S.s24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_failed!,
                textAlign: TextAlign.center,
                style: sans(13, color: AppColors.fg3, height: 1.5)),
            SizedBox(height: S.of(14)),
            Btn('Retry', icon: 'refresh', small: true, onTap: _retry),
            SizedBox(height: S.s6),
            Btn('Open in browser',
                icon: 'external-link',
                small: true,
                variant: BtnVariant.ghost,
                onTap: () => launchUrl(widget.uri,
                    mode: LaunchMode.externalApplication)),
          ]),
        ),
      );
    }
    return Stack(children: [
      Positioned.fill(
          child: Listener(
              onPointerSignal: (e) {
                if (e is PointerScrollEvent)
                  _scrollPage(e.localPosition, e.scrollDelta);
              },
              onPointerPanZoomUpdate: (e) =>
                  _scrollPage(e.localPosition, -e.panDelta),
              child: WebViewWidget(controller: _controller))),
      if (_progress < 100)
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: LinearProgressIndicator(
            value: _progress == 0 ? null : _progress / 100,
            minHeight: 2,
            backgroundColor: Colors.transparent,
            color: AppColors.accent,
          ),
        ),
    ]);
  }
}

class _CsvTable extends StatelessWidget {
  const _CsvTable({required this.text});
  final String text;

  List<List<String>> _rows() {
    final sep = text.split('\n').first.contains('\t') ? '\t' : ',';
    final rows = <List<String>>[];
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) continue;
      final cells = <String>[];
      final cell = StringBuffer();
      var quoted = false;
      for (var i = 0; i < line.length; i++) {
        final c = line[i];
        if (c == '"') {
          if (quoted && i + 1 < line.length && line[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = !quoted;
          }
        } else if (c == sep && !quoted) {
          cells.add(cell.toString());
          cell.clear();
        } else {
          cell.write(c);
        }
      }
      cells.add(cell.toString().trimRight());
      rows.add(cells);
      if (rows.length > 500) break;
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    if (rows.isEmpty) return const SizedBox.shrink();
    final width = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    Widget cell(String text, {bool head = false}) => Padding(
          padding: EdgeInsets.symmetric(horizontal: S.s12, vertical: S.s8),
          child: Text(text,
              style: head
                  ? sans(13, weight: W.label, color: AppColors.fg1)
                  : sans(13, color: AppColors.fg2)),
        );
    return SingleChildScrollView(
      padding: EdgeInsets.all(S.s16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder(
            horizontalInside: BorderSide(color: AppColors.border),
          ),
          children: [
            for (var i = 0; i < rows.length; i++)
              TableRow(
                decoration:
                    i == 0 ? BoxDecoration(color: AppColors.tint1) : null,
                children: [
                  for (var c = 0; c < width; c++)
                    cell(c < rows[i].length ? rows[i][c] : '', head: i == 0),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Everything a session has handed over: its artifacts, latest first, then
/// the files it sent, newest first.
class SessionDeliverables extends StatefulWidget {
  const SessionDeliverables({
    super.key,
    required this.client,
    required this.session,
    required this.files,
    this.onOpenFileTab,
    this.onClose,
  });

  final DaemonClient client;
  final String session;
  final List<({String path, String caption})> files;
  final void Function(String path, String name)? onOpenFileTab;
  final VoidCallback? onClose;

  @override
  State<SessionDeliverables> createState() => _SessionDeliverablesState();
}

class _SessionDeliverablesState extends State<SessionDeliverables> {
  List<ArtifactInfo>? _artifacts;
  String? _error;
  String? _selected;
  bool _dismissed = false;

  /// Desktop list beside the open artifact; narrow hosts keep the list alone
  /// and open artifacts in a drawer.
  Widget _split(List<ArtifactInfo> artifacts,
      List<({String path, String caption})> files) {
    final newest = [...artifacts]..sort((x, y) =>
        (y.latest?.createdAt ?? 0).compareTo(x.latest?.createdAt ?? 0));
    final sel =
        _selected ?? (_dismissed || newest.isEmpty ? null : newest.first.id);
    final open = artifacts.any((a) => a.id == sel) ? sel : null;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        width: 300,
        decoration: BoxDecoration(
            border: Border(right: BorderSide(color: AppColors.border))),
        child: ArtifactGrid(
          client: widget.client,
          session: widget.session,
          artifacts: artifacts,
          files: files,
          onOpenFileTab: widget.onOpenFileTab,
          selectedId: open,
          onSelect: (a) => setState(() {
            _selected = a.id;
            _dismissed = false;
          }),
        ),
      ),
      Expanded(
        child: open == null
            ? Center(
                child: Text('Select an artifact to preview it.',
                    style: sans(13, color: AppColors.fg4)))
            : ArtifactViewer(
                key: ValueKey('deliverable-$open'),
                client: widget.client,
                session: widget.session,
                id: open,
                onClose: () => setState(() {
                  _selected = null;
                  _dismissed = true;
                }),
              ),
      ),
    ]);
  }

  @override
  void initState() {
    super.initState();
    widget.client.artifacts(widget.session).then((a) {
      if (mounted) setState(() => _artifacts = a);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final artifacts = _artifacts;
    final seen = <String>{};
    final files = [
      for (final f in widget.files.reversed)
        if (seen.add(f.path)) f,
    ];
    if (!kMobile &&
        _error == null &&
        artifacts != null &&
        (artifacts.isNotEmpty || files.isNotEmpty)) {
      return Material(
        color: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, box) => box.maxWidth >= 640
              ? _split(artifacts, files)
              : _wrap(context, artifacts, files),
        ),
      );
    }
    return _wrap(context, artifacts, files);
  }

  Widget _wrap(BuildContext context, List<ArtifactInfo>? artifacts,
      List<({String path, String caption})> files) {
    return Material(
      color: kMobile ? AppColors.pageBg : Colors.transparent,
      child: SafeArea(
        bottom: false,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (kMobile)
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: EdgeInsets.only(top: S.s6),
                decoration: BoxDecoration(
                  color: AppColors.border2,
                  borderRadius: BorderRadius.circular(R.pill),
                ),
              ),
            ),
          if (kMobile && !ShellPanelRoot.inPanel(context))
            _SheetHeader(onDone: widget.onClose)
          else if (!ShellPanelRoot.inPanel(context))
            Container(
              padding: EdgeInsets.fromLTRB(
                  S.s16, kMobile ? S.s8 : S.s12, S.s8, S.of(10)),
              child: Row(children: [
                Expanded(
                  child: Text('Artifacts & files',
                      style: sans(15, weight: W.label, color: AppColors.fg1)),
                ),
                if (widget.onClose != null)
                  IconBtn('x',
                      size: 32,
                      iconSize: 15,
                      tooltip: 'Close',
                      onTap: widget.onClose),
              ]),
            ),
          Expanded(
            child: _error != null
                ? EmptyState(
                    icon: 'alert-triangle',
                    title: 'Couldn\'t load artifacts',
                    body: _error)
                : artifacts == null
                    ? Center(child: Spinner(size: 16, color: AppColors.fg3))
                    : artifacts.isEmpty && files.isEmpty
                        ? const EmptyState(
                            icon: 'layers',
                            title: 'Nothing shared yet',
                            body:
                                'Artifacts and files the agent hands over in this chat collect here.',
                          )
                        : !kMobile
                            ? ArtifactGrid(
                                client: widget.client,
                                session: widget.session,
                                artifacts: artifacts,
                                files: files,
                                onOpenFileTab: widget.onOpenFileTab,
                              )
                            : ArtifactCollection(
                                client: widget.client,
                                session: widget.session,
                                artifacts: artifacts,
                                files: files,
                                onOpenFileTab: widget.onOpenFileTab,
                              ),
          ),
        ]),
      ),
    );
  }
}

/// Phone sheet header: close, centred title, like the board's viewer sheets.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({this.onDone});

  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: SizedBox(
          height: 48,
          child: Row(children: [
            SizedBox(
              width: 48,
              child: onDone == null
                  ? null
                  : RoundBtn(
                      key: const ValueKey('deliverables-done'),
                      icon: 'x',
                      size: 48,
                      iconSize: 20,
                      tooltip: 'Close',
                      onTap: onDone),
            ),
            Expanded(
              child: Text('Artifacts and files',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(15, weight: W.label, color: AppColors.fg1)),
            ),
            const SizedBox(width: 48),
          ]),
        ),
      );
}
