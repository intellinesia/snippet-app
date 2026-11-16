import 'package:flutter/material.dart';

import '../api.dart';
import '../mochi.dart';
import '../models.dart';
import '../motion.dart';
import '../motion_routes.dart';
import '../platform.dart';
import '../pull_refresh.dart';
import '../settings_form.dart';
import '../shell_panel.dart';
import '../theme.dart';
import '../desktop_layout.dart';
import '../widgets.dart';
import 'memory_entries.dart';
import 'shell_nav.dart';

/// What agents remember: one git repo per scope (you, each project, each
/// agent, each session). Read-only here; agents write it and consolidation keeps
/// it tidy on its own.
class MemoryScreen extends StatefulWidget {
  final DaemonClient client;
  final bool embedded;
  final VoidCallback? onBack;

  /// For a host that already names the page, like the agent panel's segments.
  final bool hideBack;

  /// Open straight into one scope (`agent:<id>`, `session:<id>`, …).
  final String? initialKey;

  const MemoryScreen({
    super.key,
    required this.client,
    this.embedded = false,
    this.onBack,
    this.hideBack = false,
    this.initialKey,
  });

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  List<MemoryScope>? _scopes;
  String? _error;
  String? _open;
  bool _allSessions = false;
  DateTime? _shownAt;

  @override
  void initState() {
    super.initState();
    _scopes = widget.client.cachedMemoryScopes();
    _open = widget.initialKey;
    _load();
  }

  Future<void> _load() async {
    try {
      final scopes = await widget.client.memoryScopes();
      if (mounted) {
        setState(() {
          _scopes = scopes;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// Phones push the scope as its own screen so the system back button
  /// returns to this list instead of leaving Memory altogether.
  void _openScopeKey(String key) {
    if (!kMobile) {
      setState(() => _open = key);
      return;
    }
    final scope = _scopes?.where((s) => s.key == key).firstOrNull;
    Navigator.of(context)
        .push(AppPageRoute<void>(
          builder: (ctx) => Scaffold(
            backgroundColor: AppColors.paneBg,
            body: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (kMobile)
                    SettingsHeader(
                      title: scopeTitle(scope, key),
                      compact: true,
                      onBack: () => Navigator.of(ctx).maybePop(),
                    )
                  else
                    NavBackRow(
                        title: scopeTitle(scope, key),
                        onBack: () => Navigator.of(ctx).maybePop()),
                  Expanded(
                    child: _ScopeView(
                        client: widget.client, scopeKey: key, scope: scope),
                  ),
                ],
              ),
            ),
          ),
        ))
        .then((_) => _load());
  }

  MemoryScope? get _openScope =>
      _scopes?.where((s) => s.key == _open).firstOrNull;

  void _close() {
    if (_open != null && widget.initialKey == null) {
      setState(() => _open = null);
      _load();
    } else {
      (widget.onBack ?? () => Navigator.pop(context))();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kMobile &&
        widget.embedded &&
        widget.initialKey == null &&
        widget.onBack == null) {
      return _deskDialog();
    }
    final open = _open;
    final scope = _openScope;
    final title = open == null ? 'Memory' : scopeTitle(scope, open);
    final body = Swap(
      stateKey: open ?? 'list',
      fill: true,
      child: open == null
          ? _list()
          : _ScopeView(
              key: ValueKey(open),
              client: widget.client,
              scopeKey: open,
              scope: scope,
            ),
    );
    final back = !widget.hideBack &&
        (open != null || widget.onBack != null || !widget.embedded);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (back)
          if (kMobile)
            SettingsHeader(title: title, compact: true, onBack: _close)
          else
            NavBackRow(title: title, onBack: _close)
        else if (!widget.embedded)
          const SizedBox.shrink(),
        Expanded(child: body),
      ],
    );
    final scoped = kMobile ? CardGroupScope(child: content) : content;
    if (widget.embedded) {
      // Inside a shell pane the pane's own tint shows through, like Files.
      final page = kMobile ||
          (widget.initialKey != null && ShellPanelScope.maybeOf(context) == null);
      return Material(
        color: page ? AppColors.paneBg : Colors.transparent,
        child: page ? SafeArea(bottom: false, child: scoped) : scoped,
      );
    }
    return Scaffold(body: SafeArea(bottom: false, child: scoped));
  }

  Widget _list() {
    final scopes = _scopes;
    if (scopes == null) {
      return Center(
        child: _error == null
            ? const Spinner(size: 20)
            : Padding(
                padding: EdgeInsets.all(S.s24),
                child: Text(_error!,
                    textAlign: TextAlign.center, style: TS.meta()),
              ),
      );
    }
    _shownAt ??= DateTime.now();
    final global = scopes.where((s) => s.kind == 'global').toList();
    final projects = scopes.where((s) => s.kind == 'project').toList()
      ..sort((a, b) => (b.lastCommitAt ?? 0).compareTo(a.lastCommitAt ?? 0));
    final agents = scopes.where((s) => s.kind == 'agent').toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    final sessions = scopes.where((s) => s.kind == 'session').toList()
      ..sort((a, b) => (b.lastCommitAt ?? 0).compareTo(a.lastCommitAt ?? 0));
    final shownSessions = _allSessions ? sessions : sessions.take(5).toList();
    var index = 0;
    Widget group(String label, List<MemoryScope> items, {Widget? footer}) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Appear(
        index: index++,
        since: _shownAt,
        child: Padding(
          padding: EdgeInsets.only(bottom: kMobile ? 0 : S.of(18)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (label.isNotEmpty)
                kMobile ? SettingsGroupLabel(label) : SectionHeader(label),
              ListGroup(children: [
                for (final s in items)
                  if (kMobile)
                    V5SettingsRow(
                      label: scopeTitle(s, s.key),
                      subtitle: scopeStatus(s),
                      leading: scopeLeading(s, v5: true),
                      onTap: () => _openScopeKey(s.key),
                    )
                  else
                    ListRow(
                      title: scopeTitle(s, s.key),
                      subtitle: scopeStatus(s),
                      leading: scopeLeading(s),
                      trailing: AppIcon('chevron-right',
                          size: 15, color: AppColors.fg4),
                      onTap: () => _openScopeKey(s.key),
                    ),
                if (footer != null) footer,
              ]),
            ],
          ),
        ),
      );
    }

    return PullToRefresh(
      onRefresh: _load,
      child: PageBody(
        children: [
          Padding(
              padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s16),
              child: Text(
                  'What your agents remember, kept as files in git. Agents write it as they work, and it is consolidated in the background.',
                  style: sans(13, height: 19 / 13, color: AppColors.fg3)),
            ),
          group('', global),
          group('Projects', projects),
          group('Agents', agents),
          group(
            'Sessions',
            shownSessions,
            footer: sessions.length > 5 && !_allSessions
                ? ListRow(
                    title: 'Show all ${sessions.length} sessions',
                    titleWidget: Text('Show all ${sessions.length} sessions',
                        style: sans(14, color: AppColors.accent)),
                    onTap: () => setState(() => _allSessions = true),
                  )
                : null,
          ),
          if (scopes.isEmpty)
            const EmptyState(
              icon: 'brain',
              title: 'Nothing remembered yet',
              body: 'Memory fills in as agents work.',
            ),
        ],
      ),
    );
  }

  Widget _deskDialog() {
    final open = _open;
    if (open != null) {
      final scope = _openScope;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(S.s32, S.s24, S.s32, 0),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: SettingsHeader(
                  back: SettingsBack('Memory', onTap: _close),
                  title: scopeTitle(scope, open),
                  subtitle: scope == null ? null : scopeStatus(scope),
                ),
              ),
            ),
          ),
          Expanded(
            child: _ScopeView(
              key: ValueKey(open),
              client: widget.client,
              scopeKey: open,
              scope: scope,
              hideSubtitle: true,
            ),
          ),
        ],
      );
    }
    final scopes = _scopes;
    if (scopes == null) {
      return SettingsColumn(children: [
        const SettingsHeader(
          title: 'Memory',
          subtitle:
              'What your agents remember, kept as files in git and consolidated in the background.',
        ),
        SizedBox(height: S.s8),
        SettingsGroup(children: [
          _error == null
              ? const SettingsRow(label: 'Loading memory…')
              : SettingsRow(
                  label: "Couldn't load memory",
                  sub: _error,
                  danger: true,
                  trailing: Btn('Retry',
                      small: true, variant: BtnVariant.secondary, onTap: _load),
                ),
        ]),
      ]);
    }
    final global = scopes.where((s) => s.kind == 'global').toList();
    final projects = scopes.where((s) => s.kind == 'project').toList()
      ..sort((a, b) => (b.lastCommitAt ?? 0).compareTo(a.lastCommitAt ?? 0));
    final agents = scopes.where((s) => s.kind == 'agent').toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    final sessions = scopes.where((s) => s.kind == 'session').toList()
      ..sort((a, b) => (b.lastCommitAt ?? 0).compareTo(a.lastCommitAt ?? 0));
    final shownSessions = _allSessions ? sessions : sessions.take(5).toList();
    Widget group(String label, List<MemoryScope> items, {Widget? extra}) {
      if (items.isEmpty) return const SizedBox.shrink();
      return SettingsGroup(
        header: label.isEmpty ? null : label,
        children: [
          for (final s in items)
            SettingsRow(
              label: scopeTitle(s, s.key),
              sub: scopeStatus(s),
              leading: scopeLeading(s),
              chevron: true,
              onTap: () => _openScopeKey(s.key),
            ),
          if (extra != null) extra,
        ],
      );
    }

    return SettingsColumn(children: [
      const SettingsHeader(
        title: 'Memory',
        subtitle:
            'What your agents remember, kept as files in git and consolidated in the background.',
      ),
      SizedBox(height: S.s8),
      if (scopes.isEmpty)
        const SettingsGroup(children: [
          SettingsRow(
              label: 'Nothing remembered yet',
              sub: 'Memory fills in as agents work.'),
        ])
      else ...[
        group('', global),
        group('Projects', projects),
        group('Agents', agents),
        group(
          'Sessions',
          shownSessions,
          extra: sessions.length > 5 && !_allSessions
              ? SettingsRow(
                  label: 'Show all ${sessions.length} sessions',
                  onTap: () => setState(() => _allSessions = true),
                )
              : null,
        ),
      ],
    ]);
  }
}

String scopeTitle(MemoryScope? s, String key) {
  if (s == null) {
    final kind = key.split(':').first;
    return switch (kind) {
      'global' => 'You',
      'session' => 'This session',
      _ => key.split(':').skip(1).join(':'),
    };
  }
  return switch (s.kind) {
    'global' => 'You',
    'session' => sessionScopeTitle(s.label),
    _ => s.label,
  };
}

String sessionScopeTitle(String id) {
  final workspace =
      id.split('/').first.replaceFirst(RegExp(r'-[0-9a-f]{8,}$'), '');
  return id.contains('/conversations/') ? '$workspace · chat' : workspace;
}

String scopeIcon(String kind) => switch (kind) {
      'global' => 'user',
      'project' => 'folder',
      'agent' => 'agent',
      _ => 'chat-thread',
    };

/// An agent scope shows the agent's character; the rest a kind icon.
Widget scopeLeading(MemoryScope s, {bool v5 = false}) {
  if (s.kind == 'agent' && s.key.startsWith('agent:')) {
    final size = v5 ? 30.0 : 28.0;
    return SizedBox.square(
      dimension: size,
      child: AgentMochi(s.key.substring('agent:'.length), size: size),
    );
  }
  return v5 ? V5IconTile(scopeIcon(s.kind)) : IconTile(scopeIcon(s.kind));
}

/// "2 hours ago" style, as the status lines read in full words.
String memoryAgo(int unixSec) {
  final d = DateTime.now()
      .difference(DateTime.fromMillisecondsSinceEpoch(unixSec * 1000));
  String n(int v, String unit) => '$v $unit${v == 1 ? '' : 's'} ago';
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return n(d.inMinutes, 'minute');
  if (d.inHours < 24) {
    return n(d.inHours, 'hour');
  }
  if (d.inDays == 1) return 'yesterday';
  if (d.inDays < 30) return n(d.inDays, 'day');
  return n((d.inDays / 30).floor(), 'month');
}

String scopeStatus(MemoryScope s) {
  final entries = '${s.entries} ${s.entries == 1 ? 'entry' : 'entries'}';
  if (s.consolidating) return '$entries · consolidating now';
  if (s.kind == 'session') {
    return s.lastCommitAt == null
        ? entries
        : '$entries · updated ${memoryAgo(s.lastCommitAt!)}';
  }
  final consolidated = s.lastConsolidated == null
      ? 'not consolidated yet'
      : 'consolidated ${memoryAgo(s.lastConsolidated!)}';
  return '$entries · $consolidated';
}

/// One scope: its MEMORY.md (or a linked topic file), its files, its history.
class _ScopeView extends StatefulWidget {
  final DaemonClient client;
  final String scopeKey;
  final MemoryScope? scope;
  final bool hideSubtitle;
  const _ScopeView({
    super.key,
    required this.client,
    required this.scopeKey,
    required this.scope,
    this.hideSubtitle = false,
  });

  @override
  State<_ScopeView> createState() => _ScopeViewState();
}

enum _Tab { memory, files, history }

class _ScopeViewState extends State<_ScopeView> {
  _Tab _tab = _Tab.memory;
  final List<String> _trail = ['MEMORY.md'];
  String? _content;
  List<String> _files = const [];
  List<MemoryCommit>? _history;
  String? _error;
  final _search = TextEditingController();
  MemoryEntry? _topic;
  MemoryEntry? _note;

  String get _path => _trail.last;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _loadFile();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadFile() async {
    setState(() {
      _content = null;
      _error = null;
    });
    try {
      final f = await widget.client.memoryFile(widget.scopeKey, path: _path);
      if (mounted) {
        setState(() {
          _content = f.content;
          _files = f.files;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _loadHistory() async {
    try {
      final h = await widget.client.memoryHistory(widget.scopeKey);
      if (mounted) setState(() => _history = h);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _openFile(String path) {
    final file = path.contains('.') ? path : '$path.md';
    setState(() {
      _tab = _Tab.memory;
      if (_trail.last != file) _trail.add(file);
    });
    _loadFile();
  }

  void _backFile() {
    if (_note != null) {
      setState(() => _note = null);
      return;
    }
    if (_trail.length < 2) return;
    setState(() {
      _trail.removeLast();
      if (_trail.length < 2) _topic = null;
    });
    _loadFile();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scope;
    final side = kMobile ? M.gutter : 24.0;
    final page = PopScope(
      canPop: _trail.length < 2 && _note == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backFile();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (s != null && !widget.hideSubtitle)
            Padding(
              padding: EdgeInsets.fromLTRB(side + S.s4, 0, side, S.s8),
              child: Text(scopeStatus(s),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, color: AppColors.fg4)),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(side, 0, side, S.of(10)),
            child: Row(children: [
              Pills<_Tab>(
                items: const [
                  (_Tab.memory, 'Memory'),
                  (_Tab.files, 'Files'),
                  (_Tab.history, 'History'),
                ],
                selected: _tab,
                onSelect: (t) {
                  setState(() => _tab = t);
                  if (t == _Tab.history && _history == null) _loadHistory();
                },
              ),
            ]),
          ),
          Expanded(
            child: Swap(
              stateKey: '$_tab:$_path:${_content != null}',
              fill: true,
              child: switch (_tab) {
                _Tab.memory => _memory(side),
                _Tab.files => _fileList(side),
                _Tab.history => _historyList(side),
              },
            ),
          ),
        ],
      ),
    );
    if (kMobile) return page;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680 + 48),
        child: page,
      ),
    );
  }

  String _emptyBody() {
    final key = widget.scopeKey;
    if (key.startsWith('agent:')) {
      final name = widget.scope?.label ?? key.substring('agent:'.length);
      return 'Filled by sessions and tasks run as $name. Lessons from your other sessions go to global and project memory.';
    }
    if (key.startsWith('project:')) {
      return 'Filled by sessions working in this project.';
    }
    return 'Entries appear here as agents save what they learn.';
  }

  Widget _memory(double side) {
    final content = _content;
    if (content == null) {
      return Center(
        child: _error == null
            ? const Spinner(size: 20)
            : const EmptyState(
                icon: 'brain',
                title: 'Nothing remembered yet',
                body: 'This memory fills in as work happens here.',
              ),
      );
    }
    final hasEntries = content
        .split('\n')
        .any((l) => l.trim().startsWith('- ') || l.contains('[['));
    if (!hasEntries && _trail.length < 2) {
      return Center(
        child: EmptyState(
          icon: 'brain',
          title: 'Nothing remembered yet',
          body: _emptyBody(),
        ),
      );
    }
    if (kMobile && _trail.length < 2) {
      return _note == null ? _index(side, content) : _noteView(side, _note!);
    }
    final topic = kMobile && _trail.length == 2 ? _topic : null;
    return SelectionArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(side, S.s4, side, S.s40),
        children: [
          if (_trail.length > 1)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _backFile,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.fg3,
                  minimumSize: kMobile ? const Size(0, 30) : const Size(0, 28),
                  padding: EdgeInsets.symmetric(horizontal: kMobile ? S.s6 : S.s8),
                  tapTargetSize: kMobile
                      ? null
                      : MaterialTapTargetSize.shrinkWrap,
                ),
                icon: AppIcon('chevron-left', size: 14, color: AppColors.fg3),
                label: Text(_trail[_trail.length - 2],
                    style: sans(13, color: AppColors.fg3)),
              ),
            ),
          if (topic != null)
            Padding(
              padding: EdgeInsets.only(left: S.s4, bottom: S.s8),
              child: Row(children: [
                Expanded(
                  child: Text('${topic.file}.md',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(14, color: AppColors.fg1)),
                ),
                MemoryAction('Forget', () => _forgetTopic(topic), danger: true),
              ]),
            ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: SizedBox(
                width: double.infinity,
                child: MarkdownBody(
                  data: memoryMarkdown(content),
                  selectable: false,
                  styleSheet: documentMarkdownStyle(context)
                      .copyWith(em: sans(12, color: AppColors.fg4)),
                  builders: {'pre': PreBlockBuilder()},
                  onTapLink: (_, href, __) {
                    if (href != null && href.startsWith('memory:')) {
                      _openFile(href.substring('memory:'.length));
                    } else {
                      openMarkdownLink(href, context);
                    }
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _forgetTopic(MemoryEntry e) async {
    if (!await forgetMemoryEntry(context, widget.client, widget.scopeKey, e)) {
      return;
    }
    _backFile();
    _loadFile();
  }

  Future<void> _forgetNote(MemoryEntry e) async {
    if (!await forgetMemoryEntry(context, widget.client, widget.scopeKey, e)) {
      return;
    }
    setState(() => _note = null);
    _loadFile();
  }

  Future<void> _editNote(MemoryEntry e) async {
    final text =
        await editMemoryNote(context, widget.client, widget.scopeKey, e);
    if (text == null) return;
    setState(() => _note = null);
    _loadFile();
  }

  /// Phone: the scope's index as entries with search; a topic or note opens in full.
  Widget _index(double side, String content) {
    final all = parseMemoryEntries(content);
    final shown = [
      for (final e in all)
        if (memoryEntryMatches(e, _search.text)) e
    ];
    final q = _search.text.trim();
    return ListView(
      padding: EdgeInsets.fromLTRB(side, S.s2, side, S.s40),
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: S.s8),
          child: MemorySearchField(controller: _search),
        ),
        if (shown.isEmpty)
          Padding(
            padding: EdgeInsets.all(S.s24),
            child: Text(q.isEmpty ? _emptyBody() : 'No entries match.',
                textAlign: TextAlign.center,
                style: sans(13, height: 1.5, color: AppColors.fg4)),
          )
        else
          for (final e in shown)
            MemoryEntryCard(
              entry: e,
              onTap: () {
                final f = e.file;
                if (f == null) {
                  setState(() => _note = e);
                } else {
                  _topic = e;
                  _openFile(f);
                }
              },
            ),
        Padding(
          padding: EdgeInsets.fromLTRB(S.s4, S.s4, S.s4, 0),
          child: Text('Saved by agents while they work.',
              style: sans(12, color: AppColors.fg4)),
        ),
      ],
    );
  }

  Widget _noteView(double side, MemoryEntry e) {
    final when = memoryDay(e.added);
    return SelectionArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(side, S.s4, side, S.s40),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _backFile,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.fg3,
                minimumSize: const Size(0, 44),
                padding: EdgeInsets.symmetric(horizontal: S.s6),
              ),
              icon: AppIcon('chevron-left', size: 14, color: AppColors.fg3),
              label: Text('Memory', style: sans(13, color: AppColors.fg3)),
            ),
          ),
          Row(children: [
            Expanded(
              child: Text(when.isEmpty ? 'Note' : 'Added $when',
                  style: sans(12, color: AppColors.fg4)),
            ),
            MemoryAction('Edit', () => _editNote(e)),
            MemoryAction('Forget', () => _forgetNote(e), danger: true),
          ]),
          SizedBox(height: S.s8),
          Text(e.text, style: sans(14, height: 1.55, color: AppColors.fg2)),
        ],
      ),
    );
  }

  Widget _fileList(double side) => PageBody(
        topPadding: 4,
        children: [
          ListGroup(children: [
            for (final f in _files)
              ListRow(
                title: f,
                titleWidget: Text(f,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(13, color: AppColors.fg1)),
                leading: IconTile(f == 'MEMORY.md' ? 'brain' : 'file-text'),
                onTap: () {
                  setState(() {
                    _trail
                      ..clear()
                      ..add('MEMORY.md');
                  });
                  _openFile(f);
                },
              ),
          ]),
        ],
      );

  Widget _historyList(double side) {
    final history = _history;
    if (history == null) return const Center(child: Spinner(size: 20));
    return PageBody(
      topPadding: 4,
      children: [
        for (final c in history)
          Padding(
            padding: EdgeInsets.symmetric(vertical: S.s8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: EdgeInsets.only(top: S.s2),
                child: AppIcon(c.isConsolidation ? 'layers' : 'git-commit',
                    size: 15,
                    color:
                        c.isConsolidation ? AppColors.accent : AppColors.fg4),
              ),
              SizedBox(width: S.of(10)),
              Expanded(
                child: Text(
                    c.isConsolidation
                        ? c.subject.substring('Consolidate:'.length).trim()
                        : c.subject,
                    style: sans(14, height: 19 / 14, color: AppColors.fg1)),
              ),
              SizedBox(width: S.of(10)),
              Text(relativeTime(c.date),
                  style: sans(12, color: AppColors.fg4, tabular: true)),
            ]),
          ),
      ],
    );
  }
}

/// MEMORY.md as readable markdown: `[[links]]` become tappable, and the
/// `[source: …; added: …]` metadata shrinks to a quiet date.
String memoryMarkdown(String text) {
  var out = text.replaceAllMapped(
      RegExp(r'\[\[([^\]]+)\]\]'), (m) => '[${m[1]}](memory:${m[1]})');
  out = out.replaceAllMapped(
      RegExp(r'[ \t]*\[(?:source|added)[^\]\n]*\]', multiLine: true), (m) {
    final added = RegExp(r'added: (\d{4}-\d{2}-\d{2})').firstMatch(m[0]!);
    return added == null ? '' : '  *${added[1]}*';
  });
  return out;
}
