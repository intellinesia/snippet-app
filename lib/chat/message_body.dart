import 'package:flutter/material.dart';
import 'draft_sink.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;

import '../api.dart';
import '../canvas/canvas_link.dart';
import '../canvas/artifact_link_card.dart' show linkCardFor;
import '../media_views.dart';
import '../message_reactions.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'chat_style.dart';
import 'desktop_rich_cards.dart';

final _standaloneUrlRe =
    RegExp(r'^(?:<(https?://[^\s<>]+)>|(https?://[^\s<>]+))$');
final _linkedInActivityRe =
    RegExp(r'-activity-\d+(?:-[A-Za-z0-9_]+)?$', caseSensitive: false);

String _decodeSegment(String raw) {
  try {
    return Uri.decodeComponent(raw);
  } catch (_) {
    return raw;
  }
}

String _humaniseSlug(String raw) => raw
    .replaceAll(RegExp(r'[-_]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Host and human-readable title derived from a standalone link URL.
({String host, String title}) describeLinkUrl(Uri uri) {
  var host = uri.host.toLowerCase();
  if (host.startsWith('www.')) host = host.substring(4);
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if ((host == 'linkedin.com' || host.endsWith('.linkedin.com')) &&
      segments.length >= 2 &&
      segments[0] == 'posts') {
    final rawSlug = _decodeSegment(segments[1]);
    final stripped = rawSlug.replaceFirst(_linkedInActivityRe, '');
    final underscore = stripped.indexOf('_');
    if (underscore > 0) {
      final author = _humaniseSlug(stripped.substring(0, underscore));
      final slug = _humaniseSlug(stripped.substring(underscore + 1));
      if (author.isNotEmpty && slug.isNotEmpty) {
        return (host: host, title: '$author · $slug');
      }
      if (author.isNotEmpty) return (host: host, title: author);
    } else {
      final fallback = _humaniseSlug(stripped);
      if (fallback.isNotEmpty) return (host: host, title: fallback);
    }
  }
  if (segments.isNotEmpty) {
    final last = _humaniseSlug(_decodeSegment(segments.last));
    if (last.isNotEmpty) return (host: host, title: last);
  }
  return (host: host, title: host);
}

sealed class _BodySegment {}

class _MarkdownSegment extends _BodySegment {
  _MarkdownSegment(this.text);
  final String text;
}

class _LinkSegment extends _BodySegment {
  _LinkSegment(this.url, this.uri);
  final String url;
  final Uri uri;
}

class _CanvasSegment extends _BodySegment {
  _CanvasSegment(this.card);
  final CanvasMarkdownSegment card;
}

List<_BodySegment> _splitBodySegments(String shown) {
  final unwrapped = unwrapCodedLinks(shown);
  final canvasSegs = splitCanvasMarkdown(unwrapped);
  final out = <_BodySegment>[];

  for (final seg in canvasSegs) {
    switch (seg) {
      case CanvasCardSegment() || ArtifactCardSegment():
        out.add(_CanvasSegment(seg));
      case CanvasTextSegment(:final text):
        final mdLines = <String>[];
        var inFence = false;

        void flushMd() {
          if (mdLines.isEmpty) return;
          final chunk = mdLines.join('\n').trim();
          mdLines.clear();
          if (chunk.isNotEmpty) out.add(_MarkdownSegment(chunk));
        }

        for (final line in text.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
            inFence = !inFence;
            mdLines.add(line);
            continue;
          }
          if (!inFence) {
            final m = _standaloneUrlRe.firstMatch(trimmed);
            if (m != null) {
              final url = (m.group(1) ?? m.group(2))!;
              final uri = Uri.tryParse(url);
              if (uri != null &&
                  (uri.scheme == 'http' || uri.scheme == 'https') &&
                  uri.host.isNotEmpty) {
                flushMd();
                out.add(_LinkSegment(url, uri));
                continue;
              }
            }
          }
          mdLines.add(line);
        }
        flushMd();
    }
  }
  return out;
}

String _blockquotePlainText(md.Node node) {
  if (node is md.Text) return node.text;
  if (node is! md.Element) return node.textContent;
  if (node.tag == 'br') return '\n';
  final children = node.children;
  if (children == null || children.isEmpty) return '';
  if (node.tag == 'blockquote' || node.tag == 'ul' || node.tag == 'ol') {
    final sep = node.tag == 'blockquote' ? '\n\n' : '\n';
    return [for (final c in children) _blockquotePlainText(c)]
        .where((s) => s.isNotEmpty)
        .join(sep);
  }
  if (node.tag == 'li') {
    return '- ${children.map(_blockquotePlainText).join()}';
  }
  return children.map(_blockquotePlainText).join();
}

Widget _phoneListBullet(MarkdownBulletParameters parameters) {
  if (!kMobile) {
    return Text(
      parameters.style == BulletStyle.unorderedList
          ? '•'
          : '${parameters.index + 1}.',
      textAlign: parameters.style == BulletStyle.unorderedList
          ? TextAlign.center
          : TextAlign.right,
      style: sans(15, color: AppColors.fg2),
    );
  }
  if (parameters.style == BulletStyle.unorderedList) {
    return Align(
      alignment: Alignment.center,
      child: Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(color: AppColors.fg2, shape: BoxShape.circle),
      ),
    );
  }
  return Text('${parameters.index + 1}.',
      textAlign: TextAlign.right, style: sans(15, color: AppColors.fg2));
}

/// Renders markdown blockquotes in chat bubbles as copyable draft cards.
class DraftBlockBuilder extends MarkdownElementBuilder {
  DraftBlockBuilder({required this.mine});

  final bool mine;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(BuildContext context, md.Element element,
      TextStyle? preferredStyle, TextStyle? parentStyle) {
    final plain = _blockquotePlainText(element).trim();
    if (plain.isEmpty) return null;
    return _DraftCard(text: plain, mine: mine);
  }
}

class _DraftCard extends StatefulWidget {
  const _DraftCard({required this.text, required this.mine});

  final String text;
  final bool mine;

  @override
  State<_DraftCard> createState() => _DraftCardState();
}

class _DraftCardState extends State<_DraftCard> {
  bool _dismissed = false;

  String get text => widget.text;
  bool get mine => widget.mine;

  Widget _phone() => Container(
        width: double.infinity,
        margin: EdgeInsets.symmetric(vertical: S.s4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: AppColors.surface1, borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Draft message',
                style: sans(13, weight: FontWeight.w500, color: AppColors.fg1)),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              height: 126,
              padding: const EdgeInsets.all(8),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SingleChildScrollView(
                child: Text(text,
                    style: sans(15, height: 1.4, color: AppColors.fg1)),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              SizedBox(
                width: 72,
                child: DesktopRichButton('Copy',
                    variant: DesktopRichButtonVariant.secondary,
                    parentSurface: 1, onTap: () {
                  Clipboard.setData(ClipboardData(text: text));
                  toast(context, 'Copied');
                }),
              ),
              const SizedBox(width: 8),
              DesktopRichButton('Post to group', parentSurface: 1, onTap: () {
                if (!DraftSink.use(text)) {
                  Clipboard.setData(ClipboardData(text: text));
                  toast(context, 'Draft copied');
                }
              }),
            ]),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    if (_dismissed) return const SizedBox.shrink();
    if (kMobile) return _phone();
    return Padding(
      padding: EdgeInsets.symmetric(vertical: S.s4),
      child: DesktopDraftBlock(
        text: text,
        onUse: () {
          if (!DraftSink.use(text)) {
            Clipboard.setData(ClipboardData(text: text));
            toast(context, 'Copied');
          }
        },
        onDismiss: () => setState(() => _dismissed = true),
      ),
    );
  }
}

/// Metadata for RC-10. The daemon does not currently expose an unfurl endpoint;
/// when one is added it can be wired through [phoneLinkPreviewLoader] without
/// changing the chat renderer.
class LinkPreviewData {
  const LinkPreviewData({this.title = '', this.snippet = ''});
  final String title;
  final String snippet;
}

typedef LinkPreviewLoader = Future<LinkPreviewData?> Function(Uri uri);

/// Phone-only preview resolver. Null means no daemon metadata path exists yet,
/// so the card uses the deterministic URL-derived ready treatment.
LinkPreviewLoader? phoneLinkPreviewLoader;

class _LinkCard extends StatefulWidget {
  const _LinkCard({required this.url, required this.uri});

  final String url;
  final Uri uri;

  @override
  State<_LinkCard> createState() => _LinkCardState();
}

class _LinkCardState extends State<_LinkCard> {
  LinkPreviewData? _data;
  bool _loading = false;
  bool _failed = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_LinkCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _load();
  }

  Future<void> _load() async {
    final loader = phoneLinkPreviewLoader;
    if (!kMobile || loader == null) return;
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _failed = false;
      _data = null;
    });
    try {
      final data = await loader(widget.uri);
      if (!mounted || seq != _seq) return;
      final empty = data == null ||
          (data.title.trim().isEmpty && data.snippet.trim().isEmpty);
      setState(() {
        _data = data;
        _loading = false;
        _failed = empty;
      });
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final info = describeLinkUrl(widget.uri);
    if (!kMobile) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: S.s4),
        child: DesktopLinkPreviewCard(
          url: widget.url,
          title: info.title,
          host: info.host,
          onTap: () => openMarkdownLink(widget.url, context),
        ),
      );
    }
    if (_loading) return _loadingCard();
    if (_failed) return _failedCard(info);
    return _readyCard(info);
  }

  String get _hostPath {
    final path = widget.uri.path.replaceAll(RegExp(r'^/+'), '');
    return path.isEmpty ? widget.uri.host : '${widget.uri.host}/$path';
  }

  Widget _shell({required double height, required Widget child}) => Container(
        width: double.infinity,
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => openMarkdownLink(widget.url, context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: child,
            ),
          ),
        ),
      );

  Widget _loadingCard() {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(3),
          ),
        );
    return _shell(
      height: 92,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            bar(180.5, 10),
            const SizedBox(height: 8),
            bar(212.7, 8),
          ]),
        ]),
        const Spacer(),
        Text('Fetching preview for $_hostPath',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sans(12, color: AppColors.fg3)),
      ]),
    );
  }

  Widget _failedCard(({String host, String title}) info) => _shell(
        height: 96,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AppIcon('link', size: 14, color: AppColors.fg2),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_hostPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, color: AppColors.fg1)),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            AppIcon('x', size: 12, color: AppColors.fg2),
            const SizedBox(width: 8),
            Expanded(
              child: Text('No preview available',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, color: AppColors.fg2)),
            ),
            Material(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => openMarkdownLink(widget.url, context),
                child: SizedBox(
                  height: 36,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      AppIcon('external-link', size: 14, color: AppColors.fg1),
                      const SizedBox(width: 4),
                      Text('Open link',
                          style: sans(13,
                              weight: FontWeight.w500, color: AppColors.fg1)),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ]),
      );

  Widget _readyCard(({String host, String title}) info) {
    final firstSegment = widget.uri.pathSegments.isEmpty
        ? ''
        : ' - ${widget.uri.pathSegments.first}';
    final title = _data?.title.trim().isNotEmpty == true
        ? _data!.title.trim()
        : info.title;
    final snippet = _data?.snippet.trim().isNotEmpty == true
        ? _data!.snippet.trim()
        : widget.url;
    return _shell(
      height: 146,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AppIcon('link', size: 14, color: AppColors.fg2),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${info.host}$firstSegment',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(13, color: AppColors.fg3)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: sans(15,
                weight: FontWeight.w500,
                height: 21 / 15,
                color: AppColors.fg1)),
        const SizedBox(height: 4),
        Expanded(
          child: Align(
            alignment: Alignment.topLeft,
            child: Text(snippet,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: sans(13, height: 18 / 13, color: AppColors.fg2)),
          ),
        ),
      ]),
    );
  }
}

String _sentIconFor(String path) {
  final ext = path.split('.').last.toLowerCase();
  return switch (ext) {
    'md' || 'txt' || 'log' => 'file-text',
    'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' => 'image',
    'zip' || 'tar' || 'gz' => 'archive',
    'mp3' || 'wav' || 'm4a' || 'ogg' => 'file-audio',
    'mp4' || 'mov' || 'webm' => 'file-video',
    _ => 'file',
  };
}

/// A chat bubble's content: text as markdown plus sent images, files, voice
/// notes with their transcripts, and pasted blocks.
class ChatMessageBody extends StatelessWidget {
  const ChatMessageBody({
    super.key,
    required this.client,
    required this.body,
    required this.mine,
    this.markdown,
  });

  final DaemonClient client;
  final String body;
  final bool mine;

  /// Rewrites the visible text before it is rendered, e.g. to bold mentions.
  final String Function(String text)? markdown;

  @override
  Widget build(BuildContext context) {
    final (pasted, text) = splitPastedBlocks(body);
    final transcripts = audioTranscriptItems(text);
    final shown = hideAttachmentMarkers(text);
    final attachments =
        mine ? parseSentAttachments(body) : const <SentAttachment>[];
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
    final segments =
        shown.isNotEmpty ? _splitBodySegments(shown) : const <_BodySegment>[];
    final styleSheet = chatMarkdownStyle(context, mine: mine).copyWith(
      blockquotePadding: EdgeInsets.zero,
      blockquoteDecoration: const BoxDecoration(),
    );
    final builders = <String, MarkdownElementBuilder>{
      'pre': PreBlockBuilder(),
      'blockquote': DraftBlockBuilder(mine: mine),
    };
    Widget? textWidget;
    if (segments.length == 1 && segments.first is _MarkdownSegment) {
      final seg = segments.first as _MarkdownSegment;
      textWidget = MarkdownBody(
        data: unwrapCodedLinks(markdown?.call(seg.text) ?? seg.text),
        selectable: false,
        extensionSet: md.ExtensionSet.gitHubFlavored,
        styleSheet: styleSheet,
        builders: builders,
        bulletBuilder: _phoneListBullet,
        onTapLink: (txt, href, title) => openMarkdownLink(href, context, txt),
      );
    } else if (segments.isNotEmpty) {
      textWidget = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0) SizedBox(height: S.s6),
            switch (segments[i]) {
              _MarkdownSegment(:final text) => MarkdownBody(
                  data: unwrapCodedLinks(markdown?.call(text) ?? text),
                  selectable: false,
                  extensionSet: md.ExtensionSet.gitHubFlavored,
                  styleSheet: styleSheet,
                  builders: builders,
                  onTapLink: (txt, href, title) =>
                      openMarkdownLink(href, context, txt),
                ),
              _LinkSegment(:final url, :final uri) =>
                _LinkCard(url: url, uri: uri),
              _CanvasSegment(:final card) => linkCardFor(card, client),
            },
          ],
        ],
      );
    }
    final styledText = textWidget == null
        ? null
        : (kMobile ? textWidget : MessageSelectionArea(child: textWidget));
    final hasExtras = images.isNotEmpty ||
        files.isNotEmpty ||
        audio.isNotEmpty ||
        pasted.isNotEmpty;
    if (!hasExtras) return styledText ?? const SizedBox.shrink();
    final maxWidth = kMobile
        ? (MediaQuery.sizeOf(context).width - 32).clamp(160.0, 361.0)
        : (MediaQuery.sizeOf(context).width - 40).clamp(220.0, 420.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (images.isNotEmpty) ...[
          ImageGallery(client: client, paths: images, maxWidth: maxWidth),
          if (styledText != null ||
              files.isNotEmpty ||
              audio.isNotEmpty ||
              pasted.isNotEmpty)
            SizedBox(height: S.s6),
        ],
        if (files.isNotEmpty) ...[
          for (var i = 0; i < files.length; i++) ...[
            if (i > 0) SizedBox(height: S.s6),
            kMobile
                ? DesktopSentAttachmentRow(
                    icon: _sentIconFor(files[i]),
                    name: baseName(files[i]),
                    onOpen: () => openMedia(context, client, files[i]),
                  )
                : FileChip(client: client, path: files[i]),
          ],
          if (styledText != null || audio.isNotEmpty || pasted.isNotEmpty)
            SizedBox(height: S.s6),
        ],
        for (var i = 0; i < audio.length; i++) ...[
          VoiceNote(
            client: client,
            path: audio[i],
            ink: mine ? ChatColors.sentTextIn(context) : AppColors.fg1,
            transcript: kMobile
                ? null
                : (i < transcripts.length
                    ? AudioTranscriptCard(items: [transcripts[i]])
                    : (transcripts.isEmpty
                        ? Text('Transcribing…',
                            style: chatText(mine: mine, context: context))
                        : null)),
          ),
          if (kMobile && i < transcripts.length) ...[
            SizedBox(height: S.s6),
            AudioTranscriptCard(items: [transcripts[i]]),
          ],
          if (styledText != null || pasted.isNotEmpty || i < audio.length - 1)
            SizedBox(height: S.s6),
        ],
        if (styledText != null) styledText,
        for (final block in pasted) ...[
          SizedBox(height: S.s6),
          PastedTextCard(text: block),
        ],
      ],
    );
  }
}
