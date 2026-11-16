import 'package:flutter/material.dart';

import '../file_icons.dart';
import '../motion_routes.dart';
import '../platform.dart';
import '../theme.dart';
import '../tool_activity.dart';
import '../widgets.dart';
import 'mobile_chrome.dart';

List<ToolStep> sessionChangeSteps(List<Map<String, dynamic>> events) {
  final out = <ToolStep>[];
  Map<String, dynamic>? pending;
  for (final e in events) {
    final k = e['kind'];
    if (k == 'tool_call') {
      pending = e;
    } else if (k == 'tool_result') {
      final p = pending;
      pending = null;
      final tool = (p?['tool_name'] ?? e['tool_name'])?.toString() ?? '';
      if (toolBaseName(tool) != 'change_files') continue;
      out.add(ToolStep(tool: tool, args: p?['arguments'], result: e['result']));
    }
  }
  return out;
}

(String, String) _split(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? (path, '') : (path.substring(i + 1), path.substring(0, i));
}

class ShellChange {
  ShellChange(this.path);
  final String path;
  int add = 0;
  int del = 0;
}

/// Files the daemon saw change on disk (turn_changes) that no change_files call explains,
/// i.e. edits made through shell commands, scripts and formatters.
List<ShellChange> shellChanges(
    List<Map<String, dynamic>> events, Iterable<FileChange> covered) {
  final byPath = <String, ShellChange>{};
  for (final e in events) {
    if (e['kind'] != 'turn_changes') continue;
    for (final f in (e['files'] as List? ?? const [])) {
      if (f is! Map) continue;
      final rel = f['path']?.toString() ?? '';
      if (rel.isEmpty) continue;
      if (covered.any((c) => c.path == rel || c.path.endsWith('/$rel'))) {
        continue;
      }
      final c = byPath.putIfAbsent(rel, () => ShellChange(rel));
      c.add += (f['add'] as num?)?.toInt() ?? 0;
      c.del += (f['del'] as num?)?.toInt() ?? 0;
    }
  }
  return byPath.values.toList();
}

/// The grouped list of changed files, shared by the page and the Checkpoints drawer.
class FileChangesList extends StatelessWidget {
  const FileChangesList(
      {super.key, required this.steps, this.shell = const [], this.onOpenFile});

  final List<ToolStep> steps;
  final List<ShellChange> shell;
  final void Function(String path)? onOpenFile;

  /// How many change_files edits touched [path] in this session.
  int _edits(String path) {
    var n = 0;
    for (final s in steps) {
      if (s.failed) continue;
      for (final c in s.changes) {
        final p = c['action'] == 'move'
            ? '${c['path']} \u2192 ${c['to']}'
            : c['path']?.toString();
        if (p == path) n++;
      }
    }
    return n;
  }

  Widget _row(BuildContext context,
      {required String path,
      int edits = 0,
      required Widget trailing,
      required VoidCallback? onTap}) {
    final (name, dir) = _split(path);
    final sub = [
      if (dir.isNotEmpty) dir,
      if (edits > 0) '$edits edit${edits == 1 ? '' : 's'}',
    ].join(' \u00b7 ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(S.s12, S.of(10), S.s16, S.of(10)),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface3,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: FileGlyph(name, size: 16),
          ),
          SizedBox(width: S.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(15, color: AppColors.fg1)),
                if (sub.isNotEmpty)
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, color: AppColors.fg4)),
              ],
            ),
          ),
          SizedBox(width: S.s8),
          trailing,
        ]),
      ),
    );
  }

  Widget _delta(int add, int del) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Text('+$add', style: mono(13, color: AppColors.ok)),
        SizedBox(width: S.s6),
        Text('\u2212$del', style: mono(13, color: AppColors.danger)),
      ]);

  @override
  Widget build(BuildContext context) {
    final changes = fileChanges(steps);
    return CardGroupScope(
      child: ListGroup(children: [
        for (final c in changes)
          _row(context,
              path: c.path,
              edits: _edits(c.path),
              trailing: c.kind == FileChangeKind.deleted
                  ? Text('deleted', style: sans(13, color: AppColors.danger))
                  : _delta(c.added, c.removed),
              onTap: () => Navigator.of(context).push(
                    AppPageRoute<void>(
                      builder: (_) =>
                          FileChangeDetail(path: c.path, steps: steps),
                    ),
                  )),
        for (final c in shell)
          _row(context,
              path: c.path,
              trailing: _delta(c.add, c.del),
              onTap: onOpenFile == null ? null : () => onOpenFile!(c.path)),
      ]),
    );
  }
}

/// "File changes · N" and its list, for hosts that show it beside other content.
class FileChangesSection extends StatelessWidget {
  const FileChangesSection(
      {super.key, required this.steps, this.shell = const [], this.onOpenFile});

  final List<ToolStep> steps;
  final List<ShellChange> shell;
  final void Function(String path)? onOpenFile;

  @override
  Widget build(BuildContext context) {
    final total = fileChanges(steps).length + shell.length;
    if (total == 0) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(S.s4, S.s16, S.s4, S.s8),
        child: Text('File changes \u00b7 $total',
            style: sans(13, color: AppColors.fg3)),
      ),
      FileChangesList(steps: steps, shell: shell, onOpenFile: onOpenFile),
    ]);
  }
}

class FileChangesScreen extends StatelessWidget {
  const FileChangesScreen(
      {super.key, required this.steps, this.shell = const [], this.onOpenFile});

  final List<ToolStep> steps;
  final List<ShellChange> shell;
  final void Function(String path)? onOpenFile;

  @override
  Widget build(BuildContext context) {
    final total = fileChanges(steps).length + shell.length;
    return Scaffold(
      backgroundColor: AppColors.paneBg,
      body: SafeArea(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MobileBackBar(
            title: 'File changes',
            trailing: [
              Padding(
                padding: EdgeInsets.only(right: S.s4),
                child: Text('$total file${total == 1 ? '' : 's'}',
                    style: sans(12, color: AppColors.fg3)),
              ),
            ],
          ),
          Expanded(
            child: total == 0
                ? const EmptyState(
                    icon: 'file',
                    title: 'No file changes yet',
                    body: 'Files this session edits show up here.')
                : ListView(
                    padding: EdgeInsets.fromLTRB(S.s16, S.s6, S.s16, S.s32),
                    children: [
                      FileChangesList(
                          steps: steps, shell: shell, onOpenFile: onOpenFile),
                    ],
                  ),
          ),
        ]),
      ),
    );
  }
}

class FileChangeDetail extends StatelessWidget {
  const FileChangeDetail({super.key, required this.path, required this.steps});

  final String path;
  final List<ToolStep> steps;

  List<Map> get _edits => [
        for (final s in steps)
          if (!s.failed)
            for (final c in s.changes)
              if ((c['action'] == 'move'
                      ? '${c['path']} → ${c['to']}'
                      : c['path']?.toString()) ==
                  path)
                c,
      ];

  Widget _lines(String text, Color fg, Color bg, String sign) {
    final lines = text.trimRight().split('\n');
    return Container(
      color: bg,
      padding: EdgeInsets.symmetric(vertical: S.s2),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: S.of(10)),
        child: Text(lines.map((l) => '$sign $l').join('\n'),
            style: codeMono(12, height: 1.55, color: fg)),
      ),
    );
  }

  Widget _edit(Map c) {
    final action = c['action']?.toString() ?? '';
    final add = Color.lerp(AppColors.ok, AppColors.fg1, 0.55)!;
    final del = Color.lerp(AppColors.danger, AppColors.fg1, 0.55)!;
    final addBg = AppColors.ok.withValues(alpha: 0.10);
    final delBg = AppColors.danger.withValues(alpha: 0.10);
    final Widget body = switch (action) {
      'create' => _lines(c['content']?.toString() ?? '', add, addBg, '+'),
      'replace' => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if ((c['find']?.toString() ?? '').isNotEmpty)
              _lines(c['find'].toString(), del, delBg, '−'),
            if ((c['with']?.toString() ?? '').isNotEmpty)
              _lines(c['with'].toString(), add, addBg, '+'),
          ],
        ),
      'delete' => Padding(
          padding: EdgeInsets.all(S.of(14)),
          child: Text('File deleted', style: sans(14, color: AppColors.danger)),
        ),
      'move' => Padding(
          padding: EdgeInsets.all(S.of(14)),
          child: Text('Moved to ${c['to']}',
              style: sans(14, color: AppColors.fg2)),
        ),
      _ => const SizedBox.shrink(),
    };
    return Container(
      margin: EdgeInsets.only(bottom: S.s12),
      decoration: BoxDecoration(
        color: kMobile
            ? Color.lerp(AppColors.bg, Colors.black, 0.35)
            : AppColors.tint1,
        borderRadius: BorderRadius.circular(R.of(14)),
        border: Border.all(color: AppColors.fg1.withValues(alpha: 0.07)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: S.s6),
        child: body,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (name, dir) = _split(path);
    final edits = _edits;
    return Scaffold(
      backgroundColor: AppColors.paneBg,
      body: SafeArea(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MobileBackBar(
            title: name,
            subtitle: dir.isEmpty
                ? '${edits.length} edit${edits.length == 1 ? '' : 's'}'
                : dir,
            onTitleTap: () {},
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(S.s16, S.of(10), S.s16, S.s32),
              children: [for (final c in edits) _edit(c)],
            ),
          ),
        ]),
      ),
    );
  }
}
