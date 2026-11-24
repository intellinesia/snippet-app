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

String _humaniseSlug(String raw) =>
    raw.replaceAll(RegExp(r'[-_]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

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
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: AppColors.surface1, borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              AppIcon('edit', size: 16, color: AppColors.fg2),
              const SizedBox(width: 8),
              Text('Draft reply',
                  style: sans(12, weight: W.label, color: AppColors.fg2)),
            ]),
            const SizedBox(height: 8),
            Text(text,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: sans(15, height: 1.4, color: AppColors.fg1)),
            const SizedBox(height: 12),
            DraftActions(
              onUse: () {
                if (!DraftSink.use(text)) {
                  Clipboard.setData(ClipboardData(text: text));
                  toast(context, 'Copied');
                }
              },
              onDismiss: () => setState(() => _dismissed = true),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    if (kMobile) return _dismissed ? const SizedBox.shrink() : _phone();
    return Padding(
      padding: EdgeInsets.symmetric(vertical: S.s4),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(S.s12, S.s6, S.s8, S.s6),
              child: Row(
                children: [
                  Text('Draft',
                      style: sans(11, weight: W.label, color: AppColors.fg3)),
                  const Spacer(),
                  Builder(
                    builder: (btnCtx) => Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(R.sm),
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: text));
                          toast(btnCtx, 'Copied');
                        },
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: S.s6, vertical: S.of(3)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppIcon('copy', size: 12, color: AppColors.fg3),
                              SizedBox(width: S.s4),
                              Text('Copy',
                                  style: sans(11,
                                      weight: W.label, color: AppColors.fg2)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: AppColors.border),
            Padding(
              padding: EdgeInsets.fromLTRB(S.s12, S.s8, S.s12, S.of(10)),
              child: Text(
                text,
                style: chatText(mine: mine).copyWith(color: AppColors.fg1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.url, required this.uri});

  final String url;
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final info = describeLinkUrl(uri);
    final radius = BorderRadius.circular(kMobile ? 10 : R.lg);
    return Container(
      width: kMobile ? double.infinity : null,
      constraints: BoxConstraints(minHeight: kMobile ? 76 : 0),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: radius,
        border: kMobile ? null : Border.all(color: AppColors.border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: () => openMarkdownLink(url, context),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: kMobile ? 12 : S.s12, vertical: S.of(10)),
            child: Row(
              mainAxisSize: kMobile ? MainAxisSize.max : MainAxisSize.min,
              children: [
                if (kMobile)
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: AppColors.surface3,
                        borderRadius: BorderRadius.circular(8)),
                    child: AppIcon('globe', size: 20, color: AppColors.fg3),
                  )
                else
                  AppIcon('globe', size: 15, color: AppColors.fg3),
                SizedBox(width: S.of(10)),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        info.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13, weight: W.label, color: AppColors.fg1),
                      ),
                      SizedBox(height: S.s2),
                      Text(
                        info.host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: codeMono(11, color: AppColors.fg3),
                      ),
                    ],
                  ),
                ),
                if (kMobile) ...[
                  const SizedBox(width: 8),
                  AppIcon('external-link', size: 16, color: AppColors.fg3),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
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
          onTapLink: (txt, href, title) =>
              openMarkdownLink(href, context, txt),
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
      final maxWidth =
          (MediaQuery.sizeOf(context).width - 32).clamp(160.0, 280.0);
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
              FileChip(client: client, path: files[i]),
            ],
            if (styledText != null || audio.isNotEmpty || pasted.isNotEmpty)
              SizedBox(height: S.s6),
          ],
          for (var i = 0; i < audio.length; i++) ...[
            VoiceNote(
              client: client,
              path: audio[i],
              ink: mine ? ChatColors.sentTextIn(context) : AppColors.fg1,
              transcript: i < transcripts.length
                  ? AudioTranscriptCard(items: [transcripts[i]])
                  : (transcripts.isEmpty
                      ? Text('Transcribing…',
                          style: chatText(mine: mine, context: context))
                      : null),
            ),
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
