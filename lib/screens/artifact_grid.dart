import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import '../clock.dart';
import 'agent_card.dart' show agentRowTime;
import 'artifact_viewer.dart';
import 'file_viewer.dart';
import '../file_icons.dart';

class ArtifactGrid extends StatefulWidget {
  const ArtifactGrid({
    super.key,
    required this.client,
    required this.session,
    required this.artifacts,
    required this.files,
    this.onOpenFileTab,
  });

  final DaemonClient client;
  final String session;
  final List<ArtifactInfo> artifacts;
  final List<({String path, String caption})> files;
  final void Function(String path, String name)? onOpenFileTab;

  @override
  State<ArtifactGrid> createState() => _ArtifactGridState();
}

String _group(String kind) => switch (kind) {
      'html' => 'Pages',
      'image' || 'svg' => 'Images',
      _ => 'Docs',
    };

String _kindLabel(String kind) => switch (kind) {
      'html' => 'Page',
      'markdown' => 'Doc',
      'image' || 'svg' => 'Image',
      'csv' => 'Table',
      'pdf' => 'PDF',
      'code' => 'Code',
      'collection' => 'Collection',
      _ => 'File',
    };

class _ArtifactGridState extends State<ArtifactGrid> {
  String _filter = 'All';

  Widget _chip(String label, int n) {
    final on = _filter == label;
    return Padding(
      padding: EdgeInsets.only(right: S.s4),
      child: Material(
        color: on ? AppColors.tint2 : Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kMobile ? R.pill : R.sm),
            side: BorderSide(color: on ? Colors.transparent : AppColors.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(kMobile ? R.pill : R.sm),
          onTap: () => setState(() => _filter = label),
          child: Container(
            height: 24,
            padding: EdgeInsets.symmetric(horizontal: S.of(10)),
            alignment: Alignment.center,
            child: Text('$label $n',
                style: sans(12, color: on ? AppColors.fg1 : AppColors.fg3)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, int>{};
    for (final a in widget.artifacts) {
      groups[_group(a.kind)] = (groups[_group(a.kind)] ?? 0) + 1;
    }
    final total = widget.artifacts.length + widget.files.length;
    final arts = [
      for (final a in widget.artifacts)
        if (_filter == 'All' || _group(a.kind) == _filter) a
    ];
    final files = _filter == 'All' || _filter == 'Files'
        ? widget.files
        : const <({String path, String caption})>[];
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth > 640;
      final side = wide ? 32.0 : 14.0;
      final cols = ((box.maxWidth - side * 2 + 10) / (wide ? 230 : 170))
          .floor()
          .clamp(2, 6);
      final cards = <Widget>[
        for (final a in arts)
          _Card(
            title: a.title.isEmpty ? a.id : a.title,
            meta: [
              _kindLabel(a.kind),
              if (a.latest != null) 'v${a.latest!.n}',
              if ((a.latest?.createdAt ?? 0) > 0)
                relativeTime(a.latest!.createdAt),
            ].join(' · '),
            thumb: _ArtifactThumb(client: widget.client, artifact: a),
            onTap: () => openArtifact(context,
                client: widget.client,
                session: widget.session,
                id: a.id,
                version: a.latest?.n ?? 1),
          ),
        for (final f in files)
          _Card(
            title: f.path.split('/').last,
            meta: f.caption.isEmpty ? 'File' : f.caption,
            thumb: Center(
              child: FileGlyph(f.path, size: 26),
            ),
            onTap: widget.onOpenFileTab == null
                ? null
                : () => widget.onOpenFileTab!(f.path, f.path.split('/').last),
          ),
      ];
      return ListView(
        padding: EdgeInsets.fromLTRB(side, wide ? S.s20 : S.s2, side, S.s24),
        children: [
          if (wide)
            Padding(
              padding: EdgeInsets.only(bottom: S.s12),
              child: Text('Artifacts',
                  style: sans(18, weight: W.label, color: AppColors.fg1)),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _chip('All', total),
              for (final g in ['Pages', 'Images', 'Docs'])
                if ((groups[g] ?? 0) > 0) _chip(g, groups[g]!),
              if (widget.files.isNotEmpty) _chip('Files', widget.files.length),
            ]),
          ),
          SizedBox(height: S.s12),
          GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: wide ? 1.15 : 1.0,
            children: cards,
          ),
        ],
      );
    });
  }
}

class _Card extends StatefulWidget {
  const _Card(
      {required this.title, required this.meta, required this.thumb, this.onTap});
  final String title;
  final String meta;
  final Widget thumb;
  final VoidCallback? onTap;

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.tint1,
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(
                color: _hover
                    ? AppColors.accent.withValues(alpha: 0.45)
                    : AppColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Container(color: AppColors.surface2.withValues(alpha: 0.5), child: widget.thumb),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(S.of(10), S.s8, S.of(10), S.of(9)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13, color: AppColors.fg1)),
                    SizedBox(height: S.s2),
                    Text(widget.meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(11, color: AppColors.fg4)),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ArtifactThumb extends StatefulWidget {
  const _ArtifactThumb({required this.client, required this.artifact});
  final DaemonClient client;
  final ArtifactInfo artifact;

  @override
  State<_ArtifactThumb> createState() => _ArtifactThumbState();
}

class _ArtifactThumbState extends State<_ArtifactThumb> {
  Future<String>? _text;

  bool get _textual => const {'markdown', 'code', 'csv'}
      .contains(widget.artifact.kind);

  @override
  void initState() {
    super.initState();
    final v = widget.artifact.latest;
    if (v != null && _textual) _text = widget.client.artifactText(v.url);
  }

  Widget _page() => Padding(
        padding: EdgeInsets.all(S.s12),
        child: Container(
          padding: EdgeInsets.all(S.of(9)),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              AppIcon('globe', size: 10, color: AppColors.fg4),
              SizedBox(width: S.of(5)),
              Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                      color: AppColors.surface3,
                      borderRadius: BorderRadius.circular(R.of(3)))),
            ]),
            SizedBox(height: S.of(7)),
            Expanded(
              child: Container(
                  decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(R.xs))),
            ),
            SizedBox(height: S.of(5)),
            Row(children: [
              Expanded(
                child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(R.xs))),
              ),
              SizedBox(width: S.of(5)),
              Expanded(
                child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(R.xs))),
              ),
            ]),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final a = widget.artifact;
    final v = a.latest;
    if (v == null) return Center(child: AppIcon(artifactIcon(a.kind), size: 24, color: AppColors.fg4));
    final uri = widget.client.artifactUri(v.url).toString();
    if (a.kind == 'image') {
      return Image.network(uri,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Center(child: AppIcon('image', size: 24, color: AppColors.fg4)));
    }
    if (a.kind == 'svg') {
      return Padding(
        padding: EdgeInsets.all(S.s12),
        child: SvgPicture.network(uri, fit: BoxFit.contain),
      );
    }
    if (a.kind == 'html') return _page();
    if (_text != null) {
      return FutureBuilder<String>(
        future: _text,
        builder: (_, snap) => Padding(
          padding: EdgeInsets.fromLTRB(S.s12, S.of(10), S.s12, 0),
          child: Text(
            (snap.data ?? '').split('\n').take(9).join('\n'),
            maxLines: 9,
            overflow: TextOverflow.clip,
            style: mono(9, height: 1.45, color: AppColors.fg4),
          ),
        ),
      );
    }
    return Center(child: AppIcon(artifactIcon(a.kind), size: 26, color: AppColors.fg4));
  }
}

/// Phone "Artifacts and files": search, kind chips, then a two-column grid of
/// cards by day. Images show themselves; every other kind a type tile.
class ArtifactCollection extends StatefulWidget {
  const ArtifactCollection({
    super.key,
    required this.client,
    required this.session,
    required this.artifacts,
    required this.files,
    this.onOpenFileTab,
    this.now,
  });

  final DaemonClient client;
  final String session;
  final List<ArtifactInfo> artifacts;
  final List<({String path, String caption})> files;
  final void Function(String path, String name)? onOpenFileTab;

  /// Clock override for tests.
  final DateTime? now;

  @override
  State<ArtifactCollection> createState() => _ArtifactCollectionState();
}

String _chipOf(String kind) => switch (kind) {
      'html' => 'Pages',
      'image' || 'svg' => 'Images',
      'csv' => 'Tables',
      _ => 'Docs',
    };

String _kindName(String kind) => switch (kind) {
      'html' => 'Web page',
      'markdown' => 'Document',
      'image' || 'svg' => 'Image',
      'csv' => 'Table',
      'pdf' => 'PDF',
      'code' => 'Code',
      'collection' => 'Collection',
      _ => 'File',
    };

String _fileKind(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  final ext = dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
  return switch (ext) {
    'md' || 'markdown' || 'txt' || 'rst' || 'doc' || 'docx' => 'markdown',
    'html' || 'htm' => 'html',
    'pdf' => 'pdf',
    'csv' || 'tsv' || 'xls' || 'xlsx' => 'csv',
    'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'heic' => 'image',
    'svg' => 'svg',
    _ => ext.isEmpty ? 'file' : 'code',
  };
}

class _ArtifactCollectionState extends State<ArtifactCollection> {
  String _filter = 'All';
  final _search = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      final q = _search.text.trim().toLowerCase();
      if (q != _q) setState(() => _q = q);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _day(int unixSec) {
    if (unixSec <= 0) return 'Earlier';
    final at = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
    final n = widget.now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final d = DateTime(at.year, at.month, at.day);
    final ago = today.difference(d).inDays;
    return ago <= 0
        ? 'Today'
        : ago == 1
            ? 'Yesterday'
            : 'Earlier';
  }

  String _time(int unixSec) {
    if (unixSec <= 0) return '';
    final at = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
    final n = widget.now ?? DateTime.now();
    if (n.difference(at).inDays < 7 && _day(unixSec) != 'Earlier') {
      return clock12(at);
    }
    return agentRowTime(at, now: n);
  }

  bool _matches(String title, String caption, String kind) =>
      _q.isEmpty ||
      title.toLowerCase().contains(_q) ||
      caption.toLowerCase().contains(_q) ||
      _kindName(kind).toLowerCase().contains(_q);

  void _openFile(String path) {
    final name = path.split('/').last;
    if (openFileForViewing(context,
        client: widget.client, path: path, name: name)) {
      return;
    }
    if (widget.onOpenFileTab != null) {
      widget.onOpenFileTab!(path, name);
      return;
    }
    presentFileOnDesktop(context, client: widget.client, path: path, name: name);
  }

  Future<void> _downloadFile(String path) async {
    final name = path.split('/').last;
    try {
      toast(context, 'Downloading $name…');
      final msg = await downloadRemoteFileWithCancel(context, widget.client,
          path: path, name: name);
      if (msg != null && mounted) toast(context, msg);
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  Widget _chip(String label, int n) {
    final on = _filter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Semantics(
        button: true,
        selected: on,
        child: GestureDetector(
          key: ValueKey('artifact-chip-$label'),
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _filter = label),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? AppColors.fg1 : AppColors.surface2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: on ? AppColors.fg1 : AppColors.line),
            ),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: label),
                TextSpan(
                  text: '  $n',
                  style: sans(14,
                      tabular: true,
                      color: on
                          ? AppColors.pageBg.withValues(alpha: 0.6)
                          : AppColors.fg4),
                ),
              ]),
              style: sans(14,
                  height: 1.2, color: on ? AppColors.pageBg : AppColors.fg2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchField(int arts, int files) {
    final hint = [
      'Search $arts artifact${arts == 1 ? '' : 's'}',
      if (files > 0) '$files file${files == 1 ? '' : 's'}',
    ].join(' and ');
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.lineStrong),
      ),
      child: Row(children: [
        AppIcon('search', size: 18, color: AppColors.fg4),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            key: const ValueKey('artifact-search'),
            controller: _search,
            cursorColor: AppColors.accent,
            style: sans(16, color: AppColors.fg1),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration.collapsed(
              hintText: hint,
              hintStyle: sans(16, color: AppColors.fg4),
            ),
          ),
        ),
        if (_q.isNotEmpty)
          GestureDetector(
            onTap: _search.clear,
            child: AppIcon('x', size: 16, color: AppColors.fg3),
          ),
      ]),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
        child: Text(text, style: sans(15, height: 20 / 15, color: AppColors.fg3)),
      );

  Widget _grid(List<Widget> cards) => LayoutBuilder(builder: (context, box) {
        final w = (box.maxWidth - 10) / 2;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final c in cards) SizedBox(width: w, height: 206, child: c),
        ]);
      });

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final a in widget.artifacts) {
      counts[_chipOf(a.kind)] = (counts[_chipOf(a.kind)] ?? 0) + 1;
    }
    final total = widget.artifacts.length + widget.files.length;
    final arts = [
      for (final a in widget.artifacts.reversed)
        if ((_filter == 'All' || _chipOf(a.kind) == _filter) &&
            _matches(a.title, a.caption, a.kind))
          a,
    ]..sort((x, y) =>
        (y.latest?.createdAt ?? 0).compareTo(x.latest?.createdAt ?? 0));
    final files = [
      if (_filter == 'All' || _filter == 'Files')
        for (final f in widget.files)
          if (_matches(f.path.split('/').last, f.caption, _fileKind(f.path))) f,
    ];
    final days = <String, List<Widget>>{};
    for (final a in arts) {
      final at = a.latest?.createdAt ?? 0;
      (days[_day(at)] ??= []).add(_ArtifactCard(
        key: ValueKey('artifact-card-${a.id}'),
        title: a.title.isEmpty ? a.id : a.title,
        kind: a.kind,
        meta: [
          if (a.latest != null) 'v${a.latest!.n}',
          if (_time(at).isNotEmpty) _time(at),
        ].join(' · '),
        preview: _ArtifactTile(client: widget.client, artifact: a),
        onTap: () => openArtifact(context,
            client: widget.client,
            session: widget.session,
            id: a.id,
            version: a.latest?.n ?? 1),
      ));
    }
    final children = <Widget>[
      _searchField(widget.artifacts.length, widget.files.length),
      const SizedBox(height: 12),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(children: [
          _chip('All', total),
          for (final g in ['Pages', 'Images', 'Docs', 'Tables'])
            if ((counts[g] ?? 0) > 0) _chip(g, counts[g]!),
          if (widget.files.isNotEmpty) _chip('Files', widget.files.length),
        ]),
      ),
      for (final d in ['Today', 'Yesterday', 'Earlier'])
        if (days[d] != null) ...[_label(d), _grid(days[d]!)],
      if (files.isNotEmpty) ...[
        _label('Files'),
        _grid([
          for (final f in files)
            _ArtifactCard(
              key: ValueKey('file-card-${f.path}'),
              title: f.path.split('/').last,
              kind: _fileKind(f.path),
              meta: f.caption.isEmpty ? _kindName(_fileKind(f.path)) : f.caption,
              preview: _fileKind(f.path) == 'image'
                  ? Image(
                      image: widget.client.imageProvider(f.path),
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, __, ___) =>
                          _TypeTile(kind: 'image', label: 'Image'),
                    )
                  : _TypeTile(
                      kind: _fileKind(f.path),
                      label: _kindName(_fileKind(f.path)),
                      glyph: FileGlyph(f.path, size: 24)),
              onTap: () => _openFile(f.path),
              action: Tooltip(
                message: 'Download',
                child: GestureDetector(
                  key: ValueKey('file-download-${f.path}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _downloadFile(f.path),
                  child: SizedBox.square(
                    dimension: 32,
                    child: Center(
                        child: AppIcon('download',
                            size: 18, color: AppColors.fg2)),
                  ),
                ),
              ),
            ),
        ]),
      ],
      if (arts.isEmpty && files.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Text('Nothing matches.',
              textAlign: TextAlign.center,
              style: sans(15, color: AppColors.fg3)),
        ),
    ];
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: children,
    );
  }
}

class _ArtifactCard extends StatelessWidget {
  const _ArtifactCard({
    super.key,
    required this.title,
    required this.kind,
    required this.meta,
    required this.preview,
    this.onTap,
    this.action,
  });

  final String title;
  final String kind;
  final String meta;
  final Widget preview;
  final VoidCallback? onTap;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        label: '$title, ${_kindName(kind)}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            clipBehavior: Clip.antiAlias,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(16,
                        weight: FontWeight.w500,
                        height: 21 / 16,
                        color: AppColors.fg1)),
                const SizedBox(height: 6),
                Row(children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surface3,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: AppIcon(artifactIcon(kind),
                        size: 12, color: AppColors.fg2),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(14, tabular: true, color: AppColors.fg3)),
                  ),
                  if (action != null) action!,
                ]),
                const SizedBox(height: 10),
                Expanded(
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: AppColors.surface1,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(12)),
                      border: Border(
                        top: BorderSide(color: AppColors.line),
                        left: BorderSide(color: AppColors.line),
                        right: BorderSide(color: AppColors.line),
                      ),
                    ),
                    child: preview,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// A kind without a picture: its icon and what it is, centred.
class _TypeTile extends StatelessWidget {
  const _TypeTile(
      {required this.kind, required this.label, this.caption, this.glyph});

  final String kind;
  final String label;
  final String? caption;
  final Widget? glyph;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(10),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            glyph ??
                AppIcon(artifactIcon(kind), size: 22, color: AppColors.fg3),
            const SizedBox(height: 6),
            Text(label, style: sans(13, color: AppColors.fg3)),
            if ((caption ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(caption!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: sans(13, height: 1.35, color: AppColors.fg4)),
            ],
          ]),
        ),
      );
}

/// Image artifacts show the image; everything else a type tile, because the
/// daemon renders no page thumbnails yet.
class _ArtifactTile extends StatelessWidget {
  const _ArtifactTile({required this.client, required this.artifact});

  final DaemonClient client;
  final ArtifactInfo artifact;

  @override
  Widget build(BuildContext context) {
    final a = artifact;
    final v = a.latest;
    final tile = _TypeTile(
        kind: a.kind, label: _kindName(a.kind), caption: a.caption);
    if (v == null) return tile;
    final uri = client.artifactUri(v.url).toString();
    if (a.kind == 'image') {
      return Image.network(uri,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          errorBuilder: (_, __, ___) => tile);
    }
    if (a.kind == 'svg') {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: SvgPicture.network(uri, fit: BoxFit.contain),
      );
    }
    return tile;
  }
}
