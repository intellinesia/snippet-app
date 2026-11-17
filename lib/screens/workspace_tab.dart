import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'file_tree_sidebar_panel.dart';
import 'file_viewer.dart';
import 'git.dart' show GitFileDiffView;

/// Desktop workspace tab: commit controls on top, changed files or the whole
/// tree on the left, the selected file's diff (or content) on the right.
///
/// Corners follow the desktop scale: 6 for chips, buttons, inputs and selected
/// rows, 8 for panels.
class WorkspaceTab extends StatefulWidget {
  final DaemonClient client;
  final String sessionId;
  final String workspacePath;
  final void Function(String path, String name)? onOpenFile;

  const WorkspaceTab({
    super.key,
    required this.client,
    required this.sessionId,
    required this.workspacePath,
    this.onOpenFile,
  });

  @override
  State<WorkspaceTab> createState() => _WorkspaceTabState();
}

const double _kStrip = 46;
const double _kLeft = 260;
const double _kRow = 24;
const double _kChip = 6;
const double _kPanel = 8;

class _Stat {
  final int add;
  final int del;
  const _Stat(this.add, this.del);
}

class _WorkspaceTabState extends State<WorkspaceTab> {
  GitStatus? _status;
  String? _error;
  final Map<String, _Stat> _stats = {};
  final _message = TextEditingController();
  bool _allFiles = false;
  String? _selected; // changed file path
  String? _openPath; // unchanged file chosen from the tree
  bool _busy = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 6), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _message.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final s = await widget.client.gitStatus(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _status = s;
        _error = s.ok ? null : (s.error ?? 'Not a git repository');
        if (_selected != null && !s.files.any((f) => f.path == _selected)) {
          _selected = null;
        }
        _selected ??= s.files.isEmpty ? null : s.files.first.path;
      });
      for (final f in s.files) {
        unawaited(_loadStat(f));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _loadStat(GitFile f) async {
    try {
      final p = await widget.client.gitDiff(widget.sessionId,
          file: f.path, staged: f.staged && !f.unstaged, untracked: f.untracked);
      var a = 0, d = 0;
      for (final l in p.split('\n')) {
        if (l.startsWith('+') && !l.startsWith('+++')) a++;
        if (l.startsWith('-') && !l.startsWith('---')) d++;
      }
      if (mounted) setState(() => _stats[f.path] = _Stat(a, d));
    } catch (_) {}
  }

  Future<void> _run(Future<void> Function() job, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
      if (mounted) toast(context, done);
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
    if (mounted) setState(() => _busy = false);
    unawaited(_refresh());
  }

  Future<void> _commit({bool push = false}) async {
    final msg = _message.text.trim();
    if (msg.isEmpty) {
      toast(context, 'Write a commit message first', danger: true);
      return;
    }
    await _run(() async {
      await widget.client.gitCommit(widget.sessionId, msg);
      if (push) await widget.client.gitPush(widget.sessionId);
      _message.clear();
    }, push ? 'Committed and pushed' : 'Committed');
  }

  Future<void> _openPr() => _run(() async {
        final url = await widget.client.createPr(widget.sessionId);
        if (url.isNotEmpty) {
          unawaited(launchUrl(Uri.parse(url),
              mode: LaunchMode.externalApplication));
        }
      }, 'Pull request opened');

  _Stat get _total {
    var a = 0, d = 0;
    for (final s in _stats.values) {
      a += s.add;
      d += s.del;
    }
    return _Stat(a, d);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return ColoredBox(
      color: AppColors.pageBg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _strip(),
        Container(height: 1, color: AppColors.border),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: _kLeft, child: _left()),
            Container(width: 1, color: AppColors.border),
            Expanded(child: _right()),
          ]),
        ),
      ]),
    );
  }

  Widget _strip() {
    final s = _status;
    final t = _total;
    return SizedBox(
      height: _kStrip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(_kChip),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon('git-branch', size: 12, color: AppColors.fg3),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  s == null || s.branch.isEmpty ? '…' : s.branch,
                  overflow: TextOverflow.ellipsis,
                  style: codeMono(11.5, color: AppColors.fg1),
                ),
              ),
              if (t.add > 0) ...[
                const SizedBox(width: 6),
                Text('+${t.add}', style: mono(11.5, color: AppColors.ok)),
              ],
              if (t.del > 0) ...[
                const SizedBox(width: 4),
                Text('-${t.del}', style: mono(11.5, color: AppColors.danger)),
              ],
              if (s != null && s.ahead > 0) ...[
                const SizedBox(width: 6),
                Text('↑${s.ahead}', style: mono(11.5, color: AppColors.fg3)),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 28,
              child: TextField(
                controller: _message,
                style: sans(12.5, color: AppColors.fg1),
                cursorColor: AppColors.accent,
                onSubmitted: (_) => _commit(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Commit message',
                  hintStyle: sans(12.5, color: AppColors.fg4),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  filled: true,
                  fillColor: AppColors.surface1,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(_kChip),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(_kChip),
                    borderSide: BorderSide(color: AppColors.accentLine),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _btn('Commit', () => _commit()),
          const SizedBox(width: 6),
          _btn('Commit and push', () => _commit(push: true), primary: true),
          const SizedBox(width: 6),
          _btn('Open PR', _openPr),
        ]),
      ),
    );
  }

  Widget _btn(String label, VoidCallback onTap, {bool primary = false}) {
    return Material(
      color: primary ? AppColors.fg1 : AppColors.surface2,
      borderRadius: BorderRadius.circular(_kChip),
      child: InkWell(
        borderRadius: BorderRadius.circular(_kChip),
        onTap: _busy ? null : onTap,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Text(label,
              style: sans(12.5,
                  weight: FontWeight.w500,
                  color: primary ? AppColors.bg : AppColors.fg1)),
        ),
      ),
    );
  }

  Widget _left() {
    final n = _status?.files.length ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(_kPanel),
          ),
          child: Row(children: [
            _seg('Changes $n', !_allFiles, () => setState(() => _allFiles = false)),
            _seg('All files', _allFiles, () => setState(() => _allFiles = true)),
          ]),
        ),
      ),
      Expanded(child: _allFiles ? _tree() : _changes()),
    ]);
  }

  Widget _seg(String label, bool on, VoidCallback tap) => Expanded(
        child: Material(
          color: on ? AppColors.surface3 : Colors.transparent,
          borderRadius: BorderRadius.circular(_kChip),
          child: InkWell(
            borderRadius: BorderRadius.circular(_kChip),
            onTap: tap,
            child: SizedBox(
              height: 24,
              child: Center(
                child: Text(label,
                    style: sans(12,
                        weight: FontWeight.w500,
                        color: on ? AppColors.fg1 : AppColors.fg3)),
              ),
            ),
          ),
        ),
      );

  Widget _changes() {
    final s = _status;
    if (s == null && _error == null) {
      return const Center(child: Spinner(size: 16));
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(_error!, style: sans(12, color: AppColors.fg3)),
      );
    }
    final files = s!.files;
    if (files.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text('Working tree clean', style: sans(12, color: AppColors.fg3)),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        for (final f in files)
          _row(
            icon: 'file',
            name: f.path.split('/').last,
            stat: _stats[f.path],
            selected: _openPath == null && _selected == f.path,
            onTap: () => setState(() {
              _selected = f.path;
              _openPath = null;
            }),
          ),
      ],
    );
  }

  Widget _row({
    required String icon,
    required String name,
    required bool selected,
    required VoidCallback onTap,
    _Stat? stat,
  }) {
    return Material(
      color: selected ? AppColors.surface3 : Colors.transparent,
      borderRadius: BorderRadius.circular(_kChip),
      child: InkWell(
        borderRadius: BorderRadius.circular(_kChip),
        onTap: onTap,
        child: SizedBox(
          height: _kRow,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              AppIcon(icon, size: 12, color: AppColors.fg4),
              const SizedBox(width: 8),
              Expanded(
                child: Text(name,
                    overflow: TextOverflow.ellipsis,
                    style: codeMono(12, color: AppColors.fg1)),
              ),
              if (stat != null) ...[
                if (stat.add > 0)
                  Text('+${stat.add}', style: mono(11, color: AppColors.ok)),
                if (stat.del > 0) ...[
                  const SizedBox(width: 4),
                  Text('-${stat.del}', style: mono(11, color: AppColors.danger)),
                ],
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _tree() => FileTreeSidebarPanel(
        showHeader: false,
        client: widget.client,
        workspacePath: widget.workspacePath,
        onOpenFile: (path, name) {
          final changed = _status?.files.any((f) => f.path == path) ?? false;
          setState(() {
            if (changed) {
              _selected = path;
              _openPath = null;
            } else {
              _openPath = path;
            }
          });
        },
      );

  Widget _right() {
    final open = _openPath;
    if (open != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _header(open, null),
        Expanded(
          child: FileViewer(
            key: ValueKey('ws-file-$open'),
            client: widget.client,
            path: open,
            name: open.split('/').last,
            embedded: true,
          ),
        ),
      ]);
    }
    GitFile? file;
    for (final f in _status?.files ?? const <GitFile>[]) {
      if (f.path == _selected) file = f;
    }
    if (file == null) {
      return Center(
        child: Text('Select a file to see its changes',
            style: sans(12.5, color: AppColors.fg4)),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(file.path, _stats[file.path]),
      Expanded(
        child: GitFileDiffView(
          key: ValueKey('ws-diff-${file.path}-${file.staged}-${file.unstaged}'),
          client: widget.client,
          sessionId: widget.sessionId,
          file: file.path,
          staged: file.staged && !file.unstaged,
          untracked: file.untracked,
          embedded: true,
        ),
      ),
    ]);
  }

  Widget _header(String path, _Stat? stat) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Flexible(
          child: Text(path,
              overflow: TextOverflow.ellipsis,
              style: codeMono(12.5, color: AppColors.fg1)),
        ),
        if (stat != null) ...[
          const SizedBox(width: 8),
          if (stat.add > 0)
            Text('+${stat.add}', style: mono(11.5, color: AppColors.ok)),
          if (stat.del > 0) ...[
            const SizedBox(width: 4),
            Text('-${stat.del}', style: mono(11.5, color: AppColors.danger)),
          ],
        ],
      ]),
    );
  }
}
