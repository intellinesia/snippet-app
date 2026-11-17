part of 'session_rail.dart';

/// Desktop drill-in panel: a root of grouped rows and one page per area.
extension _RailPages on _SessionRailState {
  Widget _navRow(String icon, String label,
      {String? value,
      bool hot = false,
      Widget? trailing,
      Widget? leading,
      VoidCallback? onTap,
      bool first = false,
      bool last = false}) {
    final r = Radius.circular(R.of(13));
    final s = Radius.circular(R.of(5));
    return Material(
      color: Grouped.row,
      borderRadius:
          BorderRadius.vertical(top: first ? r : s, bottom: last ? r : s),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.fg1.withValues(alpha: 0.04),
        child: SizedBox(
          height: 42,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              leading ?? AppIcon(icon, size: 16, color: AppColors.fg3),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, color: AppColors.fg1)),
              ),
              if (value != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  flex: 0,
                  child: Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(12,
                          color: hot ? AppColors.accent : AppColors.fg3,
                          tabular: true)),
                ),
              ],
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing,
              ] else if (onTap != null) ...[
                const SizedBox(width: 8),
                AppIcon('chevron-right', size: 12, color: AppColors.fg4),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  /// Rows as one group: 2px gaps, rounded only at the ends.
  Widget _navGroup(String? title, List<Widget Function(bool, bool)> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
            child: Text(title, style: sans(12, color: AppColors.fg3)),
          ),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          rows[i](i == 0, i == rows.length - 1),
        ],
      ]),
    );
  }

  Widget _card2(String? title, List<Widget> children, {String? meta}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
              child: Row(children: [
                Expanded(
                    child: Text(title, style: sans(12, color: AppColors.fg3))),
                if (meta != null)
                  Text(meta, style: sans(11.5, color: AppColors.fg4)),
              ]),
            ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Grouped.row,
                borderRadius: BorderRadius.circular(R.of(13))),
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

  /// The root page: the goal, the actions, then every area one tap away.
  List<Widget> _desktopRoot(List<Widget> head) {
    final s = widget.state;
    final w = widget;
    final lanes = [...?s?.lanes];
    final running = lanes.where((l) => l.running).length;
    final files = fileChanges(sessionChangeSteps(s?.events ?? const []));
    final cps = s?.checkpoints.length ?? 0;
    final jobs = _procs.where((p) => p['running'] == true).length;
    final ctx = _contextPct(s);
    final wake = _wake;
    final plan = _SessionRailState._plan(s);
    final provider = widget.providers[widget.ownProfile] ??
        widget.providers[widget.profileLabel];
    return [
      ...head,
      if (plan != null)
        _card2('Plan', [Column(children: _planRows(plan))],
            meta:
                '${plan.where((p) => _SessionRailState._stepState(p) == 2).length} of ${plan.length} done'),
      _navGroup('Work', [
        if (lanes.isNotEmpty || w.onLanes != null)
          (f, l) => _navRow('git-branch', 'Lanes',
              value: lanes.isEmpty
                  ? null
                  : running > 0
                      ? '$running running · ${lanes.length}'
                      : '${lanes.length}',
              hot: running > 0,
              first: f,
              last: l,
              onTap: () => _go('lanes')),
        if (w.onProcesses != null)
          (f, l) => _navRow('activity', 'Jobs',
              value: jobs > 0 ? '$jobs running' : null,
              hot: jobs > 0,
              first: f,
              last: l,
              onTap: () => _go('jobs')),
        if (w.onChanges != null)
          (f, l) => _navRow('file-diff', 'Changes',
              value: files.isEmpty
                  ? null
                  : '${files.length} file${files.length == 1 ? '' : 's'}',
              first: f,
              last: l,
              onTap: w.onChanges),
        if (w.onCheckpoints != null)
          (f, l) => _navRow('history', 'Checkpoints',
              value: cps == 0 ? null : '$cps',
              first: f,
              last: l,
              onTap: () => _go('checkpoints')),
      ]),
      _navGroup('Without you', [
        (f, l) => _navRow('scheduled', 'Wakes',
            value: !_wakeKnown
                ? null
                : wake == null
                    ? 'None'
                    : _nextWakeText(wake),
            first: f,
            last: l,
            onTap: () => _go('wakes')),
        if (_warm != null)
          (f, l) => _navRow('timer', 'Keep warm',
              first: f,
              last: l,
              trailing: SettingsSwitch(value: _warm!, onChanged: _setWarm),
              onTap: () => _setWarm(!_warm!)),
      ]),
      _navGroup('Context', [
        if (s != null)
          (f, l) => _navRow('gauge', 'Usage',
              leading: provider == null
                  ? null
                  : SizedBox.square(
                      dimension: 16, child: ProviderLogo(provider, size: 16)),
              value: ctx == null
                  ? w.profileLabel
                  : '${w.profileLabel} · ${ctx.round()}%',
              first: f,
              last: l,
              onTap: () => _go('usage')),
        if (w.onMemory != null)
          (f, l) =>
              _navRow('brain', 'Memory', first: f, last: l, onTap: w.onMemory),
        if (w.onDeliverables != null)
          (f, l) => _navRow('folder', 'Shared files',
              first: f, last: l, onTap: w.onDeliverables),
      ]),
      const SizedBox(height: 6),
    ];
  }

  Widget _subHeader(String title, {String? meta}) => Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line))),
        child: Row(children: [
          IconBtn('chevron-left',
              size: 30, iconSize: 15, tooltip: 'Back', onTap: () => _go(null)),
          const SizedBox(width: 4),
          Text(title, style: sans(13, weight: W.label, color: AppColors.fg1)),
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
                tab(2, 'Finished', done.length),
              ]),
            ),
          ),
          if (lanes.isEmpty) _empty('No lanes yet.'),
          if (_laneFilter != 2) group('Running', run),
          if (_laneFilter != 1) group('Finished', done),
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
        final wake = _wake;
        return [
          _subHeader('Wakes'),
          _card2(
              'Next wake',
              [
                Text(
                    !_wakeKnown
                        ? ''
                        : wake == null
                            ? 'No wake scheduled'
                            : _nextWakeText(wake),
                    style: sans(17, color: AppColors.fg1)),
                if (wake != null && wake.scheduleText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(wake.scheduleText,
                      style: sans(12, color: AppColors.fg3)),
                ],
              ],
              meta: wake == null
                  ? null
                  : wake.enabled
                      ? 'On'
                      : 'Paused'),
          _navGroup(null, [
            (f, l) => _navRow('scheduled', 'Manage wakes',
                first: f, last: l, onTap: widget.onWakes),
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
          ]),
          const SizedBox(height: 6),
        ];
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
                                      : 'Finished',
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
}
