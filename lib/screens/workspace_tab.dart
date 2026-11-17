import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'file_tree_sidebar_panel.dart';
import 'file_viewer.dart';
import 'git.dart' show GitFileDiffView;
import 'workspace_popovers.dart' show gitLetter, gitLetterColour;

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
const double _kLeft = 300;
const double _kRow = 28;
const double _kCtl = 30;
const double _kChip = 6;

class _Stat {
  final int add;
  final int del;
  final int hunks;
  const _Stat(this.add, this.del, [this.hunks = 0]);
}

Widget _delta(_Stat? s, {double size = 11}) {
  if (s == null) return const SizedBox.shrink();
  return Row(mainAxisSize: MainAxisSize.min, children: [
    if (s.add > 0) Text('+${s.add}', style: mono(size, color: AppColors.ok)),
    if (s.add > 0 && s.del > 0) const SizedBox(width: 6),
    if (s.del > 0)
      Text('−${s.del}', style: mono(size, color: AppColors.danger)),
  ]);
}

class _WorkspaceTabState extends State<WorkspaceTab> {
  GitStatus? _status;
  String? _error;
  final Map<String, _Stat> _stats = {};
  final _message = TextEditingController();
  bool _allFiles = false;
  String? _selected; // changed file path
  String? _openPath; // file chosen from the tree or Open file
  String _filter = '';
  bool _searching = false;
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
          file: f.path,
          staged: f.staged && !f.unstaged,
          untracked: f.untracked);
      var a = 0, d = 0, h = 0;
      for (final l in p.split('\n')) {
        if (l.startsWith('@@')) h++;
        if (l.startsWith('+') && !l.startsWith('+++')) a++;
        if (l.startsWith('-') && !l.startsWith('---')) d++;
      }
      if (mounted) setState(() => _stats[f.path] = _Stat(a, d, h));
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
          unawaited(
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication));
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
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    return SizedBox(
      height: _kStrip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          Container(
            height: _kCtl,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(_kChip),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon('git-branch', size: 13, color: AppColors.fg3),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  s == null || s.branch.isEmpty ? '…' : s.branch,
                  overflow: TextOverflow.ellipsis,
                  style: codeMono(12, color: AppColors.fg1),
                ),
              ),
              if (t.add > 0) ...[
                const SizedBox(width: 8),
                Text('+${t.add}', style: mono(11.5, color: AppColors.ok)),
              ],
              if (t.del > 0) ...[
                const SizedBox(width: 6),
                Text('−${t.del}', style: mono(11.5, color: AppColors.danger)),
              ],
              if (s != null && s.ahead > 0) ...[
                const SizedBox(width: 8),
                Text('↑${s.ahead}', style: mono(11.5, color: AppColors.fg3)),
              ],
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                    () => _commit(),
                const SingleActivator(LogicalKeyboardKey.enter, control: true):
                    () => _commit(),
              },
              child: SizedBox(
                height: _kCtl,
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
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    suffixIconConstraints:
                        const BoxConstraints(minWidth: 0, minHeight: 0),
                    suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Center(
                        widthFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            child: Text(mac ? '⌘ ↵' : 'Ctrl ↵',
                                style: mono(10.5, color: AppColors.fg4)),
                          ),
                        ),
                      ),
                    ),
                    filled: true,
                    fillColor: AppColors.pageBg,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(_kChip),
                      borderSide: BorderSide(color: AppColors.border2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(_kChip),
                      borderSide: BorderSide(color: AppColors.accent),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _btn('Commit', () => _commit()),
          const SizedBox(width: 8),
          _btn('Commit and push', () => _commit(push: true), primary: true),
          const SizedBox(width: 8),
          _btn('Open PR', _openPr, icon: 'git-pull-request-arrow'),
        ]),
      ),
    );
  }

  Widget _btn(String label, VoidCallback onTap,
      {bool primary = false, String? icon}) {
    final fg = primary ? AppColors.bg : AppColors.fg1;
    return Material(
      color: primary ? AppColors.fg1 : AppColors.surface3,
      borderRadius: BorderRadius.circular(_kChip),
      child: InkWell(
        borderRadius: BorderRadius.circular(_kChip),
        onTap: _busy ? null : onTap,
        child: Container(
          height: _kCtl,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              AppIcon(icon, size: 13, color: fg),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: sans(12.5,
                    weight: primary ? W.strong : FontWeight.w400, color: fg)),
          ]),
        ),
      ),
    );
  }

  Widget _left() {
    final n = _status?.files.length ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Row(children: [
          Expanded(
            child: Container(
              height: 28,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(_kChip),
              ),
              child: Row(children: [
                _seg('Changes', '$n', !_allFiles,
                    () => setState(() => _allFiles = false)),
                _seg('All files', null, _allFiles,
                    () => setState(() => _allFiles = true)),
              ]),
            ),
          ),
          if (!_allFiles) ...[
            const SizedBox(width: 8),
            IconBtn('search',
                tooltip: 'Filter changes',
                onTap: () => setState(() {
                      _searching = !_searching;
                      if (!_searching) _filter = '';
                    })),
          ],
        ]),
      ),
      if (_searching && !_allFiles)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: SizedBox(
            height: 28,
            child: TextField(
              autofocus: true,
              onChanged: (v) =>
                  setState(() => _filter = v.trim().toLowerCase()),
              style: sans(12.5, color: AppColors.fg1),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Filter changed files',
                hintStyle: sans(12.5, color: AppColors.fg4),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                filled: true,
                fillColor: AppColors.pageBg,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(_kChip),
                  borderSide: BorderSide(color: AppColors.border2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(_kChip),
                  borderSide: BorderSide(color: AppColors.accent),
                ),
              ),
            ),
          ),
        ),
      Expanded(child: _allFiles ? _tree() : _changes()),
      _footer(),
    ]);
  }

  Widget _footer() {
    final ahead = _status?.ahead ?? 0;
    if (ahead == 0) return const SizedBox.shrink();
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border))),
      child: Row(children: [
        AppIcon('git-branch', size: 13, color: AppColors.fg4),
        const SizedBox(width: 8),
        Text('$ahead to push', style: sans(12, color: AppColors.fg3)),
      ]),
    );
  }

  Widget _seg(String label, String? count, bool on, VoidCallback tap) =>
      Expanded(
        child: Material(
          color: on ? AppColors.surface3 : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          child: InkWell(
            borderRadius: BorderRadius.circular(5),
            onTap: tap,
            child: Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(label,
                    style: sans(12, color: on ? AppColors.fg1 : AppColors.fg3)),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Text(count, style: mono(10.5, color: AppColors.fg4)),
                ],
              ]),
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
    final files = s!.files
        .where((f) => _filter.isEmpty || f.path.toLowerCase().contains(_filter))
        .toList();
    if (files.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(s.files.isEmpty ? 'Working tree clean' : 'No matches',
            style: sans(12, color: AppColors.fg3)),
      );
    }
    final groups = <String, List<GitFile>>{};
    for (final f in files) {
      final i = f.path.lastIndexOf('/');
      groups.putIfAbsent(i < 0 ? '' : f.path.substring(0, i), () => []).add(f);
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        for (final e in groups.entries) ...[
          if (e.key.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 2),
              child: Text(e.key,
                  overflow: TextOverflow.ellipsis,
                  style: sans(11.5, color: AppColors.fg4)),
            ),
          for (final f in e.value)
            _row(
              letter: gitLetter(f),
              name: f.path.split('/').last,
              stat: _stats[f.path],
              selected: _openPath == null && _selected == f.path,
              onTap: () => setState(() {
                _selected = f.path;
                _openPath = null;
              }),
            ),
        ],
      ],
    );
  }

  Widget _row({
    required String letter,
    required String name,
    required bool selected,
    required VoidCallback onTap,
    _Stat? stat,
  }) {
    return Material(
      color: selected ? AppColors.surface2 : Colors.transparent,
      borderRadius: BorderRadius.circular(_kChip),
      child: InkWell(
        borderRadius: BorderRadius.circular(_kChip),
        onTap: onTap,
        child: SizedBox(
          height: _kRow,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              SizedBox(
                width: 14,
                child: Text(letter,
                    textAlign: TextAlign.center,
                    style: mono(11, color: gitLetterColour(letter))),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(name,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12.5,
                        color: selected ? AppColors.fg1 : AppColors.fg2)),
              ),
              _delta(stat),
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

  String _abs(String path) => path.startsWith('/')
      ? path
      : '${widget.workspacePath.replaceAll(RegExp(r'/+$'), '')}/$path';

  Widget _right() {
    final open = _openPath;
    if (open != null) {
      GitFile? changed;
      for (final f in _status?.files ?? const <GitFile>[]) {
        if (f.path == open) changed = f;
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _header(open, changed == null ? null : gitLetter(changed), null,
            action: changed == null
                ? null
                : (
                    'Show diff',
                    () => setState(() {
                          _selected = open;
                          _openPath = null;
                        })
                  )),
        Expanded(
          child: FileViewer(
            key: ValueKey('ws-file-$open'),
            client: widget.client,
            path: _abs(open),
            name: open.split('/').last,
            embedded: true,
            header: false,
            sessionId: widget.sessionId,
            relPath: open,
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
    final path = file.path;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(path, gitLetter(file), _stats[path],
          action: ('Open file', () => setState(() => _openPath = path))),
      Expanded(
        child: GitFileDiffView(
          key: ValueKey('ws-diff-$path-${file.staged}-${file.unstaged}'),
          client: widget.client,
          sessionId: widget.sessionId,
          file: path,
          staged: file.staged && !file.unstaged,
          untracked: file.untracked,
          embedded: true,
        ),
      ),
    ]);
  }

  Widget _header(String path, String? letter, _Stat? stat,
      {(String, VoidCallback)? action}) {
    final i = path.lastIndexOf('/');
    final dir = i < 0 ? '' : path.substring(0, i + 1);
    final name = i < 0 ? path : path.substring(i + 1);
    return Container(
      height: 44,
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(children: [
        if (letter != null) ...[
          Text(letter, style: mono(11, color: gitLetterColour(letter))),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Row(children: [
            Flexible(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: dir, style: codeMono(12, color: AppColors.fg3)),
                  TextSpan(
                      text: name, style: codeMono(12, color: AppColors.fg1)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (stat != null) ...[
              const SizedBox(width: 10),
              _delta(stat),
            ],
          ]),
        ),
        if (stat != null && stat.hunks > 0) ...[
          Text('${stat.hunks} ${stat.hunks == 1 ? 'hunk' : 'hunks'}',
              style: sans(12, color: AppColors.fg4)),
          const SizedBox(width: 10),
        ],
        if (action != null)
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(_kChip),
            child: InkWell(
              borderRadius: BorderRadius.circular(_kChip),
              onTap: action.$2,
              child: Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border2),
                  borderRadius: BorderRadius.circular(_kChip),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  AppIcon('file', size: 13, color: AppColors.fg2),
                  const SizedBox(width: 6),
                  Text(action.$1, style: sans(12, color: AppColors.fg2)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}
