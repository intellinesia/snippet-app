import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../models.dart';
import '../mobile_kit.dart';
import '../motion_routes.dart';
import '../panel.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import '../pull_refresh.dart';
import 'compact_btn.dart';

/// Git for one session's workspace: status (staged / changed / untracked),
/// per-file diff, stage/unstage/commit, branch switch, push/pull. All operations
/// go through the daemon's /git/* endpoints (server-side `git`).
class GitScreen extends StatefulWidget {
  final DaemonClient client;
  final String sessionId;

  /// When set, git runs against this folder directly (no session needed) — used
  /// from the file explorer. Takes precedence over [sessionId].
  final String? folder;

  /// When hosted in a desktop panel, dismisses the panel from the root bar.
  final VoidCallback? onClose;

  /// When true, render embedded in a sidebar (no Scaffold / SnAppBar).
  final bool embedded;

  const GitScreen({
    super.key,
    required this.client,
    this.sessionId = '',
    this.folder,
    this.onClose,
    this.embedded = false,
  });

  @override
  State<GitScreen> createState() => _GitScreenState();
}

class _GitScreenState extends State<GitScreen> {
  // The git endpoints accept either a session id or a folder path.
  String get _repo => (widget.folder != null && widget.folder!.isNotEmpty)
      ? widget.folder!
      : widget.sessionId;

  GitStatus? _st;
  bool _loading = true;
  bool _refreshing = false;
  bool _busy = false;
  final Set<String> _optStaged = {};
  final Set<String> _optUnstaged = {};
  String? _error;

  final TextEditingController _commitController = TextEditingController();
  final FocusNode _commitFocus = FocusNode();
  final Set<String> _expandedSections = {};
  int _loadGen = 0;
  static const _collapsedLimit = 8;

  @override
  void initState() {
    super.initState();
    _commitController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _commitController.dispose();
    _commitFocus.dispose();
    super.dispose();
  }

  bool _initing = false;

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
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _initing = false);
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    final gen = ++_loadGen;
    setState(() {
      if (_st == null) {
        _loading = true;
      } else {
        _refreshing = true;
      }
      _error = null;
    });
    try {
      final st = await widget.client.gitStatus(_repo);
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _st = st;
        _loading = false;
        _refreshing = false;
        if (!st.ok) _error = st.error ?? 'not a git repository';
      });
    } catch (e) {
      if (mounted && gen == _loadGen) {
        setState(() {
          _error = '$e';
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _toggleStage(GitFile f, {required bool staged}) async {
    setState(() => (staged ? _optUnstaged : _optStaged).add(f.path));
    try {
      final r = staged
          ? await widget.client.gitUnstage(_repo, paths: [f.path])
          : await widget.client.gitStage(_repo, paths: [f.path]);
      if (r['ok'] != true) {
        final err = (r['stderr'] as String?)?.trim();
        _toast(err == null || err.isEmpty ? 'git failed' : err);
      }
    } catch (e) {
      _toast('$e');
    }
    await _load();
    if (mounted) {
      setState(() => (staged ? _optUnstaged : _optStaged).remove(f.path));
    }
  }

  void _toast(String m) {
    if (mounted) toast(context, m);
  }

  /// Run a write op, surface git's stderr on failure, then reload.
  Future<bool> _op(Future<Map<String, dynamic>> Function() f,
      {String? okMsg}) async {
    if (_busy) return false;
    setState(() => _busy = true);
    var ok = false;
    try {
      final r = await f();
      ok = r['ok'] == true;
      if (!ok) {
        final err = (r['stderr'] as String?)?.trim();
        _toast(err == null || err.isEmpty ? 'git failed' : err);
      } else if (okMsg != null) {
        _toast(okMsg);
      }
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _load();
      }
    }
    return ok;
  }

  Future<void> _commit() async {
    final msg = _commitController.text.trim();
    if (msg.isEmpty) {
      _commitFocus.requestFocus();
      _toast('Enter a commit message');
      return;
    }
    if (await _op(() => widget.client.gitCommit(_repo, msg),
        okMsg: 'Committed')) {
      _commitController.clear();
    }
  }

  Future<void> _stageAllAndCommit() async {
    final msg = _commitController.text.trim();
    if (msg.isEmpty) {
      _commitFocus.requestFocus();
      _toast('Enter a commit message');
      return;
    }
    final ok = await _op(() async {
      final s = await widget.client.gitStage(_repo, all: true);
      if (s['ok'] != true) return s;
      return await widget.client.gitCommit(_repo, msg);
    }, okMsg: 'Staged and committed');
    if (ok) _commitController.clear();
  }

  void _openDiff(GitFile f, {required bool staged}) {
    Widget view() => GitFileDiffView(
          client: widget.client,
          sessionId: _repo,
          file: f.path,
          staged: staged && f.staged,
          untracked: f.untracked,
        );
    if (!kMobile && ShellPanelRoot.of(context) == null) {
      presentScreen<void>(
        context,
        style: PanelStyle.drawer,
        purpose: ShellPanelPurpose.file,
        panelId: 'diff:${f.path}',
        originClient: widget.client,
        maxWidth: 1060,
        maxHeight: 760,
        builder: (_, __) => view(),
      );
      return;
    }
    Navigator.push(context, AppPageRoute<void>(builder: (_) => view()));
  }

  Future<void> _branchSheet([BuildContext? anchor]) async {
    late final ({
      String current,
      List<String> local,
      List<String> remotes
    }) data;
    try {
      data = await widget.client.gitBranches(_repo);
    } catch (e) {
      _toast('$e');
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
        _op(
          () => widget.client.gitCheckout(_repo, name, create: create),
          okMsg: create ? 'Created $name' : 'Switched to $name',
        );
      },
    );
    if (!kMobile && anchor != null) {
      await showAnchoredPanel<void>(anchor, width: 380, child: picker);
    } else {
      await showAppSheet<void>(context,
          title: 'Branches', maxWidth: 420, child: picker);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final st = _st;
    if (kMobile && !widget.embedded) return _phone(st);
    final content = Column(children: [
      if (widget.embedded)
        Container(
          height: PaneRow.height,
          padding: EdgeInsets.fromLTRB(S.of(18), 0, S.s8, 0),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: AppColors.paneLine, width: AppColors.hairline)),
          ),
          child: Row(children: [
            Expanded(
              child: Text('Source control',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(PaneRow.label, color: AppColors.fg3)),
            ),
            if (widget.onClose != null) ...[
              SizedBox(width: S.s2),
              IconBtn('x',
                  size: 26,
                  iconSize: 13,
                  tooltip: 'Close to sessions',
                  onTap: widget.onClose),
            ],
          ]),
        )
      else
        SnAppBar(
          title: 'Git',
          onBack: widget.onClose ?? () => Navigator.pop(context),
        ),
      if (_busy || _refreshing)
        LinearProgressIndicator(
          minHeight: 2,
          backgroundColor: AppColors.tint2,
          color: AppColors.accent,
        ),
      if (_loading)
        Expanded(
          child: Center(child: DelayedSpinner(size: 22)),
        )
      else if (_error != null && (st == null || !st.ok))
        Expanded(
          child: st == null
              ? EmptyState(
                  icon: 'alert-triangle',
                  title: 'Couldn\'t read Git status',
                  body: _error!,
                )
              : EmptyState(
                  icon: 'git-branch',
                  title: 'Not a Git repository',
                  body:
                      'Initialize Git here to track changes, branches and pull requests.',
                  action: Btn(_initing ? 'Initializing…' : 'Initialize Git',
                      small: true,
                      icon: 'git-branch',
                      disabled: _initing,
                      onTap: _initRepo),
                ),
        )
      else
        Expanded(child: _body(st!)),
    ]);

    if (widget.embedded) return content;
    return Scaffold(
      body: SafeArea(bottom: false, child: content),
    );
  }

  // ---- Phone page (kit) ----

  Widget _phone(GitStatus? st) {
    final a = kAndroidLook;
    final slivers = <Widget>[];
    if (_busy || _refreshing) {
      slivers.add(SliverToBoxAdapter(
        child: LinearProgressIndicator(
          minHeight: 2,
          backgroundColor: AppColors.tint2,
          color: AppColors.accent,
        ),
      ));
    }
    if (_loading) {
      slivers.add(SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: DelayedSpinner(size: 22)),
      ));
    } else if (_error != null && (st == null || !st.ok)) {
      slivers.add(SliverFillRemaining(
        hasScrollBody: false,
        child: st == null
            ? EmptyState(
                icon: 'alert-triangle',
                title: 'Couldn\'t read Git status',
                body: _error!,
              )
            : EmptyState(
                icon: 'git-branch',
                title: 'Not a Git repository',
                body:
                    'Initialise Git here to track changes, branches and pull requests.',
                action: MkPill(_initing ? 'Initialising…' : 'Initialise Git',
                    icon: 'git-branch', onTap: _initing ? null : _initRepo),
              ),
      ));
    } else {
      slivers.addAll(_phoneSlivers(st!));
    }
    slivers.add(SliverToBoxAdapter(child: SizedBox(height: a ? 24 : 32)));
    return Material(
      color: AppColors.bg,
      child: MkPage(
        title: 'Git',
        onBack: widget.onClose ?? () => Navigator.pop(context),
        bottomClearance: false,
        onRefresh: _loading ? null : () async => _load(),
        slivers: slivers,
      ),
    );
  }

  List<Widget> _phoneSlivers(GitStatus st) {
    final moving = {..._optStaged, ..._optUnstaged};
    final staged = [
      ...st.staged.where((f) => !_optUnstaged.contains(f.path)),
      ...[...st.changed, ...st.untracked]
          .where((f) => _optStaged.contains(f.path) && !f.staged),
    ];
    final changed = [
      ...st.changed.where((f) => !_optStaged.contains(f.path)),
      ...st.staged.where(
          (f) => _optUnstaged.contains(f.path) && f.x != 'A' && !f.unstaged),
    ];
    final untracked = [
      ...st.untracked.where((f) => !_optStaged.contains(f.path)),
      ...st.staged.where((f) => _optUnstaged.contains(f.path) && f.x == 'A'),
    ];
    final empty = st.files.isEmpty && moving.isEmpty;
    Widget box(Widget w) => SliverToBoxAdapter(child: w);
    final hasUp = st.upstream != null;
    final sync = hasUp
        ? (st.ahead == 0 && st.behind == 0
            ? 'Up to date'
            : [
                if (st.ahead > 0) '${st.ahead} to push',
                if (st.behind > 0) '${st.behind} to pull',
              ].join(' · '))
        : 'Not published';
    return [
      box(MkGroup(children: [
        PhoneListRow(
          leading: phoneRowIcon(AppIcon('git-branch',
              size: kAndroidLook ? 19 : 17, color: AppColors.fg2)),
          title: Text(st.branch.isEmpty ? '(no branch)' : st.branch,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(14, color: AppColors.fg1)),
          sub: sync,
          trailing: AppIcon('chevron-down', size: 16, color: AppColors.fg4),
          onTap: _busy ? null : _branchSheet,
        ),
        if (hasUp) ...[
          MkGroupRow(
            icon: 'arrow-down',
            label: st.behind > 0 ? 'Pull ${st.behind}' : 'Pull',
            chevron: false,
            onTap: _busy
                ? null
                : () =>
                    _op(() => widget.client.gitPull(_repo), okMsg: 'Pulled'),
          ),
          MkGroupRow(
            icon: 'arrow-up',
            label: st.ahead > 0 ? 'Push ${st.ahead}' : 'Push',
            chevron: false,
            onTap: _busy
                ? null
                : () =>
                    _op(() => widget.client.gitPush(_repo), okMsg: 'Pushed'),
          ),
        ] else
          MkGroupRow(
            icon: 'upload',
            label: 'Publish branch',
            chevron: false,
            onTap: _busy
                ? null
                : () =>
                    _op(() => widget.client.gitPush(_repo), okMsg: 'Published'),
          ),
      ])),
      if (empty)
        box(Padding(
          padding: const EdgeInsets.only(top: 32),
          child: EmptyState(
            icon: 'check-check',
            title: 'Working tree clean',
            body: 'No changes to commit.',
          ),
        ))
      else ...[
        if (staged.isNotEmpty)
          ..._phoneSection('Staged', 'Unstage all',
              () => _op(() => widget.client.gitUnstage(_repo)), staged, true),
        if (changed.isNotEmpty)
          ..._phoneSection(
              'Changes',
              'Stage all',
              () => _op(() => widget.client.gitStage(_repo, all: true)),
              changed,
              false),
        if (untracked.isNotEmpty)
          ..._phoneSection(
              'Untracked',
              'Stage all',
              () => _op(() => widget.client.gitStage(_repo, all: true)),
              untracked,
              false),
      ],
      box(_phoneCommit(st)),
    ];
  }

  List<Widget> _phoneSection(String title, String actionLabel,
      VoidCallback onAction, List<GitFile> files, bool staged) {
    final expanded = files.length <= _collapsedLimit + 2 ||
        _expandedSections.contains(title);
    final shown = expanded ? files : files.take(_collapsedLimit).toList();
    return [
      SliverToBoxAdapter(
          child: MkSection(title,
              trailing: actionLabel, onTrailing: _busy ? null : onAction)),
      SliverToBoxAdapter(
        child: MkGroup(children: [
          for (var i = 0; i < shown.length; i++)
            _phoneFile(shown[i],
                staged: staged, last: i == shown.length - 1 && expanded),
          if (!expanded)
            MkGroupRow(
              icon: 'chevron-down',
              label: 'Show ${files.length - _collapsedLimit} more',
              chevron: false,
              onTap: () => setState(() => _expandedSections.add(title)),
            ),
        ]),
      ),
    ];
  }

  Widget _phoneFile(GitFile f, {required bool staged, required bool last}) {
    final code = staged
        ? (f.x.trim().isNotEmpty ? f.x : (f.untracked ? 'A' : f.y))
        : (f.untracked ? '?' : (f.y.trim().isNotEmpty ? f.y : f.x));
    final (fg, _) = toneColors(_statusTone(code));
    final slash = f.path.lastIndexOf('/');
    final name = slash < 0 ? f.path : f.path.substring(slash + 1);
    final dir = slash < 0 ? '' : f.path.substring(0, slash);
    return Semantics(
      label: f.path,
      child: PhoneListRow(
        leading: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration:
              BoxDecoration(color: AppColors.surface3, shape: BoxShape.circle),
          child: Text(code == '?' ? 'U' : code,
              style: mono(12, weight: FontWeight.w600, color: fg)),
        ),
        title: Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mono(13.5, color: AppColors.fg1)),
        sub: dir.isEmpty ? null : dir,
        monoSub: true,
        trailing: MkIconTap(staged ? 'minus' : 'plus',
            staged ? 'Unstage ${f.path}' : 'Stage ${f.path}', () {
          if (!_busy) _toggleStage(f, staged: staged);
        }),
        onTap: () => _openDiff(f, staged: staged),
        last: last,
      ),
    );
  }

  Widget _phoneCommit(GitStatus st) {
    final hasStaged = st.staged.isNotEmpty;
    final hasAny = st.files.isNotEmpty;
    final hasMsg = _commitController.text.trim().isNotEmpty;
    final canCommit = !_busy && hasMsg && hasAny;
    final a = kAndroidLook;
    final label = hasStaged
        ? 'Commit ${st.staged.length}'
        : hasAny
            ? 'Commit all'
            : 'Commit';
    // Stays tappable with staged files and no message; _commit focuses the field.
    final VoidCallback? onTap = hasStaged
        ? (_busy ? null : _commit)
        : (canCommit ? _stageAllAndCommit : null);
    return Padding(
      padding:
          EdgeInsets.fromLTRB(a ? 16 : MK.gutter, 24, a ? 16 : MK.gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(MK.groupRadius),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _commitController,
                  focusNode: _commitFocus,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  onChanged: (_) => setState(() {}),
                  style: sans(15, color: AppColors.fg1),
                  cursorColor: AppColors.fg1,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    hintText: 'Commit message',
                    hintStyle: sans(15, color: AppColors.fg4),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          MkPill(label, tone: MkPillTone.primary, expand: true, onTap: onTap),
        ],
      ),
    );
  }

  // ---- End phone page ----

  Widget _body(GitStatus st) {
    final moving = {..._optStaged, ..._optUnstaged};
    final staged = [
      ...st.staged.where((f) => !_optUnstaged.contains(f.path)),
      ...[...st.changed, ...st.untracked]
          .where((f) => _optStaged.contains(f.path) && !f.staged),
    ];
    final changed = [
      ...st.changed.where((f) => !_optStaged.contains(f.path)),
      ...st.staged.where(
          (f) => _optUnstaged.contains(f.path) && f.x != 'A' && !f.unstaged),
    ];
    final untracked = [
      ...st.untracked.where((f) => !_optStaged.contains(f.path)),
      ...st.staged.where((f) => _optUnstaged.contains(f.path) && f.x == 'A'),
    ];
    final empty = st.files.isEmpty && moving.isEmpty;
    return Column(children: [
      _header(st),
      Expanded(
        child: PullToRefresh(
          onRefresh: () async => _load(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: kMobile
                ? EdgeInsets.fromLTRB(S.s16, S.of(10), S.s16, S.s24)
                : EdgeInsets.fromLTRB(S.s12, S.of(10), S.s12, S.s16),
            children: [
              if (empty)
                Padding(
                  padding: EdgeInsets.only(top: S.s24),
                  child: EmptyState(
                    icon: 'check-check',
                    title: 'Working tree clean',
                    body: 'No changes to commit.',
                  ),
                )
              else ...[
                if (staged.isNotEmpty) ...[
                  _sectionCard(
                    title: 'Staged',
                    count: staged.length,
                    actionLabel: 'Unstage all',
                    onAction: () => _op(() => widget.client.gitUnstage(_repo)),
                    files: staged,
                    staged: true,
                  ),
                  SizedBox(height: S.s16),
                ],
                if (changed.isNotEmpty) ...[
                  _sectionCard(
                    title: 'Changes',
                    count: changed.length,
                    actionLabel: 'Stage all',
                    onAction: () =>
                        _op(() => widget.client.gitStage(_repo, all: true)),
                    files: changed,
                    staged: false,
                  ),
                  SizedBox(height: S.s16),
                ],
                if (untracked.isNotEmpty) ...[
                  _sectionCard(
                    title: 'Untracked',
                    count: untracked.length,
                    actionLabel: 'Stage all',
                    onAction: () =>
                        _op(() => widget.client.gitStage(_repo, all: true)),
                    files: untracked,
                    staged: false,
                  ),
                ],
              ],
              _commitComposer(st),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _header(GitStatus st) {
    final hasUp = st.upstream != null;
    return Padding(
      padding: kMobile
          ? EdgeInsets.fromLTRB(S.s16, S.s6, S.s16, S.s4)
          : EdgeInsets.fromLTRB(S.s12, S.s8, S.s12, S.s4),
      child: Row(children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Builder(
              builder: (anchor) => InkWell(
                onTap: _busy ? null : () => _branchSheet(anchor),
                borderRadius: BorderRadius.circular(R.sm),
                child: Container(
                  height: kMobile ? 40 : 28,
                  padding: EdgeInsets.symmetric(horizontal: S.s4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    AppIcon('git-branch', size: 15, color: AppColors.fg3),
                    SizedBox(width: S.s6),
                    Flexible(
                      child: Text(
                        st.branch.isEmpty ? '(no branch)' : st.branch,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            codeMono(kMobile ? 13 : 12, color: AppColors.fg1),
                      ),
                    ),
                    SizedBox(width: S.s4),
                    AppIcon('chevron-down', size: 14, color: AppColors.fg4),
                  ]),
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: S.s8),
        if (hasUp) ...[
          CompactBtn(
            st.behind > 0 ? 'Pull ${st.behind}' : 'Pull',
            disabled: _busy,
            onTap: () =>
                _op(() => widget.client.gitPull(_repo), okMsg: 'Pulled'),
          ),
          SizedBox(width: S.s6),
          CompactBtn(
            st.ahead > 0 ? 'Push ${st.ahead}' : 'Push',
            disabled: _busy,
            onTap: () =>
                _op(() => widget.client.gitPush(_repo), okMsg: 'Pushed'),
          ),
        ] else
          CompactBtn(
            'Publish',
            disabled: _busy,
            onTap: () =>
                _op(() => widget.client.gitPush(_repo), okMsg: 'Published'),
          ),
      ]),
    );
  }

  Widget _commitComposer(GitStatus st) {
    final hasStaged = st.staged.isNotEmpty;
    final hasAny = st.files.isNotEmpty;
    final hasMsg = _commitController.text.trim().isNotEmpty;
    final canCommit = !_busy && hasMsg && hasAny;
    void submit() {
      if (canCommit) hasStaged ? _commit() : _stageAllAndCommit();
    }

    return Padding(
      padding: EdgeInsets.only(top: S.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            constraints: BoxConstraints(minHeight: kMobile ? 44 : 56),
            padding: EdgeInsets.symmetric(horizontal: S.of(12), vertical: S.s6),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(kMobile ? R.md : R.sm),
              border: Border.all(color: AppColors.border),
            ),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                    submit,
                const SingleActivator(LogicalKeyboardKey.enter, control: true):
                    submit,
              },
              child: TextField(
                controller: _commitController,
                focusNode: _commitFocus,
                minLines: kMobile ? 1 : 2,
                maxLines: 4,
                style: kMobile
                    ? sans(16, color: AppColors.fg1)
                    : TS.ui(AppColors.fg1),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: kMobile
                      ? 'Commit message'
                      : 'Commit message (${kMacOS ? 'Cmd' : 'Ctrl'}+Enter to commit)',
                  hintStyle: kMobile
                      ? sans(16, color: AppColors.fg4)
                      : TS.ui(AppColors.fg4),
                  contentPadding: EdgeInsets.symmetric(vertical: S.s4),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          SizedBox(height: S.s8),
          Row(children: [
            Text(
              hasStaged
                  ? '${st.staged.length} staged'
                  : hasAny
                      ? 'Nothing staged · ${st.changed.length + st.untracked.length} changed'
                      : 'Clean',
              style: TS.meta(),
            ),
            const Spacer(),
            if (hasStaged)
              // Stays primary while the message is empty; _commit focuses the field.
              CompactBtn('Commit ${st.staged.length}',
                  primary: true, disabled: _busy, onTap: _commit)
            else if (hasAny)
              CompactBtn('Commit all',
                  disabled: !canCommit, onTap: _stageAllAndCommit)
            else
              const CompactBtn('Commit', disabled: true),
          ]),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required int count,
    required String actionLabel,
    required VoidCallback onAction,
    required List<GitFile> files,
    required bool staged,
  }) {
    final expanded = files.length <= _collapsedLimit + 2 ||
        _expandedSections.contains(title);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(S.s4, S.s4, S.s4, S.s4),
          child: Row(children: [
            Expanded(
              child: Text(title,
                  style: sans(13, weight: W.label, color: AppColors.fg2)),
            ),
            InkWell(
              onTap: _busy ? null : onAction,
              borderRadius: BorderRadius.circular(R.sm),
              child: Container(
                constraints: BoxConstraints(minHeight: kMobile ? 32 : 24),
                alignment: Alignment.center,
                padding: EdgeInsets.symmetric(horizontal: S.s4),
                child: Text(actionLabel,
                    style: sans(kMobile ? 13 : 12, color: AppColors.fg3)),
              ),
            ),
          ]),
        ),
        CardGroupScope(
            child: ListGroup(children: [
          for (final f in expanded ? files : files.take(_collapsedLimit))
            _fileItem(f, staged: staged),
          if (!expanded)
            ListRow(
              title: 'Show ${files.length - _collapsedLimit} more',
              titleWidget: Text('Show ${files.length - _collapsedLimit} more',
                  style: TS.label(AppColors.accent)),
              onTap: () => setState(() => _expandedSections.add(title)),
            ),
        ])),
      ],
    );
  }

  Widget _fileItem(GitFile f, {required bool staged}) {
    final code = staged
        ? (f.x.trim().isNotEmpty ? f.x : (f.untracked ? 'A' : f.y))
        : (f.untracked ? '?' : (f.y.trim().isNotEmpty ? f.y : f.x));
    final tone = _statusTone(code);
    final (fg, bg) = toneColors(tone);
    return Tooltip(
        message: f.path,
        waitDuration: const Duration(milliseconds: 600),
        child: Semantics(
          label: f.path,
          child: InkWell(
            onTap: () => _openDiff(f, staged: staged),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  S.s12, kMobile ? 0 : S.s2, S.s4, kMobile ? 0 : S.s2),
              child: Row(children: [
                Container(
                  width: kMobile ? 22 : 20,
                  height: kMobile ? 22 : 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(R.sm),
                  ),
                  child: Text(code == '?' ? 'U' : code,
                      style: mono(11, weight: FontWeight.w600, color: fg)),
                ),
                SizedBox(width: S.of(10)),
                Expanded(
                  child: Text(f.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: codeMono(kMobile ? 13 : 12, color: AppColors.fg1)),
                ),
                IconBtn(
                  staged ? 'minus' : 'plus',
                  size: kMobile ? 40 : 30,
                  iconSize: kMobile ? 16 : 14,
                  tooltip: staged ? 'Unstage' : 'Stage',
                  onTap: _busy ? null : () => _toggleStage(f, staged: staged),
                ),
              ]),
            ),
          ),
        ));
  }

  Tone _statusTone(String code) => switch (code) {
        'M' => kMobile ? Tone.neutral : Tone.run,
        'A' => Tone.ok,
        'D' => Tone.danger,
        'R' => Tone.accent,
        '?' => Tone.ok,
        _ => Tone.neutral,
      };
}

class GitBranchPicker extends StatefulWidget {
  final String current;
  final List<String> local;
  final List<String> remotes;
  final void Function(String name, {required bool create}) onSelect;
  const GitBranchPicker({
    super.key,
    required this.current,
    required this.local,
    required this.remotes,
    required this.onSelect,
  });
  @override
  State<GitBranchPicker> createState() => _GitBranchPickerState();
}

class _GitBranchPickerState extends State<GitBranchPicker> {
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _q.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  bool _hit(String name) {
    final q = _q.text.trim().toLowerCase();
    return q.isEmpty || name.toLowerCase().contains(q);
  }

  String _localNameForRemote(String remote) {
    final i = remote.indexOf('/');
    return i < 0 ? remote : remote.substring(i + 1);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final local = widget.local.where(_hit).toList();
    final remotes = widget.remotes.where(_hit).toList();
    final q = _q.text.trim();
    final canCreate = q.isNotEmpty &&
        !widget.local.contains(q) &&
        !q.contains(' ') &&
        !q.startsWith('-');

    if (!kMobile) return _desktop(local, remotes, q, canCreate);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppField(
          controller: _q,
          hint: 'Search local or remote branches',
          icon: 'search',
        ),
        SizedBox(height: S.of(10)),
        if (local.isNotEmpty) ...[
          SectionHeader('Local',
              padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s6)),
          ListGroup(children: [
            for (final b in local)
              _branchRow(
                name: b,
                current: b == widget.current,
                onTap: b == widget.current
                    ? null
                    : () => widget.onSelect(b, create: false),
              ),
          ]),
          SizedBox(height: S.s16),
        ],
        if (remotes.isNotEmpty) ...[
          SectionHeader('Remote',
              padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s6)),
          ListGroup(children: [
            for (final b in remotes)
              _branchRow(
                name: b,
                remote: true,
                onTap: () => widget.onSelect(b, create: false),
              ),
          ]),
          SizedBox(height: S.s16),
        ],
        if (local.isEmpty && remotes.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: S.s16),
            child: Center(
              child: Text(
                q.isEmpty ? 'No branches.' : 'No matches for “$q”.',
                style: TS.ui(AppColors.fg3),
              ),
            ),
          ),
        Btn(
          canCreate ? 'Create branch “$q”' : 'New branch',
          icon: 'plus',
          variant: BtnVariant.secondary,
          full: true,
          onTap: () async {
            if (canCreate) {
              widget.onSelect(q, create: true);
              return;
            }
            final name = await promptText(context,
                title: 'New branch', hint: 'branch name', saveLabel: 'Create');
            if (name == null || name.trim().isEmpty) return;
            widget.onSelect(name.trim(), create: true);
          },
        ),
      ],
    );
  }

  Future<void> _newBranch() async {
    final name = await promptText(context,
        title: 'New branch', hint: 'branch name', saveLabel: 'Create');
    if (name == null || name.trim().isEmpty) return;
    widget.onSelect(name.trim(), create: true);
  }

  void _submit(
      List<String> local, List<String> remotes, String q, bool canCreate) {
    final pick = local.where((b) => b != widget.current).firstOrNull;
    if (pick != null) {
      widget.onSelect(pick, create: false);
    } else if (remotes.isNotEmpty) {
      widget.onSelect(remotes.first, create: false);
    } else if (canCreate) {
      widget.onSelect(q, create: true);
    }
  }

  Widget _desktopLabel(String text) => Padding(
        padding: EdgeInsets.fromLTRB(S.of(10), S.s12, S.of(10), S.s4),
        child: Text(text, style: sans(12, color: AppColors.fg4)),
      );

  Widget _desktopRow({
    required String icon,
    required Widget label,
    required VoidCallback? onTap,
    bool current = false,
  }) =>
      Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.md),
          onTap: onTap,
          child: SizedBox(
            height: 32,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: S.of(10)),
              child: Row(children: [
                AppIcon(icon,
                    size: 14,
                    color: current ? AppColors.accent : AppColors.fg3),
                SizedBox(width: S.of(10)),
                Expanded(child: label),
                if (current)
                  AppIcon('check', size: 14, color: AppColors.accent),
              ]),
            ),
          ),
        ),
      );

  Widget _desktop(
      List<String> local, List<String> remotes, String q, bool canCreate) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppField(
          controller: _q,
          hint: 'Search or create a branch',
          icon: 'search',
          autofocus: true,
          onSubmitted: (_) => _submit(local, remotes, q, canCreate),
        ),
        if (local.isNotEmpty) ...[
          _desktopLabel('Local'),
          for (final b in local)
            _desktopRow(
              icon: 'git-branch',
              current: b == widget.current,
              onTap: b == widget.current
                  ? null
                  : () => widget.onSelect(b, create: false),
              label: Text(b,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(13,
                      color: b == widget.current
                          ? AppColors.accent
                          : AppColors.fg1)),
            ),
        ],
        if (remotes.isNotEmpty) ...[
          _desktopLabel('Remote'),
          for (final b in remotes)
            _desktopRow(
              icon: 'globe',
              onTap: () => widget.onSelect(b, create: false),
              label: Text.rich(
                TextSpan(children: [
                  TextSpan(text: _localNameForRemote(b)),
                  TextSpan(
                      text: '  ${b.split('/').first}',
                      style: sans(12, color: AppColors.fg4)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(13, color: AppColors.fg1),
              ),
            ),
        ],
        if (local.isEmpty && remotes.isEmpty && !canCreate)
          Padding(
            padding: EdgeInsets.symmetric(vertical: S.of(14)),
            child: Center(
              child: Text(q.isEmpty ? 'No branches' : 'No matches',
                  style: sans(13, color: AppColors.fg3)),
            ),
          ),
        SizedBox(height: S.s6),
        Container(height: 1, color: AppColors.border),
        SizedBox(height: S.s6),
        _desktopRow(
          icon: 'plus',
          onTap:
              canCreate ? () => widget.onSelect(q, create: true) : _newBranch,
          label: Text(canCreate ? 'Create branch “$q”' : 'New branch…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(13,
                  color: canCreate ? AppColors.accent : AppColors.fg2)),
        ),
      ],
    );
  }

  Widget _branchRow({
    required String name,
    required VoidCallback? onTap,
    bool current = false,
    bool remote = false,
  }) {
    return ListRow(
      title: name,
      onTap: onTap,
      leading: AppIcon('git-branch',
          size: 16, color: current ? AppColors.accent : AppColors.fg3),
      titleWidget: Text(remote ? _localNameForRemote(name) : name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TS.code(current ? AppColors.accent : AppColors.fg1)),
      subtitle: remote ? name : null,
      trailing: current ? const Tag('Current', tone: Tone.accent) : null,
    );
  }
}

enum _DiffLineType { meta, hunk, add, del, context }

const _patchHeaders = [
  'index ',
  '--- ',
  '+++ ',
  'new file mode',
  'deleted file mode',
  'old mode',
  'new mode',
  'similarity index',
  'dissimilarity index',
  'rename from',
  'rename to',
  'copy from',
  'copy to',
];

class _DiffLineData {
  final int? oldLine;
  final int? newLine;
  final String text;
  final _DiffLineType type;

  const _DiffLineData({
    this.oldLine,
    this.newLine,
    required this.text,
    required this.type,
  });
}

/// Read-only unified-diff viewer with +/- line tints and dual line number gutters.
///
/// Public so a single change can open as a shell tab: the git sidebar panel
/// inspects a diff beside the chat, and that is the same widget the full Git
/// screen pushes. [embedded] drops the app bar when a shell tab already
/// provides chrome.
class GitFileDiffView extends StatefulWidget {
  final DaemonClient client;
  final String sessionId;
  final String file;
  final bool staged;
  final bool untracked;
  final bool embedded;

  const GitFileDiffView({
    super.key,
    required this.client,
    required this.sessionId,
    required this.file,
    required this.staged,
    required this.untracked,
    this.embedded = false,
  });

  @override
  State<GitFileDiffView> createState() => _GitFileDiffViewState();
}

class _GitFileDiffViewState extends State<GitFileDiffView> {
  String? _patch;
  String? _error;
  bool _loading = true;
  List<_DiffLineData> _parsedLines = const [];
  int _additions = 0;
  int _deletions = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await widget.client.gitDiff(
        widget.sessionId,
        file: widget.file,
        staged: widget.staged,
        untracked: widget.untracked,
      );
      if (!mounted) return;
      final parsed = _parseDiff(p);
      setState(() {
        _patch = p;
        _parsedLines = parsed.lines;
        _additions = parsed.additions;
        _deletions = parsed.deletions;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  ({List<_DiffLineData> lines, int additions, int deletions}) _parseDiff(
      String patch) {
    if (patch.trim().isEmpty) {
      return (lines: const <_DiffLineData>[], additions: 0, deletions: 0);
    }
    final rawLines = patch.split('\n');
    final result = <_DiffLineData>[];
    int oldLine = 0;
    int newLine = 0;
    int adds = 0;
    int dels = 0;
    var inHunk = false;
    final hunkRe = RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@(.*)');

    for (final raw in rawLines) {
      if (raw.isEmpty || raw.startsWith('\\')) continue;
      final match = hunkRe.firstMatch(raw);
      if (match != null) {
        oldLine = int.parse(match.group(1)!);
        newLine = int.parse(match.group(2)!);
        final context = match.group(3)!.trim();
        if (!kMobile || inHunk || context.isNotEmpty) {
          result.add(_DiffLineData(
            oldLine: null,
            newLine: null,
            text: kMobile ? context : raw,
            type: _DiffLineType.hunk,
          ));
        }
        inHunk = true;
      } else if (raw.startsWith('diff ')) {
        inHunk = false;
      } else if (!inHunk && raw.startsWith('Binary files')) {
        result.add(_DiffLineData(
          oldLine: null,
          newLine: null,
          text: 'Binary file changed',
          type: _DiffLineType.meta,
        ));
      } else if (!inHunk && _patchHeaders.any(raw.startsWith)) {
      } else if (raw.startsWith('+')) {
        adds++;
        result.add(_DiffLineData(
          oldLine: null,
          newLine: newLine++,
          text: raw.length > 1 ? raw.substring(1) : '',
          type: _DiffLineType.add,
        ));
      } else if (raw.startsWith('-')) {
        dels++;
        result.add(_DiffLineData(
          oldLine: oldLine++,
          newLine: null,
          text: raw.length > 1 ? raw.substring(1) : '',
          type: _DiffLineType.del,
        ));
      } else if (raw.startsWith(' ')) {
        result.add(_DiffLineData(
          oldLine: oldLine++,
          newLine: newLine++,
          text: raw.length > 1 ? raw.substring(1) : '',
          type: _DiffLineType.context,
        ));
      } else {
        result.add(_DiffLineData(
          oldLine: null,
          newLine: null,
          text: raw,
          type: _DiffLineType.context,
        ));
      }
    }
    return (lines: result, additions: adds, deletions: dels);
  }

  Widget _diffHeader(String name, String? parentDir, {required bool showBack}) {
    return Container(
      height: PaneRow.height,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(
                color: AppColors.paneLine, width: AppColors.hairline)),
      ),
      child: Row(children: [
        if (showBack) ...[
          IconBtn('chevron-left',
              size: 26,
              iconSize: 14,
              tooltip: 'Back',
              onTap: () => Navigator.pop(context)),
          SizedBox(width: S.s4),
        ] else
          SizedBox(width: S.s4),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: name),
              if ((parentDir ?? '').isNotEmpty)
                TextSpan(
                    text: '  $parentDir',
                    style: sans(12, color: AppColors.fg4)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sans(PaneRow.label,
                weight: W.label,
                color: Color.lerp(AppColors.fg1, AppColors.fg2, 0.3)),
          ),
        ),
        if (_additions > 0) ...[
          Text('+$_additions', style: mono(12, color: AppColors.diffAddFg)),
          SizedBox(width: S.s4),
        ],
        if (_deletions > 0) ...[
          Text('-$_deletions', style: mono(12, color: AppColors.diffDelFg)),
          SizedBox(width: S.s4),
        ],
        if (_patch != null && _patch!.isNotEmpty)
          IconBtn('clipboard', size: 26, iconSize: 13, tooltip: 'Copy diff',
              onTap: () {
            Clipboard.setData(ClipboardData(text: _patch!));
            toast(context, 'Diff copied');
          }),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final name = widget.file.split('/').last;
    final slash = widget.file.lastIndexOf('/');
    final parentDir = slash > 0 ? widget.file.substring(0, slash) : null;

    final bar = SnAppBar(
      title: name,
      subtitle: parentDir,
      onBack: () => Navigator.pop(context),
      actions: [
        if (_additions > 0 || _deletions > 0)
          Padding(
            padding: EdgeInsets.only(right: S.s8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_additions > 0)
                Tag('+$_additions', tone: Tone.ok, mono: true),
              if (_additions > 0 && _deletions > 0) SizedBox(width: S.s4),
              if (_deletions > 0)
                Tag('-$_deletions', tone: Tone.danger, mono: true),
            ]),
          ),
        if (_patch != null && _patch!.isNotEmpty)
          IconBtn('clipboard', tooltip: 'Copy diff', onTap: () {
            Clipboard.setData(ClipboardData(text: _patch!));
            toast(context, 'Diff copied');
          }),
      ],
    );

    final body = Column(children: [
      if (!widget.embedded && kMobile) bar,
      if (!kMobile) _diffHeader(name, parentDir, showBack: !widget.embedded),
      if (_loading)
        Expanded(
          child: Center(child: DelayedSpinner(size: 22)),
        )
      else if (_error != null)
        Expanded(
          child: EmptyState(
            icon: 'alert-triangle',
            title: 'Diff failed',
            body: _error!,
          ),
        )
      else if (_parsedLines.isEmpty)
        Expanded(
          child: EmptyState(
            icon: 'file',
            title: widget.untracked ? 'Untracked file' : 'No diff',
            body: widget.untracked
                ? 'New file — stage it to include it in the next commit.'
                : 'No changes to show for this view.',
          ),
        )
      else
        Expanded(child: _diffBody()),
    ]);

    if (widget.embedded) {
      return kMobile
          ? ColoredBox(color: AppColors.pageCanvas, child: body)
          : body;
    }
    return Scaffold(
      backgroundColor: kMobile ? AppColors.pageCanvas : Colors.transparent,
      body: SafeArea(bottom: false, child: body),
    );
  }

  Widget _diffBody() {
    _gutterWidth = _measureGutter();
    return LayoutBuilder(builder: (context, c) {
      final paneWidth = c.maxWidth.isFinite ? c.maxWidth : 0.0;
      final width = _contentWidth();
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width > paneWidth ? width : paneWidth,
          child: SelectionArea(
            child: ListView.builder(
              itemCount: _parsedLines.length,
              itemBuilder: (_, i) => _renderDiffLine(_parsedLines[i]),
            ),
          ),
        ),
      );
    });
  }

  double _gutterWidth = 14;

  // Rows are built lazily, so the horizontal extent can't come from measuring
  // them all; the widest is near enough the longest in a monospaced face.
  double _contentWidth() {
    var longest = '';
    for (final l in _parsedLines) {
      if (l.text.length > longest.length) longest = l.text;
    }
    final painter = TextPainter(
      text: TextSpan(
          text: longest,
          style: DefaultTextStyle.of(context)
              .style
              .merge(codeMono(12, height: 1.4))),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width + (kMobile ? _gutterWidth + 40 : (_gutterWidth + 14) * 2 + 32);
  }

  double _measureGutter() {
    var max = 0;
    for (final l in _parsedLines) {
      for (final v in [l.oldLine ?? 0, l.newLine ?? 0]) {
        if (v > max) max = v;
      }
    }
    // Measured in the real face: a fixed per-digit guess wrapped wide numbers
    // where the mono font runs wider than 7pt.
    final painter = TextPainter(
      text: TextSpan(
          text: '8' * max.toString().length,
          style: codeMono(kMobile ? 11 : 12)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width.ceilToDouble() + 2;
    painter.dispose();
    return width < 18 ? 18 : width;
  }

  Widget _renderDiffLine(_DiffLineData line) {
    if (line.type == _DiffLineType.hunk && !kMobile) {
      return Container(
        width: double.infinity,
        height: 28,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.only(left: 12),
        alignment: Alignment.centerLeft,
        color: AppColors.tint1,
        child: Text(line.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                codeMono(11.5, weight: FontWeight.w400, color: AppColors.fg4)),
      );
    }
    if (line.type == _DiffLineType.hunk) {
      return Container(
        width: double.infinity,
        margin: EdgeInsets.symmetric(vertical: S.s8),
        padding: EdgeInsets.symmetric(horizontal: S.s12, vertical: S.s2),
        child: Text(line.text.isEmpty ? '⋯' : line.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TS.codeSmall(AppColors.fg4)),
      );
    }

    if (line.type == _DiffLineType.meta) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: S.s12, vertical: S.of(1)),
        child: Text(line.text, style: TS.codeSmall(AppColors.fg4)),
      );
    }

    final isAdd = line.type == _DiffLineType.add;
    final isDel = line.type == _DiffLineType.del;

    Color? bg;
    Color fg = AppColors.fg2;
    Color gutterFg = kMobile ? AppColors.fg4 : AppColors.diffGutter;
    String sign = ' ';

    if (isAdd) {
      bg = AppColors.diffAddBg;
      fg = AppColors.diffAddFg;
      gutterFg = kMobile
          ? AppColors.diffAddFg.withValues(alpha: 0.6)
          : AppColors.diffGutter;
      sign = '+';
    } else if (isDel) {
      bg = AppColors.diffDelBg;
      fg = AppColors.diffDelFg;
      gutterFg = kMobile
          ? AppColors.diffDelFg.withValues(alpha: 0.6)
          : AppColors.diffGutter;
      sign = '-';
    }

    final oldStr = line.oldLine?.toString() ?? '';
    final newStr = line.newLine?.toString() ?? '';

    if (kMobile) {
      final n = (line.newLine ?? line.oldLine)?.toString() ?? '';
      return Container(
        width: double.infinity,
        color: bg,
        padding: EdgeInsets.symmetric(vertical: S.of(1)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: S.s8),
          SizedBox(
            width: _gutterWidth,
            child: Text(n,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                textAlign: TextAlign.right,
                style: codeMono(11, height: 1.5, color: gutterFg)),
          ),
          SizedBox(
            width: 16,
            child: Text(sign,
                textAlign: TextAlign.center,
                style: codeMono(12, height: 1.4, weight: W.label, color: fg)),
          ),
          Padding(
            padding: EdgeInsets.only(right: S.s16),
            child: Text(
              line.text.isEmpty ? ' ' : line.text,
              style: codeMono(12, height: 1.4, color: fg),
            ),
          ),
        ]),
      );
    }

    return Container(
      width: double.infinity,
      color: bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _gutterWidth + 14,
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Text(oldStr,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  textAlign: TextAlign.right,
                  style: codeMono(12, height: 20 / 12, color: gutterFg)),
            ),
          ),
          SizedBox(
            width: _gutterWidth + 14,
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Text(newStr,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  textAlign: TextAlign.right,
                  style: codeMono(12, height: 20 / 12, color: gutterFg)),
            ),
          ),
          SizedBox(
            width: 16,
            child: Text(sign, style: codeMono(12, height: 20 / 12, color: fg)),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(
              line.text.isEmpty ? ' ' : line.text,
              style: codeMono(12, height: 20 / 12, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// A kit-styled group row with a custom title widget (mono paths, rich names).
class PhoneListRow extends StatelessWidget {
  const PhoneListRow({
    super.key,
    required this.leading,
    required this.title,
    this.sub,
    this.monoSub = false,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.last = true,
  });
  final VoidCallback? onLongPress;
  final bool selected;
  final Widget leading;
  final Widget title;
  final String? sub;
  final bool monoSub;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final a = kAndroidLook;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        title,
        if (sub != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(sub!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: monoSub ? mkMonoSub() : sans(13, color: AppColors.fg3)),
          ),
      ],
    );
    return Material(
        color: selected ? AppColors.surface2 : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          splashFactory: a ? InkRipple.splashFactory : NoSplash.splashFactory,
          highlightColor: AppColors.fg1.withValues(alpha: 0.04),
          child: Padding(
            padding: a
                ? const EdgeInsets.fromLTRB(16, 6, 4, 6)
                : const EdgeInsets.only(left: 16, right: 2),
            child: Row(children: [
              leading,
              SizedBox(width: a ? 14 : 12),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    border: a || last
                        ? null
                        : Border(
                            bottom: BorderSide(color: MK.hairline, width: 0.5)),
                  ),
                  child: Row(children: [
                    Expanded(child: text),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      trailing!,
                    ],
                  ]),
                ),
              ),
            ]),
          ),
        ));
  }
}

/// The tonal icon tile at the head of a kit group row (circle on Android).
Widget phoneRowIcon(Widget icon) {
  final a = kAndroidLook;
  return Container(
    width: a ? 40 : 30,
    height: a ? 40 : 30,
    decoration: BoxDecoration(
      color: AppColors.surface3,
      shape: a ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: a ? null : BorderRadius.circular(9),
    ),
    child: Center(child: icon),
  );
}
