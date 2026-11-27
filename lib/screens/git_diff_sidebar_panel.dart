import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../swr.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import '../file_icons.dart';
import 'git.dart';
import 'pull_request_detail.dart' show PrSidebarList;
import 'shell_nav.dart';
import '../pull_refresh.dart';

/// Capy's quiet empty-panel mascot, redrawn as vector shapes so it can scale.
class PanelEmptyArt extends StatelessWidget {
  const PanelEmptyArt({super.key, this.width = 95, this.height = 96});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(width, height),
        painter: const _PanelEmptyArtPainter(),
      );
}

class _PanelEmptyArtPainter extends CustomPainter {
  const _PanelEmptyArtPainter();

  static const _bright = Color(0xFF4D4D4D);
  static const _dark = Color(0xFF262626);
  static const _void = Color(0xFF070707);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 95, size.height / 96);
    final bright = Paint()..color = _bright;
    final dark = Paint()..color = _dark;
    final voidInk = Paint()..color = _void;

    final leftSail = Path()
      ..moveTo(45, 13)
      ..cubicTo(40, 27, 36, 43, 32, 58)
      ..lineTo(45, 58)
      ..close();
    final rightSail = Path()
      ..moveTo(52, 13)
      ..cubicTo(58, 29, 67, 45, 82, 62)
      ..lineTo(52, 62)
      ..close();
    canvas.drawPath(leftSail, bright);
    canvas.drawPath(rightSail, bright);

    final seam = Paint()
      ..color = _dark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(37, 43), const Offset(45, 43), seam);
    canvas.drawLine(const Offset(53, 40), const Offset(66, 38), seam);
    canvas.drawLine(const Offset(53, 52), const Offset(75, 50), seam);

    final capy = Path()
      ..moveTo(17, 70)
      ..lineTo(18, 58)
      ..cubicTo(11, 57, 10, 48, 15, 43)
      ..cubicTo(20, 37, 32, 38, 38, 44)
      ..cubicTo(49, 44, 57, 53, 59, 66)
      ..lineTo(59, 70)
      ..close();
    canvas.drawPath(capy, dark);
    canvas.drawCircle(const Offset(34, 40), 3.2, dark);
    canvas.drawCircle(const Offset(22, 47), 1.4, voidInk);

    final mast = Paint()
      ..color = _void
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(48, 14), const Offset(48, 70), mast);
    final flag = Path()
      ..moveTo(51, 11)
      ..lineTo(58, 13)
      ..lineTo(51, 16)
      ..close();
    canvas.drawPath(flag, dark);

    final hull = Path()
      ..moveTo(12, 70)
      ..lineTo(82, 66)
      ..cubicTo(80, 75, 76, 82, 68, 84)
      ..cubicTo(58, 88, 49, 85, 39, 86)
      ..cubicTo(27, 91, 17, 87, 14, 78)
      ..close();
    canvas.drawPath(hull, bright);
    final grain = Paint()
      ..color = _dark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(17, 77), const Offset(65, 74), grain);
    canvas.drawLine(const Offset(66, 70), const Offset(79, 68), grain);
    canvas.drawCircle(const Offset(26, 78), 5, grain);
    canvas.drawLine(const Offset(18, 88), const Offset(31, 86), grain);
    canvas.drawLine(const Offset(61, 88), const Offset(75, 86), grain);
  }

  @override
  bool shouldRepaint(_PanelEmptyArtPainter old) => false;
}

/// Git Diff sidebar panel.
///
/// Layout follows the measured reference: a 32px branch row directly under the
/// section header, then 26px file rows. The previous version put a bordered
/// card at the top followed by a hard 20px gap and then over-padded rows, which
/// is what made the spacing read as broken — every vertical rhythm in the panel
/// was a different number.
class GitDiffSidebarPanel extends StatefulWidget {
  const GitDiffSidebarPanel({
    super.key,
    required this.client,
    required this.workspacePath,
    this.sessionId,
    this.onOpenDiff,
    this.tab = 'changes',
    this.onTab,
    this.onOpenPullRequest,
    this.header,
    this.showHeader = true,
  });

  final String tab;
  final ValueChanged<String>? onTab;
  final ValueChanged<int>? onOpenPullRequest;
  final Widget? header;
  final bool showHeader;

  final DaemonClient client;
  final String workspacePath;
  final String? sessionId;

  /// Called when a changed file is tapped. The host opens it as a tab in the
  /// main pane, so a diff reads in the same tab system as everything else.
  final void Function(GitFile file)? onOpenDiff;

  @override
  State<GitDiffSidebarPanel> createState() => _GitDiffSidebarPanelState();
}

class _GitDiffSidebarPanelState extends State<GitDiffSidebarPanel> {
  final _commitCtl = TextEditingController();
  bool _committing = false;
  bool _pushing = false;
  GitStatus? _status;
  bool _loading = true;
  String? _error;
  bool _initing = false;
  Swr<GitStatus>? _git;
  bool _branchBusy = false;

  String get _repo =>
      widget.sessionId != null && widget.sessionId!.trim().isNotEmpty
          ? widget.sessionId!
          : widget.workspacePath;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  @override
  void dispose() {
    _commitCtl.dispose();
    _git?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant GitDiffSidebarPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId ||
        oldWidget.workspacePath != widget.workspacePath ||
        oldWidget.client != widget.client) {
      _watch();
    }
  }

  void _watch() {
    _git?.dispose();
    final git = Swr<GitStatus>(
      client: widget.client,
      key: 'git:$_repo',
      fetch: () => widget.client.gitStatus(_repo),
      revalidateOn: _touchesRepo,
      onChange: _sync,
    );
    _git = git;
    _status = git.data;
    _loading = git.data == null;
    _error = null;
  }

  bool _touchesRepo(DeviceEventFrame e) =>
      const {DeviceEventHub.attachedToolResult, 'idle', 'done', 'error'}
          .contains(e['kind']) &&
      ((widget.sessionId != null && e['session'] == widget.sessionId) ||
          e['workspace'] == widget.workspacePath);

  void _sync() {
    final git = _git;
    if (!mounted || git == null) return;
    setState(() {
      final data = git.data;
      if (data != null && !identical(data, _status)) {
        _status = data;
      }
      _loading = git.loading;
      _error = data == null && git.error != null ? '${git.error}' : null;
    });
  }

  Future<void> refresh({bool background = false}) async {
    await _git?.refresh();
  }

  Future<void> _branchSheet([BuildContext? anchor]) async {
    if (_branchBusy) return;
    late final ({
      String current,
      List<String> local,
      List<String> remotes
    }) data;
    try {
      data = await widget.client.gitBranches(_repo);
    } catch (e) {
      if (mounted) toast(context, '$e');
      return;
    }
    if (!mounted) return;
    if (anchor != null && !anchor.mounted) return;
    final picker = GitBranchPicker(
      current: data.current,
      local: data.local,
      remotes: data.remotes,
      onSelect: (name, {required bool create}) {
        Navigator.pop(context);
        unawaited(_checkoutBranch(name, create: create));
      },
    );
    if (!kMobile && anchor != null) {
      await showAnchoredPanel<void>(anchor, width: 380, child: picker);
    } else {
      await showAppSheet<void>(context,
          title: 'Branches', maxWidth: 420, child: picker);
    }
  }

  Future<void> _checkoutBranch(String name, {required bool create}) async {
    if (_branchBusy) return;
    setState(() => _branchBusy = true);
    try {
      final result =
          await widget.client.gitCheckout(_repo, name, create: create);
      if (!mounted) return;
      if (result['ok'] != true) {
        final error = (result['stderr'] as String?)?.trim();
        toast(context, error == null || error.isEmpty ? 'git failed' : error);
      } else {
        toast(context, create ? 'Created $name' : 'Switched to $name');
      }
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) {
        setState(() => _branchBusy = false);
        await refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final repoName = widget.workspacePath.isEmpty
        ? 'Workspace'
        : lastPathSegment(widget.workspacePath, ifEmpty: 'Workspace');
    final files = _status?.files ?? const <GitFile>[];
    final branch = _status?.branch ?? '';
    final isClean = files.isEmpty;
    final notRepo = _status != null &&
        !_status!.ok &&
        (_status!.error ?? '').trim().isNotEmpty;

    final tabbed = !kMobile &&
        widget.onTab != null &&
        widget.onOpenPullRequest != null &&
        (widget.sessionId ?? '').isNotEmpty;
    final showPrs = tabbed && widget.tab == 'prs';
    final changes = LayoutBuilder(builder: (context, box) => PullToRefresh(
      onRefresh: refresh,
      child: Container(
        color: kMobile ? AppColors.pageBg : Colors.transparent,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(top: kMobile ? S.s8 : 0, bottom: S.s16),
          children: [
            if (!tabbed && widget.showHeader)
              ShellSectionHeader(
                label: 'Git Diff',
                leading: widget.header,
              ),
            if (notRepo)
              SizedBox(
                height: (box.maxHeight - 80).clamp(260.0, 640.0),
                child: _notRepoState(repoName),
              )
            else ...[
            _branchRow(repoName, branch, files.length),
            if (_loading && _status == null)
              Padding(
                padding: EdgeInsets.symmetric(vertical: S.s24),
                child: Center(
                  child: Spinner(size: 18),
                ),
              )
            else if (_error != null)
              _errorState()
            else if (isClean)
              SizedBox(
                height: (box.maxHeight - 120).clamp(240.0, 640.0),
                child: _cleanState(),
              )
            else ...[
              if (!kMobile && (widget.sessionId ?? '').isNotEmpty)
                _commitBox(files.length),
              if (!kMobile) _changedHeader() else _phoneSummary(files.length),
              for (final f in files) _fileRow(f),
            ],
            ],
          ],
        ),
      ),
    ));
    if (!tabbed) return changes;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: 38,
        padding: EdgeInsets.fromLTRB(S.of(10), S.s2, S.s8, S.s2),
        child: Row(children: [
          _tabChip('changes', files.isEmpty ? 'Changes' : 'Changes  ${files.length}'),
          _tabChip('prs', 'Pull requests'),
        ]),
      ),
      Expanded(
        child: showPrs
            ? PrSidebarList(
                client: widget.client,
                session: widget.sessionId!,
                onOpen: widget.onOpenPullRequest!,
              )
            : changes,
      ),
    ]);
  }

  String _gitFail(Map<String, dynamic> r, String what) {
    final e = ((r['stderr'] ?? r['error']) as String?)?.trim() ?? '';
    return e.isEmpty ? '$what failed' : e;
  }

  Future<void> _commit() async {
    final msg = _commitCtl.text.trim();
    final sid = widget.sessionId;
    if (msg.isEmpty || sid == null || _committing) return;
    setState(() => _committing = true);
    try {
      final staged = await widget.client.gitStage(sid, all: true);
      if (staged['ok'] != true) throw _gitFail(staged, 'Stage');
      final committed = await widget.client.gitCommit(sid, msg);
      if (committed['ok'] != true) throw _gitFail(committed, 'Commit');
      _commitCtl.clear();
      await refresh(background: true);
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _committing = false);
    }
  }

  Future<void> _push() async {
    final sid = widget.sessionId;
    if (sid == null || _pushing) return;
    setState(() => _pushing = true);
    try {
      final pushed = await widget.client.gitPush(sid);
      if (pushed['ok'] != true) throw _gitFail(pushed, 'Push');
      if (mounted) toast(context, 'Pushed');
      await refresh(background: true);
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _pushing = false);
    }
  }

  Future<void> _stash() async {
    final sid = widget.sessionId;
    if (sid == null) return;
    final ok = await confirmAction(context,
        title: 'Stash changes?',
        body: 'Moves uncommitted changes to the git stash. Bring them back with git stash pop.',
        confirmLabel: 'Stash',
        danger: false);
    if (!ok) return;
    try {
      final stashed = await widget.client.gitStash(sid, 'push');
      if (stashed['ok'] != true) throw _gitFail(stashed, 'Stash');
      await refresh(background: true);
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  Future<void> _discard() async {
    final sid = widget.sessionId;
    if (sid == null) return;
    final ok = await confirmAction(context,
        title: 'Discard all changes?',
        body:
            'Every uncommitted change in this workspace is deleted, including new files. This cannot be undone.',
        confirmLabel: 'Discard');
    if (!ok) return;
    try {
      final discarded = await widget.client.gitDiscard(sid);
      if (discarded['ok'] != true) throw _gitFail(discarded, 'Discard');
      await refresh(background: true);
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  bool _opening = false;

  Future<void> _openPr() async {
    final sid = widget.sessionId;
    if (sid == null || _opening) return;
    setState(() => _opening = true);
    try {
      final url = await widget.client.createPr(sid);
      if (mounted) toast(context, url.isEmpty ? 'Pull request opened' : 'Opened $url');
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Widget _changedHeader() => Padding(
        padding: EdgeInsets.fromLTRB(S.of(18), S.of(18), S.of(14), S.s6),
        child: Row(children: [
          Expanded(
            child: Text('CHANGED',
                style: sans(11, spacing: 0.9, color: AppColors.fg4)),
          ),
          if ((widget.sessionId ?? '').isNotEmpty) ...[
            InkWell(
              onTap: _stash,
              borderRadius: BorderRadius.circular(R.sm),
              hoverColor: Colors.transparent,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: S.s4, vertical: S.s2),
                child: Text('Stash', style: sans(12, color: AppColors.fg3)),
              ),
            ),
            SizedBox(width: S.s6),
            InkWell(
              onTap: _discard,
              borderRadius: BorderRadius.circular(R.sm),
              hoverColor: Colors.transparent,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: S.s4, vertical: S.s2),
                child: Text('Discard all',
                    style: sans(12, color: AppColors.fg3)),
              ),
            ),
          ],
        ]),
      );

  Widget _roundBtn(String icon, String tip, VoidCallback? onTap) => Tooltip(
        message: tip,
        child: Opacity(
          opacity: onTap == null ? 0.45 : 1,
          child: Material(
            color: AppColors.tint2,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 32,
                height: 32,
                child: Center(
                    child: AppIcon(icon, size: 14, color: AppColors.fg2)),
              ),
            ),
          ),
        ),
      );

  Widget _deskPill(String label,
          {required bool light,
          String? icon,
          bool disabled = false,
          VoidCallback? onTap}) =>
      Opacity(
        opacity: disabled ? 0.45 : 1,
        child: Material(
          color: light ? AppColors.fg1 : AppColors.tint2,
          borderRadius: BorderRadius.circular(R.of(16)),
          child: InkWell(
            borderRadius: BorderRadius.circular(R.of(16)),
            onTap: disabled ? null : onTap,
            child: Container(
              height: 32,
              padding: EdgeInsets.symmetric(horizontal: S.of(14)),
              alignment: Alignment.center,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[
                  AppIcon(icon, size: 13, color: AppColors.fg2),
                  SizedBox(width: S.s6),
                ],
                Text(label,
                    style: sans(13,
                        weight: light ? FontWeight.w500 : W.body,
                        color: light ? AppColors.bg : AppColors.fg2)),
              ]),
            ),
          ),
        ),
      );

  Widget _commitBox(int count) => Padding(
        padding: EdgeInsets.fromLTRB(S.s12, S.s6, S.s12, S.s8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.tint1,
              borderRadius: BorderRadius.circular(R.lg),
              border: Border.all(color: AppColors.line),
            ),
            padding: EdgeInsets.fromLTRB(S.s12, S.of(10), S.s12, S.s8),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.enter,
                          meta: true): _commit,
                      const SingleActivator(LogicalKeyboardKey.enter,
                          control: true): _commit,
                    },
                    child: TextField(
                      controller: _commitCtl,
                      minLines: 2,
                      maxLines: 5,
                      onChanged: (_) => setState(() {}),
                      style: sans(13, color: AppColors.fg1),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'Commit message',
                        hintStyle: sans(13, color: AppColors.fg4),
                      ),
                    ),
                  ),
                  SizedBox(height: S.s6),
                  Text('⌘↵ to commit', style: sans(12, color: AppColors.fg4)),
                ]),
          ),
          SizedBox(height: S.of(10)),
          if (!kMobile)
            LayoutBuilder(builder: (context, box) => Row(children: [
              Expanded(
                child: _deskPill(
                    _committing
                        ? 'Committing…'
                        : 'Commit $count file${count == 1 ? '' : 's'}',
                    light: true,
                    disabled: _commitCtl.text.trim().isEmpty || _committing,
                    onTap: _commit),
              ),
              SizedBox(width: S.s8),
              _roundBtn('upload', _pushing ? 'Pushing…' : 'Push',
                  _pushing ? null : _push),
              SizedBox(width: S.s6),
              box.maxWidth < 300
                  ? _roundBtn('git-pull-request-arrow', 'Open PR',
                      _opening ? null : _openPr)
                  : _deskPill(_opening ? 'Opening…' : 'Open PR',
                      light: false,
                      icon: 'git-pull-request-arrow',
                      disabled: _opening,
                      onTap: _openPr),
            ]))
          else
          Row(children: [
            Expanded(
              child: Btn(
                _committing
                    ? 'Committing…'
                    : 'Commit $count file${count == 1 ? '' : 's'}',
                variant: BtnVariant.primary,
                full: true,
                disabled: _commitCtl.text.trim().isEmpty || _committing,
                onTap: _commit,
              ),
            ),
            SizedBox(width: S.s8),
            Btn(_pushing ? 'Pushing…' : 'Push',
                variant: BtnVariant.secondary,
                icon: 'upload',
                disabled: _pushing,
                onTap: _push),
          ]),
        ]),
      );

  Widget _tabChip(String key, String label) {
    final on = widget.tab == key;
    return Padding(
      padding: EdgeInsets.only(right: S.s2),
      child: Material(
        color: on ? AppColors.tint2 : Colors.transparent,
        borderRadius: BorderRadius.circular(R.of(7)),
        child: InkWell(
          onTap: () => widget.onTab?.call(key),
          borderRadius: BorderRadius.circular(R.of(7)),
          hoverColor: kMobile
              ? AppColors.surface2.withValues(alpha: 0.5)
              : AppColors.tint3,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: S.s8, vertical: S.s4),
            child: Text(label,
                style: sans(13, color: on ? AppColors.fg1 : AppColors.fg3)),
          ),
        ),
      ),
    );
  }

  /// Branch + change count on one flat row. Tapping the row opens the same
  /// local/remote branch picker used by the full Git screen.
  Widget _branchRow(String repoName, String branch, int changes) =>
      kMobile ? _branchRowMobile(repoName, branch, changes) : _branchRowDesk(repoName, branch);

  Widget _branchRowDesk(String repoName, String branch) {
    final st = _status;
    return Padding(
      padding: EdgeInsets.fromLTRB(S.s8, S.s2, S.s8, 0),
      child: Builder(
        builder: (anchor) => InkWell(
          borderRadius: BorderRadius.circular(R.of(7)),
          onTap: _branchBusy ? null : () => _branchSheet(anchor),
          child: Container(
            height: 28,
            padding: EdgeInsets.symmetric(horizontal: S.s6),
            child: Row(children: [
              AppIcon('git-branch', size: 13, color: AppColors.fg3),
              SizedBox(width: S.s8),
              Expanded(
                child: Text(branch.isEmpty ? repoName : branch,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, color: AppColors.fg2)),
              ),
              if (st != null && (st.upstream ?? '').isNotEmpty)
                Text('↑${st.ahead} ↓${st.behind}',
                    style: mono(11, color: AppColors.fg4)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _branchRowMobile(String repoName, String branch, int changes) => Padding(
        padding: kMobile
            ? EdgeInsets.fromLTRB(S.s12, S.s4, S.s12, S.s6)
            : EdgeInsets.fromLTRB(S.s8, S.s2, S.s8, S.s4),
        child: Builder(
          builder: (anchor) => Material(
            color: AppColors.tint2,
            borderRadius: BorderRadius.circular(kMobile ? 10 : 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(kMobile ? 10 : 8),
              onTap: _branchBusy ? null : () => _branchSheet(anchor),
              child: Container(
                height: kMobile ? 36 : 30,
                padding: const EdgeInsets.symmetric(horizontal: kNavPadH),
                child: Row(children: [
                  AppIcon('git-branch', size: kMobile ? 14 : 13, color: AppColors.accent),
                  SizedBox(width: S.s8),
                  Expanded(
                    child: Text(
                      branch.isEmpty ? repoName : branch,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kMobile ? TS.label(AppColors.fg1) : sans(13, color: AppColors.fg1),
                    ),
                  ),
                  if (changes > 0) ...[
                    SizedBox(width: S.s6),
                    Text('$changes changed', style: TS.meta()),
                  ],
                  SizedBox(width: S.s6),
                  AppIcon('chevron-down', size: 13, color: AppColors.fg3),
                ]),
              ),
            ),
          ),
        ),
      );

  /// SH-04 phone row: name 14/400, directory 13/400 fg3 below, pitch 56. The
  /// model carries no line counts, so the status letter badge stays trailing.
  Widget _phoneFileRow(GitFile f) {
    final name = lastPathSegment(f.path, ifEmpty: f.path);
    final slash = f.path.lastIndexOf('/');
    final dir = slash > 0 ? f.path.substring(0, slash) : '';
    return Semantics(
      button: true,
      label: f.path,
      excludeSemantics: true,
      child: InkWell(
        onTap: widget.onOpenDiff == null ? null : () => widget.onOpenDiff!(f),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(14, color: AppColors.fg1)),
                      if (dir.isNotEmpty)
                        Text(dir,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(13, color: AppColors.fg3)),
                    ]),
              ),
              const SizedBox(width: 12),
              _statusLetter(f),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _phoneSummary(int n) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text('$n ${n == 1 ? 'file' : 'files'}',
            style: sans(14, weight: W.label, color: AppColors.fg1)),
      );

  Widget _fileRow(GitFile f) {
    if (kMobile) return _phoneFileRow(f);
    final name = lastPathSegment(f.path, ifEmpty: f.path);
    final slash = f.path.lastIndexOf('/');
    final dir = slash > 0 ? f.path.substring(0, slash) : '';
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: S.s8),
      child: Tooltip(
        message: f.path,
        waitDuration: const Duration(milliseconds: 600),
        child: Semantics(
          label: f.path,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(R.card),
            child: InkWell(
              borderRadius: BorderRadius.circular(R.md),
              onTap: widget.onOpenDiff == null
                  ? null
                  : () => widget.onOpenDiff!(f),
              child: Padding(
                padding: kMobile
                    ? EdgeInsets.fromLTRB(S.of(10), S.of(7), S.of(10), S.of(7))
                    : EdgeInsets.fromLTRB(S.of(10), S.of(5), S.of(10), S.of(5)),
                child: Row(children: [
                  if (kMobile) ...[
                    _statusLetter(f),
                    SizedBox(width: S.of(10)),
                  ] else ...[
                    FileGlyph(name, size: 14),
                    SizedBox(width: S.of(9)),
                  ],
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: name),
                        if (dir.isNotEmpty)
                          TextSpan(
                              text: '  $dir',
                              style: sans(12, color: AppColors.fg4)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(kMobile ? 13 : 13,
                          color: kMobile ? AppColors.fg1 : AppColors.fg2),
                    ),
                  ),
                  if (!kMobile) ...[
                    SizedBox(width: S.s8),
                    _statusMark(f),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The git status character, matching how the full Git screen derives it:
  /// the index char for a staged file, `?` for untracked, else the worktree
  /// char. Colour is the only state signal in the panel.
  Widget _statusMark(GitFile f) {
    final raw = f.staged ? f.x : (f.untracked ? '?' : f.y);
    final l = raw.trim().isEmpty ? 'M' : raw.trim();
    final letter = l == '?' ? 'A' : l;
    final color = switch (letter) {
      'A' => AppColors.diffAddFg,
      'D' => AppColors.diffDelFg,
      _ => AppColors.fg2,
    };
    return Text(letter, style: mono(11, color: color));
  }

  Widget _statusLetter(GitFile f) {
    final raw = f.staged ? f.x : (f.untracked ? '?' : f.y);
    final letter = raw.trim().isEmpty ? 'M' : raw.trim();
    final color =
        f.staged ? AppColors.fg1 : (f.untracked ? AppColors.fg3 : AppColors.fg2);
    return Tooltip(
      message: f.staged ? 'staged' : (f.untracked ? 'untracked' : 'unstaged'),
      child: Container(
        width: kMobile ? 20 : 16,
        height: kMobile ? 20 : 16,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(kMobile ? 6 : 4),
        ),
        child: Text(letter, style: mono(kMobile ? 11 : 10, color: color)),
      ),
    );
  }

  Future<void> _initRepo() async {
    if (_initing) return;
    setState(() => _initing = true);
    try {
      final r = await widget.client.gitInit(_repo);
      if (!mounted) return;
      if (r['ok'] != true) {
        final err = (r['stderr'] as String?)?.trim();
        toast(context, err == null || err.isEmpty ? 'git init failed' : err,
            danger: true);
      } else {
        toast(context, 'Git initialized');
      }
      await refresh();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _initing = false);
    }
  }

  Widget _notRepoState(String repoName) => EmptyState(
        icon: 'git-branch',
        title: 'Not a Git repository',
        body:
            'Initialize Git in $repoName to track changes, branches and pull requests here.',
        action: Btn(_initing ? 'Initializing…' : 'Initialize Git',
            small: true,
            icon: 'git-branch',
            disabled: _initing,
            onTap: _initRepo),
      );

  // Capy: a quiet centred note rather than the generic empty card.
  Widget _cleanState() => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const PanelEmptyArt(width: 72, height: 56),
            const SizedBox(height: 12),
            Text('No local changes',
                style: sans(12.5, weight: W.label, color: AppColors.fg3)),
            const SizedBox(height: 4),
            Text('The working tree is clean',
                textAlign: TextAlign.center,
                style: sans(12,
                    color: Color.lerp(AppColors.fg4, AppColors.panelBg, 0.4))),
          ]),
        ),
      );

  Widget _errorState() => Padding(
        padding: EdgeInsets.fromLTRB(S.s20, S.of(14), S.s20, S.s8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: EdgeInsets.only(top: S.s2),
              child:
                  AppIcon('alert-triangle', size: 14, color: AppColors.danger),
            ),
            SizedBox(width: S.s8),
            Expanded(
              child: Text(_error!,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, height: 1.4, color: AppColors.fg2)),
            ),
          ]),
          Padding(
            padding: EdgeInsets.only(left: S.of(14), top: S.s4),
            child: TextButton(
              onPressed: refresh,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accent,
                minimumSize: const Size(0, 30),
                padding: EdgeInsets.symmetric(horizontal: S.s8),
              ),
              child:
                  Text('Try again', style: sans(13, color: AppColors.accent)),
            ),
          ),
        ]),
      );

}
