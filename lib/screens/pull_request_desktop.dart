part of 'pull_request_detail.dart';

const _prFilters = [
  ('open', 'Open'),
  ('review', 'Needs review'),
  ('mine', 'Mine'),
  ('closed', 'Closed'),
];

(String, Color) _prStateIcon(PrSummary pr) => switch (pr.state) {
      'MERGED' => ('git-commit', AppColors.accent),
      'CLOSED' => ('x-circle', AppColors.danger),
      _ =>
        pr.draft ? ('git-branch', AppColors.fg4) : ('git-branch', AppColors.ok),
    };

Color get _prTitleInk => Color.lerp(AppColors.fg1, AppColors.fg2, 0.3)!;

Widget _prDot(Color c, {double size = 7}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );

class PrListPanel extends StatefulWidget {
  const PrListPanel({
    super.key,
    required this.client,
    required this.session,
    required this.status,
    required this.selected,
    required this.onSelect,
    this.showTitle = true,
    this.onLoaded,
    this.refreshTick,
  });

  final DaemonClient client;
  final String session;
  final GithubStatus status;
  final int? selected;
  final ValueChanged<int> onSelect;
  final bool showTitle;
  final ValueChanged<List<PrSummary>>? onLoaded;
  final int? refreshTick;

  @override
  State<PrListPanel> createState() => _PrListPanelState();
}

class _PrListPanelState extends State<PrListPanel> {
  String _filter = 'open';
  List<PrSummary>? _prs;
  String? _next;
  bool _loadingMore = false;
  String? _error;
  String _query = '';
  int _loadGen = 0;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PrListPanel old) {
    super.didUpdateWidget(old);
    if (old.refreshTick != widget.refreshTick || old.session != widget.session) {
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final filter = _filter;
    final session = widget.session;
    final gen = ++_loadGen;
    try {
      final page = await widget.client.githubPrPage(widget.session, filter);
      if (!mounted ||
          gen != _loadGen ||
          filter != _filter ||
          session != widget.session) {
        return;
      }
      setState(() {
        _prs = page.prs;
        _next = page.next;
      });
      widget.onLoaded?.call(page.prs);
    } catch (e) {
      if (mounted &&
          gen == _loadGen &&
          filter == _filter &&
          session == widget.session) {
        setState(() => _error = '$e');
      }
    }
  }

  Future<void> _loadMore() async {
    final cursor = _next;
    if (cursor == null || _loadingMore) return;
    final filter = _filter;
    final gen = _loadGen;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.client
          .githubPrPage(widget.session, filter, cursor: cursor);
      if (!mounted || gen != _loadGen || filter != _filter) return;
      setState(() {
        _prs = appendPrs(_prs, page.prs);
        _next = page.next;
      });
      widget.onLoaded?.call(_prs!);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _pick(String key) {
    if (key == _filter) return;
    setState(() {
      _filter = key;
      _prs = null;
      _next = null;
    });
    _load();
  }

  List<PrSummary> get _visible {
    final q = _query.trim().toLowerCase();
    final prs = _prs ?? const <PrSummary>[];
    if (q.isEmpty) return prs;
    return prs
        .where((p) =>
            p.title.toLowerCase().contains(q) ||
            '#${p.number}'.contains(q) ||
            p.author.toLowerCase().contains(q) ||
            p.head.toLowerCase().contains(q))
        .toList();
  }

  Widget _filterBar() => Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: SizedBox(
          height: PaneRow.pill,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _prFilters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 2),
            itemBuilder: (_, i) {
              final (key, label) = _prFilters[i];
              final on = _filter == key;
              return TapDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _pick(key),
                child: Container(
                  height: PaneRow.pill,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on ? PaneRow.plate : null,
                    borderRadius: BorderRadius.circular(PaneRow.radius),
                  ),
                  child: Text(label,
                      maxLines: 1,
                      style: sans(PaneRow.label,
                          color: on ? PaneRow.labelOn : PaneRow.labelOff)),
                ),
              );
            },
          ),
        ),
      );

  Widget _row(PrSummary pr) {
    final selected = pr.number == widget.selected;
    final (icon, ink) = _prStateIcon(pr);
    final meta = <InlineSpan>[
      TextSpan(text: '#${pr.number} · ${pr.author} · ${prAgo(pr.updatedAt)}'),
    ];
    void state(String label, Color tone) {
      meta.add(TextSpan(
          text: ' · $label',
          style: sans(12, color: tone.withValues(alpha: 0.9))));
    }

    switch (rollup(pr.checks)) {
      case ChecksState.passing:
        state('checks passed', AppColors.ok);
      case ChecksState.failing:
        state('checks failing', AppColors.danger);
      case ChecksState.pending:
        state('checks running', AppColors.run);
      case ChecksState.none:
    }
    switch (pr.reviewDecision) {
      case 'APPROVED':
        state('approved', AppColors.ok);
      case 'CHANGES_REQUESTED':
        state('changes requested', AppColors.danger);
    }
    final titleInk = Color.lerp(AppColors.fg1, AppColors.fg2, 0.3)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
      child: Material(
        color: selected ? PaneRow.plate : Colors.transparent,
        borderRadius: BorderRadius.circular(PaneRow.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(PaneRow.radius),
          hoverColor: AppColors.hoverPlate,
          onTap: () => widget.onSelect(pr.number),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: AppIcon(icon, size: 14, color: ink),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pr.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(13, color: titleInk)),
                      const SizedBox(height: 3),
                      Text.rich(
                        TextSpan(
                            style: sans(12, color: AppColors.fg4),
                            children: meta),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 16, 6),
        child: Text(text, style: sans(11.5, color: AppColors.fg4)),
      );

  Widget _group(List<PrSummary> list) =>
      Column(children: [for (final p in list) _row(p)]);

  List<Widget> _rows(List<PrSummary> prs) {
    if (_filter != 'open' || _query.trim().isNotEmpty) return [_group(prs)];
    final me = widget.status.viewer;
    final review =
        prs.where((p) => p.author != me && p.reviewers.contains(me)).toList();
    final mine = prs.where((p) => p.author == me).toList();
    final others =
        prs.where((p) => !review.contains(p) && !mine.contains(p)).toList();
    final groups = [
      ('Needs your review', review),
      ('Yours', mine),
      ('Others', others),
    ].where((g) => g.$2.isNotEmpty).toList();
    if (groups.length == 1) return [_group(prs)];
    return [
      for (final (label, list) in groups) ...[
        _label(label),
        _group(list),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final prs = _prs;
    final visible = _visible;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.showTitle)
        Container(
          height: PaneRow.height,
          padding: const EdgeInsets.fromLTRB(10, 0, 8, 0),
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.paneLine, width: AppColors.hairline))),
          child: Row(children: [
            AppIcon('pull-request', size: PaneRow.icon, color: AppColors.fg3),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Pull requests',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(PaneRow.label,
                      weight: W.label, color: PaneRow.labelOn)),
            ),
            IconBtn('refresh',
                size: 28, iconSize: 13, tooltip: 'Refresh', onTap: _load),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(R.of(8)),
          ),
          child: Row(children: [
            AppIcon('search', size: 13, color: AppColors.fg4),
            SizedBox(width: S.s8),
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                style: sans(13, color: AppColors.fg1),
                cursorColor: AppColors.accent,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Filter by title, number, author',
                  hintStyle: sans(13, color: AppColors.fg4),
                ),
              ),
            ),
          ]),
        ),
      ),
      _filterBar(),
      Expanded(
        child: _error != null
            ? prMessage(_error!)
            : prs == null
                ? Center(child: Spinner(size: 16, color: AppColors.fg3))
                : visible.isEmpty
                    ? prMessage(_query.trim().isNotEmpty
                        ? 'Nothing matches.'
                        : switch (_filter) {
                            'review' => 'Nothing waiting on your review.',
                            'mine' => 'You have no open pull requests.',
                            'closed' => 'No closed pull requests.',
                            _ => 'No open pull requests.',
                          })
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (n) => prNearEnd(n, _loadMore),
                          child: ListView(
                            padding: EdgeInsets.only(bottom: S.s16),
                            children: [
                              ..._rows(visible),
                              if (_next != null)
                                prLoadMore(_loadingMore, _loadMore),
                            ],
                          ),
                        ),
                      ),
      ),
    ]);
  }
}

class PrSidebarList extends StatefulWidget {
  const PrSidebarList({
    super.key,
    required this.client,
    required this.session,
    required this.onOpen,
  });

  final DaemonClient client;
  final String session;
  final ValueChanged<int> onOpen;

  @override
  State<PrSidebarList> createState() => _PrSidebarListState();
}

class _PrSidebarListState extends State<PrSidebarList> {
  GithubStatus? _status;
  bool _checked = false;
  int? _selected;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(PrSidebarList old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      setState(() {
        _status = null;
        _checked = false;
        _selected = null;
      });
      _check();
    }
  }

  Future<void> _check() async {
    final session = widget.session;
    final status = await widget.client.githubStatus(session);
    if (!mounted || session != widget.session) return;
    setState(() {
      _status = status != null && status.available ? status : null;
      _checked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (!_checked) {
      return Center(child: Spinner(size: 16, color: AppColors.fg3));
    }
    if (status == null) {
      return prMessage(
          'Pull requests need the GitHub CLI installed and signed in, in a GitHub repository.');
    }
    return PrListPanel(
      client: widget.client,
      session: widget.session,
      status: status,
      selected: _selected,
      showTitle: false,
      onSelect: (n) {
        setState(() => _selected = n);
        widget.onOpen(n);
      },
    );
  }
}

class DesktopPrDetailScreen extends StatelessWidget {
  const DesktopPrDetailScreen({
    super.key,
    required this.client,
    required this.session,
    required this.number,
    required this.status,
  });

  final DaemonClient client;
  final String session;
  final int number;
  final GithubStatus status;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.paneBg,
        child: _DesktopPrDetail(
          client: client,
          session: session,
          number: number,
          status: status,
          listHidden: false,
          onToggleList: null,
          onChanged: () async {},
        ),
      );
}

class DesktopPullRequests extends StatefulWidget {
  const DesktopPullRequests({
    super.key,
    required this.client,
    required this.session,
    required this.status,
    this.openNumber,
  });

  final DaemonClient client;
  final String session;
  final GithubStatus status;
  final int? openNumber;

  @override
  State<DesktopPullRequests> createState() => _DesktopPullRequestsState();
}

class _DesktopPullRequestsState extends State<DesktopPullRequests> {
  int? _selected;
  bool _listHidden = false;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _selected = widget.openNumber;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final list = ColoredBox(
      color: AppColors.bg,
      child: PrListPanel(
        client: widget.client,
        session: widget.session,
        status: widget.status,
        selected: selected,
        refreshTick: _tick,
        onSelect: (n) => setState(() => _selected = n),
      ),
    );
    return Material(
      color: AppColors.paneBg,
      child: LayoutBuilder(builder: (context, box) {
        final narrow = box.maxWidth < 760;
        final showList = !_listHidden && (!narrow || selected == null);
        final detail = selected == null
            ? const TaskEmptyNote(
                title: 'Select a pull request', art: EmptyArtKind.search)
            : _DesktopPrDetail(
                key: ValueKey('pr-$selected'),
                client: widget.client,
                session: widget.session,
                number: selected,
                status: widget.status,
                listHidden: !showList,
                onToggleList: () => setState(() {
                  if (narrow) {
                    _selected = null;
                  } else {
                    _listHidden = !_listHidden;
                  }
                }),
                onChanged: () async => setState(() => _tick++),
              );
        if (narrow) return showList ? list : detail;
        // The Tasks layout: the list takes the room, the selected pull
        // request sits in a pane on the right; hiding the list widens it.
        final paneW = (box.maxWidth * 0.5).clamp(480.0, 760.0).toDouble();
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (showList) ...[
            Expanded(child: list),
            Container(width: AppColors.hairline, color: AppColors.paneLine),
            SizedBox(width: paneW, child: detail),
          ] else
            Expanded(child: detail),
        ]);
      }),
    );
  }
}

class _DesktopPrDetail extends StatefulWidget {
  const _DesktopPrDetail({
    super.key,
    required this.client,
    required this.session,
    required this.number,
    required this.status,
    required this.listHidden,
    required this.onToggleList,
    required this.onChanged,
  });

  final DaemonClient client;
  final String session;
  final int number;
  final GithubStatus status;
  final bool listHidden;
  final VoidCallback? onToggleList;
  final Future<void> Function() onChanged;

  @override
  State<_DesktopPrDetail> createState() => _DesktopPrDetailState();
}

class _DesktopPrDetailState extends State<_DesktopPrDetail> {
  PrDetail? _pr;
  String? _diff;
  bool _diffFailed = false;
  String? _diffOid;
  String? _error;
  bool _busy = false;
  int _tab = 0;
  String? _scrollTo;
  final _comment = TextEditingController();

  String get _key =>
      '${widget.client.baseUrl}|${widget.session}|${widget.number}';
  List<PendingComment> get _pending => _pendingByPr.putIfAbsent(_key, () => []);
  Set<String> get _viewed => _viewedByPr.putIfAbsent(_key, () => {});
  bool get _open => _pr?.summary.state == 'OPEN';
  bool get _isAuthor => _pr?.summary.author == widget.status.viewer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _loadDiff() async {
    try {
      final diff =
          await widget.client.githubPrDiff(widget.session, widget.number);
      if (mounted) {
        setState(() {
          _diff = diff;
          _diffFailed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _diffFailed = true);
    }
  }

  Future<void> _load() async {
    if (_diffOid == null && _diff == null) _loadDiff();
    try {
      final pr = await widget.client.githubPr(widget.session, widget.number);
      if (!mounted) return;
      if (_diffOid != null && _diffOid != pr.headOid) _loadDiff();
      setState(() {
        _diffOid = pr.headOid;
        _pr = pr;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _reload() async {
    await _load();
    await widget.onChanged();
  }

  Future<void> _postComment() async {
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.client.commentOnPr(widget.session, widget.number, text);
      _comment.clear();
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review() async {
    final submitted = await submitPrReviewFlow(context,
        client: widget.client,
        session: widget.session,
        number: widget.number,
        pending: _pending,
        isAuthor: _isAuthor);
    if (submitted && mounted) {
      setState(() {});
      await _reload();
    }
  }

  Future<void> _menu(BuildContext anchor) async {
    final s = _pr!.summary;
    final open = s.state == 'OPEN';
    final action = await showAppMenu<String>(
      context,
      anchor: anchor,
      minWidth: 230,
      items: [
        if (open && !s.draft)
          appMenuRow<String>(
              value: 'draft', icon: 'git-branch', label: 'Convert to draft'),
        if (open && s.draft)
          appMenuRow<String>(
              value: 'ready', icon: 'eye', label: 'Ready for review'),
        if (open)
          appMenuRow<String>(
              value: 'close', icon: 'x-circle', label: 'Close pull request'),
        if (s.state == 'CLOSED')
          appMenuRow<String>(
              value: 'reopen', icon: 'refresh', label: 'Reopen pull request'),
        appMenuRow<String>(value: 'copy', icon: 'copy', label: 'Copy link'),
        appMenuRow<String>(
            value: 'github', icon: 'globe', label: 'Open on GitHub'),
      ],
    );
    if (action == null || !mounted) return;
    if (action == 'github') {
      launchUrl(Uri.parse(s.url), mode: LaunchMode.externalApplication);
      return;
    }
    if (action == 'copy') {
      Clipboard.setData(ClipboardData(text: s.url));
      toast(context, 'Link copied');
      return;
    }
    if (action == 'close') {
      final ok = await confirmAction(context,
          title: 'Close #${s.number}?',
          body: 'It can be reopened later; the branch stays.',
          confirmLabel: 'Close pull request');
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await widget.client.prState(widget.session, widget.number, action);
      await _reload();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showFiles(String? path) => setState(() {
        _tab = 2;
        _scrollTo = path;
      });

  Widget _header(PrDetail pr) {
    final s = pr.summary;
    final pending = _pending.length;
    final titleInk = Color.lerp(AppColors.fg1, AppColors.fg2, 0.3)!;
    final (stateLabel, stateInk) = switch (s.state) {
      'MERGED' => ('Merged', AppColors.accent),
      'CLOSED' => ('Closed', AppColors.danger),
      _ => s.draft ? ('Draft', AppColors.fg3) : ('Open', AppColors.ok),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: PaneRow.height,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.paneLine, width: AppColors.hairline))),
        child: Row(children: [
          if (widget.listHidden && widget.onToggleList != null) ...[
            IconBtn('sidebar',
                size: 28,
                iconSize: 13,
                tooltip: 'Show list',
                onTap: widget.onToggleList),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: s.title,
                        style: sans(13, weight: W.label, color: titleInk)),
                    TextSpan(
                        text: '  #${s.number}',
                        style: sans(12, color: AppColors.fg4)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: stateLabel,
                        style: sans(12, weight: W.label, color: stateInk)),
                    TextSpan(
                        text:
                            ' · ${s.author} · ${s.head} → ${s.base} · opened ${prAgo(pr.createdAt)}',
                        style: sans(12, color: AppColors.fg4)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (_open) ...[
            Btn(pending == 0 ? 'Review' : 'Finish review ($pending)',
                small: true,
                variant: BtnVariant.surface,
                disabled: _busy,
                onTap: _review),
            const SizedBox(width: 4),
          ],
          Builder(
            builder: (anchor) => IconBtn('more-horizontal',
                size: 28,
                iconSize: 13,
                tooltip: 'More',
                onTap: _busy ? null : () => _menu(anchor)),
          ),
          if (!widget.listHidden && widget.onToggleList != null)
            IconBtn('sidebar',
                size: 28,
                iconSize: 13,
                tooltip: 'Hide list',
                onTap: widget.onToggleList),
        ]),
      ),
      Container(
        height: PaneRow.height,
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.paneLine, width: AppColors.hairline))),
        child: LayoutBuilder(builder: (context, box) {
          final conversation = pr.timeline
              .where((e) => e.kind != PrEventKind.commit)
              .length;
          String tabLabel(String label, int count) =>
              count > 0 ? '$label $count' : label;
          return Row(children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  PanePill(
                      icon: 'message',
                      label: tabLabel('Conversation', conversation),
                      active: _tab == 0,
                      onTap: () => setState(() {
                            _tab = 0;
                            _scrollTo = null;
                          })),
                  const SizedBox(width: 2),
                  PanePill(
                      icon: 'git-commit',
                      label: tabLabel('Commits', pr.commits.length),
                      active: _tab == 1,
                      onTap: () => setState(() {
                            _tab = 1;
                            _scrollTo = null;
                          })),
                  const SizedBox(width: 2),
                  PanePill(
                      icon: 'file-diff',
                      label: tabLabel('Files changed', pr.files.length),
                      active: _tab == 2,
                      onTap: () => setState(() {
                            _tab = 2;
                            _scrollTo = null;
                          })),
                ]),
              ),
            ),
            if (box.maxWidth >= 520) ...[
              const SizedBox(width: 8),
              prSize(s.additions, s.deletions, size: 12),
            ],
          ]);
        }),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final pr = _pr;
    if (_error != null) return prMessage(_error!);
    if (pr == null) {
      return Center(child: Spinner(size: 16, color: AppColors.fg3));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(pr),
      Expanded(
        child: switch (_tab) {
          1 => _DesktopCommits(
              client: widget.client,
              session: widget.session,
              commits: pr.commits),
          2 when _diffFailed && _diff == null =>
            prMessage("Couldn't load the diff for this pull request."),
          2 when _diff == null =>
            Center(child: Spinner(size: 16, color: AppColors.fg3)),
          2 => _DesktopFiles(
              key: ValueKey('files-$_scrollTo'),
              client: widget.client,
              session: widget.session,
              number: widget.number,
              pr: pr,
              diff: _diff!,
              pending: _pending,
              viewed: _viewed,
              canComment: _open,
              onChanged: () async {
                await _load();
              },
              onPendingChanged: () => setState(() {}),
              scrollTo: _scrollTo,
            ),
          _ => _conversation(pr),
        },
      ),
    ]);
  }

  Widget _conversation(PrDetail pr) {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 980;
      final side = _sidebar(pr);
      final main =
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!wide) ...[
          side,
          SizedBox(height: S.s20),
          _sideTitle('Conversation'),
        ],
        _event(
          avatar: pr.summary.author,
          header: Text.rich(TextSpan(children: [
            TextSpan(
                text: pr.summary.author,
                style: sans(13, weight: W.label, color: _prTitleInk)),
            TextSpan(
                text: '  opened ${prAgo(pr.createdAt)}',
                style: TS.meta(AppColors.fg4)),
          ])),
          body: pr.body.trim().isEmpty
              ? Text('No description provided.', style: TS.meta(AppColors.fg4))
              : PrCommentBody(pr.body),
          card: true,
        ),
        ..._timeline(pr),
        SizedBox(height: S.of(14)),
        if (_open || pr.summary.state == 'CLOSED')
          Padding(
            padding: EdgeInsets.only(left: S.of(44)),
            child: PrMarkdownComposer(
              controller: _comment,
              minLines: 3,
              hint: 'Add a comment',
              onChanged: () => setState(() {}),
              footer: Row(children: [
                Text('Markdown supported', style: TS.meta(AppColors.fg4)),
                const Spacer(),
                Btn('Comment',
                    small: true,
                    variant: BtnVariant.surface,
                    disabled: _busy || _comment.text.trim().isEmpty,
                    onTap: _postComment),
              ]),
            ),
          ),
      ]);
      return RefreshIndicator(
        onRefresh: _reload,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(S.s20, S.of(18), S.s20, S.s40),
          child: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: main),
                  SizedBox(width: S.of(28)),
                  SizedBox(width: 280, child: side),
                ])
              : main,
        ),
      );
    });
  }

  Widget _event({
    String? avatar,
    String? icon,
    Color? ink,
    required Widget header,
    Widget? body,
    bool card = false,
    bool line = true,
  }) {
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 32,
          child: Stack(alignment: Alignment.topCenter, children: [
            if (line)
              Positioned.fill(
                child: Center(
                    child: Container(width: AppColors.hairline, color: AppColors.paneLine)),
              ),
            Padding(
              padding: EdgeInsets.only(top: S.s2),
              child: avatar != null
                  ? prAvatar(avatar, size: 28)
                  : Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: AppColors.tint2, shape: BoxShape.circle),
                      child: AppIcon(icon ?? 'git-commit',
                          size: 12, color: ink ?? AppColors.fg3),
                    ),
            ),
          ]),
        ),
        SizedBox(width: S.s12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: S.of(18)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: EdgeInsets.only(top: S.s6), child: header),
              if (body != null) ...[
                SizedBox(height: S.s8),
                card
                    ? Container(
                        width: double.infinity,
                        padding: EdgeInsets.fromLTRB(
                            S.of(14), S.s12, S.of(14), S.s12),
                        decoration: BoxDecoration(
                          color: Grouped.card,
                          borderRadius: BorderRadius.circular(R.of(9)),
                          border: Border.all(color: Grouped.cardBorder),
                        ),
                        child: body,
                      )
                    : body,
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  List<Widget> _timeline(PrDetail pr) {
    final threadsByReview = <String, List<PrThread>>{};
    for (final t in pr.threads) {
      final id = t.comments.isEmpty ? '' : t.comments.first.reviewId;
      if (id.isNotEmpty) threadsByReview.putIfAbsent(id, () => []).add(t);
    }
    final out = <Widget>[];
    for (final e in pr.timeline) {
      switch (e.kind) {
        case PrEventKind.commit:
          out.add(_event(
            icon: 'git-commit',
            header: Row(children: [
              Expanded(
                child: Text(e.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, color: AppColors.fg2)),
              ),
              SizedBox(width: S.of(10)),
              Text(e.sha.length > 7 ? e.sha.substring(0, 7) : e.sha,
                  style: mono(12, color: AppColors.fg4)),
            ]),
          ));
        case PrEventKind.review:
          final (verb, icon, ink) = switch (e.reviewState) {
            'APPROVED' => (
                'approved these changes',
                'check-circle',
                AppColors.ok
              ),
            'CHANGES_REQUESTED' => (
                'requested changes',
                'alert-circle',
                AppColors.danger
              ),
            'DISMISSED' => (
                'had a review dismissed',
                'x-circle',
                AppColors.fg4
              ),
            _ => ('reviewed', 'eye', AppColors.fg3),
          };
          final threads = threadsByReview[e.reviewId] ?? const [];
          out.add(_event(
            icon: icon,
            ink: ink,
            header: Text.rich(TextSpan(children: [
              TextSpan(
                  text: e.author,
                  style: sans(13, weight: W.label, color: _prTitleInk)),
              TextSpan(text: ' $verb', style: sans(13, color: AppColors.fg2)),
              TextSpan(text: '  ${prAgo(e.at)}', style: TS.meta(AppColors.fg4)),
            ])),
            body: e.body.trim().isEmpty && threads.isEmpty
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        if (e.body.trim().isNotEmpty)
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.fromLTRB(
                                S.of(14), S.s12, S.of(14), S.s12),
                            margin: EdgeInsets.only(
                                bottom: threads.isEmpty ? 0 : S.s8),
                            decoration: BoxDecoration(
                              color: Grouped.card,
                              borderRadius: BorderRadius.circular(R.of(9)),
                              border: Border.all(color: Grouped.cardBorder),
                            ),
                            child: PrCommentBody(e.body),
                          ),
                        if (threads.isNotEmpty)
                          TextButton.icon(
                            onPressed: () => _showFiles(threads.first.path),
                            style: TextButton.styleFrom(
                              padding:
                                  EdgeInsets.symmetric(horizontal: S.of(10)),
                              minimumSize: const Size(0, 30),
                              backgroundColor: Grouped.card,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(R.sm)),
                            ),
                            icon: AppIcon('message',
                                size: 13, color: AppColors.accent),
                            label: Text(
                                '${threads.length} comment${threads.length == 1 ? '' : 's'} on ${threads.map((t) => t.path.split('/').last).toSet().join(', ')}',
                                style: sans(12,
                                    weight: W.label, color: AppColors.fg2)),
                          ),
                      ]),
          ));
        case PrEventKind.comment:
          out.add(_event(
            avatar: e.author,
            header: Text.rich(TextSpan(children: [
              TextSpan(
                  text: e.author,
                  style: sans(13, weight: W.label, color: _prTitleInk)),
              TextSpan(
                  text: '  commented ${prAgo(e.at)}',
                  style: TS.meta(AppColors.fg4)),
            ])),
            body: PrCommentBody(e.body),
            card: true,
          ));
      }
    }
    return out;
  }

  Widget _sideTitle(String text) => Padding(
        padding: EdgeInsets.only(bottom: S.s8),
        child:
            Text(text, style: sans(12, weight: W.label, color: AppColors.fg3)),
      );

  Widget _sideCard(List<Widget> rows) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Grouped.card,
          borderRadius: BorderRadius.circular(R.of(10)),
          border: Border.all(color: Grouped.cardBorder),
        ),
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Container(height: AppColors.hairline, color: AppColors.paneLine),
            rows[i],
          ],
        ]),
      );

  // Tinted icon tile, title with a quiet detail beside it, chevron when tappable.
  Widget _sideRow(String icon, Color ink, String label,
          {String detail = '', VoidCallback? onTap, Widget? trailing}) =>
      InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: EdgeInsets.symmetric(horizontal: S.s8, vertical: S.s4),
          child: Row(children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: ink.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(R.of(6))),
              child: AppIcon(icon, size: 12, color: ink),
            ),
            SizedBox(width: S.s8),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: label, style: sans(13, color: _prTitleInk)),
                  if (detail.isNotEmpty)
                    TextSpan(text: '  $detail', style: TS.meta(AppColors.fg4)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) trailing,
            if (onTap != null && trailing == null)
              AppIcon('chevron-right', size: 12, color: AppColors.fg3),
          ]),
        ),
      );

  Widget _sidebar(PrDetail pr) {
    final s = pr.summary;
    final reviews = <String, String>{
      for (final e in pr.timeline.where((e) => e.kind == PrEventKind.review))
        e.author: e.reviewState,
    };
    final reviewers = {...s.reviewers, ...reviews.keys}.toList();
    final checks = s.checks;
    final merge = switch (pr.mergeState) {
      'CLEAN' || 'HAS_HOOKS' => (
          'check',
          AppColors.ok,
          'Ready to merge',
          'No conflicts with ${s.base}'
        ),
      'DIRTY' => (
          'alert-triangle',
          AppColors.danger,
          'Conflicts',
          'Resolve them before merging'
        ),
      'BEHIND' => (
          'alert-triangle',
          AppColors.run,
          'Out of date',
          'Update it with ${s.base}'
        ),
      'BLOCKED' => (
          'x-circle',
          AppColors.danger,
          'Blocked',
          'Required reviews or checks are missing'
        ),
      'UNSTABLE' => (
          'alert-triangle',
          AppColors.run,
          'Some checks failed',
          'It can still be merged'
        ),
      'DRAFT' => (
          'git-branch',
          AppColors.fg3,
          'Draft',
          'Mark it ready before merging'
        ),
      _ => ('clock', AppColors.fg3, 'Checking mergeability', ''),
    };
    final rollupState = rollup(checks);
    final checkTone = switch (rollupState) {
      ChecksState.failing => AppColors.danger,
      ChecksState.pending => AppColors.run,
      _ => AppColors.ok,
    };
    final checksLine = switch (rollupState) {
      ChecksState.failing => 'Some checks failed',
      ChecksState.pending => 'Checks are running',
      ChecksState.passing => 'All checks have passed',
      ChecksState.none => 'No checks',
    };
    final decision = s.reviewDecision;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sideTitle('Status'),
      _sideCard([
        _sideRow(merge.$1, merge.$2, merge.$3, detail: merge.$4),
        if (checks.isNotEmpty)
          _sideRow(
            rollupState == ChecksState.failing
                ? 'x'
                : rollupState == ChecksState.pending
                    ? 'clock'
                    : 'check',
            checkTone,
            checksLine,
            detail:
                '${checks.length} ${checks.length == 1 ? 'check' : 'checks'}',
          ),
        if (decision == 'APPROVED' || decision == 'CHANGES_REQUESTED')
          _sideRow(
            decision == 'APPROVED' ? 'eye' : 'alert-circle',
            decision == 'APPROVED' ? AppColors.fg2 : AppColors.danger,
            decision == 'APPROVED' ? 'Approved' : 'Changes requested',
            detail: reviews.isEmpty
                ? ''
                : '${reviews.length} ${reviews.length == 1 ? 'review' : 'reviews'}',
          ),
      ]),
      if (_open) ...[
        SizedBox(height: S.s8),
        PrMergeBox(
          client: widget.client,
          session: widget.session,
          pr: pr,
          status: widget.status,
          onDone: _reload,
          padding: EdgeInsets.zero,
        ),
      ],
      SizedBox(height: S.s20),
      _sideTitle('Changes'),
      _sideCard([
        _sideRow('file', AppColors.fg2,
            '${pr.files.length} ${pr.files.length == 1 ? 'file' : 'files'}',
            detail: '+${s.additions} \u2212${s.deletions}',
            onTap: () => _showFiles(null)),
        _sideRow('git-commit', AppColors.fg2,
            '${pr.commits.length} ${pr.commits.length == 1 ? 'commit' : 'commits'}',
            onTap: () => setState(() => _tab = 1)),
      ]),
      SizedBox(height: S.s20),
      _sideTitle('Reviewers'),
      if (reviewers.isEmpty)
        Text('No reviewers', style: TS.meta(AppColors.fg4))
      else
        _sideCard([
          for (final r in reviewers)
            Container(
              constraints: const BoxConstraints(minHeight: 32),
              padding: EdgeInsets.symmetric(horizontal: S.s8, vertical: S.s4),
              child: Row(children: [
                prAvatar(r, size: 20),
                SizedBox(width: S.s8),
                Expanded(child: Text(r, style: sans(13, color: _prTitleInk))),
                switch (reviews[r]) {
                  'APPROVED' => Tooltip(
                      message: 'Approved',
                      child: AppIcon('check', size: 14, color: AppColors.ok)),
                  'CHANGES_REQUESTED' => Tooltip(
                      message: 'Changes requested',
                      child: AppIcon('alert-circle',
                          size: 13, color: AppColors.danger)),
                  'COMMENTED' => Tooltip(
                      message: 'Commented',
                      child:
                          AppIcon('message', size: 13, color: AppColors.fg3)),
                  _ => Tooltip(
                      message: 'Awaiting review',
                      child: _prDot(AppColors.run, size: 6)),
                },
              ]),
            ),
        ]),
      if (checks.isNotEmpty) ...[
        SizedBox(height: S.s20),
        _sideTitle('Checks  ${checks.length}'),
        _sideCard([
          for (final c in checks)
            _sideRow(
              switch (c.state) {
                ChecksState.failing => 'x-circle',
                ChecksState.pending => 'clock',
                _ => 'check-circle',
              },
              switch (c.state) {
                ChecksState.failing => AppColors.danger,
                ChecksState.pending => AppColors.run,
                _ => AppColors.ok,
              },
              c.name,
              detail: c.workflow,
              onTap: c.url.isEmpty
                  ? null
                  : () => launchUrl(Uri.parse(c.url),
                      mode: LaunchMode.externalApplication),
            ),
        ]),
      ],
    ]);
  }
}

class _DesktopCommits extends StatefulWidget {
  const _DesktopCommits(
      {required this.client, required this.session, required this.commits});
  final DaemonClient client;
  final String session;
  final List<PrCommit> commits;

  @override
  State<_DesktopCommits> createState() => _DesktopCommitsState();
}

class _DesktopCommitsState extends State<_DesktopCommits> {
  PrCommit? _open;
  Map<String, List<DiffLine>>? _files;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.commits.isNotEmpty) {
      _open = widget.commits.last;
      _load(_open!);
    }
  }

  void _show(PrCommit c) {
    setState(() {
      _open = c;
      _files = null;
      _error = null;
    });
    _load(c);
  }

  Future<void> _load(PrCommit c) async {
    try {
      final d = await widget.client.githubCommitDiff(widget.session, c.oid);
      if (mounted && _open == c) setState(() => _files = parseUnifiedDiff(d));
    } catch (e) {
      if (mounted && _open == c) setState(() => _error = '$e');
    }
  }

  Widget _row(PrCommit c) {
    final short = c.oid.length > 7 ? c.oid.substring(0, 7) : c.oid;
    final on = _open == c;
    return Material(
      color: on ? AppColors.tint2 : Colors.transparent,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        onTap: () => _show(c),
        borderRadius: BorderRadius.circular(R.md),
        child: Padding(
          padding: EdgeInsets.fromLTRB(S.s12, S.of(10), S.of(10), S.of(10)),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.headline,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13,
                            weight: W.label,
                            height: 1.35,
                            color: AppColors.fg1)),
                    SizedBox(height: S.of(3)),
                    Text('${c.author} · ${prAgo(c.date)}',
                        style: TS.meta(AppColors.fg4)),
                  ]),
            ),
            SizedBox(width: S.of(10)),
            Text(short, style: mono(12, color: AppColors.fg3)),
            IconBtn('copy', size: 26, iconSize: 12, tooltip: 'Copy SHA',
                onTap: () {
              Clipboard.setData(ClipboardData(text: c.oid));
              toast(context, 'Copied $short');
            }),
          ]),
        ),
      ),
    );
  }

  Widget _diff() {
    final c = _open!;
    final files = _files;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(S.s20, S.of(14), S.s20, S.s6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.headline,
              style: sans(15, weight: W.strong, color: AppColors.fg1)),
          if (c.body.trim().isNotEmpty) ...[
            SizedBox(height: S.s6),
            Text(c.body.trim(),
                style: sans(13, height: 1.5, color: AppColors.fg3)),
          ],
        ]),
      ),
      Expanded(
        child: _error != null
            ? prMessage(_error!)
            : files == null
                ? Center(child: Spinner(size: 16, color: AppColors.fg3))
                : CustomScrollView(slivers: [
                    for (final e in files.entries)
                      SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: S.s12),
                        sliver: PrFileDiff(
                          file: PrFile(
                            path: e.key,
                            additions: e.value
                                .where((l) => l.kind == DiffKind.add)
                                .length,
                            deletions: e.value
                                .where((l) => l.kind == DiffKind.del)
                                .length,
                            changeType: '',
                          ),
                          lines: e.value,
                          threads: const [],
                          pending: const [],
                          viewed: false,
                          onViewed: null,
                          canComment: false,
                          client: widget.client,
                          session: widget.session,
                          number: 0,
                          onPendingChanged: () {},
                          onThreadsChanged: () async {},
                        ),
                      ),
                    SliverToBoxAdapter(child: SizedBox(height: S.s32)),
                  ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.commits.isEmpty) return prMessage('No commits.');
    final list = ListView(
      padding: EdgeInsets.fromLTRB(S.s12, S.of(10), S.s12, S.s24),
      children: [for (final c in widget.commits.reversed) _row(c)],
    );
    if (_open == null) return list;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 320, child: list),
      Container(width: 1, color: AppColors.border),
      Expanded(child: _diff()),
    ]);
  }
}

class _DesktopFiles extends StatefulWidget {
  const _DesktopFiles({
    super.key,
    required this.client,
    required this.session,
    required this.number,
    required this.pr,
    required this.diff,
    required this.pending,
    required this.viewed,
    required this.canComment,
    required this.onChanged,
    required this.onPendingChanged,
    this.scrollTo,
  });

  final DaemonClient client;
  final String session;
  final int number;
  final PrDetail pr;
  final String diff;
  final List<PendingComment> pending;
  final Set<String> viewed;
  final bool canComment;
  final Future<void> Function() onChanged;
  final VoidCallback onPendingChanged;
  final String? scrollTo;

  @override
  State<_DesktopFiles> createState() => _DesktopFilesState();
}

class _DesktopFilesState extends State<_DesktopFiles> {
  late final Map<String, List<DiffLine>> _parsed =
      parseUnifiedDiff(widget.diff);
  final Map<String, GlobalKey> _keys = {};

  @override
  void initState() {
    super.initState();
    final to = widget.scrollTo;
    if (to != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jump(to));
    }
  }

  void _jump(String path) {
    prReveal(_keys[path]);
  }

  Future<void> _jumpMenu(BuildContext anchor) async {
    final path = await showAppMenu<String>(
      context,
      anchor: anchor,
      minWidth: 300,
      items: [
        for (final f in widget.pr.files)
          appMenuRow<String>(
            value: f.path,
            icon: widget.viewed.contains(f.path) ? 'check-circle' : 'file-code',
            label: f.path.split('/').last,
            description: f.path.contains('/')
                ? f.path.substring(0, f.path.lastIndexOf('/'))
                : null,
            trailing: '+${f.additions} −${f.deletions}',
          ),
      ],
    );
    if (path != null) _jump(path);
  }

  Widget _bar() {
    final files = widget.pr.files;
    final viewed = files.where((f) => widget.viewed.contains(f.path)).length;
    final pending = widget.pending.length;
    return Padding(
      padding: EdgeInsets.fromLTRB(S.s20, S.s4, S.of(14), S.s4),
      child: Row(children: [
        Text('$viewed of ${files.length} viewed',
            style: sans(12, color: AppColors.fg3, tabular: true)),
        SizedBox(width: S.s8),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            width: 40,
            height: 3,
            child: LinearProgressIndicator(
              value: files.isEmpty ? 0 : viewed / files.length,
              color: viewed == files.length ? AppColors.ok : AppColors.accent,
              backgroundColor: AppColors.fg1.withValues(alpha: 0.12),
            ),
          ),
        ),
        if (pending > 0) ...[
          SizedBox(width: S.s12),
          AppIcon('message', size: 12, color: AppColors.accent),
          SizedBox(width: S.of(5)),
          Text('$pending pending', style: sans(13, color: AppColors.accent)),
        ],
        const Spacer(),
        Builder(
          builder: (anchor) => TextButton.icon(
            onPressed: () => _jumpMenu(anchor),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28),
              padding: EdgeInsets.symmetric(horizontal: S.s8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(R.sm)),
            ),
            icon: AppIcon('folder-open', size: 13, color: AppColors.fg3),
            label: Text('Jump to file', style: sans(12, color: AppColors.fg2)),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.pr.files;
    if (files.isEmpty) return prMessage('No files changed.');
    final diffs = CustomScrollView(
      slivers: [
        for (final f in files)
          SliverPadding(
            key: _keys.putIfAbsent(f.path, () => GlobalKey()),
            padding: EdgeInsets.symmetric(horizontal: S.s12),
            sliver: PrFileDiff(
              file: f,
              lines: _parsed[f.path] ?? const [],
              startCollapsed:
                  prStartCollapsed(files) && f.path != widget.scrollTo,
              threads:
                  widget.pr.threads.where((t) => t.path == f.path).toList(),
              pending: widget.pending,
              viewed: widget.viewed.contains(f.path),
              onViewed: (v) => setState(() =>
                  v ? widget.viewed.add(f.path) : widget.viewed.remove(f.path)),
              canComment: widget.canComment,
              client: widget.client,
              session: widget.session,
              number: widget.number,
              onPendingChanged: () {
                setState(() {});
                widget.onPendingChanged();
              },
              onThreadsChanged: widget.onChanged,
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: S.s40)),
      ],
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _bar(),
      Expanded(child: diffs),
    ]);
  }
}
