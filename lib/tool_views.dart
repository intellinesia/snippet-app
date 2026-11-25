import 'dart:convert';

import 'package:flutter/material.dart';

import 'coordination_tool_views.dart';
import 'media_views.dart';
import 'theme.dart';
import 'tool_activity.dart';
import 'widgets.dart';
import 'platform.dart';
import 'state_cards.dart';
import 'tap_detector.dart';

// The daemon can evolve independently of the client. Keep malformed or newer
// result items visible only as far as they can be safely rendered; one bad item
// must not make the entire tool panel fail to build.
List<Map> _mapItems(dynamic value) =>
    value is List ? value.whereType<Map>().toList() : const <Map>[];

/// Per-tool rendering: a glyph + one-line summary for the inline tool row, and
// a rich, tool-specific body for the detail drawer (never raw JSON unless unknown).

bool _isCanvasToolName(String tool) =>
    tool.startsWith('canvas') ||
    tool == 'frame_apply' ||
    tool == 'canvas_apply' ||
    tool == 'canvas_ask';

bool _isGitToolName(String tool) =>
    tool.startsWith('git_') ||
    tool == 'git' ||
    tool == 'commit' ||
    tool == 'push' ||
    tool == 'pull_request' ||
    tool == 'pr' ||
    tool.startsWith('github_pr');

/// Lucide-ish glyph name for a tool (resolved via [iconFor]).
String toolIcon(String tool) {
  final base = toolBaseName(tool);
  return switch (base) {
    'change_files' => 'edit',
    'view_image' => 'image',
    'bash' => 'terminal',
    'read_file' || 'view_file' => 'file-text',
    'list_dir' => 'folder',
    'search_content' || 'grep_search' || 'find_by_name' || 'glob' => 'search',
    'web_search' || 'web_read' => 'globe',
    'set_session_title' => 'edit',
    'search_skills' || 'skill' => 'sparkles',
    'monitor' => 'eye',
    'present_file' => 'file',
    'manage_process' => 'cpu',
    'share_artifact' => 'file',
    'delegate_task' => 'users',
    'send_agent_message' ||
    'post_chat' ||
    'group_thread' ||
    'post_task_coordination' =>
      'message-square',
    'ask_user' => 'help-circle',
    _ when _isCanvasToolName(base) => 'layers',
    _ when _isGitToolName(base) => 'git-branch',
    _ => 'code',
  };
}

/// One-line, tool-aware summary for the inline activity line.
String toolArgSummary(String tool, dynamic args) {
  tool = toolBaseName(tool);
  if (args is! Map) return '';
  String s(String k) => args[k]?.toString() ?? '';
  String first(String v) => v.split('\n').first.trim();
  if (_isCanvasToolName(tool)) {
    return first([
      s('operation').isNotEmpty ? s('operation') : s('action'),
      s('frame').isNotEmpty ? '"${s('frame')}"' : s('title'),
      s('revision').isNotEmpty ? 'r${s('revision')}' : '',
    ].where((v) => v.isNotEmpty).join(' '));
  }
  if (_isGitToolName(tool)) {
    return first([
      s('operation').isNotEmpty ? s('operation') : s('action'),
      s('message').isNotEmpty ? '"${s('message')}"' : '',
      s('hash').isNotEmpty
          ? s('hash').substring(0, s('hash').length < 7 ? s('hash').length : 7)
          : '',
      s('pr').isNotEmpty ? '#${s('pr')}' : s('pull_request'),
    ].where((v) => v.isNotEmpty).join(' '));
  }
  final v = switch (tool) {
    // The command itself, not a placeholder. Showing "shell command" for every
    // bash call made the transcript unreadable: `cargo test`, `rm -rf build` and
    // `git push` all rendered identically, so a person watching the agent work
    // could not tell what it was doing without expanding every row.
    'bash' => s('label').isNotEmpty ? s('label') : s('command'),
    'manage_process' => [
        switch (s('action')) {
          'kill' => 'Stop',
          'log' => 'Read log of',
          'wait' => 'Wait for',
          _ => 'List processes',
        },
        if (s('action') != 'list' && s('id').isNotEmpty) s('id'),
      ].join(' '),
    'web_search' => s('query'),
    'search_content' => [
        s('query').isNotEmpty ? s('query') : s('pattern'),
        if (s('path').isNotEmpty) 'in ${s('path')}',
      ].where((v) => v.isNotEmpty).join(' '),
    'web_read' => s('url'),
    'change_files' => _changesSummary(normalizeChanges(args)),
    'view_image' => s('path'),
    'set_session_title' => s('title'),
    'search_skills' => s('query'),
    'skill' => s('name'),
    'monitor' => s('path').isNotEmpty ? s('path') : s('action'),
    'present_file' => s('path'),
    'share_artifact' => s('title').isNotEmpty
        ? s('title')
        : s('path').isNotEmpty
            ? s('path').split('/').last
            : s('artifact_id'),
    'read_file' => s('path'),
    'view_file' => s('AbsolutePath').contains('/.gemini/antigravity-cli/')
        ? 'saved tool output'
        : s('AbsolutePath'),
    'ping_user' => s('title'),
    'schedule_wake' || 'schedule_followup' => s('note'),
    _ => '',
  };
  if (v.isNotEmpty) return first(v);
  for (final k in const [
    'title',
    'id',
    'name',
    'command',
    'path',
    'query',
    'pattern',
    'url',
    'file',
    'content'
  ]) {
    if (args[k] is String) return first(args[k] as String);
  }
  return '';
}

/// Whether a step has anything behind its row — the one rule the transcript
/// rows and the tool sheet share.
bool toolHasDetail(ToolStep step) {
  final tool = toolBaseName(step.tool);
  final args = step.args;
  final result = step.result;
  String arg(String key) {
    if (args is! Map) return '';
    return (args[key] ?? '').toString();
  }

  bool resultHasBody() {
    if (result == null) return false;
    if (result is! Map) return result.toString().trim().isNotEmpty;
    if ((result['status'] ?? '').toString() == 'error') return true;
    final data = result['data'] is Map ? result['data'] as Map : result;
    for (final key in const ['stdout', 'stderr', 'content', 'text', 'output']) {
      if ((data[key] ?? '').toString().trim().isNotEmpty) return true;
    }
    for (final key in const ['entries', 'matches', 'results']) {
      final list = data[key];
      if (list is List && list.isNotEmpty) return true;
    }
    return false;
  }

  // A failure always has something to show: the error.
  if (result is Map && (result['status'] ?? '').toString() == 'error') {
    return true;
  }
  // A running step can still have content in its arguments (a diff, a long
  // command); each check below looks only where its content lives.
  if (ackTools.contains(tool)) return false;
  final data = result is Map && result['data'] is Map
      ? result['data'] as Map
      : (result is Map ? result : null);
  final coordination =
      coordinationHasDetail(tool, args is Map ? args : null, data);
  if (coordination != null) return coordination;
  if (_isCanvasToolName(tool) || _isGitToolName(tool)) {
    return args is Map && args.isNotEmpty || resultHasBody();
  }

  switch (tool) {
    case 'change_files':
      return normalizeChanges(args).isNotEmpty;
    case 'view_image':
    case 'present_file':
      return arg('path').trim().isNotEmpty ||
          (data?['path'] ?? '').toString().trim().isNotEmpty;
    case 'bash':
      final cmd = arg('command');
      return arg('label').trim().isNotEmpty ||
          cmd.split('\n').length > 1 ||
          cmd.length > 80 ||
          resultHasBody();
    case 'web_search':
    case 'web_read':
      return resultHasBody();
    case 'read_file':
      return true;
    case 'manage_process':
      return (data?['log'] ?? '').toString().trim().isNotEmpty;
    default:
      final shown = toolArgSummary(tool, args);
      return shown.contains('…') ||
          resultHasBody() ||
          (args is Map && args.isNotEmpty);
  }
}

/// Friendly title for the drawer header.
String toolTitle(String tool) {
  final base = toolBaseName(tool);
  return switch (base) {
    'change_files' => 'Change',
    'view_image' => 'Image',
    'bash' => 'Run',
    'web_search' => 'Search',
    'web_read' => 'Page',
    'set_session_title' => 'Title',
    'search_skills' => 'Skills',
    'skill' => 'Skill',
    'monitor' => 'Watch',
    'present_file' => 'Present',
    'read_file' => 'Read',
    'view_file' => 'Read',
    _ when _isCanvasToolName(base) => 'Canvas',
    _ when _isGitToolName(base) => 'Git',
    _ => _humanizeTool(base),
  };
}

String _humanizeTool(String tool) {
  final parts = tool.split(RegExp(r'[_\-]+')).where((p) => p.isNotEmpty);
  return parts
      .map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}')
      .join(' ');
}

/// Tool detail rendering is isolated behind a small error boundary. A malformed
/// result must produce a useful panel message instead of taking down the sheet.
Widget safeToolDetailView(BuildContext context,
    {required String tool, dynamic args, dynamic result}) {
  return Builder(builder: (panelContext) {
    try {
      return toolDetailView(panelContext,
          tool: tool, args: args, result: result);
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'snippet tool panel',
        context: ErrorDescription('building $tool details'),
      ));
      return const _ToolPanelError();
    }
  });
}

class _ToolPanelError extends StatelessWidget {
  const _ToolPanelError();
  @override
  Widget build(BuildContext context) {
    return Text('This tool panel could not render its result.',
        style: sans(13, color: AppColors.fg1));
  }
}

/// The unframed body for a tool, meant to sit inside one block.
/// [result] is the full ToolResult map ({status, data, error}); null while
/// the call is still pending.
Widget toolDetailView(BuildContext context,
    {required String tool, dynamic args, dynamic result}) {
  tool = toolBaseName(tool);
  final Map? a = args is Map ? args : null;
  final Map? r = result is Map ? result : null;
  final status = r?['status']?.toString();
  final data = r?['data'];
  final Map? d = data is Map ? data : (r != null && status == null ? r : null);
  final err = r?['error'];
  final errMsg = err is Map ? err['message']?.toString() : null;
  final running = result == null;

  if (status == 'error' && errMsg != null && tool == 'bash') {
    final cmd = (a?['label'] ?? a?['command'] ?? 'Command').toString().trim();
    return _wrap([
      ToolErrorPanel(
          title: '${cmd.split('\n').first} failed',
          output: _displayText(errMsg))
    ]);
  }

  final rows = <Widget>[];
  if (status == 'error' && errMsg != null) {
    // Errors are sentences: wrap them so the whole message reads.
    rows.add(Text(_displayText(errMsg).trim(),
        style: sans(_bodySize, height: 1.45, color: AppColors.fg2)));
    rows.add(SizedBox(height: S.s8));
  }

  if (d != null &&
      (d['data_omitted'] == true ||
          d['truncated'] == true && d['preview'] != null)) {
    rows.addAll(_toolBody(context, tool, a, d, status, running));
    if (d['preview'] != null) {
      rows.add(SizedBox(height: S.s8));
      rows.add(_hscroll(
          Text(_displayText(d['preview'].toString()), style: _code())));
    }
    if (d['hint'] != null) {
      rows.add(SizedBox(height: S.s8));
      rows.add(_Hint(d['hint'].toString()));
    }
    return _wrap(rows);
  }

  rows.addAll(_toolBody(context, tool, a, d, status, running));
  if (rows.isEmpty) {
    rows.add(Text('No details.', style: sans(_bodySize, color: AppColors.fg3)));
  }
  return _wrap(rows);
}

double get _bodySize => kMobile ? 13.5 : 13;

TextStyle _code([Color? color]) => codeMono(kMobile ? 13 : 12,
    height: kMobile ? 1.45 : 1.65, color: color ?? AppColors.fg2);

Widget _wrap(List<Widget> rows) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);

Widget _hscroll(Widget child) => _HScroll(child);

class _HScroll extends StatelessWidget {
  const _HScroll(this.child);
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: c.maxWidth),
            child: IntrinsicWidth(child: child),
          ),
        ),
      );
}

List<Widget> _toolBody(BuildContext context, String tool, Map? a, Map? d,
    String? status, bool running) {
  if (_isCanvasToolName(tool)) return _canvasView(a, d, status);
  if (_isGitToolName(tool)) return _gitView(a, d, status);
  switch (tool) {
    case 'change_files':
      return _changeFilesView(a, d, failed: status == 'error');
    case 'view_image':
      return _imageView(context, a, d);
    case 'bash':
      return _bashView(a, d, running: running);
    case 'web_search':
      return _webSearchView(context, a, d);
    case 'web_read':
      return _webReadView(a, d);
    case 'search_content':
      return _searchContentView(a, d);
    case 'set_session_title':
      return _titleView(a, d);
    case 'search_skills':
    case 'skill':
      return _skillView(tool, a, d);
    case 'monitor':
      return _monitorView(a, d);
    case 'present_file':
      return _presentView(context, a, d);
    case 'read_file':
      return _readFileView(a, d);
    case 'manage_process':
      final log = d?['log']?.toString() ?? '';
      if (log.trim().isNotEmpty) {
        return _bashView(null, {'stdout': log}, running: running);
      }
      final note = d?['note']?.toString() ?? '';
      if (note.isNotEmpty) {
        return [Text(note, style: sans(_bodySize, color: AppColors.fg2))];
      }
      return _simpleFallback(a, d);
    default:
      if (d?['custom_tool'] != null) {
        return _bashView({'command': d?['command'], 'label': tool}, d,
            running: running);
      }
      return coordinationToolBody(context, tool, a, d) ?? _simpleFallback(a, d);
  }
}

// ---- meta + copy ----

List<String> toolMetaParts(ToolStep step) {
  final tool = toolBaseName(step.tool);
  final d = step.data;
  String plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';
  switch (tool) {
    case 'bash':
      final code = step.exitCode;
      final ms = d?['duration_ms'];
      final secs = d?['duration_secs'] ?? d?['elapsed_secs'];
      final time = ms is num
          ? '${(ms / 1000).toStringAsFixed(1)}s'
          : secs is num
              ? '${secs.toStringAsFixed(1)}s'
              : null;
      return [
        if (d?['background'] == true) 'background',
        if (code != null && code != 0) 'exit $code',
        if (time != null) time,
      ];
    case 'read_file':
      final entries = d?['entries'];
      if (entries is List) {
        final n = (d?['total'] as num?)?.toInt() ?? entries.length;
        return [plural(n, 'entry', 'entries')];
      }
      final total = (d?['total_lines'] as num?)?.toInt();
      return [if (total != null) plural(total, 'line', 'lines')];
    case 'search_content':
      final n = _searchMatches(d).length;
      return [if (n > 0) plural(n, 'match', 'matches')];
    case 'web_search':
      final n = _mapItems(d?['results']).length;
      return [if (n > 0) plural(n, 'result', 'results')];
    case 'web_read':
      final date = d?['published_date']?.toString() ?? '';
      final words = (d?['word_count'] ?? d?['words']) as num?;
      return [
        if (date.isNotEmpty) date,
        if (words != null) plural(words.toInt(), 'word', 'words'),
      ];
    case 'manage_process':
      final code = (d?['exit_status'] as num?)?.toInt();
      return [
        if (d?['outcome'] == 'timeout') 'still running',
        if (code != null && code != 0) 'exit $code',
      ];
    case 'view_image':
      final w = (d?['width'] as num?)?.toInt();
      final h = (d?['height'] as num?)?.toInt();
      return [if (w != null && h != null) '$w×$h'];
    case 'skill':
    case 'search_skills':
      final results = d?['results'];
      if (results is List) return [plural(results.length, 'skill', 'skills')];
      return const [];
  }
  if (_isCanvasToolName(tool)) {
    final revision =
        d?['revision'] ?? (step.args is Map ? step.args['revision'] : null);
    final ops = (step.args is Map ? step.args['ops'] : null);
    return [
      if (ops is List) plural(ops.length, 'op', 'ops'),
      if (revision != null && revision.toString().isNotEmpty) 'r$revision',
    ];
  }
  if (_isGitToolName(tool)) {
    final hash = (d?['hash'] ?? d?['commit'] ?? '').toString();
    final files = (d?['files_changed'] ?? d?['files']) as num?;
    return [
      if (hash.isNotEmpty) hash.substring(0, hash.length < 7 ? hash.length : 7),
      if (files != null) plural(files.toInt(), 'file', 'files'),
    ];
  }
  final ms = d?['duration_ms'];
  final secs = d?['duration_secs'] ?? d?['elapsed_secs'];
  return [
    if (ms is num) '${(ms / 1000).toStringAsFixed(1)}s',
    if (ms is! num && secs is num) '${secs.toStringAsFixed(1)}s',
  ];
}

// ---- per-tool views ----

Widget _fileLabel(String name, int adds, int dels, {String note = ''}) =>
    Row(children: [
      Flexible(
        child: Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: codeMono(kMobile ? 12 : 12, color: AppColors.fg3)),
      ),
      if (adds > 0) ...[
        SizedBox(width: S.s8),
        Text('+$adds',
            style: codeMono(kMobile ? 12 : 12,
                color: kMobile ? AppColors.ok : AppColors.fg2)),
      ],
      if (dels > 0) ...[
        SizedBox(width: S.s6),
        Text('−$dels',
            style: codeMono(kMobile ? 12 : 12,
                color: kMobile ? AppColors.danger : AppColors.fg3)),
      ],
      if (note.isNotEmpty) ...[
        SizedBox(width: S.s8),
        Text(note, style: codeMono(kMobile ? 12 : 12, color: AppColors.fg4)),
      ],
    ]);

List<Widget> _changeFilesView(Map? a, Map? d, {bool failed = false}) {
  final changes = normalizeChanges(a);
  if (changes.isEmpty) return const [];
  final out = <Widget>[];
  for (final raw in changes.whereType<Map>()) {
    String field(String key) => raw[key]?.toString() ?? '';
    var label = field('path');
    var lines = <_DLine>[];
    var note = '';
    switch (field('action')) {
      case 'replace':
        lines = _diff(field('find'), field('with'));
        if (raw['all'] == true) note = 'all matches';
      case 'create':
        lines = [
          for (final l in _splitLines(field('content'))) _DLine(_DKind.add, l)
        ];
        if (raw['overwrite'] == true) note = 'overwrite';
      case 'delete':
        note = failed ? 'delete' : 'deleted';
      case 'move':
        label = '$label → ${field('to')}';
        note = failed ? 'move' : 'moved';
      default:
        continue;
    }
    final adds = lines.where((l) => l.kind == _DKind.add).length;
    final dels = lines.where((l) => l.kind == _DKind.del).length;
    if (out.isNotEmpty) out.add(SizedBox(height: S.s12));
    out.add(_fileLabel(label, adds, dels, note: note));
    if (lines.isNotEmpty) {
      out.add(SizedBox(height: S.s4));
      out.add(_hscroll(_DiffLines(lines)));
    }
  }
  final notes = d?['notes']?.toString();
  if (notes != null && notes.isNotEmpty) {
    out.add(SizedBox(height: S.s8));
    out.add(_Hint(notes));
  }
  return out;
}

(int, int) diffCounts(String find, String replacement) {
  final lines = _diff(find, replacement);
  return (
    lines.where((l) => l.kind == _DKind.add).length,
    lines.where((l) => l.kind == _DKind.del).length,
  );
}

final errorLineMarker = RegExp(
    r'^\s*([Ee]rror|[Ff]atal|FATAL|[Pp]anic|[Ee]xception|Traceback)\b|error\[E|\bError:|\bFAILED\b');

List<Widget> _bashView(Map? a, Map? d, {required bool running, String? error}) {
  final cmd = _displayText(a?['command']?.toString() ?? '').trimRight();
  final raw = d?['stdout'] ?? d?['output_so_far'] ?? d?['output'];
  final stdout = _displayText(raw?.toString() ?? '').trimRight();
  var stderr = _displayText(d?['stderr']?.toString() ?? '').trimRight();
  if (error != null && error.trim().isNotEmpty) {
    final e = _displayText(error).trimRight();
    stderr = stderr.isEmpty ? e : '$stderr\n$e';
  }
  final labelled = (a?['label']?.toString() ?? '').trim().isNotEmpty;
  final showCommand = cmd.isNotEmpty &&
      (!kMobile ||
          labelled ||
          running ||
          cmd.contains('\n') ||
          cmd.length > 60);
  // The command wraps so it reads in full; output scrolls to keep columns.
  final cmdSpans = <InlineSpan>[];
  final spans = <InlineSpan>[];
  void line(String text, Color color) {
    if (spans.isNotEmpty) spans.add(const TextSpan(text: '\n'));
    spans.add(TextSpan(text: text, style: TextStyle(color: color)));
  }

  if (showCommand) {
    final cmdLines = cmd.split('\n');
    for (var i = 0; i < cmdLines.length; i++) {
      if (cmdSpans.isNotEmpty) cmdSpans.add(const TextSpan(text: '\n'));
      cmdSpans.add(TextSpan(
          text: i == 0 ? '\$ ' : '  ', style: TextStyle(color: AppColors.fg4)));
      cmdSpans.add(
          TextSpan(text: cmdLines[i], style: TextStyle(color: AppColors.fg1)));
    }
  }
  if (stdout.isNotEmpty) {
    for (final l in stdout.split('\n')) {
      final comment = l.trimLeft().startsWith('#');
      line(
          l,
          errorLineMarker.hasMatch(l)
              ? (kMobile ? AppColors.danger : AppColors.fg1)
              : comment
                  ? AppColors.fg3
                  : (kMobile ? AppColors.fg2 : AppColors.fg1));
    }
  }
  if (stderr.isNotEmpty) {
    if (stdout.isNotEmpty) spans.add(const TextSpan(text: '\n'));
    for (final l in stderr.split('\n')) {
      line(l, kMobile ? AppColors.danger : AppColors.fg1);
    }
  }
  final command = cmdSpans.isEmpty
      ? null
      : Text.rich(TextSpan(style: _code(), children: cmdSpans));
  if (spans.isEmpty) {
    return [
      if (command != null) command,
      if (command == null)
        Text(running ? 'No output yet' : 'No output',
            style: sans(_bodySize, color: AppColors.fg3))
    ];
  }
  return [
    if (command != null) ...[command, const SizedBox(height: 8)],
    _hscroll(Text.rich(TextSpan(style: _code(), children: spans))),
  ];
}

Widget _numberedCode(String text, {int start = 1}) {
  final lines = text.split('\n');
  final width = '${start + lines.length - 1}'.length;
  final numbers = [
    for (var i = 0; i < lines.length; i++) '${start + i}'.padLeft(width)
  ].join('\n');
  return _hscroll(Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(numbers, style: _code(AppColors.fg4)),
      SizedBox(width: S.of(14)),
      Text(text, style: _code()),
    ],
  ));
}

List<Widget> _readFileView(Map? a, Map? d) {
  final entries = d?['entries'];
  if (entries is List) {
    if (entries.isEmpty) {
      return [
        Text('Empty folder', style: sans(_bodySize, color: AppColors.fg3))
      ];
    }
    return [
      for (final e in entries)
        () {
          final parts = e.toString().split('\t');
          return Padding(
            padding: EdgeInsets.symmetric(vertical: S.s2),
            child: Row(children: [
              Expanded(
                child: Text(parts.first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _code(AppColors.fg1)),
              ),
              if (parts.length > 1) ...[
                SizedBox(width: S.s12),
                Text(parts.sublist(1).join(' '), style: _code(AppColors.fg3)),
              ],
            ]),
          );
        }(),
    ];
  }
  if (d?['binary'] == true) {
    return [
      Text('Binary file, ${d?['bytes'] ?? '?'} bytes',
          style: sans(_bodySize, color: AppColors.fg3))
    ];
  }
  final content = _displayText((d?['content'] ?? '').toString());
  if (content.isEmpty) {
    return [Text('Empty file', style: sans(_bodySize, color: AppColors.fg3))];
  }
  final start = ((d?['start_line'] ?? d?['offset']) as num?)?.toInt() ?? 1;
  final body = content.replaceFirst(RegExp(r'\n$'), '');
  final all = body.split('\n');
  const cap = 400;
  final shown = all.length > cap ? all.take(cap).join('\n') : body;
  return [
    _numberedCode(shown, start: start < 1 ? 1 : start),
    if (all.length > cap) ...[
      SizedBox(height: S.s6),
      Text('Showing the first $cap of ${all.length} lines',
          style: sans(13, color: AppColors.fg3)),
    ],
  ];
}

class _Match {
  const _Match(this.path, this.line, this.text);
  final String path;
  final String line;
  final String text;
}

List<_Match> _searchMatches(Map? d) {
  final raw = d?['matches'] ?? d?['results'];
  if (raw is! List) return const [];
  String s(dynamic v) => v?.toString() ?? '';
  return [
    for (final m in raw)
      if (m is Map)
        _Match(s(m['path'] ?? m['file']), s(m['line'] ?? m['line_number']),
            s(m['text'] ?? m['content'] ?? m['line_text']).trim())
      else
        () {
          final parts = m.toString().split(':');
          return parts.length >= 3
              ? _Match(parts[0], parts[1], parts.sublist(2).join(':').trim())
              : _Match('', '', m.toString());
        }(),
  ];
}

List<Widget> _searchContentView(Map? a, Map? d) {
  final query = (a?['query'] ?? a?['pattern'] ?? '').toString();
  final matches = _searchMatches(d);
  if (matches.isEmpty) {
    final text = _displayText((d?['output'] ?? d?['text'] ?? '').toString());
    return [
      Text(text.trim().isEmpty ? 'No matches' : text.trimRight(),
          style: sans(_bodySize, color: AppColors.fg3))
    ];
  }
  return [
    for (final m in matches)
      Padding(
        padding: EdgeInsets.symmetric(vertical: S.of(3)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (m.path.isNotEmpty)
            Text(m.line.isEmpty ? m.path : '${m.path}:${m.line}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: codeMono(kMobile ? 12 : 12, color: AppColors.fg3)),
          if (m.text.isNotEmpty) _highlightedLine(m.text, query),
        ]),
      ),
  ];
}

String _host(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  return host.startsWith('www.') ? host.substring(4) : host;
}

List<Widget> _webSearchView(BuildContext context, Map? a, Map? d) {
  final results = _mapItems(d?['results']);
  if (results.isEmpty) return const [];
  return [
    for (var i = 0; i < results.length; i++)
      Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : S.s12),
        child: _WebResult(
          title: results[i]['title']?.toString() ?? '',
          url: results[i]['url']?.toString() ?? '',
          date: results[i]['published_date']?.toString() ?? '',
          snippet: results[i]['snippet']?.toString() ?? '',
        ),
      ),
  ];
}

class _WebResult extends StatelessWidget {
  const _WebResult(
      {required this.title,
      required this.url,
      required this.date,
      required this.snippet});
  final String title;
  final String url;
  final String date;
  final String snippet;

  @override
  Widget build(BuildContext context) {
    final host = _host(url);
    final meta = [if (host.isNotEmpty) host, if (date.isNotEmpty) date];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: url.isEmpty ? null : () => openMarkdownLink(url, context),
        child: Text(title.isEmpty ? (host.isEmpty ? url : host) : title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: sans(_bodySize + 0.5,
                weight: W.label, color: AppColors.accent)),
      ),
      if (meta.isNotEmpty)
        Padding(
          padding: EdgeInsets.only(top: S.of(1)),
          child: Text(meta.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: codeMono(kMobile ? 12 : 12, color: AppColors.fg3)),
        ),
      if (snippet.isNotEmpty)
        Padding(
          padding: EdgeInsets.only(top: S.of(3)),
          child: Text(snippet,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: sans(_bodySize, height: 1.45, color: AppColors.fg2)),
        ),
    ]);
  }
}

List<Widget> _webReadView(Map? a, Map? d) {
  final out = <Widget>[];
  final title = d?['title']?.toString() ?? '';
  if (title.isNotEmpty) {
    out.add(Text(title,
        style: sans(_bodySize + 1, weight: W.label, color: AppColors.fg1)));
  }
  final text = d?['text']?.toString();
  if (text != null && text.trim().isNotEmpty) {
    if (out.isNotEmpty) out.add(SizedBox(height: S.s6));
    out.add(Text(_displayText(text).trim(),
        style: sans(_bodySize, height: 1.5, color: AppColors.fg2)));
  }
  return out;
}

Widget _detailLine(String label, String value, {bool monoText = true}) {
  if (value.trim().isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: EdgeInsets.only(bottom: S.s4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 82,
        child: Text(label, style: sans(11.5, color: AppColors.fg3)),
      ),
      Expanded(
        child: Text(value,
            style: monoText
                ? codeMono(12, height: 1.5, color: AppColors.fg1)
                : sans(_bodySize, height: 1.45, color: AppColors.fg2)),
      ),
    ]),
  );
}

List<Widget> _canvasView(Map? a, Map? d, String? status) {
  String pick(String key) => (d?[key] ?? a?[key] ?? '').toString().trim();
  final operation = [
    pick('operation'),
    pick('action'),
    pick('kind'),
  ].firstWhere((v) => v.isNotEmpty, orElse: () => 'canvas call');
  final frame = [pick('frame'), pick('frame_id'), pick('title'), pick('id')]
      .firstWhere((v) => v.isNotEmpty, orElse: () => '');
  final revision = pick('revision').isNotEmpty ? 'r${pick('revision')}' : '';
  final ops = a?['ops'];
  final question = [pick('question'), pick('ask'), pick('body')]
      .firstWhere((v) => v.isNotEmpty, orElse: () => '');
  final rows = <Widget>[
    if (status == 'error')
      Padding(
        padding: EdgeInsets.only(bottom: S.s6),
        child: Row(children: [
          AppIcon('x', size: 13, color: AppColors.fg1),
          SizedBox(width: S.s6),
          Text('Failed',
              style: sans(12, weight: W.label, color: AppColors.fg1)),
        ]),
      ),
    _detailLine('Operation', operation),
    _detailLine('Frame', frame),
    if (revision.isNotEmpty) _detailLine('Revision', revision),
    if (ops is List) _detailLine('Operations', '${ops.length}'),
    if (question.isNotEmpty) _detailLine('Ask', question, monoText: false),
  ];
  return rows.isEmpty ? _simpleFallback(a, d) : rows;
}

List<Widget> _gitView(Map? a, Map? d, String? status) {
  String pick(String key) => (d?[key] ?? a?[key] ?? '').toString().trim();
  final operation = [pick('operation'), pick('action'), pick('command')]
      .firstWhere((v) => v.isNotEmpty, orElse: () => 'git operation');
  final hash = pick('hash').isNotEmpty ? pick('hash') : pick('commit');
  final shortHash =
      hash.isEmpty ? '' : hash.substring(0, hash.length < 7 ? hash.length : 7);
  final message = pick('message');
  final pr = [pick('pr'), pick('pull_request'), pick('number')]
      .firstWhere((v) => v.isNotEmpty, orElse: () => '');
  final rows = <Widget>[
    if (status == 'error')
      Padding(
        padding: EdgeInsets.only(bottom: S.s6),
        child: Row(children: [
          AppIcon('x', size: 13, color: AppColors.fg1),
          SizedBox(width: S.s6),
          Text('Failed',
              style: sans(12, weight: W.label, color: AppColors.fg1)),
        ]),
      ),
    _detailLine('Operation', operation),
    if (shortHash.isNotEmpty) _detailLine('Commit', shortHash),
    if (message.isNotEmpty) _detailLine('Message', message),
    if (pr.isNotEmpty) _detailLine('PR', pr.startsWith('#') ? pr : '#$pr'),
    if (pick('url').isNotEmpty) _detailLine('URL', pick('url')),
  ];
  return rows.length <= (status == 'error' ? 2 : 1)
      ? _simpleFallback(a, d)
      : rows;
}

String? _jsonTail(dynamic value) {
  if (value == null) return null;
  String encoded;
  try {
    encoded = jsonEncode(value);
  } catch (_) {
    encoded = value.toString();
  }
  encoded = encoded.trim();
  if (encoded.isEmpty || encoded == '{}' || encoded == 'null') return null;
  const cap = 900;
  if (encoded.length > cap) {
    encoded = '…${encoded.substring(encoded.length - cap)}';
  }
  return encoded;
}

List<Widget> _simpleFallback(Map? a, Map? d) {
  final bits = <String>[];
  void take(dynamic v) {
    if (v is String && v.trim().isNotEmpty) bits.add(v.trim());
  }

  if (a != null) {
    for (final k in const [
      'title',
      'id',
      'name',
      'path',
      'query',
      'content',
      'text'
    ]) {
      take(a[k]);
    }
  }
  if (d != null) {
    for (final k in const [
      'title',
      'id',
      'name',
      'path',
      'content',
      'text',
      'message'
    ]) {
      take(d[k]);
    }
  }
  final rows = <Widget>[];
  if (bits.isNotEmpty) {
    rows.add(Text(_displayText(bits.first).trimRight(),
        style: sans(_bodySize, height: 1.45, color: AppColors.fg2)));
  }
  final argTail = _jsonTail(a);
  final resultTail = _jsonTail(d);
  void jsonRow(String label, String tail) {
    rows.add(Padding(
      padding: EdgeInsets.only(top: rows.isEmpty ? 0 : S.s6),
      child: Text('$label $tail',
          style: codeMono(11.5, height: 1.5, color: AppColors.fg3)),
    ));
  }

  if (argTail != null) jsonRow('args', argTail);
  if (resultTail != null && resultTail != argTail) {
    jsonRow('result', resultTail);
  }
  if (rows.isEmpty) {
    rows.add(Text('Done', style: sans(_bodySize, color: AppColors.fg3)));
  }
  return rows;
}

// ---- shared pieces ----

Widget _highlightedLine(String text, String query) {
  final base = _code();
  final q = query.trim();
  if (q.isEmpty) {
    return Text(text,
        maxLines: 2, overflow: TextOverflow.ellipsis, style: base);
  }
  final lower = text.toLowerCase();
  final needle = q.toLowerCase();
  final spans = <InlineSpan>[];
  var i = 0;
  while (i < text.length) {
    final at = lower.indexOf(needle, i);
    if (at < 0) {
      spans.add(TextSpan(text: text.substring(i)));
      break;
    }
    if (at > i) spans.add(TextSpan(text: text.substring(i, at)));
    spans.add(TextSpan(
      text: text.substring(at, at + needle.length),
      style: TextStyle(color: AppColors.accent, fontWeight: weightFor(W.label)),
    ));
    i = at + needle.length;
  }
  return Text.rich(TextSpan(style: base, children: spans),
      maxLines: 2, overflow: TextOverflow.ellipsis);
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);
  @override
  Widget build(BuildContext context) =>
      Text(text, style: sans(_bodySize - 1, color: AppColors.fg3));
}

String _changesSummary(dynamic changes) {
  if (changes is! List || changes.isEmpty) return '';
  final first = changes.first is Map
      ? (changes.first as Map)['path']?.toString() ?? ''
      : '';
  return changes.length == 1 ? first : '$first (+${changes.length - 1} more)';
}

List<Widget> _imageView(BuildContext context, Map? a, Map? d) {
  final path = (d?['path'] ?? a?['path'])?.toString() ?? '';
  final client = DaemonScope.maybeOf(context);
  if (path.isEmpty) return const [];
  if (client == null) return [Text(path, style: TS.label(AppColors.fg2))];
  return [
    LayoutBuilder(
      builder: (_, c) => SingleImage(
        client: client,
        path: path,
        maxWidth: c.maxWidth.clamp(72.0, kMobile ? 240.0 : 360.0),
        maxHeight: kMobile ? 180 : 200,
      ),
    ),
  ];
}

List<Widget> _titleView(Map? a, Map? d) {
  final title = (d?['title'] ?? a?['title'])?.toString() ?? '';
  if (title.trim().isEmpty) {
    return [Text('Cleared title', style: sans(13, color: AppColors.fg3))];
  }
  return [
    Text(title,
        style: sans(kMobile ? 14 : 13, weight: W.label, color: AppColors.fg1)),
  ];
}

List<Widget> _skillView(String tool, Map? a, Map? d) {
  final name = (d?['name'] ?? a?['name'] ?? a?['query'])?.toString() ?? '';
  final text =
      (d?['content'] ?? d?['description'] ?? d?['text'])?.toString() ?? '';
  final out = <Widget>[];
  if (name.isNotEmpty) {
    out.add(Text(name, style: TS.label(AppColors.fg1)));
  }
  if (text.trim().isNotEmpty) {
    if (out.isNotEmpty) out.add(SizedBox(height: S.s6));
    out.add(_ToolMarkdown(_displayText(text).trimRight()));
  }
  if (out.isEmpty) {
    out.add(Text(toolTitle(tool), style: sans(13, color: AppColors.fg3)));
  }
  return out;
}

List<Widget> _monitorView(Map? a, Map? d) {
  final action = (a?['action'] ?? d?['action'] ?? 'add').toString();
  final path = (a?['path'] ?? d?['path'])?.toString() ?? '';
  final filter = (a?['filter'] ?? d?['filter'])?.toString() ?? '';
  final out = <Widget>[
    Text(action, style: TS.label(AppColors.fg1)),
  ];
  if (path.isNotEmpty) {
    out.add(SizedBox(height: S.s4));
    out.add(Text(path, style: codeMono(12, color: AppColors.fg2)));
  }
  if (filter.isNotEmpty) {
    out.add(SizedBox(height: S.s4));
    out.add(Text(filter, style: codeMono(11, color: AppColors.fg3)));
  }
  return out;
}

List<Widget> _presentView(BuildContext context, Map? a, Map? d) {
  final path = (a?['path'] ?? d?['path'])?.toString() ?? '';
  final caption = (a?['caption'] ?? d?['caption'])?.toString() ?? '';
  final client = DaemonScope.maybeOf(context);
  return [
    if (path.isNotEmpty)
      client == null
          ? Text(path, style: TS.label(AppColors.fg1))
          : FileChip(client: client, path: path),
    if (caption.isNotEmpty) ...[
      SizedBox(height: S.s4),
      Text(caption, style: sans(13, color: AppColors.fg3)),
    ],
  ];
}

class _ToolMarkdown extends StatelessWidget {
  final String data;
  const _ToolMarkdown(this.data);
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return MarkdownBody(
      data: data,
      selectable: false,
      styleSheet: markdownStyle(context),
      builders: {'pre': PreBlockBuilder()},
      onTapLink: (txt, href, title) => openMarkdownLink(href, context, txt),
    );
  }
}

// Tool previews may be JSON strings that were encoded once for the result
// envelope. Restore escaped control characters for display without changing the
// underlying command/file data.
final _ansiEscape = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');

String _displayText(String text) => text
    .replaceAll(_ansiEscape, '')
    .replaceAll(r'\r\n', '\n')
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\r', '\r');

List<String> _splitLines(String text) {
  final t = text.trimRight();
  return t.isEmpty ? const [] : t.split('\n');
}

enum _DKind { ctx, add, del }

class _DLine {
  final _DKind kind;
  final String text;
  const _DLine(this.kind, this.text);
}

/// Line-level unified diff via LCS. Falls back to remove-all/add-all for very
/// large inputs (keeps it O(1) instead of O(n·m)).
List<_DLine> _diff(String aStr, String bStr) {
  final a = _splitLines(aStr);
  final b = _splitLines(bStr);
  var head = 0;
  while (head < a.length && head < b.length && a[head] == b[head]) {
    head++;
  }
  var tail = 0;
  while (tail < a.length - head &&
      tail < b.length - head &&
      a[a.length - 1 - tail] == b[b.length - 1 - tail]) {
    tail++;
  }
  final prefix = [for (final l in a.take(head)) _DLine(_DKind.ctx, l)];
  final suffix = [
    for (final l in a.skip(a.length - tail)) _DLine(_DKind.ctx, l)
  ];
  return [
    ...prefix,
    ..._diffMiddle(
        a.sublist(head, a.length - tail), b.sublist(head, b.length - tail)),
    ...suffix
  ];
}

List<_DLine> _diffMiddle(List<String> a, List<String> b) {
  final n = a.length, m = b.length;
  if (n * m > 250000) {
    return [
      for (final l in a) _DLine(_DKind.del, l),
      for (final l in b) _DLine(_DKind.add, l),
    ];
  }
  // LCS dp table (suffix form).
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = a[i] == b[j]
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final out = <_DLine>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      out.add(_DLine(_DKind.ctx, a[i]));
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      out.add(_DLine(_DKind.del, a[i]));
      i++;
    } else {
      out.add(_DLine(_DKind.add, b[j]));
      j++;
    }
  }
  while (i < n) {
    out.add(_DLine(_DKind.del, a[i++]));
  }
  while (j < m) {
    out.add(_DLine(_DKind.add, b[j++]));
  }
  return out;
}

// ---- diff ----

class _DiffLines extends StatelessWidget {
  final List<_DLine> diffLines;
  const _DiffLines(this.diffLines);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final l in diffLines.take(_maxLines)) _row(l),
          if (diffLines.length > _maxLines)
            Padding(
              padding: EdgeInsets.all(S.s6),
              child: Text('${diffLines.length - _maxLines} more lines',
                  style: _code(AppColors.fg4)),
            ),
        ],
      );

  // A transcript row can't scroll lazily; a generated file would stall the chat.
  static const _maxLines = 400;

  Widget _row(_DLine l) {
    final desktop = !kMobile;
    final (Color bg, Color fg, String sign) = switch (l.kind) {
      _DKind.add => desktop
          ? (AppColors.surface3, AppColors.fg1, '+')
          : (AppColors.diffAddBg, AppColors.diffAddFg, '+'),
      _DKind.del => desktop
          ? (AppColors.bg, AppColors.fg3, '−')
          : (AppColors.diffDelBg, AppColors.diffDelFg, '-'),
      _DKind.ctx => (
          Colors.transparent,
          desktop ? AppColors.fg2 : AppColors.fg3,
          ' '
        ),
    };
    return Container(
      color: bg,
      padding: EdgeInsets.symmetric(horizontal: S.s6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 14, child: Text(sign, style: _code(fg))),
        Text(l.text.isEmpty ? ' ' : l.text, style: _code(fg)),
      ]),
    );
  }
}
