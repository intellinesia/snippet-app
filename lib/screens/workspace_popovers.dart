import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../file_icons.dart';

/// Desktop session-header chips: Files and the branch. Each opens an anchored
/// popover; the full workspace lives in the shell's own pane.

String gitLetter(GitFile f) {
  if (f.untracked || f.x == 'A' || f.y == 'A') return 'A';
  if (f.x == 'D' || f.y == 'D') return 'D';
  if (f.x == 'R' || f.y == 'R') return 'R';
  return 'M';
}

Color gitLetterColour(String l) => switch (l) {
      'A' => AppColors.ok,
      'D' => AppColors.danger,
      'R' => AppColors.accent,
      _ => AppColors.run,
    };

class LineCounts {
  const LineCounts(this.added, this.removed);
  final int added;
  final int removed;
}

/// Per-file +/- from the unified patch (staged and unstaged). The status
/// endpoint carries no line counts.
Map<String, LineCounts> parsePatchCounts(String patch) {
  final out = <String, LineCounts>{};
  String? file;
  var a = 0, r = 0;
  void flush() {
    final f = file;
    if (f != null) {
      final old = out[f];
      out[f] = LineCounts((old?.added ?? 0) + a, (old?.removed ?? 0) + r);
    }
    a = 0;
    r = 0;
  }

  for (final line in patch.split('\n')) {
    if (line.startsWith('diff --git ')) {
      flush();
      final m = RegExp(r' b/(.*)$').firstMatch(line);
      file = m?.group(1);
    } else if (line.startsWith('+++') || line.startsWith('---')) {
      continue;
    } else if (line.startsWith('+')) {
      a++;
    } else if (line.startsWith('-')) {
      r++;
    }
  }
  flush();
  return out;
}

class WorkspaceChanges {
  const WorkspaceChanges(this.status, this.counts);
  final GitStatus status;
  final Map<String, LineCounts> counts;

  int get added => counts.values.fold(0, (n, c) => n + c.added);
  int get removed => counts.values.fold(0, (n, c) => n + c.removed);
}

/// Null when the workspace is not a git repo or the daemon is unreachable.
Future<WorkspaceChanges?> loadWorkspaceChanges(
    DaemonClient client, String session) async {
  try {
    final st = await client.gitStatus(session);
    if (!st.ok) return null;
    var counts = <String, LineCounts>{};
    if (st.files.isNotEmpty) {
      try {
        final r = await Future.wait([
          client.gitDiff(session),
          client.gitDiff(session, staged: true),
        ]);
        for (final p in r) {
          parsePatchCounts(p).forEach((k, v) {
            final o = counts[k];
            counts[k] = LineCounts(
                (o?.added ?? 0) + v.added, (o?.removed ?? 0) + v.removed);
          });
        }
      } catch (_) {
        counts = {};
      }
    }
    return WorkspaceChanges(st, counts);
  } catch (_) {
    return null;
  }
}

class _ChipShell extends StatelessWidget {
  const _ChipShell({required this.onTap, required this.child, this.active});
  final VoidCallback onTap;
  final Widget child;
  final bool? active;

  @override
  Widget build(BuildContext context) {
    final on = active ?? false;
    return Material(
      color: on ? AppColors.surface3 : AppColors.surface2,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}

/// "Files" chip with the lazily expanding workspace tree.
class FilesChip extends StatefulWidget {
  const FilesChip({
    super.key,
    required this.client,
    required this.sessionId,
    required this.workspace,
    required this.onOpenFile,
    this.onOpenWorkspace,
  });
  final DaemonClient client;
  final String sessionId;
  final String workspace;
  final void Function(String path, String name) onOpenFile;
  final VoidCallback? onOpenWorkspace;

  @override
  State<FilesChip> createState() => _FilesChipState();
}

class _FilesChipState extends State<FilesChip> {
  bool _open = false;

  Future<void> _show(BuildContext anchor) async {
    setState(() => _open = true);
    await showAnchoredPanel<void>(anchor,
        width: 320,
        maxHeight: 460,
        child: FilesPopover(
          client: widget.client,
          sessionId: widget.sessionId,
          workspace: widget.workspace,
          onOpenFile: (path, name) {
            Navigator.of(anchor, rootNavigator: true).pop();
            widget.onOpenFile(path, name);
          },
          onOpenWorkspace: widget.onOpenWorkspace == null
              ? null
              : () {
                  Navigator.of(anchor, rootNavigator: true).pop();
                  widget.onOpenWorkspace!();
                },
        ));
    if (mounted) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) => Builder(
        builder: (ctx) => _ChipShell(
          active: _open,
          onTap: () => _show(ctx),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon('folder', size: 14, color: AppColors.fg2),
            const SizedBox(width: 6),
            Text('Files', style: sans(12, color: AppColors.fg1)),
          ]),
        ),
      );
}

/// Branch chip: name, +added/-removed and commits ahead. Absent outside a repo.
class GitChip extends StatefulWidget {
  const GitChip({
    super.key,
    required this.client,
    required this.sessionId,
    required this.turnStatus,
    required this.githubReady,
    this.onOpenDiff,
    this.onOpenWorkspace,
  });
  final DaemonClient client;
  final String sessionId;

  /// Refreshes on change: a turn only changes the worktree.
  final String? turnStatus;
  final bool githubReady;
  final void Function(GitFile file)? onOpenDiff;
  final VoidCallback? onOpenWorkspace;

  @override
  State<GitChip> createState() => _GitChipState();
}

class _GitChipState extends State<GitChip> {
  WorkspaceChanges? _data;
  int _gen = 0;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant GitChip old) {
    super.didUpdateWidget(old);
    if (old.sessionId != widget.sessionId) {
      _data = null;
      _load();
    } else if (old.turnStatus != widget.turnStatus) {
      _load();
    }
  }

  Future<void> _load() async {
    final gen = ++_gen;
    final d = await loadWorkspaceChanges(widget.client, widget.sessionId);
    if (!mounted || gen != _gen) return;
    setState(() => _data = d);
  }

  Future<void> _show(BuildContext anchor) async {
    setState(() => _open = true);
    await showAnchoredPanel<void>(anchor,
        width: 380,
        maxHeight: 560,
        child: GitPopover(
          client: widget.client,
          sessionId: widget.sessionId,
          data: _data!,
          githubReady: widget.githubReady,
          onChanged: _load,
          onOpenDiff: widget.onOpenDiff == null
              ? null
              : (f) {
                  Navigator.of(anchor, rootNavigator: true).pop();
                  widget.onOpenDiff!(f);
                },
          onOpenWorkspace: widget.onOpenWorkspace == null
              ? null
              : () {
                  Navigator.of(anchor, rootNavigator: true).pop();
                  widget.onOpenWorkspace!();
                },
        ));
    if (mounted) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) return const SizedBox.shrink();
    final st = d.status;
    final branch = st.branch.isEmpty ? 'HEAD' : st.branch;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Builder(
        builder: (ctx) => _ChipShell(
          active: _open,
          onTap: () => _show(ctx),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon('git-branch', size: 14, color: AppColors.fg2),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(branch,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(12, color: AppColors.fg1)),
            ),
            if (d.added > 0) ...[
              const SizedBox(width: 6),
              Text('+${d.added}', style: mono(11, color: AppColors.ok)),
            ],
            if (d.removed > 0) ...[
              const SizedBox(width: 4),
              Text('-${d.removed}', style: mono(11, color: AppColors.danger)),
            ],
            if (st.ahead > 0) ...[
              const SizedBox(width: 6),
              Text('↑${st.ahead}', style: mono(11, color: AppColors.fg3)),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(
      {required this.controller,
      required this.hint,
      this.icon,
      this.onChanged,
      this.onSubmitted,
      this.autofocus = false});
  final TextEditingController controller;
  final String hint;
  final String? icon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          if (icon != null) ...[
            AppIcon(icon!, size: 14, color: AppColors.fg3),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              style: sans(12, color: AppColors.fg1),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
                hintText: hint,
                hintStyle: sans(12, color: AppColors.fg4),
              ),
            ),
          ),
        ]),
      );
}

class _Row extends StatefulWidget {
  const _Row(
      {required this.indent,
      required this.leading,
      required this.icon,
      required this.label,
      this.sub,
      this.letter,
      this.trailing,
      this.onTap});
  final String? sub;
  final String? letter;
  final double indent;
  final Widget? leading;
  final Widget icon;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: widget.onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            height: 26,
            padding: EdgeInsets.only(left: 6 + widget.indent, right: 8),
            decoration: BoxDecoration(
              color: _hover ? AppColors.surface3 : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              SizedBox(width: 14, child: widget.leading),
              const SizedBox(width: 4),
              widget.icon,
              const SizedBox(width: 8),
              Expanded(
                child: Row(children: [
                  Flexible(
                    child: Text(widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12.5, color: AppColors.fg1)),
                  ),
                  if (widget.sub != null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(widget.sub!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(11.5, color: AppColors.fg4)),
                    ),
                  ],
                ]),
              ),
              if (widget.letter != null)
                Text(widget.letter!,
                    style: mono(11, color: gitLetterColour(widget.letter!))),
              if (widget.trailing != null) widget.trailing!,
            ]),
          ),
        ),
      );
}

Widget _delta(LineCounts? c) {
  if (c == null) return const SizedBox.shrink();
  return Row(mainAxisSize: MainAxisSize.min, children: [
    if (c.added > 0) Text('+${c.added}', style: mono(11, color: AppColors.ok)),
    if (c.removed > 0) ...[
      const SizedBox(width: 4),
      Text('−${c.removed}', style: mono(11, color: AppColors.danger)),
    ],
  ]);
}

class FilesPopover extends StatefulWidget {
  const FilesPopover({
    super.key,
    required this.client,
    required this.sessionId,
    required this.workspace,
    required this.onOpenFile,
    this.onOpenWorkspace,
  });
  final DaemonClient client;
  final String sessionId;
  final String workspace;
  final void Function(String path, String name) onOpenFile;
  final VoidCallback? onOpenWorkspace;

  @override
  State<FilesPopover> createState() => _FilesPopoverState();
}

class _FilesPopoverState extends State<FilesPopover> {
  final _search = TextEditingController();
  final _children = <String, List<FsEntry>>{};
  final _expanded = <String>{};
  final _loading = <String>{};
  Map<String, LineCounts> _changes = {};
  Map<String, String> _letters = {};
  List<String>? _all;
  String _q = '';
  String? _error;

  String get _root => widget.workspace;

  @override
  void initState() {
    super.initState();
    _list(_root);
    loadWorkspaceChanges(widget.client, widget.sessionId).then((d) {
      if (mounted && d != null) {
        setState(() {
          _changes = {
            for (final f in d.status.files)
              f.path: d.counts[f.path] ?? const LineCounts(0, 0)
          };
          _letters = {for (final f in d.status.files) f.path: gitLetter(f)};
        });
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _list(String path) async {
    if (_children.containsKey(path) || !_loading.add(path)) return;
    try {
      final l = await widget.client.fs(path.isEmpty ? null : path);
      final es = [...l.entries]..sort((a, b) {
          if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      if (mounted) setState(() => _children[path] = es);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _loading.remove(path);
    }
  }

  String _rel(String p) {
    final r = _root.endsWith('/') ? _root : '$_root/';
    return p.startsWith(r) ? p.substring(r.length) : p;
  }

  LineCounts? _countFor(String rel, {bool dir = false}) {
    if (!dir) return _changes[rel];
    var a = 0, r = 0, any = false;
    _changes.forEach((k, v) {
      if (k.startsWith('$rel/')) {
        a += v.added;
        r += v.removed;
        any = true;
      }
    });
    return any ? LineCounts(a, r) : null;
  }

  void _onQuery(String q) {
    setState(() => _q = q.trim().toLowerCase());
    if (_q.isNotEmpty && _all == null) {
      widget.client.fsFiles(_root).then((f) {
        if (mounted) setState(() => _all = f);
      }).catchError((_) {
        if (mounted) setState(() => _all = const []);
      });
    }
  }

  void _open(String rel) {
    final full = rel.startsWith('/') ? rel : '$_root/$rel';
    widget.onOpenFile(full, rel.split('/').last);
  }

  List<Widget> _tree(String dir, int depth) {
    final es = _children[dir];
    if (es == null) {
      return [
        if (_loading.contains(dir))
          Padding(
            padding:
                EdgeInsets.only(left: 24.0 + depth * 16, top: 4, bottom: 4),
            child: Text('Loading', style: sans(12, color: AppColors.fg4)),
          ),
      ];
    }
    final out = <Widget>[];
    for (final e in es) {
      final rel = _rel(e.path);
      if (e.isDir) {
        final open = _expanded.contains(e.path);
        out.add(_Row(
          indent: depth * 16.0,
          leading: AppIcon(open ? 'chevron-down' : 'chevron-right',
              size: 12, color: AppColors.fg3),
          icon: FileGlyph(e.name, isDir: true, open: open),
          label: e.name,
          trailing: open ? null : _delta(_countFor(rel, dir: true)),
          onTap: () {
            setState(
                () => open ? _expanded.remove(e.path) : _expanded.add(e.path));
            if (!open) _list(e.path);
          },
        ));
        if (open) out.addAll(_tree(e.path, depth + 1));
      } else {
        out.add(_Row(
          indent: depth * 16.0,
          leading: null,
          icon: FileGlyph(e.name),
          label: e.name,
          trailing: _delta(_countFor(rel)),
          onTap: () => _open(rel),
        ));
      }
    }
    return out;
  }

  List<Widget> _results() {
    final hits = [
      for (final f in _all ?? const <String>[])
        if (f.toLowerCase().contains(_q)) f
    ].take(40).toList();
    if (_all == null) {
      return [_note('Searching')];
    }
    if (hits.isEmpty) return [_note('No matching files')];
    return [
      _section('Matches'),
      for (final f in hits)
        _Row(
          indent: 0,
          leading: null,
          icon: FileGlyph(f.split('/').last),
          label: f.split('/').last,
          sub: f.contains('/') ? f.substring(0, f.lastIndexOf('/')) : null,
          letter: _letters[f],
          onTap: () => _open(f),
        ),
    ];
  }

  Widget _section(String t) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
          child: Text(t, style: sans(11.5, color: AppColors.fg4)),
        ),
      );

  Widget _note(String t) => Padding(
        padding: const EdgeInsets.all(10),
        child: Text(t, style: sans(12, color: AppColors.fg4)),
      );

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
        child: Row(children: [
          Text('Files',
              style: sans(12, weight: W.strong, color: AppColors.fg1)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_root,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(11.5, color: AppColors.fg4)),
          ),
          if (_changes.isNotEmpty)
            Tag('${_changes.length} changed', tone: Tone.neutral),
        ]),
      ),
      _Field(
        controller: _search,
        hint: 'Go to file',
        icon: 'search',
        autofocus: true,
        onChanged: _onQuery,
        onSubmitted: (_) {
          if (_q.isEmpty) return;
          final h = (_all ?? const <String>[])
              .where((f) => f.toLowerCase().contains(_q));
          if (h.isNotEmpty) _open(h.first);
        },
      ),
      const SizedBox(height: 6),
      if (_error != null && _children.isEmpty)
        _note(_error!)
      else if (_q.isNotEmpty)
        ..._results()
      else ...[
        _section('Project'),
        ..._tree(_root, 0),
      ],
      if (widget.onOpenWorkspace != null) ...[
        const SizedBox(height: 8),
        Divider(height: 1, color: AppColors.border),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Text('↵ open in a tab',
                style: sans(11.5, color: AppColors.fg4)),
          ),
          Btn('Open workspace',
              small: true,
              variant: BtnVariant.ghost,
              onTap: widget.onOpenWorkspace),
        ]),
      ],
    ]);
  }
}

class GitPopover extends StatefulWidget {
  const GitPopover({
    super.key,
    required this.client,
    required this.sessionId,
    required this.data,
    required this.githubReady,
    required this.onChanged,
    this.onOpenDiff,
    this.onOpenWorkspace,
  });
  final DaemonClient client;
  final String sessionId;
  final WorkspaceChanges data;
  final bool githubReady;
  final Future<void> Function() onChanged;
  final void Function(GitFile file)? onOpenDiff;
  final VoidCallback? onOpenWorkspace;

  @override
  State<GitPopover> createState() => _GitPopoverState();
}

class _GitPopoverState extends State<GitPopover> {
  final _msg = TextEditingController();
  late WorkspaceChanges _data = widget.data;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  String _fail(Map<String, dynamic> r, String what) {
    final e = ((r['stderr'] ?? r['error']) as String?)?.trim() ?? '';
    return e.isEmpty ? '$what failed' : e;
  }

  Future<void> _run(Future<String?> Function() op) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    String? info;
    try {
      info = await op();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    final d = await loadWorkspaceChanges(widget.client, widget.sessionId);
    unawaited(widget.onChanged());
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (d != null) _data = d;
      if (_error == null) _info = info;
    });
  }

  /// Returns an error message, or null on success.
  Future<String?> _commit() async {
    final msg = _msg.text.trim();
    if (msg.isEmpty) return 'Write a commit message first.';
    final c = widget.client;
    final id = widget.sessionId;
    final staged = await c.gitStage(id, all: true);
    if (staged['ok'] != true) throw _fail(staged, 'Stage');
    final r = await c.gitCommit(id, msg);
    if (r['ok'] != true) throw _fail(r, 'Commit');
    _msg.clear();
    return null;
  }

  Future<String?> _push() async {
    final r = await widget.client.gitPush(widget.sessionId);
    if (r['ok'] != true) throw _fail(r, 'Push');
    return 'Pushed';
  }

  Future<void> _commitThen({required bool push}) => _run(() async {
        final err = await _commit();
        if (err != null) throw err;
        return push ? await _push() : 'Committed';
      });

  Future<void> _openPr() => _run(() async {
        final url = await widget.client.createPr(widget.sessionId,
            title: _msg.text.trim().isEmpty ? null : _msg.text.trim());
        return url.isEmpty ? 'Pull request opened' : url;
      });

  @override
  Widget build(BuildContext context) {
    final st = _data.status;
    final files = st.files;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
          child: Row(children: [
            AppIcon('git-branch', size: 14, color: AppColors.fg2),
            const SizedBox(width: 8),
            Expanded(
              child: Text(st.branch.isEmpty ? 'HEAD' : st.branch,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(12.5, weight: W.strong, color: AppColors.fg1)),
            ),
            if (st.ahead > 0)
              Text('${st.ahead} ahead of origin',
                  style: sans(12, color: AppColors.fg3)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
          child: Row(children: [
            Text('Changes',
                style: sans(12, weight: W.strong, color: AppColors.fg1)),
            const SizedBox(width: 8),
            Text('${files.length} ${files.length == 1 ? 'file' : 'files'}',
                style: sans(12, color: AppColors.fg3)),
            const Spacer(),
            _delta(LineCounts(_data.added, _data.removed)),
          ]),
        ),
        if (files.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
            child: Text('Working tree clean',
                style: sans(12, color: AppColors.fg4)),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 190),
            child: SingleChildScrollView(
              child: Column(children: [
                for (final f in files)
                  _Row(
                    indent: 0,
                    leading: null,
                    icon: SizedBox(
                      width: 14,
                      child: Text(gitLetter(f),
                          textAlign: TextAlign.center,
                          style:
                              mono(11, color: gitLetterColour(gitLetter(f)))),
                    ),
                    label: f.path.split('/').last,
                    sub: f.path.contains('/')
                        ? f.path.substring(0, f.path.lastIndexOf('/'))
                        : null,
                    trailing: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _delta(_data.counts[f.path]),
                    ),
                    onTap: widget.onOpenDiff == null
                        ? null
                        : () => widget.onOpenDiff!(f),
                  ),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        _Field(controller: _msg, hint: 'Commit message'),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(_error!, style: sans(12, color: AppColors.danger)),
          )
        else if (_info != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(_info!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: sans(12, color: AppColors.ok)),
          ),
        const SizedBox(height: 8),
        Row(children: [
          Btn('Commit',
              small: true,
              variant: BtnVariant.secondary,
              disabled: _busy || files.isEmpty,
              onTap: () => _commitThen(push: false)),
          const SizedBox(width: 6),
          Btn('Commit and push',
              small: true,
              disabled: _busy || files.isEmpty,
              onTap: () => _commitThen(push: true)),
          const Spacer(),
          if (widget.githubReady)
            Btn('Open PR',
                small: true,
                variant: BtnVariant.ghost,
                disabled: _busy,
                onTap: _openPr),
        ]),
        if (widget.onOpenWorkspace != null) ...[
          const SizedBox(height: 10),
          Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Btn('Open workspace',
                small: true,
                variant: BtnVariant.ghost,
                onTap: widget.onOpenWorkspace),
          ),
        ],
      ],
    );
  }
}
