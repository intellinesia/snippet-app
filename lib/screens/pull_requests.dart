import 'package:flutter/material.dart';

import '../api.dart';
import '../github_models.dart';
import '../panel.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'mobile_chrome.dart';
import 'mobile_session_home.dart' show MobileSectionLabel;
import 'pull_request_detail.dart';

/// Open a session repository's pull requests: a side-pane tab on desktop, a
/// full screen on a phone.
Future<void> openPullRequests(
  BuildContext context, {
  required DaemonClient client,
  required String session,
  required GithubStatus status,
  int? number,
}) {
  return presentScreen<void>(
    context,
    style: PanelStyle.drawer,
    maxWidth: 1100,
    purpose: ShellPanelPurpose.pullRequests,
    originClient: client,
    originSessionId: session,
    builder: (_, close) => PullRequestsScreen(
        client: client,
        session: session,
        status: status,
        openNumber: number,
        onClose: close),
  );
}

Future<void> openPullRequest(
  BuildContext context, {
  required DaemonClient client,
  required String session,
  required GithubStatus status,
  required int number,
}) {
  if (kMobile) {
    return openPullRequests(context,
        client: client, session: session, status: status, number: number);
  }
  return presentScreen<void>(
    context,
    style: PanelStyle.drawer,
    maxWidth: 1100,
    purpose: ShellPanelPurpose.pullRequests,
    panelId: '$number',
    originClient: client,
    originSessionId: session,
    builder: (_, close) => DesktopPrDetailScreen(
        client: client, session: session, number: number, status: status),
  );
}

String _ago(String iso) {
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  return relativeTime(t.millisecondsSinceEpoch ~/ 1000);
}

class PullRequestsScreen extends StatefulWidget {
  const PullRequestsScreen({
    super.key,
    required this.client,
    required this.session,
    required this.status,
    this.onClose,
    this.openNumber,
  });

  final DaemonClient client;
  final String session;
  final GithubStatus status;
  final VoidCallback? onClose;
  final int? openNumber;

  @override
  State<PullRequestsScreen> createState() => _PullRequestsScreenState();
}

class _PullRequestsScreenState extends State<PullRequestsScreen> {
  static const _filters = [
    ('open', 'Open'),
    ('review', 'Needs review'),
    ('mine', 'Mine'),
    ('closed', 'Closed'),
  ];
  String _filter = 'open';
  List<PrSummary>? _prs;
  String? _next;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!kMobile) return;
    _load();
    final n = widget.openNumber;
    if (n != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openNumber(n);
      });
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final filter = _filter;
    try {
      final page = await widget.client.githubPrPage(widget.session, filter);
      if (mounted && filter == _filter) {
        setState(() {
          _prs = page.prs;
          _next = page.next;
        });
      }
    } catch (e) {
      if (mounted && filter == _filter) setState(() => _error = '$e');
    }
  }

  Future<void> _loadMore() async {
    final cursor = _next;
    if (cursor == null || _loadingMore) return;
    final filter = _filter;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.client
          .githubPrPage(widget.session, filter, cursor: cursor);
      if (!mounted || filter != _filter) return;
      setState(() {
        _prs = appendPrs(_prs, page.prs);
        _next = page.next;
      });
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

  Future<void> _open(PrSummary pr) => _openNumber(pr.number);

  Future<void> _openNumber(int number) async {
    await Navigator.of(context).push(PrRoute<void>(
      builder: (_) => PullRequestScreen(
        client: widget.client,
        session: widget.session,
        number: number,
        status: widget.status,
      ),
    ));
    if (mounted) _load();
  }

  (String, Color) _stateIcon(PrSummary pr) => switch (pr.state) {
        'MERGED' => ('git-commit', AppColors.accent),
        'CLOSED' => ('x-circle', AppColors.fg4),
        _ => ('git-pull-request-arrow', pr.draft ? AppColors.fg4 : AppColors.fg2),
      };

  Widget? _checksPill(PrSummary pr) => switch (rollup(pr.checks)) {
        ChecksState.passing => prPill('Checks passed', AppColors.ok),
        ChecksState.failing => prPill('Checks failing', AppColors.danger),
        ChecksState.pending => prPill('Checks running', AppColors.run),
        ChecksState.none => null,
      };

  Widget? _reviewPill(PrSummary pr) => switch (pr.reviewDecision) {
        'APPROVED' => prPill('Approved', AppColors.ok),
        'CHANGES_REQUESTED' => prPill('Changes requested', AppColors.danger),
        _ => null,
      };

  Widget _row(PrSummary pr) {
    final (icon, ink) = _stateIcon(pr);
    final pills = [
      for (final w in [_checksPill(pr), _reviewPill(pr)])
        if (w != null) w,
    ];
    return InkWell(
      onTap: () => _open(pr),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: M.minTarget),
        child: Padding(
          padding: EdgeInsets.fromLTRB(S.s12, S.of(10), S.s12, S.of(10)),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: AppColors.surface3,
                  borderRadius: BorderRadius.circular(R.of(10))),
              child: AppIcon(icon, size: 16, color: ink),
            ),
            SizedBox(width: S.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pr.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(14, weight: W.label, color: AppColors.fg1)),
                  SizedBox(height: S.s2),
                  Text(
                      '#${pr.number} · ${pr.author == widget.status.viewer && pr.author.isNotEmpty ? 'you' : pr.author} · ${_ago(pr.updatedAt)}${pr.draft ? ' · draft' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TS.meta(AppColors.fg3)),
                ],
              ),
            ),
            if (pills.isNotEmpty) ...[
              SizedBox(width: S.s8),
              Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < pills.length; i++) ...[
                      if (i > 0) SizedBox(height: S.s4),
                      pills[i],
                    ],
                  ]),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _group(List<PrSummary> list) => Padding(
        padding: EdgeInsets.symmetric(horizontal: S.s16),
        child: CardGroupScope(
            child: ListGroup(children: [for (final p in list) _row(p)])),
      );

  Widget _filterBar() => Padding(
        padding: EdgeInsets.fromLTRB(S.s16, S.s4, S.s16, S.s6),
        child: Container(
          padding: EdgeInsets.all(S.of(3)),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(R.of(12)),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(children: [
            for (final (key, label) in _filters)
              Expanded(
                child: InkWell(
                  onTap: () => _pick(key),
                  borderRadius: BorderRadius.circular(R.of(9)),
                  child: Container(
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: key == _filter ? AppColors.surface3 : Colors.transparent,
                      borderRadius: BorderRadius.circular(R.of(9)),
                    ),
                    child: Text(label,
                        maxLines: 1,
                        style: sans(13,
                            weight: key == _filter ? W.label : W.body,
                            color: key == _filter ? AppColors.fg1 : AppColors.fg3)),
                  ),
                ),
              ),
          ]),
        ),
      );

  List<Widget> _body(List<PrSummary> prs) {
    if (_filter != 'open') return [_group(prs)];
    final me = widget.status.viewer;
    final review = prs.where((p) => p.author != me && p.reviewers.contains(me)).toList();
    final mine = prs.where((p) => p.author == me).toList();
    final others = prs.where((p) => !review.contains(p) && !mine.contains(p)).toList();
    final groups = [
      ('Needs your review', review),
      ('Yours', mine),
      ('Others', others),
    ].where((g) => g.$2.isNotEmpty).toList();
    if (groups.length == 1) return [_group(prs)];
    return [
      for (final (label, list) in groups) ...[
        Padding(
          padding: EdgeInsets.symmetric(horizontal: S.s12),
          child: MobileSectionLabel(label, top: 14),
        ),
        _group(list),
      ],
    ];
  }

  Widget _empty() => Center(
        child: Padding(
          padding: EdgeInsets.all(S.s32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AppIcon('git-branch', size: 22, color: AppColors.fg4),
            SizedBox(height: S.of(10)),
            Text(
                switch (_filter) {
                  'review' => 'Nothing waiting on your review.',
                  'mine' => 'You have no open pull requests.',
                  'closed' => 'No closed pull requests.',
                  _ => 'No open pull requests.',
                },
                style: sans(13, color: AppColors.fg3)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!kMobile) {
      return DesktopPullRequests(
        client: widget.client,
        session: widget.session,
        status: widget.status,
        openNumber: widget.openNumber,
      );
    }
    final prs = _prs;
    return Material(
      color: kMobile ? AppColors.pageBg : Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MobileBackBar(title: 'Pull requests'),
          _filterBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _error != null || prs == null || prs.isEmpty
                  ? LayoutBuilder(
                      builder: (context, box) => ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: box.maxHeight,
                            child: _error != null
                                ? _message(_error!)
                                : prs == null
                                    ? Center(child: Spinner(size: 16, color: AppColors.fg3))
                                    : _empty(),
                          ),
                        ],
                      ),
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (n) => prNearEnd(n, _loadMore),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.only(bottom: S.s24),
                        children: [
                          ..._body(prs),
                          if (_next != null) prLoadMore(_loadingMore, _loadMore),
                        ],
                      ),
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}

Widget _message(String text) => Center(
      child: Padding(
        padding: EdgeInsets.all(S.s24),
        child: Text(text,
            textAlign: TextAlign.center,
            style: sans(13, height: 1.5, color: AppColors.fg3)),
      ),
    );

