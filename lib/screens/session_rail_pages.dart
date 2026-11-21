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
          AppIcon('chevron-right', size: 14, color: AppColors.fg4),
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
                      sans(12, weight: FontWeight.w500, color: AppColors.fg3))),
          if (meta != null) Text(meta, style: sans(11.5, color: AppColors.fg4)),
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
        _page = page;
        _laneFilter = 0;
        _armedRewind = null;
      });

  /// One 48 px stepped-surface row: icon tile, label, quiet sub line, chevron.
  Widget _overviewRow(String icon, String label, String sub,
      {VoidCallback? onTap}) {
    return _RailCard(
      onTap: onTap,
      pad: const EdgeInsets.symmetric(horizontal: 10),
      radius: R.of(10),
      child: SizedBox(
        height: 48,
        child: Row(children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface3,
              borderRadius: BorderRadius.circular(R.of(8)),
            ),
            child: AppIcon(icon, size: 15, color: AppColors.fg2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, color: AppColors.fg1)),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(11.5, color: AppColors.fg4)),
                ]),
          ),
          const SizedBox(width: 6),
          AppIcon('chevron-right', size: 14, color: AppColors.fg4),
        ]),
      ),
    );
  }

  /// Desktop session panel, quiet by default: the goal and plan when there are
  /// any, the places to go, then usage and keep warm.
  List<Widget> _overviewRoot() {
    final s = widget.state;
    final w = widget;
    final plan = _SessionRailState._plan(s);
    final t = _tasks.where((t) => t.sessionId == widget.sessionId).firstOrNull;
    final goalOn = (s?.goal?.ongoing ?? false) || _editingGoal;
    final quiet = !w.floating && !goalOn && plan == null && t == null;
    return [
      if (w.floating)
        Container(
          height: 40,
          padding: const EdgeInsets.only(left: 4),
          child: Row(children: [
            Expanded(
                child: Text('Overview',
                    style: sans(13, weight: W.strong, color: AppColors.fg1))),
            if (w.floating)
              IconBtn('x',
                  size: 30,
                  iconSize: 15,
                  tooltip: 'Close',
                  onTap: () => sessionRailFloating.value = false),
          ]),
        ),
      if (goalOn) _goalCard(),
      if (t != null && w.onOpenTask != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _RailRow(
            icon: 'task',
            label: t.title,
            value: t.workPlan.isEmpty
                ? t.status.label
                : '${t.workPlan.where((p) => p.done).length} of ${t.workPlan.length}',
            chevron: true,
            onTap: () => w.onOpenTask!(t.id),
          ),
        ),
      if (plan != null)
        _card2('Plan', [Column(children: _planRows(plan))],
            meta:
                '${plan.where((p) => _SessionRailState._stepState(p) == 2).length} of ${plan.length} done'),
      if (quiet)
        SizedBox(
          height: (_bodyH - 6).clamp(320.0, double.infinity),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Center(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (w.agentId != null) ...[
                        Center(child: _quietMascot(w.agentId!)),
                        const SizedBox(height: 20),
                      ],
                      ..._places(),
                    ]),
              ),
            ),
          ]),
        )
      else ...[
        const SizedBox(height: 10),
        ..._places(),
      ],
      const SizedBox(height: 6),
    ];
  }

  /// The session's own mascot, greyed and still, above a quiet Overview.
  Widget _quietMascot(String agentId) => Opacity(
        opacity: 0.55,
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            0.2126,
            0.7152,
            0.0722,
            0,
            0,
            0.2126,
            0.7152,
            0.0722,
            0,
            0,
            0.2126,
            0.7152,
            0.0722,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
          ]),
          child: AgentMochi(agentId, size: 84),
        ),
      );

  List<Widget> _places() {
    final s = widget.state;
    final w = widget;
    final lanes = [...?s?.lanes];
    final running = lanes.where((l) => l.running).length;
    // The worktree is what the Changes view lists; session edits are a fallback.
    final git = _git;
    final changed = git != null && git.ok
        ? git.files.length
        : fileChanges(sessionChangeSteps(s?.events ?? const [])).length;
    final jobs = _procs.where((p) => p['running'] == true).length;
    final ws = (s?.workspace ?? '').trim();
    Widget gap() => const SizedBox(height: 6);
    return [
      if (w.onChanges != null) ...[
        _overviewRow(
            'file-diff',
            'Diffs',
            changed == 0
                ? 'No changes yet'
                : '$changed file${changed == 1 ? '' : 's'} changed',
            onTap: () => _go('changes')),
        gap(),
      ],
      if (w.onFiles != null) ...[
        _overviewRow(
            'folder',
            'Files',
            ws.isEmpty
                ? 'Browse the workspace'
                : lastPathSegment(ws, ifEmpty: ws),
            onTap: () => _go('files')),
        gap(),
      ],
      if (w.onShell != null) ...[
        _overviewRow('terminal', 'Shell', 'Terminal in the workspace',
            onTap: w.onShell),
        gap(),
      ],
      if (w.onProcesses != null) ...[
        _overviewRow(
            'activity',
            'Activity',
            jobs > 0
                ? '$jobs job${jobs == 1 ? '' : 's'} running'
                : 'No background jobs',
            onTap: () => _go('jobs')),
        gap(),
      ],
      if (w.onLanes != null)
        _overviewRow(
            'git-branch',
            'Lanes',
            lanes.isEmpty
                ? 'None yet'
                : running > 0
                    ? '$running running · ${lanes.length}'
                    : '${lanes.length} finished',
            onTap: () => _go('lanes')),
    ];
  }

  Widget _subHeader(String title, {String? meta}) => Container(
        height: 40,
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
        child: Row(children: [
          IconBtn('chevron-left',
              size: 30, iconSize: 15, tooltip: 'Back', onTap: () => _go(null)),
          const SizedBox(width: 4),
          Text(title, style: sans(13, weight: W.strong, color: AppColors.fg1)),
          if (meta != null) ...[
            const SizedBox(width: 8),
            Text(meta, style: mono(12, color: AppColors.fg4)),
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
                AppIcon('chevron-right', size: 12, color: AppColors.fg4),
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
    try {
      final saved = await widget.client.setWake(
          w.owner, {'enabled': on, if (w.name != null) 'name': w.name});
      _set(() => _wakes = [
            for (final x in _wakes)
              x.owner == w.owner && x.name == w.name ? saved : x
          ]);
    } catch (e) {
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
    _set(() {
      _wakeSaving = true;
      _wakeError = null;
    });
    // The owner's unnamed wake is its default; further ones need a name.
    final taken = _wakes.any((w) => w.name == null);
    try {
      final saved = await widget.client.setWake(widget.sessionId, {
        if (taken)
          'name': 'wake-${DateTime.now().millisecondsSinceEpoch % 1000000}',
        'schedule': _wakeSched.text.trim(),
        'brief': _wakeBrief.text.trim(),
      });
      _wakeBrief.clear();
      _wakeSched.clear();
      _set(() {
        _wakes = [..._wakes, saved];
        if (saved.name == null) _wake = saved;
      });
    } catch (e) {
      final msg = '$e';
      _set(() => _wakeError =
          msg.replaceFirst(RegExp(r'^(Exception|ApiException):\s*'), ''));
    } finally {
      _set(() => _wakeSaving = false);
    }
  }
}
