import 'package:flutter/material.dart';

import '../api.dart' show DaemonClient;
import '../media_views.dart' show DaemonScope;
import '../platform.dart';
import '../screens/artifact_viewer.dart' show openArtifact;
import '../theme.dart';
import '../widgets.dart' show AppIcon;
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
    final by = [
      if (card?.author != null)
        'By ${card!.author == 'user' ? 'You' : card.author}',
      if (card?.updatedAt != null) formatCanvasRelativeTime(card!.updatedAt!),
    ].join(', ');
    return Semantics(
      button: true,
      label: 'Open ${label.isEmpty ? 'artifact' : label.toLowerCase()} $title',
      child: Align(
        alignment: Alignment.centerLeft,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: kMobile ? double.infinity : 400),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: kMobile ? AppColors.surface1 : AppColors.surface2,
              borderRadius: BorderRadius.circular(R.of(14)),
              border: Border.all(color: AppColors.border),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: card == null ? null : _open,
                child: Padding(
                  padding: EdgeInsets.all(S.s8),
                  child: LayoutBuilder(builder: (context, box) {
                    final compact = box.maxWidth < 300;
                    return Row(
                      children: [
                        if (!compact) ...[
                          _thumb(card),
                          SizedBox(width: S.s12),
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
                                      color: AppColors.fg1)),
                              SizedBox(height: S.s2),
                              Text(
                                  _loading
                                      ? 'Loading'
                                      : _missing
                                          ? 'No longer available'
                                          : meta,
                                  maxLines: 1,
                                  style: sans(12,
                                      height: 1.35, color: AppColors.fg3)),
                              if (by.isNotEmpty)
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
                          Container(
                            constraints: BoxConstraints(
                                minHeight: kMobile ? 48 : 44,
                                minWidth: kMobile ? 84 : 44),
                            alignment: Alignment.center,
                            padding: EdgeInsets.symmetric(horizontal: S.s8),
                            decoration: kMobile
                                ? BoxDecoration(
                                    color: AppColors.surface2,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: AppColors.border))
                                : null,
                            child: Text('Open',
                                style: sans(kMobile ? 14 : 13,
                                    weight: W.label,
                                    color: kMobile
                                        ? AppColors.fg1
                                        : AppColors.accent)),
                          ),
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
    final box = BorderRadius.circular(10);
    Widget fallback() => Container(
          width: 72,
          height: 72,
          decoration:
              BoxDecoration(color: AppColors.surface1, borderRadius: box),
          alignment: Alignment.center,
          child: AppIcon(
            switch (card?.kind) {
              'canvas' => 'grid',
              'image' => 'image',
              'pdf' => 'pdf',
              'document' => 'file-text',
              _ => 'file',
            },
            size: 22,
            color: AppColors.fg3,
          ),
        );
    if (url == null || daemon == null) return fallback();
    return ClipRRect(
      borderRadius: box,
      child: SizedBox(
        width: 96,
        height: 72,
        child: Image(
          image: ResizeImage(daemon.canvasImage(url), width: 256),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback(),
        ),
      ),
    );
  }
}
