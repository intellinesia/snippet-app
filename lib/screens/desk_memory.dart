import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'memory_entries.dart';
import 'memory_screen.dart' show memoryMarkdown;

class DeskMemoryView extends StatefulWidget {
  const DeskMemoryView({
    super.key,
    required this.client,
    required this.sessionId,
    this.workspace,
  });

  final DaemonClient client;
  final String sessionId;
  final String? workspace;

  @override
  State<DeskMemoryView> createState() => _DeskMemoryViewState();
}

class _DeskMemoryViewState extends State<DeskMemoryView> {
  final _search = TextEditingController();
  List<MemoryScope> _scopes = const [];
  String _scope = '';
  bool _history = false;
  final Map<String, List<MemoryEntry>> _entries = {};
  final Map<String, List<MemoryCommit>> _commits = {};
  MemoryEntry? _selected;
  String? _detail;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _init();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final s = await widget.client.memoryScopes();
      if (mounted) setState(() => _scopes = s);
    } catch (_) {}
    if (!mounted) return;
    final key = _projectKey ?? _globalKey;
    if (key == null) {
      setState(() => _loading = false);
      return;
    }
    _scope = key;
    await _load(_scope);
  }

  String? get _projectKey {
    final parts = (widget.workspace ?? '')
        .split('/')
        .where((p) => p.isNotEmpty)
        .toList()
        .reversed;
    for (final name in parts) {
      final hit = _scopes
          .where((s) => s.kind == 'project' && s.label == name)
          .firstOrNull;
      if (hit != null) return hit.key;
    }
    return null;
  }

  String? get _globalKey =>
      _scopes.where((s) => s.kind == 'global').firstOrNull?.key;

  Future<void> _load(String key) async {
    setState(() => _loading = !_entries.containsKey(key));
    try {
      final f = await widget.client.memoryFile(key);
      if (mounted) setState(() => _entries[key] = parseMemoryEntries(f.content));
    } catch (_) {
      if (mounted) setState(() => _entries[key] = const []);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadHistory() async {
    if (_commits.containsKey(_scope)) return;
    try {
      final h = await widget.client.memoryHistory(_scope);
      if (mounted) setState(() => _commits[_scope] = h);
    } catch (_) {
      if (mounted) setState(() => _commits[_scope] = const []);
    }
  }

  Future<void> _select(MemoryEntry e) async {
    setState(() {
      _selected = e;
      _detail = null;
    });
    final f = e.file;
    if (f == null) return;
    try {
      final r = await widget.client.memoryFile(_scope,
          path: f.contains('.') ? f : '$f.md');
      if (mounted && _selected == e) setState(() => _detail = r.content);
    } catch (_) {
      if (mounted && _selected == e) setState(() => _detail = '');
    }
  }

  void _pick(String key) {
    setState(() {
      _scope = key;
      _history = false;
      _selected = null;
    });
    _load(key);
  }

  Widget _chip(String label, bool on, VoidCallback tap) => Padding(
        padding: EdgeInsets.only(right: S.s4),
        child: Material(
          color: on ? AppColors.surface2 : Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kMobile ? R.pill : R.sm),
              side:
                  BorderSide(color: on ? Colors.transparent : AppColors.line)),
          child: InkWell(
            borderRadius: BorderRadius.circular(kMobile ? R.pill : R.sm),
            onTap: tap,
            child: Container(
              height: 24,
              padding: EdgeInsets.symmetric(horizontal: S.of(10)),
              alignment: Alignment.center,
              child: Text(label,
                  style: sans(12, color: on ? AppColors.fg1 : AppColors.fg3)),
            ),
          ),
        ),
      );

  Future<void> _forget(MemoryEntry e) async {
    if (!await forgetMemoryEntry(context, widget.client, _scope, e)) return;
    setState(() => _selected = null);
    await _load(_scope);
  }

  Future<void> _edit(MemoryEntry e) async {
    if (await editMemoryNote(context, widget.client, _scope, e) == null) return;
    setState(() => _selected = null);
    await _load(_scope);
  }

  Widget _detailView({bool wide = true}) {
    final e = _selected;
    if (e == null) {
      return Center(
        child: Text('Pick an entry to read it in full.',
            style: sans(13, color: AppColors.fg4)),
      );
    }
    final body = e.file == null ? e.text : _detail;
    return SelectionArea(
      child: ListView(
        padding: wide
            ? EdgeInsets.fromLTRB(S.s40, S.of(28), S.s40, S.s40)
            : EdgeInsets.fromLTRB(S.s16, S.s4, S.s16, S.s24),
        children: [
          Row(children: [
            Expanded(
              child: Text(e.file ?? 'Note',
                  style: mono(13, color: AppColors.fg1)),
            ),
            if (memoryDay(e.added).isNotEmpty)
              Text('Added ${memoryDay(e.added)}',
                  style: sans(12, color: AppColors.fg4)),
            if (e.file == null) MemoryAction('Edit', () => _edit(e)),
            MemoryAction('Forget', () => _forget(e), danger: true),
          ]),
          SizedBox(height: S.s16),
          if (body == null)
            const Align(alignment: Alignment.centerLeft, child: Spinner(size: 14))
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: MarkdownBody(
                data: memoryMarkdown(body),
                styleSheet: documentMarkdownStyle(context)
                    .copyWith(em: sans(12, color: AppColors.fg4)),
                builders: {'pre': PreBlockBuilder()},
                onTapLink: (_, href, __) => openMarkdownLink(href, context),
              ),
            ),
        ],
      ),
    );
  }

  Widget _historyList() {
    final h = _commits[_scope];
    if (h == null) return const Center(child: Spinner(size: 16));
    if (h.isEmpty) {
      return Center(
          child: Text('No history yet.', style: sans(13, color: AppColors.fg4)));
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(S.of(14), S.s4, S.of(14), S.s24),
      children: [
        for (final c in h)
          Padding(
            padding: EdgeInsets.symmetric(vertical: S.of(7)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: EdgeInsets.only(top: S.of(5)),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.isConsolidation ? AppColors.accent : AppColors.fg4,
                  ),
                ),
              ),
              SizedBox(width: S.of(10)),
              Expanded(
                child: Text(
                    c.isConsolidation
                        ? c.subject.substring('Consolidate:'.length).trim()
                        : c.subject,
                    style: sans(13, height: 1.45, color: AppColors.fg2)),
              ),
              SizedBox(width: S.s8),
              Text(relativeTime(c.date),
                  style: sans(11, color: AppColors.fg4, tabular: true)),
            ]),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final all = _entries[_scope] ?? const <MemoryEntry>[];
    final shown = [
      for (final e in all)
        if (memoryEntryMatches(e, q)) e
    ];
    final project = _projectKey;
    final global = _globalKey;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth > 640;
      final list = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (wide)
          Padding(
            padding: EdgeInsets.fromLTRB(S.s16, S.s16, S.s16, S.of(10)),
            child: Row(children: [
              Expanded(
                child: Text('Memory',
                    style: sans(15, weight: W.label, color: AppColors.fg1)),
              ),
              Text('${all.length} entries',
                  style: sans(12, color: AppColors.fg4)),
            ]),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(S.of(14), wide ? 0 : S.s2, S.of(14), S.s8),
          child: MemorySearchField(controller: _search),
        ),
        SizedBox(
          height: 30,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: S.of(14)),
            children: [
              if (project != null)
                _chip('Project', _scope == project && !_history,
                    () => _pick(project)),
              if (global != null)
                _chip('Global', _scope == global && !_history,
                    () => _pick(global)),
              _chip('History', _history, () {
                setState(() => _history = true);
                _loadHistory();
              }),
            ],
          ),
        ),
        SizedBox(height: S.s6),
        Expanded(
          child: _history
              ? _historyList()
              : _loading
                  ? const Center(child: Spinner(size: 16))
                  : shown.isEmpty
                      ? Padding(
                          padding: EdgeInsets.all(S.s24),
                          child: Text(
                              q.isEmpty
                                  ? 'Nothing remembered here yet. Agents save decisions and progress as they work.'
                                  : 'No entries match.',
                              textAlign: TextAlign.center,
                              style: sans(13,
                                  height: 1.5, color: AppColors.fg4)),
                        )
                      : ListView(
                          padding: EdgeInsets.fromLTRB(S.of(14), S.s2, S.of(14), S.s16),
                          children: [
                            for (final e in shown)
                              MemoryEntryCard(
                                entry: e,
                                wide: wide,
                                selected: identical(_selected, e),
                                onTap: () => _select(e),
                              )
                          ],
                        ),
        ),
        if (!_history)
          Padding(
            padding: EdgeInsets.fromLTRB(S.s16, S.s4, S.s16, S.of(10)),
            child: Text('Saved by agents while they work.',
                style: sans(12, color: AppColors.fg4)),
          ),
      ]);
      if (!wide) {
        final e = _selected;
        if (e != null) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: EdgeInsets.fromLTRB(S.s8, 0, S.s8, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _selected = null),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.fg3,
                    minimumSize: const Size(0, 44),
                    padding: EdgeInsets.symmetric(horizontal: S.s8),
                  ),
                  icon: AppIcon('chevron-left', size: 14, color: AppColors.fg3),
                  label: Text('Memory', style: sans(13, color: AppColors.fg3)),
                ),
              ),
            ),
            Expanded(child: _detailView(wide: false)),
          ]);
        }
        return list;
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 380, child: list),
        Container(width: 1, color: AppColors.line),
        Expanded(child: _detailView()),
      ]);
    });
  }
}
