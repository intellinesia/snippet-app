import 'dart:async';

import 'package:flutter/material.dart';

import '../motion_routes.dart';
import '../toast_avoid.dart';
import '../tap_detector.dart';
import 'mobile_home/collapsing_root.dart';
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
import '../mobile_kit.dart';
import '../empty_art.dart' show EmptyArtKind;
import 'artifact_viewer.dart' show ArtifactViewer;
import 'tasks/task_common.dart' show TaskEmptyNote;

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
    AppPageRoute<void>(builder: (_) => ArtifactsScreen(client: daemon)),
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
  bool _searchOpen = false;
  // Desktop: the previewed artifact, and whether its pane takes the width.
  ArtifactCard? _selected;
  bool _expanded = false;
  Timer? _poll;
  int _loadSeq = 0;

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
    unawaited(_load());
    if (!kMobile) {
      _poll = Timer.periodic(
          const Duration(seconds: 10), (_) => unawaited(_load(quiet: true)));
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    final seq = ++_loadSeq;
    if (!quiet) setState(() => _error = null);
    try {
      final raw = await widget.client.getArtifactCards();
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _all = [
          for (final j in raw) ArtifactCard.fromJson(j),
        ].where((c) => c.id.isNotEmpty).toList();
        _error = null;
      });
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      if (!quiet || _all == null) setState(() => _error = '$e');
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

  Widget _desktopKindChip(String? kind, String label) {
    final on = _kind == kind;
    return Material(
      color: on ? PaneRow.plate : Colors.transparent,
      borderRadius: BorderRadius.circular(PaneRow.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(PaneRow.radius),
        hoverColor: AppColors.hoverPlate,
        onTap: () => setState(() => _kind = kind),
        child: Container(
          height: PaneRow.pill,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          child: Text(label,
              maxLines: 1,
              style: sans(PaneRow.label,
                  color: on ? PaneRow.labelOn : PaneRow.labelOff)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final shown = all == null
        ? const <ArtifactCard>[]
        : filterArtifactCards(all, query: _query, kind: _kind);
    final searchW = ToastAvoid(
        child: Padding(
      padding: kMobile
          ? EdgeInsets.symmetric(horizontal: S.s16)
          : const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Container(
        height: kMobile ? 44 : 32,
        padding: EdgeInsets.symmetric(horizontal: kMobile ? S.s12 : 10),
        decoration: BoxDecoration(
          color: kMobile ? AppColors.surface2 : AppColors.surface1,
          borderRadius: BorderRadius.circular(kMobile ? R.md : R.of(8)),
        ),
        child: Row(
          children: [
            AppIcon('search',
                size: kMobile ? 16 : 13,
                color: kMobile ? AppColors.fg3 : AppColors.fg4),
            SizedBox(width: S.s8),
            Expanded(
              child: Semantics(
                textField: true,
                label: 'Search artifacts',
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  style: sans(kMobile ? 13 : 12.5, color: AppColors.fg1),
                  cursorColor: kMobile ? AppColors.fg1 : AppColors.accent,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Search artifacts',
                    hintStyle: sans(kMobile ? 13 : 12.5,
                        color: kMobile ? AppColors.fg3 : AppColors.fg4),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ));
    final chipsW = kMobile
        ? ToastAvoid(
            child: SizedBox(
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
                            padding: EdgeInsets.symmetric(horizontal: S.s12),
                            alignment: Alignment.center,
                            child: Text(label,
                                style: sans(13,
                                    weight: _kind == kind ? W.label : W.body,
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
          ))
        : ToastAvoid(
            child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: SizedBox(
              height: PaneRow.pill,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _kinds.length,
                separatorBuilder: (_, __) => const SizedBox(width: 2),
                itemBuilder: (_, i) =>
                    _desktopKindChip(_kinds[i].$1, _kinds[i].$2),
              ),
            ),
          ));
    if (kMobile) return _phone(shown, all ?? const []);
    return _desktop(shown, searchW, chipsW);
  }

  /// Desktop: the Tasks layout. A header strip and compact rows on the left,
  /// the selected artifact on the right; expand gives the preview the width.
  Widget _desktop(List<ArtifactCard> shown, Widget searchW, Widget chipsW) {
    final total = _all?.length ?? 0;
    final master = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ToastAvoid(
            child: Container(
          height: PaneRow.height,
          padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: AppColors.paneLine, width: AppColors.hairline))),
          child: Row(children: [
            if (Navigator.of(context).canPop()) ...[
              IconBtn('chevron-left',
                  size: 28,
                  iconSize: 13,
                  tooltip: 'Back',
                  onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 2),
            ],
            Text('Artifacts',
                style: sans(13.5, weight: W.label, color: PaneRow.labelOn)),
            if (total > 0) ...[
              const SizedBox(width: 8),
              Text('$total',
                  style: sans(12.5, color: AppColors.fg3, tabular: true)),
            ],
            const Spacer(),
            IconBtn('search',
                size: 28,
                iconSize: 13,
                active: _searchOpen,
                tooltip: 'Search artifacts',
                onTap: () => setState(() {
                      _searchOpen = !_searchOpen;
                      if (!_searchOpen) _query = '';
                    })),
            const SizedBox(width: 4),
            HeaderAction('New canvas', onTap: _creating ? null : _newCanvas),
          ]),
        )),
        if (_searchOpen) searchW else const SizedBox(height: 8),
        chipsW,
        Expanded(child: _body(shown)),
      ],
    );
    final sel = _selected;
    final Widget detail;
    if (sel == null) {
      detail = const TaskEmptyNote(
          title: 'Select an artifact', art: EmptyArtKind.search);
    } else {
      final expand = IconBtn(_expanded ? 'minimize' : 'expand',
          size: 28,
          iconSize: 13,
          tooltip: _expanded ? 'Show the list' : 'Expand',
          onTap: () => setState(() => _expanded = !_expanded));
      // Not 'Close': the shell hides that inside a tab, which has its own.
      final close = IconBtn('x',
          size: 28,
          iconSize: 13,
          tooltip: 'Close preview',
          onTap: () => setState(() {
                _selected = null;
                _expanded = false;
              }));
      final doc = sel.documentRef;
      detail = sel.isCanvas || doc == null
          ? _canvasPreview(sel, [expand, close])
          : ArtifactViewer(
              key: ValueKey('artifact-preview-${sel.id}'),
              client: widget.client,
              session: doc.session,
              id: doc.id,
              headerActions: [expand, close],
            );
    }
    return ColoredBox(
      color: AppColors.bg,
      child: LayoutBuilder(builder: (context, box) {
        final detailW = (box.maxWidth * 0.42).clamp(360.0, 560.0).toDouble();
        final wide = _expanded && sel != null;
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!wide) Expanded(child: master),
          if (!wide)
            Container(width: AppColors.hairline, color: AppColors.paneLine),
          if (wide)
            Expanded(child: detail)
          else
            SizedBox(width: detailW, child: detail),
        ]);
      }),
    );
  }

  Widget _canvasPreview(ArtifactCard c, List<Widget> actions) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: PaneRow.height,
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: AppColors.paneLine, width: AppColors.hairline))),
            child: Row(children: [
              Expanded(
                child: Text(c.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, weight: W.label, color: AppColors.fg1)),
              ),
              ...actions,
            ]),
          ),
          Expanded(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AppIcon('grid', size: 22, color: AppColors.fg4),
                const SizedBox(height: 10),
                Text('${c.kindLabel}  ·  r${c.rev}',
                    style: sans(12, color: AppColors.fg3)),
                const SizedBox(height: 14),
                Btn('Open canvas',
                    small: true,
                    variant: BtnVariant.surface,
                    onTap: () => openArtifactCard(context, widget.client, c)),
              ]),
            ),
          ),
        ],
      );

  /// Phone: large title with search and Show in the header, the kind
  /// filter group, then a two-column grid of preview cards.
  Widget _phone(List<ArtifactCard> shown, List<ArtifactCard> all) {
    final a = kAndroidLook;
    final canPop = Navigator.of(context).canPop();
    final actions = [
      MkAction('search', 'Search', () {
        setState(() {
          _searchOpen = !_searchOpen;
          if (!_searchOpen) _query = '';
        });
      }),
      MkAction('sliders-horizontal', 'Show', _openShow),
      MkAction('plus', 'New canvas', () {
        if (!_creating) _newCanvas();
      }),
    ];
    final head = <Widget>[
      const LargeTitle('Artifacts'),
      if (_searchOpen) _phoneSearch(),
      if (all.isNotEmpty) _phoneFilters(all.length),
    ];
    final Widget list;
    if (_error != null || _all == null || shown.isEmpty) {
      list = ListView(
          children: [...head, SizedBox(height: 280, child: _body(shown))]);
    } else {
      final rows = (shown.length + 1) ~/ 2;
      list = ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.only(bottom: MK.bottomClearance(context)),
        itemCount: rows + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [...head, SizedBox(height: a ? 8 : 6)]);
          }
          final l = shown[(i - 1) * 2];
          final r =
              (i - 1) * 2 + 1 < shown.length ? shown[(i - 1) * 2 + 1] : null;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: IntrinsicHeight(
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _card(l)),
                    const SizedBox(width: 12),
                    Expanded(child: r == null ? const SizedBox() : _card(r)),
                  ]),
            ),
          );
        },
      );
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: CollapsingRoot(
          title: 'Artifacts',
          leading: canPop
              ? MkIconButton(
                  icon: a ? 'arrow-left' : 'chevron-left',
                  label: 'Back',
                  onTap: () => Navigator.of(context).maybePop())
              : null,
          // The kit puts these on the title row (iPhone glass capsule) or in
          // the app bar (Android).
          actions: [
            for (final x in actions)
              MkIconButton(
                  icon: x.icon, label: x.label, onTap: x.onTap, bare: !a)
          ],
          child: list,
        ),
      ),
    );
  }

  Widget _phoneSearch() => ToastAvoid(
        child: Padding(
          padding: EdgeInsets.fromLTRB(kAndroidLook ? 16 : MK.gutter, 8,
              kAndroidLook ? 16 : MK.gutter, 0),
          child: Semantics(
            textField: true,
            label: 'Search artifacts',
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              style: sans(15, color: AppColors.fg1),
              cursorColor: AppColors.fg1,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: AppColors.surface2,
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 8),
                  child: AppIcon('search', size: 16, color: AppColors.fg3),
                ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 36, minHeight: 20),
                hintText: 'Search artifacts',
                hintStyle: sans(15, color: AppColors.fg3),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(kAndroidLook ? 28 : 12),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
      );

  // The board shows All, Documents, Images and Canvases; PDFs and Files are
  // picked from Show and join the group while selected.
  Widget _phoneFilters(int total) {
    const main = <(String?, String)>[
      (null, 'All'),
      ('document', 'Documents'),
      ('image', 'Images'),
      ('canvas', 'Canvases'),
    ];
    final extra = _kinds.where((k) => k.$1 == _kind && !main.contains(k));
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.35,
      child: ToastAvoid(
        child: MkFilterGroup<String?>(
          padding: MK.filterPad,
          options: [
            for (final (k, l) in [...main, ...extra])
              MkFilter(k, l, count: k == null ? total : null),
          ],
          selected: _kind,
          onSelect: (k) => setState(() => _kind = k),
        ),
      ),
    );
  }

  static String _kindIcon(String? k) => switch (k) {
        null => 'layers',
        'canvas' => 'grid',
        'image' => 'image',
        'pdf' => 'pdf',
        'document' => 'file-text',
        _ => 'file',
      };

  Future<void> _openShow() async {
    const all = '__all';
    final picked = await showAppMenu<String>(
      context,
      title: 'Show',
      items: [
        for (final (k, l) in _kinds)
          appMenuItem(
            value: k ?? all,
            label: l,
            icon: _kindIcon(k),
            selected: _kind == k,
          ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() => _kind = picked == all ? null : picked);
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  /// One grid card: a 150 preview, the title over two lines, kind and age.
  /// Android wraps it in a tonal container with 24 corners.
  Widget _card(ArtifactCard c) {
    final a = kAndroidLook;
    final meta = [
      c.kindLabel,
      if (c.updatedAt != null) _ago(c.updatedAt!),
    ].join(' · ');
    final detail = [
      c.kindLabel,
      if (c.rev > 0) 'r${c.rev}',
      if (c.author != null) c.author == 'user' ? 'You' : c.author!,
      if (c.updatedAt != null) formatCanvasRelativeTime(c.updatedAt!),
    ].join(' · ');
    final thumb = (c.thumbUrl ?? '').isEmpty
        ? (c.kind == 'document' ? const _DocLines() : _KindTile(c.kind))
        : Image(
            image: widget.client.canvasImage(c.thumbUrl!, rev: c.rev),
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (_, __, ___) =>
                c.kind == 'document' ? const _DocLines() : _KindTile(c.kind),
          );
    final pad = EdgeInsets.symmetric(horizontal: a ? 6 : 0);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 150,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(a ? 18 : 16)),
          child: thumb,
        ),
        const SizedBox(height: 8),
        Padding(
          padding: pad,
          child: Text(c.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: sans(13.5,
                  weight: W.label, height: 1.3, color: AppColors.fg1)),
        ),
        const SizedBox(height: 3),
        Padding(
          padding: pad,
          child: Text(meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(12, color: AppColors.fg4, tabular: true)),
        ),
      ],
    );
    return Semantics(
      button: true,
      label: 'Open ${c.kindLabel.toLowerCase()} ${c.displayTitle}, $detail',
      excludeSemantics: true,
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openArtifactCard(context, widget.client, c),
        child: a
            ? Container(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 12),
                decoration: BoxDecoration(
                    color: AppColors.surface1,
                    borderRadius: BorderRadius.circular(MK.cardRadius)),
                child: body,
              )
            : body,
      ),
    );
  }

  Widget _quietNote(String icon, String title, String body, {Widget? action}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppIcon(icon, size: 18, color: AppColors.fg4),
          const SizedBox(height: 10),
          Text(title,
              textAlign: TextAlign.center,
              style: sans(12.5, weight: W.label, color: AppColors.fg3)),
          const SizedBox(height: 4),
          Text(body,
              textAlign: TextAlign.center,
              style: sans(12, height: 1.4, color: AppColors.fg4)),
          if (action != null) ...[const SizedBox(height: 12), action],
        ]),
      ),
    );
  }

  Widget _body(List<ArtifactCard> shown) {
    if (_error != null) {
      return kMobile
          ? EmptyState(
              icon: 'alert-circle',
              title: "Couldn't load artifacts",
              body: 'Check that your Mac is on, then try again.',
              action: StateButton('Retry', onTap: _load))
          : _quietNote('alert-circle', "Couldn't load artifacts",
              'Check that your Mac is on, then try again.',
              action: Btn('Retry',
                  small: true, variant: BtnVariant.surface, onTap: _load));
    }
    if (_all == null) return const Center(child: DelayedSpinner(size: 22));
    if (shown.isEmpty) {
      if (!kMobile) {
        return _all!.isEmpty
            ? _quietNote('layers', 'No artifacts',
                'Agents will share canvases and files here.')
            : _quietNote(
                'search', 'No matches', 'Nothing matches your search.');
      }
      return _all!.isEmpty
          ? EmptyState(
              icon: 'layers',
              title: 'No artifacts',
              body: 'Agents will share canvases and files here.',
              action: StateButton('Ask an agent',
                  onTap: () => Navigator.of(context).maybePop()))
          : const EmptyState(
              icon: 'search',
              title: 'No matches',
              body: 'Nothing matches your search.');
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(S.s8, S.s4, S.s8, S.s24),
      itemCount: shown.length,
      itemBuilder: (_, i) => kMobile ? _row(shown[i]) : _deskRow(shown[i]),
    );
  }

  /// Desktop: one line per artifact, as the task rows. A tap previews it on
  /// the right; a double tap opens it in its own tab.
  Widget _deskRow(ArtifactCard c) {
    final on = _selected?.id == c.id;
    final author = c.author?.trim() ?? '';
    // Some producers record a file path as the author; that is not a who.
    final who = author == 'user' ? 'You' : (author.contains('/') ? '' : author);
    final meta = [c.kindLabel, if (who.isNotEmpty) who].join('  ·  ');
    return Semantics(
      button: true,
      selected: on,
      label: 'Preview ${c.kindLabel.toLowerCase()} ${c.displayTitle}',
      excludeSemantics: true,
      child: Material(
        color: on ? PaneRow.plate : Colors.transparent,
        borderRadius: BorderRadius.circular(PaneRow.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(PaneRow.radius),
          hoverColor: AppColors.hoverPlate,
          onTap: () => setState(() => _selected = c),
          onDoubleTap: () => openArtifactCard(context, widget.client, c),
          child: SizedBox(
            height: 32,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                AppIcon(
                    switch (c.kind) {
                      'canvas' => 'grid',
                      'image' => 'image',
                      'pdf' => 'pdf',
                      'document' => 'file-text',
                      _ => 'file',
                    },
                    size: 14,
                    color: AppColors.fg3),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(c.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, color: AppColors.fg1)),
                ),
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 170),
                  child: Text(meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, color: AppColors.fg3)),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                      c.updatedAt == null
                          ? ''
                          : formatCanvasRelativeTime(c.updatedAt!),
                      maxLines: 1,
                      textAlign: TextAlign.right,
                      style: sans(11.5, color: AppColors.fg3, tabular: true)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(ArtifactCard c) {
    final detail = [
      c.kindLabel,
      if (c.rev > 0) 'r${c.rev}',
      if (c.author != null) c.author == 'user' ? 'You' : c.author!,
      if (c.updatedAt != null) formatCanvasRelativeTime(c.updatedAt!),
    ].join(' · ');
    final icon = AppIcon(
      switch (c.kind) {
        'canvas' => 'grid',
        'image' => 'image',
        'pdf' => 'pdf',
        'document' => 'file-text',
        _ => 'file',
      },
      size: kMobile ? 20 : 14,
      color: AppColors.fg3,
    );
    return Semantics(
      button: true,
      label: 'Open ${c.kindLabel.toLowerCase()} ${c.displayTitle}, $detail',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(kMobile ? R.sm : PaneRow.radius),
        child: InkWell(
          onTap: () => openArtifactCard(context, widget.client, c),
          borderRadius: BorderRadius.circular(kMobile ? R.sm : PaneRow.radius),
          hoverColor: kMobile ? null : AppColors.hoverPlate,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: kMobile ? 64 : 48),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: kMobile ? S.s12 : 10,
                  vertical: kMobile ? S.s8 : 6),
              child: Row(
                children: [
                  if (kMobile)
                    icon
                  else
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.tint1,
                        borderRadius: BorderRadius.circular(R.of(7)),
                      ),
                      child: icon,
                    ),
                  SizedBox(width: kMobile ? S.s12 : 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(c.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(kMobile ? 14 : 13,
                                weight: kMobile ? W.label : W.body,
                                color: kMobile
                                    ? AppColors.fg1
                                    : Color.lerp(
                                        AppColors.fg1, AppColors.fg2, 0.3))),
                        SizedBox(height: S.s2),
                        Text(detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(12,
                                color:
                                    kMobile ? AppColors.fg3 : AppColors.fg4)),
                      ],
                    ),
                  ),
                  AppIcon('chevron-right',
                      size: kMobile ? 16 : 13, color: AppColors.fg4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A document without a rendered page: a few quiet text lines.
class _DocLines extends StatelessWidget {
  const _DocLines();
  @override
  Widget build(BuildContext context) {
    Widget bar(double f, {Color? c}) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: f,
          child: Container(
            height: 6,
            margin: const EdgeInsets.only(bottom: 7),
            decoration: BoxDecoration(
                color: c ?? AppColors.surface3,
                borderRadius: BorderRadius.circular(3)),
          ),
        );
    return Container(
      color: Color.lerp(AppColors.bg, AppColors.surface1, 0.5),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        bar(0.6, c: Color.lerp(AppColors.surface3, AppColors.fg4, 0.25)),
        bar(1),
        bar(0.85),
        bar(1),
        bar(0.7),
        bar(0.9),
      ]),
    );
  }
}

/// A kind with no picture: its icon, centred.
class _KindTile extends StatelessWidget {
  const _KindTile(this.kind);
  final String kind;
  @override
  Widget build(BuildContext context) => Center(
        child: AppIcon(
            switch (kind) {
              'canvas' => 'grid',
              'image' => 'image',
              'pdf' => 'pdf',
              'document' => 'file-text',
              _ => 'file',
            },
            size: 24,
            color: AppColors.fg4),
      );
}
