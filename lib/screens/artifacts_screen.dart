import 'package:flutter/material.dart';

import '../toast_avoid.dart';
import '../api.dart';
import '../canvas/artifact_cards.dart';
import '../canvas/artifact_link_card.dart';
import '../canvas/canvas_models.dart' show formatCanvasRelativeTime;
import '../canvas/canvas_nav.dart';
import '../media_views.dart' show DaemonScope;
import '../panel.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

/// Opens the one Artifacts list: a main-area shell tab on desktop, a page on
/// phone.
void openArtifactsList(BuildContext c) {
  final daemon = DaemonScope.maybeOf(c) ?? DaemonScope.current;
  if (daemon == null) return;
  if (!kMobile && ShellPanelScope.maybeOf(c) != null) {
    presentScreen<void>(
      c,
      style: PanelStyle.drawer,
      purpose: ShellPanelPurpose.artifacts,
      panelId: 'all',
      title: 'Artifacts',
      builder: (ctx, _) => ArtifactsScreen(client: daemon),
    );
    return;
  }
  Navigator.of(c).push<void>(
    MaterialPageRoute<void>(builder: (_) => ArtifactsScreen(client: daemon)),
  );
}

/// Canvases, documents, images, PDFs and files in one searchable list.
class ArtifactsScreen extends StatefulWidget {
  const ArtifactsScreen({super.key, required this.client});

  final DaemonClient client;

  @override
  State<ArtifactsScreen> createState() => _ArtifactsScreenState();
}

class _ArtifactsScreenState extends State<ArtifactsScreen> {
  List<ArtifactCard>? _all;
  String? _error;
  String _query = '';
  String? _kind;
  bool _creating = false;

  static const _kinds = <(String?, String)>[
    (null, 'All'),
    ('document', 'Documents'),
    ('canvas', 'Canvases'),
    ('image', 'Images'),
    ('pdf', 'PDFs'),
    ('file', 'Files'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final raw = await widget.client.getArtifactCards();
      if (!mounted) return;
      setState(() => _all = [
            for (final j in raw) ArtifactCard.fromJson(j),
          ].where((c) => c.id.isNotEmpty).toList());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _newCanvas() async {
    final title = await _askTitle();
    if (title == null || !mounted) return;
    setState(() => _creating = true);
    try {
      final j = await widget.client.postCanvas(title);
      final id = j['canvas_id']?.toString() ?? '';
      if (id.isEmpty) throw 'The daemon returned no canvas id';
      if (!mounted) return;
      openCanvas(context, canvasId: id, title: j['title']?.toString() ?? title);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Could not create canvas: $e')),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<String?> _askTitle() {
    final controller = TextEditingController(text: 'Untitled canvas');
    return showDialog<String>(
      context: context,
      barrierColor: AppColors.modalScrim,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.md),
          side: BorderSide(color: AppColors.border),
        ),
        title: Text('New canvas',
            style: sans(16, weight: W.title, color: AppColors.fg1)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: sans(14, color: AppColors.fg1),
          decoration: InputDecoration(
            hintText: 'Name',
            hintStyle: sans(14, color: AppColors.fg3),
          ),
          onSubmitted: (v) =>
              Navigator.of(ctx).pop(v.trim().isEmpty ? null : v.trim()),
        ),
        actions: [
          SizedBox(
            height: 44,
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: sans(13, color: AppColors.fg2)),
            ),
          ),
          SizedBox(
            height: 44,
            child: TextButton(
              onPressed: () {
                final t = controller.text.trim();
                Navigator.of(ctx).pop(t.isEmpty ? null : t);
              },
              child: Text('Create',
                  style: sans(13, weight: W.label, color: AppColors.fg1)),
            ),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final shown = all == null
        ? const <ArtifactCard>[]
        : filterArtifactCards(all, query: _query, kind: _kind);
    // At large text the label no longer fits beside the title.
    final compact = MediaQuery.textScalerOf(context).scale(10) >= 15;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ToastAvoid(child: Padding(
              padding: EdgeInsets.fromLTRB(S.s16, S.s16, S.s16, S.s8),
              child: Row(
                children: [
                  if (Navigator.of(context).canPop())
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      tooltip: 'Back',
                      constraints:
                          const BoxConstraints.tightFor(width: 48, height: 48),
                      icon:
                          AppIcon('arrow-left', size: 18, color: AppColors.fg1),
                    ),
                  Expanded(
                    child: Text('Artifacts',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            sans(22, weight: W.title, color: AppColors.fg1)),
                  ),
                  Semantics(
                    button: true,
                    label: 'New canvas',
                    excludeSemantics: true,
                    child: SizedBox(
                      height: kTapTarget,
                      width: compact ? kTapTarget : null,
                      child: compact
                          ? FilledButton(
                              onPressed: _creating ? null : _newCanvas,
                              style: FilledButton.styleFrom(
                                padding: EdgeInsets.zero,
                                backgroundColor: AppColors.accent,
                                foregroundColor: AppColors.accentFg,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(R.sm),
                                ),
                              ),
                              child: AppIcon('plus',
                                  size: 18, color: AppColors.accentFg),
                            )
                          : FilledButton.icon(
                              onPressed: _creating ? null : _newCanvas,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.accent,
                                foregroundColor: AppColors.accentFg,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(R.sm),
                                ),
                              ),
                              icon: AppIcon('plus',
                                  size: 16, color: AppColors.accentFg),
                              label: Text('New canvas',
                                  style: sans(13,
                                      weight: W.label,
                                      color: AppColors.accentFg)),
                            ),
                    ),
                  ),
                ],
              ),
            )),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: S.s16),
              child: Container(
                height: 44,
                padding: EdgeInsets.symmetric(horizontal: S.s12),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(R.md),
                ),
                child: Row(
                  children: [
                    AppIcon('search', size: 16, color: AppColors.fg3),
                    SizedBox(width: S.s8),
                    Expanded(
                      child: Semantics(
                        textField: true,
                        label: 'Search artifacts',
                        child: TextField(
                          onChanged: (v) => setState(() => _query = v),
                          style: sans(13, color: AppColors.fg1),
                          cursorColor: AppColors.fg1,
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: 'Search artifacts',
                            hintStyle: sans(13, color: AppColors.fg3),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: kTapTarget + S.s8,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: S.s12, vertical: S.s4),
                children: [
                  for (final (kind, label) in _kinds)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: S.s4),
                      child: Semantics(
                        button: true,
                        selected: _kind == kind,
                        label: 'Show $label',
                        excludeSemantics: true,
                        child: Material(
                          color: _kind == kind
                              ? AppColors.surface3
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(R.chip),
                          child: InkWell(
                            onTap: () => setState(() => _kind = kind),
                            borderRadius: BorderRadius.circular(R.chip),
                            child: Container(
                              constraints: BoxConstraints(
                                  minHeight: kTapTarget, minWidth: kTapTarget),
                              padding:
                                  EdgeInsets.symmetric(horizontal: S.s12),
                              alignment: Alignment.center,
                              child: Text(label,
                                  style: sans(13,
                                      weight: _kind == kind
                                          ? W.label
                                          : W.body,
                                      color: _kind == kind
                                          ? AppColors.fg1
                                          : AppColors.fg2)),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(child: _body(shown)),
          ],
        ),
      ),
    );
  }

  Widget _body(List<ArtifactCard> shown) {
    if (_error != null) {
      return _message('Artifacts unavailable: $_error',
          action: 'Retry', onAction: _load);
    }
    if (_all == null) return const Center(child: DelayedSpinner(size: 22));
    if (shown.isEmpty) {
      return _message(_all!.isEmpty
          ? 'Nothing here yet. Create a canvas, or ask an agent to make one.'
          : 'Nothing matches.');
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(S.s8, S.s4, S.s8, S.s24),
      itemCount: shown.length,
      itemBuilder: (_, i) => _row(shown[i]),
    );
  }

  Widget _row(ArtifactCard c) {
    final detail = [
      c.kindLabel,
      if (c.rev > 0) 'r${c.rev}',
      if (c.author != null) c.author == 'user' ? 'You' : c.author!,
      if (c.updatedAt != null) formatCanvasRelativeTime(c.updatedAt!),
    ].join(' · ');
    return Semantics(
      button: true,
      label: 'Open ${c.kindLabel.toLowerCase()} ${c.displayTitle}, $detail',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(R.sm),
        child: InkWell(
          onTap: () => openArtifactCard(context, widget.client, c),
          borderRadius: BorderRadius.circular(R.sm),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: S.s12, vertical: S.s8),
              child: Row(
                children: [
                  AppIcon(
                    switch (c.kind) {
                      'canvas' => 'grid',
                      'image' => 'image',
                      'pdf' => 'pdf',
                      'document' => 'file-text',
                      _ => 'file',
                    },
                    size: 20,
                    color: AppColors.fg3,
                  ),
                  SizedBox(width: S.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(14,
                                weight: W.label, color: AppColors.fg1)),
                        SizedBox(height: S.s2),
                        Text(detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(12, color: AppColors.fg3)),
                      ],
                    ),
                  ),
                  AppIcon('chevron-right', size: 16, color: AppColors.fg3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _message(String text, {String? action, VoidCallback? onAction}) =>
      Center(
        child: Padding(
          padding: EdgeInsets.all(S.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text,
                  textAlign: TextAlign.center,
                  style: sans(13, color: AppColors.fg3)),
              if (action != null) ...[
                SizedBox(height: S.s12),
                SizedBox(
                  height: 44,
                  child: TextButton(
                    onPressed: onAction,
                    child: Text(action,
                        style: sans(13, weight: W.label, color: AppColors.fg1)),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}
