import 'dart:convert';

import 'coordination_tool_views.dart';
import 'tool_views.dart';

List<Map<String, dynamic>> normalizeChanges(dynamic args) {
  if (args is! Map) return const [];
  dynamic raw = args['changes'];
  if (raw is String) {
    try {
      raw = jsonDecode(raw);
    } catch (_) {
      raw = null;
    }
  }
  if (raw == null && args['path'] != null) raw = [args];
  if (raw is! List) return const [];
  final shared = args['path'];
  dynamic pick(Map m, List<String> keys) {
    for (final k in keys) {
      if (m[k] != null) return m[k];
    }
    return null;
  }

  const actions = {'create', 'replace', 'delete', 'move'};
  return [
    for (final c in raw.whereType<Map>())
      () {
        final find = pick(c, const ['find', 'old_string', 'old', 'search']);
        final to = pick(c, const ['to', 'new_path', 'destination']);
        final content = pick(c, const ['content', 'text']);
        final declared = (c['action'] ?? c['type'])?.toString();
        final action = actions.contains(declared)
            ? declared!
            : find != null
                ? 'replace'
                : to != null
                    ? 'move'
                    : content != null
                        ? 'create'
                        : declared ?? '';
        return <String, dynamic>{
          'path': (c['path'] ?? shared ?? '').toString(),
          'action': action,
          if (find != null) 'find': find.toString(),
          'with': (pick(c, const [
                    'with',
                    'new_string',
                    'new',
                    'replace',
                    'replacement'
                  ]) ??
                  '')
              .toString(),
          if (c['all'] != null) 'all': c['all'],
          if (content != null) 'content': content.toString(),
          if (c['overwrite'] != null) 'overwrite': c['overwrite'],
          if (to != null) 'to': to.toString(),
        };
      }(),
  ];
}

class ToolStep {
  const ToolStep({required this.tool, this.args, this.result});

  final String tool;
  final dynamic args;
  final dynamic result;

  bool get running => result == null;

  Map? get data {
    final r = result;
    if (r is! Map) return null;
    return r['data'] is Map ? r['data'] as Map : r;
  }

  int? get exitCode {
    final v = data?['exit_code'];
    return v is num ? v.toInt() : null;
  }

  bool get failed {
    final r = result;
    if (r is Map && (r['status'] ?? '').toString() == 'error') return true;
    final code = exitCode;
    return toolBaseName(tool) == 'bash' && code != null && code != 0;
  }

  List<Map> get changes => normalizeChanges(args);
}

String toolBaseName(String tool) => tool.startsWith('mcp__')
    ? tool.substring(tool.lastIndexOf('__') + 2)
    : tool;

String toolVerb(String tool, {required bool running}) {
  tool = toolBaseName(tool);
  final (done, doing) = switch (tool) {
    'change_files' => ('Changed', 'Changing'),
    'view_image' => ('Viewed', 'Viewing'),
    'bash' => ('Ran', 'Running'),
    'manage_process' => ('Managed', 'Managing'),
    'search_skills' => ('Looked up skills', 'Looking up skills'),
    'skill' => ('Used skill', 'Using skill'),
    'web_search' => ('Searched the web for', 'Searching the web for'),
    'web_read' => ('Read', 'Reading'),
    'read_file' => ('Read', 'Reading'),
    'view_file' => ('Read', 'Reading'),
    'monitor' => ('Watched', 'Watching'),
    'present_file' => ('Shared', 'Sharing'),
    'set_session_title' => ('Titled the chat', 'Titling the chat'),
    'ping_user' => ('Pinged you', 'Pinging you'),
    'update_brief' => ('Updated its brief', 'Updating its brief'),
    'schedule_wake' || 'schedule_followup' => (
        'Scheduled a wake-up',
        'Scheduling a wake-up'
      ),
    'search_content' => ('Searched', 'Searching'),
    _ => (
        'Used ${toolTitle(tool).toLowerCase()}',
        'Using ${toolTitle(tool).toLowerCase()}'
      ),
  };
  return running ? doing : done;
}

String _fileName(String path) => path.split('/').last;

/// A change_files step as (verb, object): what it did to which file, or how
/// many files a mixed batch touched.
(String, String) _changeParts(ToolStep step, bool running) {
  final changes = step.changes;
  if (changes.isEmpty) return (toolVerb(step.tool, running: running), '');
  final paths = {for (final c in changes) c['path']?.toString() ?? ''};
  final actions = {for (final c in changes) c['action']?.toString() ?? ''};
  final failed = !running && step.failed;
  if (paths.length > 1 || actions.length > 1) {
    final n = paths.length;
    return (
      running ? 'Changing' : (failed ? "Couldn't change" : 'Changed'),
      '$n ${n == 1 ? 'file' : 'files'}'
    );
  }
  final first = changes.first;
  final name = _fileName(first['path']?.toString() ?? '');
  final (done, doing, tried) = switch (actions.first) {
    'create' => ('Created', 'Creating', "Couldn't create"),
    'delete' => ('Deleted', 'Deleting', "Couldn't delete"),
    'move' => ('Moved', 'Moving', "Couldn't move"),
    _ => ('Edited', 'Editing', "Couldn't edit"),
  };
  final target =
      actions.first == 'move' ? '$name → ${first['to'] ?? ''}' : name;
  return (running ? doing : (failed ? tried : done), target);
}

String toolObject(ToolStep step) {
  final summary = toolArgSummary(step.tool, step.args);
  if (summary.isEmpty) return '';
  if (toolBaseName(step.tool) == 'view_image') return _fileName(summary);
  return summary;
}

(String, String) toolSentenceParts(ToolStep step, {bool? running}) {
  final isRunning = running ?? step.running;
  final name = toolBaseName(step.tool);
  if (name == 'change_files') return _changeParts(step, isRunning);
  // A labelled command already reads as a sentence ("Run the network tests"),
  // so it stands alone; "Ran" is only for a bare command line.
  final coordination = coordinationSentence(
      name, step.args is Map ? step.args as Map : null, step.data,
      running: isRunning);
  if (coordination != null) return coordination;
  if (name == 'monitor' && step.args is Map) {
    final a = step.args as Map;
    final subject = a['label']?.toString().trim() ?? '';
    if (subject.isNotEmpty) {
      switch (a['action']) {
        case 'add':
          return ('Watching', subject);
        case 'remove':
          return ('Stopped watching', subject);
        case 'fired':
          return (subject, 'updated');
      }
    }
  }
  final label = name == 'bash' && step.args is Map
      ? ((step.args as Map)['label']?.toString().trim() ?? '')
      : '';
  if (label.isNotEmpty) return (label, '');
  return (toolVerb(step.tool, running: isRunning), toolObject(step));
}

String toolSentence(ToolStep step, {bool? running}) {
  final (verb, object) = toolSentenceParts(step, running: running);
  return object.isEmpty ? verb : '$verb $object';
}

enum FileChangeKind { created, edited, deleted, moved }

class FileChange {
  FileChange(this.path, this.kind);

  final String path;
  FileChangeKind kind;
  int added = 0;
  int removed = 0;

  String get name => kind == FileChangeKind.moved ? path : _fileName(path);
}

int _lineCount(dynamic text) {
  final s = text?.toString() ?? '';
  return s.isEmpty ? 0 : '\n'.allMatches(s.trimRight()).length + 1;
}

/// Every file the successful change_files steps touched, with net line counts.
List<FileChange> fileChanges(Iterable<ToolStep> steps) {
  final byPath = <String, FileChange>{};
  for (final step in steps) {
    if (toolBaseName(step.tool) != 'change_files' || step.failed) continue;
    for (final c in step.changes) {
      final action = c['action']?.toString() ?? '';
      final path = action == 'move'
          ? '${c['path']} → ${c['to']}'
          : c['path']?.toString() ?? '';
      if (path.isEmpty) continue;
      final kind = switch (action) {
        'create' => FileChangeKind.created,
        'delete' => FileChangeKind.deleted,
        'move' => FileChangeKind.moved,
        _ => FileChangeKind.edited,
      };
      final change = byPath.putIfAbsent(path, () => FileChange(path, kind));
      if (kind == FileChangeKind.deleted) change.kind = kind;
      switch (action) {
        case 'replace':
          final (added, removed) = diffCounts(
              c['find']?.toString() ?? '', c['with']?.toString() ?? '');
          change.added += added;
          change.removed += removed;
        case 'create':
          change.added += _lineCount(c['content']);
      }
    }
  }
  return byPath.values.toList();
}

String _plural(int n, String one, String many) => n == 1 ? one : many;

String activitySummary(List<ToolStep> steps) {
  final w = describeWork(steps);
  if (w.outcome == null) return w.text;
  return '${w.text} ${w.outcome}';
}

String _otherPhrase(int n, {required bool hasOthers}) =>
    '$n ${hasOthers ? 'other ' : ''}${_plural(n, 'step', 'steps')}';

const _wrapperCommands = {
  'env',
  'cpu-slot',
  'nice',
  'nohup',
  'time',
  'command'
};
const _skipSegments = {'cd', 'export', 'set', 'true', ':'};
const _singleVerbCommands = {
  'awk',
  'basename',
  'cat',
  'cd',
  'chmod',
  'chown',
  'cp',
  'curl',
  'cut',
  'date',
  'diff',
  'dirname',
  'echo',
  'env',
  'find',
  'grep',
  'head',
  'jq',
  'kill',
  'less',
  'ln',
  'ls',
  'mkdir',
  'mv',
  'nl',
  'printf',
  'ps',
  'pwd',
  'readlink',
  'rg',
  'rm',
  'rmdir',
  'sed',
  'sleep',
  'sort',
  'stat',
  'tail',
  'tar',
  'tee',
  'touch',
  'tr',
  'uname',
  'uniq',
  'unzip',
  'wc',
  'wget',
  'which',
  'whoami',
  'xargs',
  'zip',
};

final _ansiEscape = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');
final _envAssign = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=');
final _subcommandWord = RegExp(r'^[A-Za-z][A-Za-z0-9_-]*$');

String _displayFileName(String path) {
  final trimmed = path.trim().replaceFirst(RegExp(r'/+$'), '');
  if (trimmed.isEmpty) return path.trim().isEmpty ? '' : '/';
  return trimmed.split('/').last;
}

List<String> _disambiguatedNames(List<String> paths) {
  final names = [for (final p in paths) _displayFileName(p)];
  final counts = <String, int>{};
  for (final n in names) {
    counts[n] = (counts[n] ?? 0) + 1;
  }
  return [
    for (var i = 0; i < paths.length; i++)
      if ((counts[names[i]] ?? 0) > 1) _lastTwoSegments(paths[i]) else names[i],
  ];
}

String _lastTwoSegments(String path) {
  final parts = path
      .trim()
      .replaceFirst(RegExp(r'/+$'), '')
      .split('/')
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.length <= 1) return parts.isEmpty ? '' : parts.single;
  return '${parts[parts.length - 2]}/${parts.last}';
}

String _joinNames(List<String> names, {int limit = 4}) {
  if (names.isEmpty) return '';
  if (names.length == 1) return names.single;
  if (names.length == 2) return '${names[0]} and ${names[1]}';
  if (names.length > limit) {
    final head = names.take(limit - 1).join(', ');
    return '$head and ${names.length - (limit - 1)} more';
  }
  return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}

String _clipQuery(String text, [int max = 28]) {
  final line = text.trim().split('\n').first.trim();
  if (line.length <= max) return line;
  return '${line.substring(0, max - 1)}…';
}

List<String> _splitShellSegments(String command) {
  final segments = <String>[];
  final buf = StringBuffer();
  String? quote;
  var escaped = false;
  for (var i = 0; i < command.length; i++) {
    final ch = command[i];
    if (escaped) {
      buf.write(ch);
      escaped = false;
      continue;
    }
    if (ch == r'\' && quote != "'") {
      buf.write(ch);
      escaped = true;
      continue;
    }
    if (quote != null) {
      if (ch == quote) quote = null;
      buf.write(ch);
      continue;
    }
    if (ch == "'" || ch == '"') {
      quote = ch;
      buf.write(ch);
      continue;
    }
    if (ch == ';' || ch == '\n') {
      segments.add(buf.toString());
      buf.clear();
      continue;
    }
    if ((ch == '&' || ch == '|') &&
        i + 1 < command.length &&
        command[i + 1] == ch) {
      segments.add(buf.toString());
      buf.clear();
      i++;
      continue;
    }
    buf.write(ch);
  }
  if (buf.isNotEmpty) segments.add(buf.toString());
  return segments;
}

List<String> _tokenizeCommandHead(String segment) {
  final tokens = <String>[];
  final buf = StringBuffer();
  String? quote;
  var escaped = false;
  var hasContent = false;
  void flush() {
    if (hasContent || buf.isNotEmpty) {
      tokens.add(buf.toString());
      buf.clear();
      hasContent = false;
    }
  }

  for (var i = 0; i < segment.length; i++) {
    final ch = segment[i];
    if (escaped) {
      buf.write(ch);
      escaped = false;
      hasContent = true;
      continue;
    }
    if (ch == r'\' && quote != "'") {
      escaped = true;
      hasContent = true;
      continue;
    }
    if (quote != null) {
      if (ch == quote) {
        quote = null;
      } else {
        buf.write(ch);
      }
      hasContent = true;
      continue;
    }
    if (ch == "'" || ch == '"') {
      quote = ch;
      hasContent = true;
      continue;
    }
    if (ch == '|' || ch == '>' || ch == '<') {
      flush();
      break;
    }
    if (ch == ' ' || ch == '\t' || ch == '\r') {
      flush();
      continue;
    }
    buf.write(ch);
    hasContent = true;
  }
  flush();
  return tokens;
}

List<String> _extractCommandNames(String rawCommand) {
  final segments = _splitShellSegments(rawCommand);
  final nonSetup = <String>[];
  final setupOnly = <String>[];
  for (final raw in segments) {
    final tokens = _tokenizeCommandHead(raw);
    var idx = 0;
    while (idx < tokens.length && _envAssign.hasMatch(tokens[idx])) {
      idx++;
    }
    while (idx < tokens.length) {
      final base = _displayFileName(tokens[idx]);
      if (!_wrapperCommands.contains(base) || idx + 1 >= tokens.length) break;
      idx++;
      while (idx < tokens.length && _envAssign.hasMatch(tokens[idx])) {
        idx++;
      }
    }
    if (idx >= tokens.length) continue;
    final cmd = _displayFileName(tokens[idx]);
    if (cmd.isEmpty || cmd.startsWith('#')) continue;
    final second = idx + 1 < tokens.length ? tokens[idx + 1] : '';
    final label = !_singleVerbCommands.contains(cmd) &&
            second.isNotEmpty &&
            _subcommandWord.hasMatch(second)
        ? '$cmd $second'
        : cmd;
    if (_skipSegments.contains(cmd)) {
      setupOnly.add(label);
    } else {
      nonSetup.add(label);
    }
  }
  return nonSetup.isNotEmpty ? nonSetup : setupOnly;
}

String? _formatPassedFailed(int passed, int failed) =>
    failed > 0 ? '$passed passed, $failed failed' : '$passed passed';

String? _commandResultExcerpt(ToolStep step) {
  if (step.running) return null;
  final d = step.data;
  final r = step.result;
  final errMsg = r is Map && r['error'] is Map
      ? (r['error'] as Map)['message']?.toString() ?? ''
      : '';
  final raw = [
    (d?['stdout'] ?? d?['output_so_far'] ?? d?['output'] ?? '').toString(),
    (d?['stderr'] ?? '').toString(),
    (d?['preview'] ?? '').toString(),
    errMsg,
  ].where((s) => s.trim().isNotEmpty).join('\n');
  if (raw.trim().isEmpty) return null;
  final text = raw.replaceAll(_ansiEscape, '');

  // Sum cargo test result lines so an empty doc-test block does not hide unit results.
  final cargoMatches = RegExp(
          r'test result:\s*(?:ok|FAILED)\.\s*(\d+)\s+passed;\s*(\d+)\s+failed\b')
      .allMatches(text)
      .toList();
  if (cargoMatches.isNotEmpty) {
    var passed = 0;
    var failed = 0;
    for (final m in cargoMatches) {
      passed += int.parse(m.group(1)!);
      failed += int.parse(m.group(2)!);
    }
    return _formatPassedFailed(passed, failed);
  }

  final passedFailed =
      RegExp(r'\b(\d+)\s+passed,\s*(\d+)\s+failed\b', caseSensitive: false)
          .allMatches(text)
          .toList();
  if (passedFailed.isNotEmpty) {
    final m = passedFailed.last;
    return _formatPassedFailed(int.parse(m.group(1)!), int.parse(m.group(2)!));
  }

  final failedPassed =
      RegExp(r'\b(\d+)\s+failed,\s*(\d+)\s+passed\b', caseSensitive: false)
          .allMatches(text)
          .toList();
  if (failedPassed.isNotEmpty) {
    final m = failedPassed.last;
    return _formatPassedFailed(int.parse(m.group(2)!), int.parse(m.group(1)!));
  }

  final flutterFail = RegExp(r'\+(\d+)\s+-(\d+):\s+Some tests failed')
      .allMatches(text)
      .toList();
  if (flutterFail.isNotEmpty) {
    final m = flutterFail.last;
    return _formatPassedFailed(int.parse(m.group(1)!), int.parse(m.group(2)!));
  }

  if (RegExp(r'All tests passed!').hasMatch(text)) {
    return 'All tests passed!';
  }

  final pytestMatch = RegExp(r'=+\s*(?:(\d+)\s+failed,\s*)?(\d+)\s+passed\b')
      .allMatches(text)
      .toList();
  if (pytestMatch.isNotEmpty) {
    final m = pytestMatch.last;
    return _formatPassedFailed(
        int.parse(m.group(2)!), int.parse(m.group(1) ?? '0'));
  }

  final jestMatch =
      RegExp(r'\bTests:\s+(?:(\d+)\s+failed,\s*)?(\d+)\s+passed\b')
          .allMatches(text)
          .toList();
  if (jestMatch.isNotEmpty) {
    final m = jestMatch.last;
    return _formatPassedFailed(
        int.parse(m.group(2)!), int.parse(m.group(1) ?? '0'));
  }

  if (RegExp(r'\bNo issues found!?').hasMatch(text)) {
    return 'No issues found!';
  }

  final issuesMatch =
      RegExp(r'\b(\d+\s+issues?\s+found)\b').allMatches(text).toList();
  if (issuesMatch.isNotEmpty) {
    return issuesMatch.last.group(1)!;
  }

  final rustError = RegExp(r'error\[[A-Z]\d+\]').firstMatch(text);
  if (rustError != null) return rustError.group(0)!;

  if (RegExp(r'FAILURE:\s+Build failed').hasMatch(text) ||
      RegExp(r'^error:\s+could not compile\b', multiLine: true)
          .hasMatch(text)) {
    return 'Build failed';
  }

  final builtMatch =
      RegExp(r'(?:✓\s*)?Built\s+([^\s(]+)').allMatches(text).toList();
  if (builtMatch.isNotEmpty) {
    return 'Built ${_displayFileName(builtMatch.last.group(1)!)}';
  }

  final finishedMatch = RegExp(
          r'^\s*Finished\s+`?([A-Za-z0-9_-]+)`?\s+profile\b',
          multiLine: true)
      .allMatches(text)
      .toList();
  if (finishedMatch.isNotEmpty) {
    return 'Finished ${finishedMatch.last.group(1)!} profile';
  }

  if (RegExp(r'\bNo tests ran\b').hasMatch(text)) {
    return 'No tests ran';
  }

  return null;
}

/// A deterministic, work-centric summary of a consecutive group of tool calls.
String workSummary(List<ToolStep> steps) {
  if (steps.isEmpty) return '';

  final readPaths = <String>{};
  var readUnnamed = 0;
  final editedPaths = <String>{};
  final createdPaths = <String>{};
  final deletedPaths = <String>{};
  final movedLabels = <String>{};
  var failedChangeSteps = 0;

  final commands = <String>{};
  var bashCount = 0;
  ToolStep? lastBash;

  var searchCount = 0;
  final searchQueries = <String>[];
  var pageCount = 0;
  var otherCount = 0;

  for (final step in steps) {
    final name = toolBaseName(step.tool);
    final args = step.args is Map ? step.args as Map : null;
    switch (name) {
      case 'read_file':
      case 'view_image':
        final p = (args?['path'] ?? '').toString().trim();
        if (p.isEmpty) {
          readUnnamed++;
        } else {
          readPaths.add(p.replaceFirst(RegExp(r'/+$'), ''));
        }
      case 'view_file':
        final p =
            (args?['AbsolutePath'] ?? args?['path'] ?? '').toString().trim();
        if (p.isEmpty) {
          readUnnamed++;
        } else {
          readPaths.add(p.replaceFirst(RegExp(r'/+$'), ''));
        }
      case 'change_files':
        if (step.failed) {
          failedChangeSteps++;
          break;
        }
        final changes = fileChanges([step]);
        if (changes.isEmpty) {
          otherCount++;
          break;
        }
        for (final c in changes) {
          switch (c.kind) {
            case FileChangeKind.created:
              editedPaths.remove(c.path);
              createdPaths.add(c.path);
            case FileChangeKind.edited:
              if (!createdPaths.contains(c.path)) {
                editedPaths.add(c.path);
              }
            case FileChangeKind.deleted:
              createdPaths.remove(c.path);
              editedPaths.remove(c.path);
              deletedPaths.add(c.path);
            case FileChangeKind.moved:
              final parts = c.path.split(' → ');
              final label = parts.length == 2
                  ? '${_displayFileName(parts[0])} → ${_displayFileName(parts[1])}'
                  : c.name;
              movedLabels.add(label);
          }
        }
      case 'write_file':
        if (step.failed) {
          failedChangeSteps++;
          break;
        }
        final p = (args?['path'] ?? '').toString().trim();
        if (p.isNotEmpty) createdPaths.add(p);
      case 'edit_file':
        if (step.failed) {
          failedChangeSteps++;
          break;
        }
        final p = (args?['path'] ?? '').toString().trim();
        if (p.isNotEmpty && !createdPaths.contains(p)) editedPaths.add(p);
      case 'bash':
        bashCount++;
        lastBash = step;
        final cmd = (args?['command'] ?? '').toString().trim();
        if (cmd.isNotEmpty) {
          commands.addAll(_extractCommandNames(cmd));
        } else {
          final label = (args?['label'] ?? '').toString().trim();
          if (label.isNotEmpty) {
            commands.add(_clipQuery(label, 28));
          }
        }
      case 'search_content':
      case 'web_search':
      case 'search_skills':
        searchCount++;
        final q = (args?['query'] ?? args?['pattern'] ?? '').toString().trim();
        if (q.isNotEmpty) searchQueries.add(q);
      case 'web_read':
        pageCount++;
      default:
        otherCount++;
    }
  }

  final workParts = <String>[];
  final totalRead = readPaths.length + readUnnamed;
  if (totalRead > 0) {
    if (totalRead <= 2 && readUnnamed == 0) {
      final names = _disambiguatedNames(readPaths.toList());
      workParts.add('read ${_joinNames(names)}');
    } else {
      workParts.add('read $totalRead ${_plural(totalRead, 'file', 'files')}');
    }
  }

  if (editedPaths.isNotEmpty) {
    workParts
        .add('edited ${_joinNames(_disambiguatedNames(editedPaths.toList()))}');
  }
  if (createdPaths.isNotEmpty) {
    workParts.add(
        'created ${_joinNames(_disambiguatedNames(createdPaths.toList()))}');
  }
  if (deletedPaths.isNotEmpty) {
    workParts.add(
        'deleted ${_joinNames(_disambiguatedNames(deletedPaths.toList()))}');
  }
  if (movedLabels.isNotEmpty) {
    workParts.add('moved ${_joinNames(movedLabels.toList())}');
  }

  if (searchCount == 1 && searchQueries.length == 1) {
    workParts.add('searched for ${_clipQuery(searchQueries.single)}');
  } else if (searchCount > 0) {
    workParts
        .add('searched $searchCount ${_plural(searchCount, 'time', 'times')}');
  }

  if (pageCount > 0) {
    workParts.add('read $pageCount ${_plural(pageCount, 'page', 'pages')}');
  }

  String? ranPhrase;
  if (commands.isNotEmpty) {
    final list = commands.toList();
    if (list.length > 4) {
      ranPhrase = 'ran ${list.take(4).join(', ')} and ${list.length - 4} more';
    } else {
      ranPhrase = 'ran ${list.join(', ')}';
    }
  } else if (bashCount > 0) {
    ranPhrase = 'ran $bashCount ${_plural(bashCount, 'command', 'commands')}';
  }

  final hasPrior = workParts.isNotEmpty || ranPhrase != null;
  final otherPhrase =
      otherCount > 0 ? _otherPhrase(otherCount, hasOthers: hasPrior) : null;
  final excerpt = lastBash != null ? _commandResultExcerpt(lastBash) : null;

  final sections = <String>[
    if (workParts.isNotEmpty) workParts.join(', '),
    if (ranPhrase != null) ranPhrase,
    if (otherPhrase != null) otherPhrase,
    if (excerpt != null) excerpt,
  ];
  if (sections.isEmpty && failedChangeSteps > 0) {
    sections.add(
        'attempted $failedChangeSteps ${_plural(failedChangeSteps, 'edit', 'edits')}');
  }
  final sentence = sections.join(' · ');
  if (sentence.isEmpty) return '';
  return '${sentence[0].toUpperCase()}${sentence.substring(1)}';
}

// ---------------------------------------------------------------------------
// The work line: what a run of tool calls did, in the agent's terms. Built
// from tool arguments and results; shell syntax never reaches the sentence.
// ---------------------------------------------------------------------------

enum CommandKind { test, build, check, search, read, script, other }

class CommandInfo {
  const CommandInfo(this.label, this.kind);

  /// First program plus its subcommand ("flutter test"), or "a script".
  final String label;
  final CommandKind kind;

  bool get verifies =>
      kind == CommandKind.test ||
      kind == CommandKind.build ||
      kind == CommandKind.check;
}

const _interpreters = {
  'python',
  'python3',
  'node',
  'ruby',
  'perl',
  'bash',
  'sh',
  'zsh',
  'fish',
  'deno',
  'bun',
};
const _shellWords = {
  'if',
  'then',
  'else',
  'elif',
  'fi',
  'for',
  'while',
  'until',
  'do',
  'done',
  'case',
  'esac',
  'function',
  'assert',
  'import',
  'from',
  'print',
  'def',
  'return',
  'EOF',
  'exit',
  'trap',
  'unset',
  'alias',
  'source',
  'eval',
  'read',
  'wait',
};
const _searchPrograms = {'rg', 'grep', 'find', 'ls', 'tree', 'fd', 'ag'};
const _readPrograms = {'cat', 'sed', 'head', 'tail', 'nl', 'less', 'wc', 'bat'};
final _programWord = RegExp(r'^[A-Za-z0-9_.~/+-]+$');

/// The command a bash call is really running: the first program and its
/// subcommand. Heredoc bodies, `cd`, `export` and inline scripts never count.
CommandInfo? analyzeCommand(String raw) {
  var text = raw.replaceAll(_ansiEscape, '');
  final here = text.indexOf('<<');
  if (here >= 0) text = text.substring(0, here);
  for (final segment in _splitShellSegments(text)) {
    final tokens = _tokenizeCommandHead(segment);
    var idx = 0;
    while (idx < tokens.length && _envAssign.hasMatch(tokens[idx])) {
      idx++;
    }
    while (idx + 1 < tokens.length &&
        _wrapperCommands.contains(_displayFileName(tokens[idx]))) {
      idx++;
      while (idx < tokens.length && _envAssign.hasMatch(tokens[idx])) {
        idx++;
      }
    }
    if (idx >= tokens.length) continue;
    final program = _displayFileName(tokens[idx]);
    if (program.isEmpty ||
        _skipSegments.contains(program) ||
        _shellWords.contains(program) ||
        !_programWord.hasMatch(tokens[idx])) {
      continue;
    }
    final rest = tokens.sublist(idx + 1);
    if (_interpreters.contains(program)) {
      if (rest.length >= 2 &&
          rest[0] == '-m' &&
          _subcommandWord.hasMatch(rest[1])) {
        return _classify(rest[1], rest.length > 2 ? rest[2] : '');
      }
      final script = rest.firstWhere(
          (t) => RegExp(r'\.(py|js|mjs|ts|rb|pl|sh)$').hasMatch(t),
          orElse: () => '');
      return CommandInfo(script.isEmpty ? 'a script' : _displayFileName(script),
          CommandKind.script);
    }
    return _classify(program, rest.isEmpty ? '' : rest.first,
        third: rest.length > 1 ? rest[1] : '');
  }
  return null;
}

CommandInfo _classify(String program, String second, {String third = ''}) {
  final single = _singleVerbCommands.contains(program);
  var label = program;
  if (!single && second.isNotEmpty && _subcommandWord.hasMatch(second)) {
    label = '$program $second';
    if ((second == 'run' || second == 'exec') &&
        third.isNotEmpty &&
        _subcommandWord.hasMatch(third)) {
      label = '$program $third';
    }
  }
  final last = label.split(' ').last;
  final kind = _searchPrograms.contains(program)
      ? CommandKind.search
      : _readPrograms.contains(program)
          ? CommandKind.read
          : const {'test', 'tests', 'pytest', 'jest', 'vitest', 'rspec'}
                  .contains(last)
              ? CommandKind.test
              : const {
                  'build',
                  'compile',
                  'bundle',
                  'make',
                  'gradle',
                  'assemble'
                }.contains(last)
                  ? CommandKind.build
                  : const {
                      'analyze',
                      'lint',
                      'check',
                      'fmt',
                      'format',
                      'clippy',
                      'tsc'
                    }.contains(last)
                      ? CommandKind.check
                      : CommandKind.other;
  return CommandInfo(label, kind);
}

CommandInfo? stepCommand(ToolStep step) {
  if (toolBaseName(step.tool) != 'bash') return null;
  final a = step.args is Map ? step.args as Map : const {};
  return analyzeCommand((a['command'] ?? '').toString());
}

String _listNames(Iterable<String> names) {
  final list = names.toList();
  if (list.length == 1) return list.single;
  return '${list.sublist(0, list.length - 1).join(', ')} and ${list.last}';
}

class WorkSummary {
  const WorkSummary(this.text,
      {this.emphasis = const [], this.outcome, this.failed = false});

  /// "Edited phone_hero.dart, ran 3 tests".
  final String text;

  /// File names inside [text] drawn a step brighter.
  final List<String> emphasis;

  /// "passed" or "failed" when the results make it clear.
  final String? outcome;
  final bool failed;
}

/// Total time the steps report for themselves, or null when none do.
Duration? stepsDuration(Iterable<ToolStep> steps) {
  var ms = 0.0;
  var known = false;
  for (final s in steps) {
    final d = s.data;
    final v = d?['duration_ms'];
    final secs = d?['duration_secs'] ?? d?['elapsed_secs'];
    if (v is num) {
      ms += v;
      known = true;
    } else if (secs is num) {
      ms += secs * 1000;
      known = true;
    }
  }
  return known && ms >= 1000 ? Duration(milliseconds: ms.round()) : null;
}

String formatWorkDuration(Duration d) {
  final s = d.inMilliseconds / 1000;
  if (s < 10) return '${s.toStringAsFixed(1)}s';
  if (s < 60) return '${s.round()}s';
  final m = d.inMinutes;
  final rest = (s - m * 60).round();
  return rest == 0 ? '${m}m' : '${m}m ${rest}s';
}

final _failureMarker = RegExp(
    r'Some tests failed|test result: FAILED|error: test failed|Tests? failed\b|^FAIL(?:ED)?\b|\b[1-9]\d*\s+(?:failed|failing|errors?)\b',
    multiLine: true);

/// Whether a finished test or check step's output reports failures. A piped
/// or wrapped command (`| tail`, `cpu-slot`) exits 0 even when tests fail.
bool verifyOutputFailed(ToolStep step) {
  if (step.running) return false;
  final cmd = stepCommand(step);
  if (cmd == null || !cmd.verifies) return false;
  final excerpt = _commandResultExcerpt(step) ?? '';
  if (RegExp(r'\b[1-9]\d*\s+failed\b').hasMatch(excerpt)) return true;
  final raw = [
    for (final k in const [
      'stdout',
      'output',
      'output_so_far',
      'stderr',
      'preview'
    ])
      (step.data?[k] ?? '').toString(),
  ].join('\n').replaceAll(_ansiEscape, '');
  // Flutter's "+2 -3:" counter survives a grep that drops the summary line.
  if (RegExp(r'\+\d+(?:\s+~\d+)?\s+-[1-9]\d*:').hasMatch(raw)) return true;
  return _failureMarker.hasMatch(raw);
}

bool _stepFailed(ToolStep s) => s.failed || verifyOutputFailed(s);

/// What a run of steps did, as one sentence plus an outcome word.
WorkSummary describeWork(List<ToolStep> steps) {
  if (steps.isEmpty) return const WorkSummary('');
  final done = steps.where((s) => !s.running).toList();
  final failures = done.where(_stepFailed).length;
  var outcome =
      failures == 0 ? null : (failures == 1 ? 'failed' : '$failures failed');
  final emphasis = <String>[];

  String text;
  if (steps.length == 1) {
    final s = steps.single;
    final cmd = stepCommand(s);
    final label =
        s.args is Map ? ((s.args as Map)['label'] ?? '').toString().trim() : '';
    if (toolBaseName(s.tool) == 'bash' && label.isEmpty && cmd != null) {
      text = s.running ? 'Running ${cmd.label}' : 'Ran ${cmd.label}';
    } else if (toolBaseName(s.tool) == 'bash' && label.isEmpty) {
      text = s.running ? 'Running a command' : 'Ran a command';
    } else {
      final (verb, object) = toolSentenceParts(s);
      final shown = switch (toolBaseName(s.tool)) {
        'read_file' ||
        'view_file' ||
        'view_image' =>
          object.isEmpty ? '' : _displayFileName(object),
        _ => object,
      };
      if (const {'read_file', 'view_file', 'view_image'}
              .contains(toolBaseName(s.tool)) &&
          shown.isNotEmpty) {
        emphasis.add(shown);
      }
      text = shown.isEmpty ? verb : '$verb $shown';
    }
    if (cmd != null && cmd.verifies && !s.running && failures == 0) {
      outcome = 'passed';
    }
    return WorkSummary(text,
        emphasis: emphasis, outcome: outcome, failed: failures > 0);
  }

  final readPaths = <String>{};
  var readUnnamed = 0, images = 0, searches = 0, pages = 0, other = 0;
  var scripts = 0, verified = 0;
  final testLabels = <String>[];
  final commands = <String>[];
  for (final s in steps) {
    final name = toolBaseName(s.tool);
    final args = s.args is Map ? s.args as Map : const {};
    switch (name) {
      case 'read_file':
      case 'view_file':
        final p =
            (args['path'] ?? args['AbsolutePath'] ?? '').toString().trim();
        p.isEmpty ? readUnnamed++ : readPaths.add(p);
      case 'view_image':
        images++;
      case 'change_files':
        break;
      case 'search_content':
      case 'web_search':
      case 'search_skills':
        searches++;
      case 'web_read':
        pages++;
      case 'bash':
        final c = stepCommand(s);
        if (c == null) {
          other++;
        } else if (c.kind == CommandKind.search) {
          searches++;
        } else if (c.kind == CommandKind.read) {
          readUnnamed++;
        } else if (c.kind == CommandKind.script) {
          scripts++;
        } else {
          if (c.verifies && !s.running) verified++;
          if (c.kind == CommandKind.test) {
            testLabels.add(c.label);
          } else if (!commands.contains(c.label)) {
            commands.add(c.label);
          }
        }
      default:
        other++;
    }
  }
  final parts = <String>[];
  final totalRead = readPaths.length + readUnnamed;
  if (totalRead > 0) {
    if (totalRead <= 2 && readUnnamed == 0) {
      final names = [for (final p in readPaths) _displayFileName(p)];
      emphasis.addAll(names);
      parts.add('read ${_listNames(names)}');
    } else {
      parts.add('read $totalRead ${_plural(totalRead, 'file', 'files')}');
    }
  }
  final changes = fileChanges(steps);
  for (final (kind, verb) in const [
    (FileChangeKind.edited, 'edited'),
    (FileChangeKind.created, 'created'),
    (FileChangeKind.deleted, 'deleted'),
    (FileChangeKind.moved, 'moved'),
  ]) {
    final of = changes.where((c) => c.kind == kind).toList();
    if (of.isEmpty) continue;
    if (of.length <= 2) {
      final names = [for (final c in of) c.name];
      emphasis.addAll(names);
      parts.add('$verb ${_listNames(names)}');
    } else {
      parts.add('$verb ${of.length} files');
    }
  }
  final failedChanges = steps
      .where((s) => toolBaseName(s.tool) == 'change_files' && s.failed)
      .length;
  if (changes.isEmpty && failedChanges > 0) {
    parts
        .add('tried $failedChanges ${_plural(failedChanges, 'edit', 'edits')}');
  }
  if (images > 0) {
    parts.add('viewed $images ${_plural(images, 'image', 'images')}');
  }
  if (searches > 0) {
    parts.add('searched $searches ${_plural(searches, 'time', 'times')}');
  }
  if (pages > 0) {
    parts.add('read $pages ${_plural(pages, 'page', 'pages')}');
  }
  if (testLabels.isNotEmpty) {
    parts.add(testLabels.length == 1
        ? 'ran ${testLabels.single}'
        : 'ran ${testLabels.length} tests');
  }
  if (commands.isNotEmpty) {
    parts.add(commands.length <= 2
        ? 'ran ${commands.join(' and ')}'
        : 'ran ${commands.length} commands');
  }
  if (scripts > 0) {
    parts.add(scripts == 1 ? 'ran a script' : 'ran $scripts scripts');
  }
  if (other > 0) {
    parts.add(
        '$other ${parts.isEmpty ? '' : 'other '}${_plural(other, 'step', 'steps')}');
  }
  if (outcome == null && verified > 0 && done.length == steps.length) {
    outcome = 'passed';
  }
  text = parts.join(', ');
  if (text.isEmpty) text = 'Activity';
  text = '${text[0].toUpperCase()}${text.substring(1)}';
  return WorkSummary(text,
      emphasis: emphasis, outcome: outcome, failed: failures > 0);
}

/// The line shown while a step is still running: what is happening now.
String liveStepText(ToolStep step) {
  final label = step.args is Map
      ? ((step.args as Map)['label'] ?? '').toString().trim()
      : '';
  final cmd = stepCommand(step);
  if (label.isEmpty && cmd != null) return 'Running ${cmd.label}';
  final (verb, object) = toolSentenceParts(step, running: true);
  final name = toolBaseName(step.tool);
  final shown = const {'read_file', 'view_file', 'view_image'}.contains(name) &&
          object.isNotEmpty
      ? _displayFileName(object)
      : object;
  return shown.isEmpty ? verb : '$verb $shown';
}

/// The file or command a step touched, for the expanded step list.
String stepTarget(ToolStep step) {
  final name = toolBaseName(step.tool);
  final a = step.args is Map ? step.args as Map : const {};
  String tail(String p) {
    final parts = p.split('/').where((e) => e.isNotEmpty).toList();
    return parts.length <= 3
        ? p
        : '…/${parts.sublist(parts.length - 3).join('/')}';
  }

  switch (name) {
    case 'read_file':
    case 'view_image':
    case 'present_file':
      return tail((a['path'] ?? '').toString());
    case 'view_file':
      return tail((a['AbsolutePath'] ?? a['path'] ?? '').toString());
    case 'change_files':
      final changes = step.changes;
      final paths = {for (final c in changes) c['path']?.toString() ?? ''}
        ..remove('');
      if (paths.isEmpty) return '';
      if (paths.length == 1) return tail(paths.single);
      return '${paths.length} files';
    case 'bash':
      final c = analyzeCommand((a['command'] ?? '').toString());
      final cmd = (a['command'] ?? '').toString();
      if (c != null && c.kind != CommandKind.script) {
        final first = cmd.split('<<').first.trim().split('\n').firstWhere(
            (l) =>
                l.trim().isNotEmpty &&
                !RegExp(r'^\s*(cd|export)\b').hasMatch(l),
            orElse: () => '');
        final cleaned = first
            .replaceFirst(RegExp(r'^\s*(cd\s+\S+\s*&&\s*)'), '')
            .replaceAll(RegExp(r'\b[A-Z_]+=\S+\s+'), '')
            .replaceFirst(RegExp(r'^\s*cpu-slot\s+'), '')
            .trim();
        if (cleaned.isNotEmpty) return cleaned;
        return c.label;
      }
      final label = (a['label'] ?? '').toString().trim();
      return label.isNotEmpty ? label : (c?.label ?? 'script');
    default:
      return toolObject(step);
  }
}

enum StepChipTone { neutral, ok, danger }

class StepResultChip {
  const StepResultChip(this.text, this.tone,
      {this.added = 0, this.removed = 0});
  final String text;
  final StepChipTone tone;
  final int added;
  final int removed;
}

final _passedCount = RegExp(r'(\d+)\s+passed');
final _failedCount = RegExp(r'(\d+)\s+failed');

/// A small result for a step: a line range, +N -M, "2 passed", "failed".
StepResultChip? stepChip(ToolStep step) {
  if (step.running) return null;
  final name = toolBaseName(step.tool);
  final a = step.args is Map ? step.args as Map : const {};
  if (step.failed) {
    // A failure count says more than the exit code.
    final counted = name == 'bash' ? _verifyChip(step) : null;
    if (counted != null && counted.tone == StepChipTone.danger) return counted;
    final code = step.exitCode;
    return StepResultChip(
        name == 'bash' && code != null && code != 0
            ? 'failed · exit $code'
            : 'failed',
        StepChipTone.danger);
  }
  switch (name) {
    case 'view_image':
      return const StepResultChip('image', StepChipTone.neutral);
    case 'change_files':
      final c = fileChanges([step]);
      final added = c.fold<int>(0, (n, e) => n + e.added);
      final removed = c.fold<int>(0, (n, e) => n + e.removed);
      if (added == 0 && removed == 0) return null;
      return StepResultChip('+$added −$removed', StepChipTone.neutral,
          added: added, removed: removed);
    case 'read_file':
    case 'view_file':
      final off = a['offset'] ?? a['start_line'] ?? a['StartLine'];
      final lim = a['limit'] ?? a['end_line'] ?? a['EndLine'];
      if (off is num && lim is num) {
        final end = a.containsKey('limit') ? off + lim : lim;
        return StepResultChip(
            '${off.toInt()}-${end.toInt()}', StepChipTone.neutral);
      }
      final total = step.data?['total_lines'];
      return total is num
          ? StepResultChip('${total.toInt()} lines', StepChipTone.neutral)
          : null;
    case 'bash':
      return _verifyChip(step);
  }
  return null;
}

StepResultChip? _verifyChip(ToolStep step) {
  final cmd = stepCommand(step);
  if (cmd == null || !cmd.verifies) return null;
  final raw = [
    for (final k in const ['stdout', 'output', 'stderr'])
      (step.data?[k] ?? '').toString(),
    _commandResultExcerpt(step) ?? '',
  ].join('\n').replaceAll(_ansiEscape, '');
  // flutter and dart print "+7 -1:"; pytest and cargo print "7 passed".
  final flutter =
      RegExp(r'\+(\d+)(?:\s+~\d+)?(?:\s+-(\d+))?:').allMatches(raw).lastOrNull;
  // The excerpt sums every cargo block, so a later failure is not hidden.
  final excerpt = _commandResultExcerpt(step) ?? '';
  final p = _passedCount.firstMatch(excerpt)?.group(1) ??
      flutter?.group(1) ??
      _passedCount.firstMatch(raw)?.group(1);
  final f = _failedCount.firstMatch(excerpt)?.group(1) ??
      flutter?.group(2) ??
      _failedCount
          .allMatches(raw)
          .map((m) => m.group(1))
          .lastWhere((n) => n != '0', orElse: () => null);
  if (f != null && f != '0') {
    return StepResultChip(
        p == null ? '$f failed' : '$p passed, $f failed', StepChipTone.danger);
  }
  if (verifyOutputFailed(step)) {
    return const StepResultChip('failed', StepChipTone.danger);
  }
  return StepResultChip(
      p != null
          ? '$p passed'
          : (cmd.kind == CommandKind.test ? 'passed' : 'ok'),
      StepChipTone.ok);
}
