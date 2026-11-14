import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../api.dart';
import '../media_views.dart';
import '../message_reactions.dart';
import '../platform.dart';
import '../widgets.dart';
import 'chat_style.dart';

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
      final textWidget = shown.isNotEmpty
          ? MarkdownBody(
              data: unwrapCodedLinks(markdown?.call(shown) ?? shown),
              selectable: false,
              extensionSet: md.ExtensionSet.gitHubFlavored,
              styleSheet: chatMarkdownStyle(context, mine: mine),
              builders: {'pre': PreBlockBuilder()},
              onTapLink: (txt, href, title) =>
                  openMarkdownLink(href, context, txt),
            )
          : null;
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
              const SizedBox(height: 6),
          ],
          if (files.isNotEmpty) ...[
            for (var i = 0; i < files.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              FileChip(client: client, path: files[i]),
            ],
            if (styledText != null || audio.isNotEmpty || pasted.isNotEmpty)
              const SizedBox(height: 6),
          ],
          for (var i = 0; i < audio.length; i++) ...[
            VoiceNote(
              client: client,
              path: audio[i],
              ink: mine ? ChatColors.sentText : ChatColors.receivedText,
              transcript: i < transcripts.length
                  ? AudioTranscriptCard(items: [transcripts[i]])
                  : (transcripts.isEmpty
                      ? Text('Transcribing…', style: chatText(mine: mine))
                      : null),
            ),
            if (styledText != null || pasted.isNotEmpty || i < audio.length - 1)
              const SizedBox(height: 6),
          ],
          if (styledText != null) styledText,
          for (final block in pasted) ...[
            const SizedBox(height: 6),
            PastedTextCard(text: block),
          ],
        ],
      );
    }
}
