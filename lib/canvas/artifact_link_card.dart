import 'package:flutter/material.dart';

import '../api.dart' show DaemonClient;
import '../media_views.dart' show DaemonScope;
import '../platform.dart';
import '../screens/artifact_viewer.dart' show openArtifact;
import '../theme.dart';
import '../widgets.dart' show AppIcon;
import '../chat/desktop_rich_cards.dart';
import 'artifact_cards.dart';
import 'canvas_link.dart';
import 'canvas_link_card.dart';
import 'canvas_models.dart' show formatCanvasRelativeTime;
import 'canvas_nav.dart';

/// Opens a card in its own home: a canvas as a shell tab, everything else in
/// the existing artifact viewer.
void openArtifactCard(
    BuildContext context, DaemonClient client, ArtifactCard card,
    {int? rev}) {
  if (card.isCanvas) {
    openCanvas(context, canvasId: card.id, title: card.displayTitle);
    return;
  }
  final doc = card.documentRef;
  if (doc == null) return;
  openArtifact(context,
      client: client,
      session: doc.session,
      id: doc.id,
      version: rev,
      title: card.displayTitle);
}

/// The chat card for any link: `canvas:` deep links keep their live frame
/// card, `artifact:` links show the one shared card.
Widget linkCardFor(CanvasMarkdownSegment seg, DaemonClient? client) =>
    switch (seg) {
      CanvasCardSegment(:final title, :final ref, :final inline) =>
        CanvasLinkCard(
          title: title,
          canvasRef: ref,
          daemonClient: client,
          inline: inline,
        ),
      ArtifactCardSegment(:final title, :final ref, :final inline) =>
        ArtifactLinkCard(
          title: title,
          artifactRef: ref,
          daemonClient: client,
          inline: inline,
        ),
      CanvasTextSegment() => const SizedBox.shrink(),
    };

typedef ArtifactResolver = Future<ArtifactCard?> Function(String id);

/// Compact chat card for an `artifact:<id>` link of any kind.
class ArtifactLinkCard extends StatefulWidget {
  const ArtifactLinkCard({
    super.key,
    required this.title,
    required this.artifactRef,
    this.daemonClient,
    this.resolver,
    this.inline = false,
  });

  final String title;
  final ArtifactRef artifactRef;
  final DaemonClient? daemonClient;

  /// Replaces the daemon lookup (tests).
  final ArtifactResolver? resolver;
  final bool inline;

  @override
  State<ArtifactLinkCard> createState() => _ArtifactLinkCardState();
}

class _ArtifactLinkCardState extends State<ArtifactLinkCard> {
  ArtifactCard? _card;
  bool _loading = true;
  bool _missing = false;
  bool _started = false;

  DaemonClient? get _daemon =>
      widget.daemonClient ??
      DaemonScope.maybeOf(context) ??
      DaemonScope.current;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final resolver = widget.resolver;
    final daemon = _daemon;
    try {
      ArtifactCard? card;
      if (resolver != null) {
        card = await resolver(widget.artifactRef.id);
      } else if (daemon != null) {
        final json =
            await daemon.resolveArtifactCard(widget.artifactRef.format());
        card = json == null ? null : ArtifactCard.fromJson(json);
      }
      if (!mounted) return;
      setState(() {
        _card = card;
        _missing = card == null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _missing = true;
        _loading = false;
      });
    }
  }

  void _open() {
    final card = _card;
    final daemon = _daemon;
    if (card == null || daemon == null) return;
    openArtifactCard(context, daemon, card, rev: widget.artifactRef.rev);
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    if (_missing && widget.inline) return const SizedBox.shrink();
    final title = card?.displayTitle ??
        (widget.title.isNotEmpty ? widget.title : widget.artifactRef.id);
    final label = card == null ? '' : card.kindLabel;
    final rev = widget.artifactRef.rev ?? card?.rev;
    final meta = [
      if (label.isNotEmpty) label,
      if (rev != null && rev > 0) 'rev $rev',
    ].join(' · ');
    final rawAuthor = card?.author?.trim() ?? '';
    final isPathAuthor = rawAuthor.startsWith('/') || rawAuthor.startsWith('~');
    final by = [
      if (rawAuthor.isNotEmpty && !isPathAuthor)
        'By ${rawAuthor == 'user' ? 'You' : rawAuthor}',
      if (card?.updatedAt != null) formatCanvasRelativeTime(card!.updatedAt!),
    ].join(', ');
    final subline = [
      if (_loading)
        'Loading'
      else if (_missing)
        'No longer available'
      else ...[
        if (meta.isNotEmpty) meta,
        if (!kMobile && by.isNotEmpty) by,
      ],
    ].join(' · ');
    return Semantics(
      button: true,
      label: 'Open ${label.isEmpty ? 'artifact' : label.toLowerCase()} $title',
      child: Align(
        alignment: Alignment.centerLeft,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: kMobile ? double.infinity : 460),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              // Phone board: a flat surface2 card, no outline.
              color: kMobile ? AppColors.surface2 : AppColors.surface1,
              borderRadius: BorderRadius.circular(kMobile ? 18 : 8),
              border: kMobile ? null : Border.all(color: AppColors.border),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: card == null ? null : _open,
                child: Padding(
                  padding: kMobile
                      ? EdgeInsets.all(S.s8)
                      : const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                  child: LayoutBuilder(builder: (context, box) {
                    final compact = box.maxWidth < 300;
                    return Row(
                      children: [
                        if (!compact) ...[
                          _thumb(card),
                          SizedBox(width: kMobile ? S.s12 : 10),
                        ],
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: sans(kMobile ? 14 : 13,
                                      weight: W.label,
                                      height: 1.3,
                                      color: kMobile
                                          ? AppColors.fg1
                                          : PaneRow.labelOn)),
                              if (subline.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(subline,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: sans(kMobile ? 12 : 11.5,
                                        height: 1.35,
                                        color: kMobile
                                            ? AppColors.fg3
                                            : AppColors.fg3)),
                              ],
                              if (kMobile && by.isNotEmpty)
                                Text(by,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: sans(12,
                                        height: 1.35, color: AppColors.fg3)),
                            ],
                          ),
                        ),
                        if (card != null) ...[
                          SizedBox(width: S.s8),
                          if (kMobile)
                            // A 40 s3 pill in a 48 target, as the board's pills.
                            Container(
                              constraints: const BoxConstraints(
                                  minHeight: 48, minWidth: 76),
                              alignment: Alignment.center,
                              child: Container(
                                height: 40,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                    color: AppColors.surface3,
                                    borderRadius: BorderRadius.circular(20)),
                                child: Text('Open',
                                    style: sans(14.5,
                                        weight: FontWeight.w500,
                                        color: AppColors.fg1)),
                              ),
                            )
                          else
                            DesktopRichButton('Open',
                                variant: DesktopRichButtonVariant.ghost,
                                onTap: _open),
                        ],
                      ],
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumb(ArtifactCard? card) {
    final url = card?.thumbUrl;
    final daemon = _daemon;
    final box = BorderRadius.circular(kMobile ? 10 : 7);
    Widget fallback() => Container(
          width: kMobile ? 72 : 36,
          height: kMobile ? 72 : 36,
          decoration: BoxDecoration(
            color: kMobile ? AppColors.surface1 : AppColors.surface2,
            borderRadius: box,
            border: kMobile ? null : Border.all(color: AppColors.border),
          ),
          alignment: Alignment.center,
          child: AppIcon(
            switch (card?.kind) {
              'canvas' => 'grid',
              'image' => 'image',
              'pdf' => 'pdf',
              'document' => 'file-text',
              _ => 'file',
            },
            size: kMobile ? 22 : 16,
            color: kMobile ? AppColors.fg3 : AppColors.fg2,
          ),
        );
    if (url == null || daemon == null) return fallback();
    return ClipRRect(
      borderRadius: box,
      child: SizedBox(
        width: kMobile ? 96 : 48,
        height: kMobile ? 72 : 38,
        child: Image(
          image: ResizeImage(daemon.canvasImage(url), width: 256),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback(),
        ),
      ),
    );
  }
}
