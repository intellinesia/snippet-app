part of 'session_rail.dart';

/// Desktop drill-in panel: a root of grouped rows and one page per area.
extension _RailPages on _SessionRailState {
  /// One destination as its own 8 px card: icon tile, title, quiet value.
  Widget _navRow(String icon, String label,
      {String? value,
      bool hot = false,
      Widget? trailing,
      Widget? leading,
      VoidCallback? onTap,
      bool first = false,
      bool last = false}) {
    return _RailCard(
      onTap: onTap,
      child: Row(children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.fg1.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(R.of(6)),
          ),
          child: leading ?? AppIcon(icon, size: 15, color: AppColors.fg2),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(13, weight: FontWeight.w500, color: AppColors.fg1)),
        ),
        if (value != null) ...[
          const SizedBox(width: 8),
          Flexible(
            flex: 0,
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(12,
                    color: hot ? AppColors.accent : AppColors.fg3,
                    tabular: true)),
          ),
        ],
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing,
        ] else if (onTap != null) ...[
          const SizedBox(width: 6),
          AppIcon('chevron-right', size: 14, color: AppColors.fg3),
        ],
      ]),
    );
  }

  Widget _plab(String title, {String? meta}) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
        child: Row(children: [
          Expanded(
              child: Text(title,
                  style:
                      sans(12, weight: FontWeight.w500, color: AppColors.fg2))),
          if (meta != null) Text(meta, style: sans(12, color: AppColors.fg2)),
        ]),
      );

  /// Rows as separate cards, 6 px apart.
  Widget _navGroup(String? title, List<Widget Function(bool, bool)> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null) _plab(title),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          rows[i](i == 0, i == rows.length - 1),
        ],
      ]),
    );
  }

  Widget _card2(String? title, List<Widget> children, {String? meta}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 6, 0, 0),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null) _plab(title, meta: meta),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(R.of(8))),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children),
          ),
        ]),
      );

  void _go(String? page) => _set(() {
        if (page != null && !_openTabs.contains(page)) _openTabs.add(page);
        _page = page;
        _laneFilter = 0;
        _armedRewind = null;
      });

  void _closeTab(String page) {
    final i = _openTabs.indexOf(page);
    if (i < 0) return;
    _set(() => _openTabs.removeAt(i));
    if (_page != page) return;
    _go(_openTabs.isEmpty ? null : _openTabs[i.clamp(0, _openTabs.length - 1)]);
  }

  static (String, String)? _tabMeta(String page) => switch (page) {
        'lanes' => ('git-branch', 'Lanes'),
        'jobs' => ('activity', 'Activity'),
        'checkpoints' => ('history', 'Checkpoints'),
        'wakes' => ('clock', 'Wakes'),
        'usage' => ('gauge', 'Usage'),
        'memory' => ('book-marked', 'Memory'),
        'changes' => ('file-diff', 'Diffs'),
        'files' => ('folder', 'Files'),
        _ => null,
      };

  /// The panel's pane row: Overview, then every tab opened from + (they
  /// stay until closed), then expand and hide at the right end.
  Widget _railTabs() {
    final page = _page;
    final tabs = [
      for (final t in _openTabs)
        if (_tabMeta(t) != null) t,
      if (page != null && !_openTabs.contains(page) && _tabMeta(page) != null)
        page,
    ];
    return Container(
      key: const ValueKey('rail-tabs'),
      height: PaneRow.height,
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.paneLine))),
      child: Row(children: [
        Flexible(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              PanePill(
                  icon: 'list',
                  label: widget.isLead ? 'Lead' : 'Overview',
                  active: page == null,
                  onTap: page == null ? null : () => _go(null)),
              for (final t in tabs) ...[
                const SizedBox(width: 2),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: PanePill(
                      key: ValueKey('rail-tab-$t'),
                      icon: _tabMeta(t)!.$1,
                      label: _tabMeta(t)!.$2,
                      active: page == t,
                      onTap: page == t ? null : () => _go(t),
                      onClose: () => _closeTab(t)),
                ),
              ],
              if (!widget.isLead) ...[
                const SizedBox(width: 2),
                Builder(
                  builder: (ctx) => IconBtn('plus',
                      size: 28,
                      iconSize: 14,
                      tooltip: 'Open a tab',
                      onTap: () => _railAddMenu(ctx)),
                ),
              ],
            ]),
          ),
        ),
        const Spacer(),
        IconBtn(sessionRailWide.value ? 'minimize-2' : 'maximize-2',
            size: 28,
            iconSize: 14,
            tooltip: sessionRailWide.value ? 'Restore panel' : 'Expand panel',
            onTap: () => sessionRailWide.value = !sessionRailWide.value),
        IconBtn('sidebar',
            size: 28,
            iconSize: 14,
            tooltip: 'Hide panel',
            onTap: () => setSessionRailCollapsed(true)),
      ]),
    );
  }

  void _railAddMenu(BuildContext ctx) {
    final s = widget.state;
    final cps = s?.checkpoints.length ?? 0;
    final lanes = s?.lanes.where((l) => l.running).length ?? 0;
    final files = _git?.ok == true ? _git!.files.length : 0;
    String? count(int n) => n > 0 ? '$n' : null;
    PaneAddEntry e(String page, String icon, String label, {String? meta}) =>
        PaneAddEntry(
            icon: icon,
            label: label,
            meta: meta,
            checked: _page == page,
            onTap: () => _go(page));
    showPaneAddMenu(
      ctx,
      title: 'Panel',
      views: [
        if (widget.onChanges != null)
          e('changes', 'file-diff', 'Diffs', meta: count(files)),
        if (widget.onFiles != null) e('files', 'folder', 'Files'),
        e('jobs', 'activity', 'Activity'),
        e('checkpoints', 'history', 'Checkpoints', meta: count(cps)),
        e('memory', 'book-marked', 'Memory'),
        e('usage', 'gauge', 'Usage'),
        e('wakes', 'clock', 'Wakes'),
      ],
      crew: [
        e('lanes', 'git-branch', 'Lanes',
            meta: lanes > 0 ? '$lanes running' : null),
      ],
    );
  }

  /// Desktop Overview (Capy pass): status, what is happening now, changes,
  /// artifacts, task and quick ways into the panel's other tabs.
  List<Widget> _overviewRoot() {
    final s = widget.state;
    final w = widget;
    final agentId = (w.agentId ?? w.ownAgent ?? 'snippet').trim();
    final head = !w.floating
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox(
              height: 28,
              child: Row(children: [
                Expanded(
                  child: Text('Overview',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(14, weight: W.label, color: AppColors.fg1)),
                ),
                IconBtn('x',
                    size: 28,
                    iconSize: 15,
                    tooltip: 'Close',
                    onTap: () => sessionRailFloating.value = false),
              ]),
            ),
          );
    if (s == null && _loading) {
      return [
        head,
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Spinner(size: 16)),
        ),
      ];
    }
    if (s == null && _loadFailed) {
      return [
        head,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Details did not load',
                  style: sans(13, weight: W.label, color: AppColors.fg1)),
              const SizedBox(height: 4),
              Text('The session still runs.',
                  style: sans(12, color: AppColors.fg2)),
              const SizedBox(height: 12),
              Btn('Try again',
                  small: true, variant: BtnVariant.outline, onTap: _load),
            ],
          ),
        ),
      ];
    }
    final t = _tasks.where((t) => t.sessionId == widget.sessionId).firstOrNull;
    final git = _git;
    final gitFiles = git != null && git.ok ? git.files : const <GitFile>[];
    final fallbackFiles = gitFiles.isEmpty
        ? fileChanges(sessionChangeSteps(s?.events ?? const []))
        : const <FileChange>[];
    var adds = 0, dels = 0;
    for (final f in gitFiles) {
      if (_lineCounts['${f.path}|${f.staged}|${f.unstaged}'] case (
            final a,
            final r
          )) {
        adds += a;
        dels += r;
      }
    }
    final nFiles = gitFiles.isNotEmpty ? gitFiles.length : fallbackFiles.length;
    final steps = _activitySteps(s);
    final lanes = [...?s?.lanes];
    final running = lanes.where((l) => l.running).length;
    final ws = (s?.workspace ?? '').trim();
    final wsLabel = ws.isEmpty ? '' : lastPathSegment(ws, ifEmpty: ws);

    Widget fileRow(String path, {(int, int)? counts, VoidCallback? onTap}) =>
        TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: 26,
            child: Row(children: [
              Expanded(
                child: Text(lastPathSegment(path, ifEmpty: path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(12, color: AppColors.fg1)),
              ),
              if (counts case (final a, final r)) ...[
                const SizedBox(width: 8),
                Text('+$a', style: mono(12, color: AppColors.ok)),
                const SizedBox(width: 6),
                Text('−$r', style: mono(12, color: AppColors.danger)),
              ],
            ]),
          ),
        );

    final pills = <Widget>[
      if (w.onFiles != null)
        _OpenPill(
            icon: 'folder',
            label: wsLabel.isEmpty ? 'Files' : wsLabel,
            onTap: () => _go('files')),
      if (w.onShell != null)
        _OpenPill(icon: 'terminal', label: 'Shell', onTap: w.onShell!),
      if (lanes.isNotEmpty)
        _OpenPill(
            icon: 'git-branch',
            label: running > 0 ? 'Lanes $running' : 'Lanes',
            onTap: () => _go('lanes')),
      _OpenPill(
          icon: 'history',
          label: 'Checkpoints',
          onTap: () => _go('checkpoints')),
      _OpenPill(
          icon: 'book-marked', label: 'Memory', onTap: () => _go('memory')),
    ];

    return [
      head,
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _statusLine(s, people: _people(agentId, s)),
            if (steps.isNotEmpty) ...[
              const SizedBox(height: 14),
              _nowCard(s, steps),
            ],
            _capyHead('Changes',
                meta: nFiles == 0
                    ? null
                    : '$nFiles file${nFiles == 1 ? '' : 's'}',
                adds: adds > 0 || dels > 0 ? (adds, dels) : null,
                onTap: w.onChanges != null ? () => _go('changes') : null),
            if (gitFiles.isNotEmpty)
              for (final f in gitFiles.take(6))
                fileRow(f.path,
                    counts: _lineCounts['${f.path}|${f.staged}|${f.unstaged}'],
                    onTap: () => w.onOpenDiff != null
                        ? w.onOpenDiff!(f)
                        : _go('changes'))
            else if (fallbackFiles.isNotEmpty)
              for (final f in fallbackFiles.take(6))
                fileRow(f.path, onTap: () => _go('changes'))
            else
              Text('No changes yet.', style: sans(12, color: AppColors.fg3)),
            if (_artifacts.isNotEmpty) ...[
              _capyHead('Artifacts',
                  meta: '${_artifacts.length}', onTap: w.onDeliverables),
              for (final a in _artifacts.reversed.take(4)) _artifactRow(a),
            ],
            if (t != null) ...[
              _capyHead('Task',
                  meta: t.status.label,
                  onTap:
                      w.onOpenTask != null ? () => w.onOpenTask!(t.id) : null),
              TapDetector(
                behavior: HitTestBehavior.opaque,
                onTap: w.onOpenTask != null ? () => w.onOpenTask!(t.id) : null,
                child: Text(t.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12.5, height: 1.35, color: AppColors.fg2)),
              ),
            ],
            _capyHead('Open'),
            Wrap(spacing: 6, runSpacing: 6, children: pills),
          ],
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  Widget _capyHead(String title,
          {String? meta, (int, int)? adds, VoidCallback? onTap}) =>
      Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 8),
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Row(children: [
            Expanded(
              child: Text(title,
                  style: sans(12.5, weight: W.label, color: AppColors.fg1)),
            ),
            if (meta != null)
              Text(meta, style: sans(12, color: AppColors.fg3, tabular: true)),
            if (adds case (final a, final r)) ...[
              const SizedBox(width: 6),
              Text('+$a', style: sans(12, color: AppColors.ok, tabular: true)),
              const SizedBox(width: 4),
              Text('−$r',
                  style: sans(12, color: AppColors.danger, tabular: true)),
            ],
          ]),
        ),
      );

  /// What the session is doing: its last few steps, newest first and lit.
  Widget _nowCard(HarnessState? s, List<ToolStep> steps) {
    final live = switch (s?.status) {
      'running' || 'thinking' || 'tool' => true,
      _ => false,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.of(10)),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(live ? 'Now' : 'Last steps',
              style: sans(11, color: AppColors.fg3)),
          const SizedBox(height: 4),
          for (var i = 0; i < steps.length; i++)
            _stepRow(steps[i], lit: i == 0 && live),
        ],
      ),
    );
  }

  Widget _stepRow(ToolStep step, {bool lit = false}) {
    final ms = step.startMs;
    final when = ms == null ? '' : relativeTime(ms ~/ 1000);
    return SizedBox(
      height: 24,
      child: Row(children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: lit ? AppColors.ok : AppColors.fg3.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(toolSentence(step, running: false),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(12, color: lit ? AppColors.fg1 : AppColors.fg2)),
        ),
        if (when.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(when, style: sans(11, color: AppColors.fg3, tabular: true)),
        ],
      ]),
    );
  }

  /// The manager, then each lane's other agent once: (id, name, role).
  List<(String, String, String)> _people(String agentId, HarnessState? s) {
    final seen = <String>{agentId};
    final manager = (widget.managerName ?? '').trim();
    final out = [
      (agentId, manager.isEmpty ? _titleCase(agentId) : manager, 'manager')
    ];
    for (final lane in s?.lanes ?? const <LaneInfo>[]) {
      final who = (lane.agent ?? '').trim();
      if (who.isEmpty || !seen.add(who)) continue;
      out.add((who, _titleCase(who), lane.title));
      if (out.length >= 5) break;
    }
    return out;
  }

  Widget _statusLine(HarnessState? s,
      {List<(String, String, String)> people = const []}) {
    final (word, live) = switch (s?.status) {
      'running' || 'thinking' || 'tool' => ('Running', true),
      'waiting_approval' || 'waiting_question' => ('Waiting on you', true),
      _ => ('Idle', false),
    };
    final started = DateTime.tryParse(s?.turnStartedAt ?? '');
    final elapsed = live && started != null
        ? DateTime.now().difference(started.toLocal())
        : null;
    final model = widget.profileLabel.trim();
    return SizedBox(
      height: 24,
      child: Row(children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: live ? AppColors.ok : AppColors.fg3,
          ),
        ),
        const SizedBox(width: 8),
        Text(word, style: sans(12.5, weight: W.label, color: AppColors.fg1)),
        Expanded(
          child: Text(
              [
                if (elapsed != null) _elapsedLabel(elapsed),
                if (model.isNotEmpty) model,
              ].map((e) => '  \u00b7  $e').join(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(12, color: AppColors.fg3, tabular: true)),
        ),
        for (var i = 0; i < people.length; i++)
          Align(
            widthFactor: i == people.length - 1 ? 1 : 0.7,
            child: Tooltip(
              message: '${people[i].$2}, ${people[i].$3}',
              child: AgentMochi(people[i].$1.isEmpty ? 'snippet' : people[i].$1,
                  size: 20),
            ),
          ),
      ]),
    );
  }

  String _elapsedLabel(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds.clamp(0, 59)}s';
    if (d.inHours < 1) return '${d.inMinutes}m';
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }

  String _titleCase(String id) =>
      id.isEmpty ? id : '${id[0].toUpperCase()}${id.substring(1)}';

  /// The last few finished steps, newest first.
  List<ToolStep> _activitySteps(HarnessState? s) {
    final out = <ToolStep>[];
    Map<String, dynamic>? pending;
    for (final e in s?.events ?? const <Map<String, dynamic>>[]) {
      final k = e['kind'];
      if (k == 'tool_call') {
        pending = e;
      } else if (k == 'tool_result' && pending != null) {
        final at = pending['at_ms'];
        out.add(ToolStep(
          tool: (pending['tool_name'] ?? e['tool_name'])?.toString() ?? '',
          args: pending['arguments'],
          result: e['result'],
          startMs: at is num ? at.toInt() : null,
        ));
        pending = null;
      }
    }
    return out.reversed.take(4).toList();
  }

  Widget _artifactRow(ArtifactInfo a) {
    final kind = _titleCase(a.kind.isEmpty ? 'artifact' : a.kind);
    final n = a.versions.length;
    final meta = n > 1 ? '$kind, $n versions' : kind;
    return TapDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onDeliverables,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: AppIcon(a.kind == 'canvas' ? 'grid' : 'file-text',
                size: 14, color: AppColors.fg3),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.title.isEmpty ? a.id : a.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(11.5, weight: W.label, color: AppColors.fg1)),
                const SizedBox(height: 1),
                Text(meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(10.5, color: AppColors.fg3)),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _subHeader(String title, {String? meta}) => !kMobile &&
          !widget.floating
      // Docked, the page's pill in the panel row names it.
      ? const SizedBox(height: 2)
      : Container(
        height: 40,
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
        child: Row(children: [
          IconBtn('chevron-left',
              size: 30, iconSize: 15, tooltip: 'Back', onTap: () => _go(null)),
          const SizedBox(width: 4),
          Text(title, style: sans(13, weight: W.strong, color: AppColors.fg1)),
          if (meta != null) ...[
            const SizedBox(width: 8),
            Text(meta, style: mono(12, color: AppColors.fg3)),
          ],
          const Spacer(),
          if (widget.floating)
            IconBtn('x',
                size: 30,
                iconSize: 15,
                tooltip: 'Close',
                onTap: () => sessionRailFloating.value = false),
        ]),
      );

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.all(20),
        child: Text(text, style: sans(12.5, color: AppColors.fg3)),
      );

  List<Widget> _subPage() {
    final s = widget.state;
    switch (_page) {
      case 'lanes':
        final lanes = [...?s?.lanes];
        final run = lanes.where((l) => l.running).toList();
        final done = lanes.where((l) => !l.running).toList();
        Widget tab(int i, String label, int n) => Expanded(
              child: InkWell(
                onTap: () => _set(() => _laneFilter = i),
                borderRadius: BorderRadius.circular(R.of(8)),
                child: Container(
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: _laneFilter == i ? Grouped.row : null,
                      borderRadius: BorderRadius.circular(R.of(8))),
                  child: Text('$label $n',
                      style: sans(12,
                          color: _laneFilter == i
                              ? AppColors.fg1
                              : AppColors.fg3)),
                ),
              ),
            );
        Widget group(String t, List<LaneInfo> ls) => _navGroup(t, [
              for (final l in ls) (f, la) => _laneNavRow(l, f, la),
            ]);
        return [
          _subHeader('Lanes', meta: '${lanes.length}'),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(R.of(10))),
              child: Row(children: [
                tab(0, 'All', lanes.length),
                tab(1, 'Running', run.length),
                tab(2, 'Completed', done.length),
              ]),
            ),
          ),
          if (lanes.isEmpty) _empty('No lanes yet.'),
          if (_laneFilter != 2) group('Running', run),
          if (_laneFilter != 1) group('Completed', done),
          const SizedBox(height: 6),
        ];
      case 'jobs':
        // Newest first; old finished commands are history, so only the latest show.
        final sorted = [..._procs]..sort((a, b) =>
            '${b['started_at'] ?? ''}'.compareTo('${a['started_at'] ?? ''}'));
        final live = sorted.where((p) => p['running'] == true).toList();
        final done =
            sorted.where((p) => p['running'] != true).take(20).toList();
        Widget Function(bool, bool) row(Map<String, dynamic> p) => (f, l) {
              final id = '${p['id'] ?? ''}';
              final running = p['running'] == true;
              final st = '${p['status'] ?? ''}';
              return _navRow('activity', _jobTitle(p),
                  value: running
                      ? 'running'
                      : st.isEmpty
                          ? 'done'
                          : int.tryParse(st) != null
                              ? 'exit $st'
                              : st,
                  hot: running,
                  first: f,
                  last: l,
                  trailing: running
                      ? _OutlineButton('Stop', () async {
                          try {
                            await widget.client.bgKill(widget.sessionId, id);
                          } catch (_) {}
                          _loadLive();
                        })
                      : null,
                  onTap: widget.onProcesses);
            };
        return [
          _subHeader('Jobs',
              meta: live.isEmpty ? null : '${live.length} running'),
          if (_procs.isEmpty) _empty('No background jobs.'),
          if (live.isNotEmpty)
            _navGroup('Running', [for (final p in live) row(p)]),
          if (done.isNotEmpty)
            _navGroup('Recent', [for (final p in done) row(p)]),
          if (_procs.length > live.length + done.length)
            (_navGroup(null, [
              (f, l) => _navRow('history', 'All jobs',
                  value: '${_procs.length}',
                  first: f,
                  last: l,
                  onTap: widget.onProcesses),
            ])),
          const SizedBox(height: 6),
        ];
      case 'checkpoints':
        final all = (s?.checkpoints ?? const <Checkpoint>[]).reversed.toList();
        return [
          _subHeader('Checkpoints', meta: '${all.length}'),
          if (all.isEmpty) _empty('No checkpoints yet.'),
          for (var i = 0; i < all.length; i++)
            _checkpointRow(all[i], i == 0, i == all.length - 1),
          const SizedBox(height: 6),
        ];
      case 'wakes':
        return _wakesPage();
      case 'usage':
        final provider = widget.providers[widget.ownProfile] ??
            widget.providers[widget.profileLabel];
        final pct = _contextPct(s);
        Widget tile(String v, String l) => Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                    color: AppColors.fg1.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(R.of(8))),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(v, style: mono(13, color: AppColors.fg1)),
                      Text(l, style: sans(11, color: AppColors.fg4)),
                    ]),
              ),
            );
        final r = s?.rateSecondary;
        final showLimit = r != null && r.isReported && !r.isExpired;
        return [
          _subHeader('Usage'),
          _card2('Effective model', [_effectiveModel(provider)]),
          if (s != null && s.contextWindow > 0)
            _card2('Context window', [
              Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(pct == null ? '0%' : '${pct.round()}%',
                        style: mono(22, color: AppColors.fg1)),
                    const SizedBox(width: 8),
                    Text(
                        '${fmtSi(s.lastPromptTokens)} of ${fmtSi(s.contextWindow)} tokens',
                        style: sans(12, color: AppColors.fg3)),
                  ]),
              const SizedBox(height: 10),
              _UsageRow('Prompt and history', fmtSi(s.lastPromptTokens),
                  (pct ?? 0) / 100),
            ]),
          if (s != null && s.totalTokens > 0)
            _card2('This session', [
              Text(fmtSi(s.totalTokens), style: mono(22, color: AppColors.fg1)),
              Text('tokens', style: sans(12, color: AppColors.fg3)),
              const SizedBox(height: 10),
              Row(children: [
                tile(fmtSi(s.promptTokens), 'input'),
                const SizedBox(width: 4),
                tile(fmtSi(s.cacheReadTokens), 'cached'),
                const SizedBox(width: 4),
                tile(fmtSi(s.completionTokens), 'output'),
              ]),
            ]),
          if (showLimit)
            _card2('Limit', [
              Text('${r.usedPercent.clamp(0, 100).round()}% used',
                  style: mono(18, color: AppColors.fg1)),
              const SizedBox(height: 8),
              _UsageRow(
                  limitWindowLabel(r) == '7d'
                      ? 'This week'
                      : 'Window ${limitWindowLabel(r)}',
                  '${r.usedPercent.clamp(0, 100).round()}%',
                  r.usedPercent.clamp(0, 100) / 100,
                  warn: r.usedPercent >= 70),
            ]),
          const SizedBox(height: 6),
        ];
      case 'memory':
        return [
          _subHeader('Memory'),
          SizedBox(
            height: (_bodyH - 52).clamp(240.0, 4000.0),
            child: DeskMemoryView(
                client: widget.client,
                sessionId: widget.sessionId,
                workspace: s?.workspace),
          ),
        ];
      case 'changes':
      case 'files':
        // The list lives in the column; one file still opens wide in the pane.
        final ws = (s?.workspace ?? '').trim();
        final h = (_bodyH - 52).clamp(240.0, 4000.0);
        return [
          _subHeader(_page == 'changes' ? 'Diffs' : 'Files'),
          SizedBox(
            height: h,
            child: _page == 'changes'
                ? GitDiffSidebarPanel(
                    client: widget.client,
                    workspacePath: ws,
                    sessionId: widget.sessionId,
                    onOpenDiff: widget.onOpenDiff,
                    showHeader: false,
                  )
                : FileTreeSidebarPanel(
                    client: widget.client,
                    workspacePath: ws,
                    showHeader: false,
                    onOpenFile: widget.onOpenFile ?? (_, __) {},
                  ),
          ),
        ];
    }
    return const [];
  }

  Widget _laneNavRow(LaneInfo l, bool first, bool last) {
    final r = Radius.circular(R.of(13));
    final sm = Radius.circular(R.of(5));
    final t = DateTime.tryParse(l.startedAt);
    return Material(
      color: Grouped.row,
      borderRadius:
          BorderRadius.vertical(top: first ? r : sm, bottom: last ? r : sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openLaneView(context, l,
            client: widget.client,
            sessionId: widget.sessionId,
            liveLanes: () => widget.state?.lanes ?? [l]),
        hoverColor: AppColors.fg1.withValues(alpha: 0.04),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
            child: Row(children: [
              SizedBox.square(
                  dimension: 22, child: Center(child: _laneMark(l))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.title.isEmpty ? l.id : l.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(13, color: AppColors.fg1)),
                      Row(children: [
                        _Dot(l.running
                            ? AppColors.accent
                            : l.status == 'failed'
                                ? AppColors.danger
                                : AppColors.ok),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                              l.running
                                  ? ((l.activity ?? '').trim().isEmpty
                                      ? 'Running'
                                      : l.activity!.trim())
                                  : l.status == 'failed'
                                      ? 'Failed'
                                      : 'Completed',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(11.5, color: AppColors.fg4)),
                        ),
                      ]),
                    ]),
              ),
              if (l.running)
                _OutlineButton('Stop', () => _stopLane(l.id))
              else ...[
                if (t != null)
                  Text(relativeTime(t.millisecondsSinceEpoch ~/ 1000),
                      style: mono(11.5, color: AppColors.fg4)),
                const SizedBox(width: 6),
                AppIcon('chevron-right', size: 12, color: AppColors.fg3),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  /// The model the session actually runs, resolved from its profile.
  Widget _effectiveModel(String? provider) => FutureBuilder<ServerConfig>(
        future: widget.client.getConfig(),
        builder: (_, snap) {
          final name = widget.ownProfile ?? widget.profileLabel;
          final p = snap.data?.profiles
              .where((x) => x.name == name || x.name == widget.profileLabel)
              .firstOrNull;
          final model = (p?.model ?? '').trim();
          final prov = p?.provider ?? provider;
          Widget cell(String v, String l) => Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                  decoration: BoxDecoration(
                      color: AppColors.fg1.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(R.of(8))),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(v,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: mono(12.5, color: AppColors.fg1)),
                        Text(l, style: sans(11, color: AppColors.fg4)),
                      ]),
                ),
              );
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  if (prov != null && prov.isNotEmpty) ...[
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: AppColors.fg1.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(R.of(8))),
                      child: ProviderLogo(prov, size: 18),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(model.isEmpty ? widget.profileLabel : model,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(14,
                                  weight: W.title, color: AppColors.fg1)),
                          if (p != null && p.contextWindow > 0)
                            Text('${fmtSi(p.contextWindow)} context',
                                style: sans(11.5, color: AppColors.fg3)),
                        ]),
                  ),
                  Btn('Switch',
                      small: true,
                      variant: BtnVariant.surface,
                      onTap: widget.onModel),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  cell(widget.profileLabel, 'profile'),
                  const SizedBox(width: 4),
                  cell(prov == null || prov.isEmpty ? 'unknown' : prov,
                      'provider'),
                ]),
              ]);
        },
      );

  /// Two lines so the message reads; the first tap asks in place.
  Widget _checkpointRow(Checkpoint c, bool first, bool last) {
    final armed = _armedRewind == c.id;
    final t = DateTime.tryParse(c.createdAt);
    final r = Radius.circular(R.of(13));
    final sm = Radius.circular(R.of(5));
    return Padding(
      padding: EdgeInsets.fromLTRB(12, first ? 10 : 2, 12, 0),
      child: Material(
        color: armed ? AppColors.surface3 : Grouped.row,
        borderRadius:
            BorderRadius.vertical(top: first ? r : sm, bottom: last ? r : sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _set(() => _armedRewind = armed ? null : c.id),
          hoverColor: AppColors.fg1.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      AppIcon('history', size: 12, color: AppColors.fg4),
                      const SizedBox(width: 6),
                      Text(
                          t == null
                              ? ''
                              : relativeTime(t.millisecondsSinceEpoch ~/ 1000),
                          style: mono(11.5, color: AppColors.fg4)),
                    ]),
                    const SizedBox(height: 3),
                    Text(c.label.isEmpty ? c.id : c.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13, height: 1.4, color: AppColors.fg1)),
                    if (armed) ...[
                      const SizedBox(height: 8),
                      Text('Restore here? Files return to this point.',
                          style: sans(12, color: AppColors.fg3)),
                      const SizedBox(height: 8),
                      Row(children: [
                        const Spacer(),
                        Btn('Cancel',
                            small: true,
                            variant: BtnVariant.surface,
                            onTap: () => _set(() => _armedRewind = null)),
                        const SizedBox(width: 6),
                        Btn('Restore', small: true, onTap: () {
                          if (widget.onRewindNow != null) {
                            _go(null);
                            widget.onRewindNow!(c);
                          } else {
                            widget.onCheckpoints?.call();
                          }
                        }),
                      ]),
                    ],
                  ]),
            ),
          ),
        ),
      ),
    );
  }

  /// A label if the agent gave one, else the command without its `cd … &&` prefix.
  String _jobTitle(Map<String, dynamic> p) {
    final label = '${p['label'] ?? ''}'.trim();
    if (label.isNotEmpty) return label;
    var c = '${p['command'] ?? p['id'] ?? ''}'.replaceAll('\n', ' ').trim();
    final m = RegExp(r'^cd\s+\S+\s*(&&|;)\s*').firstMatch(c);
    if (m != null) c = c.substring(m.end);
    return c;
  }

  List<Widget> _wakesPage() {
    final list = [..._wakes]..sort((a, b) {
        if (a.enabled != b.enabled) return a.enabled ? -1 : 1;
        return a.nextRunAt.compareTo(b.nextRunAt);
      });
    final next = list
        .where((w) => w.enabled && w.nextRunAt > 0)
        .fold<WakeSchedule?>(
            null, (m, w) => m == null || w.nextRunAt < m.nextRunAt ? w : m);
    return [
      _subHeader('Wakes', meta: list.isEmpty ? null : '${list.length}'),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
              color: Grouped.row,
              borderRadius: BorderRadius.circular(R.of(13))),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Next wake', style: sans(11.5, color: AppColors.fg4)),
            const SizedBox(height: 4),
            if (!_wakeKnown)
              const SizedBox(height: 26)
            else if (next == null)
              Text('Nothing scheduled',
                  style: sans(17, weight: W.title, color: AppColors.fg2))
            else ...[
              Text.rich(TextSpan(children: [
                TextSpan(
                    text: _wakeWhen(next.nextRunAt),
                    style: mono(20, color: AppColors.fg1)),
                TextSpan(
                    text: '  ${_wakeIn(next.nextRunAt)}',
                    style: sans(12, color: AppColors.accent)),
              ])),
              const SizedBox(height: 2),
              Text(_wakeTitle(next),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12.5, color: AppColors.fg3)),
            ],
          ]),
        ),
      ),
      _groupLabel('Scheduled'),
      for (var i = 0; i < list.length; i++) _wakeRow(list[i], i == 0, false),
      _wakeAdd(first: list.isEmpty),
      _navGroup('Behaviour', [
        if (_autonomous != null && widget.onAutonomy != null)
          (f, l) => _navRow('activity', 'Automated wakes',
              value: _autonomous! ? 'On' : 'Off',
              first: f,
              last: l,
              onTap: widget.onAutonomy),
        if (_warm != null)
          (f, l) => _navRow('timer', 'Keep warm',
              first: f,
              last: l,
              trailing: SettingsSwitch(value: _warm!, onChanged: _setWarm),
              onTap: () => _setWarm(!_warm!)),
        (f, l) => _navRow('scheduled', 'All wakes',
            first: f, last: l, onTap: widget.onWakes),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Text(
            'Wakes run in this session with its history. A wake that finds nothing to do ends quietly.',
            style: sans(11.5, height: 1.45, color: AppColors.fg4)),
      ),
    ];
  }

  Widget _groupLabel(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
        child: Text(t, style: sans(12, color: AppColors.fg3)),
      );

  String _wakeTitle(WakeSchedule w) {
    final t = w.title.trim().isNotEmpty ? w.title.trim() : w.brief.trim();
    final line = t.split('\n').first;
    return line.isEmpty ? (w.name ?? 'Wake') : line;
  }

  String _wakeWhen(int at) {
    final d = DateTime.fromMillisecondsSinceEpoch(at * 1000);
    final n = DateTime.now();
    final hm =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (d.year == n.year && d.month == n.month && d.day == n.day) return hm;
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return d.difference(n).inDays < 6
        ? '${days[d.weekday - 1]} $hm'
        : '${d.day}/${d.month} $hm';
  }

  String _wakeIn(int at) {
    final m = (at * 1000 - DateTime.now().millisecondsSinceEpoch) ~/ 60000;
    if (m <= 0) return 'due';
    if (m < 60) return 'in ${m}m';
    if (m < 60 * 24) return 'in ${m ~/ 60}h ${m % 60}m';
    return 'in ${m ~/ (60 * 24)}d';
  }

  BorderRadius _rowRadius(bool first, bool last) {
    final r = Radius.circular(R.of(13));
    final s = Radius.circular(R.of(5));
    return BorderRadius.vertical(top: first ? r : s, bottom: last ? r : s);
  }

  Widget _wakeRow(WakeSchedule w, bool first, bool last) => Padding(
        padding: EdgeInsets.fromLTRB(12, first ? 0 : 2, 12, 0),
        child: Material(
          color: Grouped.row,
          borderRadius: _rowRadius(first, last),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onWakes,
            hoverColor: AppColors.fg1.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
              child: Row(children: [
                AppIcon('scheduled', size: 15, color: AppColors.fg3),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_wakeTitle(w),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(13,
                                color:
                                    w.enabled ? AppColors.fg1 : AppColors.fg3)),
                        Text(
                            [
                              if (w.enabled && w.nextRunAt > 0)
                                _wakeWhen(w.nextRunAt),
                              if (w.scheduleText.isNotEmpty) w.scheduleText,
                              if (!w.enabled) 'paused',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(11.5, color: AppColors.fg4)),
                      ]),
                ),
                const SizedBox(width: 8),
                SettingsSwitch(
                    value: w.enabled, onChanged: (on) => _toggleWake(w, on)),
              ]),
            ),
          ),
        ),
      );

  Future<void> _toggleWake(WakeSchedule w, bool on) async {
    final sessionId = widget.sessionId;
    try {
      final saved = await widget.client.setWake(
          w.owner, {'enabled': on, if (w.name != null) 'name': w.name});
      if (!mounted || widget.sessionId != sessionId) return;
      _set(() => _wakes = [
            for (final x in _wakes)
              x.owner == w.owner && x.name == w.name ? saved : x
          ]);
    } catch (e) {
      if (!mounted || widget.sessionId != sessionId) return;
      _set(() => _wakeError = '$e');
    }
  }

  Widget _wakeAdd({required bool first}) {
    Widget field(TextEditingController c, String hint, TextStyle st) =>
        TextField(
          controller: c,
          style: st,
          cursorColor: AppColors.accent,
          onChanged: (_) => _set(() => _wakeError = null),
          decoration: InputDecoration.collapsed(
              hintText: hint, hintStyle: st.copyWith(color: AppColors.fg4)),
        );
    final ready = _wakeBrief.text.trim().isNotEmpty &&
        _wakeSched.text.trim().isNotEmpty &&
        !_wakeSaving;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, first ? 0 : 2, 12, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
            color: Grouped.row, borderRadius: _rowRadius(first, true)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            AppIcon('plus', size: 14, color: AppColors.fg3),
            const SizedBox(width: 10),
            Expanded(
                child: field(_wakeBrief, 'What should it do?',
                    sans(13, color: AppColors.fg1))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                decoration: BoxDecoration(
                    color: AppColors.fg1.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(R.of(8))),
                child: field(_wakeSched, 'weekdays 09:00',
                    mono(12, color: AppColors.fg1)),
              ),
            ),
            const SizedBox(width: 8),
            Btn('Add wake',
                small: true, disabled: !ready, onTap: ready ? _addWake : null),
          ]),
          if (_wakeError != null) ...[
            const SizedBox(height: 6),
            Text(_wakeError!,
                style: sans(11.5, height: 1.4, color: AppColors.danger)),
          ],
        ]),
      ),
    );
  }

  Future<void> _addWake() async {
    final sessionId = widget.sessionId;
    _set(() {
      _wakeSaving = true;
      _wakeError = null;
    });
    // The owner's unnamed wake is its default; further ones need a name.
    final taken = _wakes.any((w) => w.name == null);
    try {
      final saved = await widget.client.setWake(sessionId, {
        if (taken)
          'name': 'wake-${DateTime.now().millisecondsSinceEpoch % 1000000}',
        'schedule': _wakeSched.text.trim(),
        'brief': _wakeBrief.text.trim(),
      });
      if (!mounted || widget.sessionId != sessionId) return;
      _wakeBrief.clear();
      _wakeSched.clear();
      _set(() {
        _wakes = [..._wakes, saved];
        if (saved.name == null) _wake = saved;
      });
    } catch (e) {
      if (!mounted || widget.sessionId != sessionId) return;
      final msg = '$e';
      _set(() => _wakeError =
          msg.replaceFirst(RegExp(r'^(Exception|ApiException):\s*'), ''));
    } finally {
      if (mounted && widget.sessionId == sessionId) {
        _set(() => _wakeSaving = false);
      }
    }
  }
}
