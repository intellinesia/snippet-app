import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart' show GitFile, GitStatus;
import '../swr.dart';
import '../theme.dart';
import '../widgets.dart';
import 'file_tree_sidebar_panel.dart';
import 'git_diff_sidebar_panel.dart';
import 'session.dart' show TerminalHost;
import 'shell_models.dart' show RightPanel, RightTab;

enum _SideTab { files, changes }

class SessionSidePanel extends StatefulWidget {
  const SessionSidePanel({
    super.key,
    required this.client,
    required this.workspacePath,
    required this.onOpenFile,
    this.host,
    this.sessionId,
    this.changesCount,
    this.onTogglePanel,
    this.onOpenDiff,
    this.readouts = const [],
    this.activeReadout,
    this.readoutBody,
    this.onSelectReadout,
    this.onCloseReadout,
    this.onClearReadout,
    this.onExpandReadout,
  });

  final ValueChanged<RightTab>? onExpandReadout;
  final ValueChanged<RightPanel>? onTogglePanel;

  final List<RightTab> readouts;
  final String? activeReadout;
  final Widget Function(RightTab readout)? readoutBody;
  final ValueChanged<RightTab>? onSelectReadout;
  final ValueChanged<RightTab>? onCloseReadout;
  final VoidCallback? onClearReadout;

  final String? sessionId;
  final int? changesCount;
  final void Function(GitFile file)? onOpenDiff;

  final DaemonClient client;
  final String workspacePath;
  final void Function(String path, String name) onOpenFile;
  final TerminalHost? host;

  static final changesRequest = ValueNotifier<int>(0);
  static final filesRequest = ValueNotifier<int>(0);

  @override
  State<SessionSidePanel> createState() => _SessionSidePanelState();
}

class _SessionSidePanelState extends State<SessionSidePanel> {
  static bool _termsOpen = true;
  static _SideTab _tab = _SideTab.files;

  static int _seenRequest = 0;
  static int _seenFilesRequest = 0;

  Swr<GitStatus>? _git;

  String get _repo =>
      widget.sessionId != null && widget.sessionId!.trim().isNotEmpty
          ? widget.sessionId!
          : widget.workspacePath;

  void _showChanges() {
    _seenRequest = SessionSidePanel.changesRequest.value;
    widget.onClearReadout?.call();
    if (mounted) setState(() => _tab = _SideTab.changes);
  }

  void _showFiles() {
    _seenFilesRequest = SessionSidePanel.filesRequest.value;
    widget.onClearReadout?.call();
    if (mounted) setState(() => _tab = _SideTab.files);
  }

  void _watchGit() {
    _git?.dispose();
    _git = null;
    if (widget.changesCount != null || _repo.isEmpty) return;
    _git = Swr<GitStatus>(
      client: widget.client,
      key: 'git:$_repo',
      fetch: () => widget.client.gitStatus(_repo),
      revalidateOn: _touchesRepo,
      onChange: () {
        if (mounted) setState(() {});
      },
    );
  }

  bool _touchesRepo(DeviceEventFrame e) =>
      const {DeviceEventHub.attachedToolResult, 'idle', 'done', 'error'}
          .contains(e['kind']) &&
      ((widget.sessionId != null && e['session'] == widget.sessionId) ||
          e['workspace'] == widget.workspacePath);

  @override
  void initState() {
    super.initState();
    if (SessionSidePanel.changesRequest.value != _seenRequest) {
      _seenRequest = SessionSidePanel.changesRequest.value;
      _tab = _SideTab.changes;
    }
    if (SessionSidePanel.filesRequest.value != _seenFilesRequest) {
      _seenFilesRequest = SessionSidePanel.filesRequest.value;
      _tab = _SideTab.files;
    }
    SessionSidePanel.changesRequest.addListener(_showChanges);
    SessionSidePanel.filesRequest.addListener(_showFiles);
    _watchGit();
  }

  @override
  void didUpdateWidget(covariant SessionSidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client ||
        oldWidget.sessionId != widget.sessionId ||
        oldWidget.workspacePath != widget.workspacePath ||
        oldWidget.changesCount != widget.changesCount) {
      _watchGit();
    }
  }

  @override
  void dispose() {
    SessionSidePanel.changesRequest.removeListener(_showChanges);
    SessionSidePanel.filesRequest.removeListener(_showFiles);
    _git?.dispose();
    super.dispose();
  }

  RightTab? get _readout => widget.readouts
      .where((r) => r.key == widget.activeReadout)
      .firstOrNull;

  String _short(String label) =>
      label.startsWith('Artifacts') ? 'Artifacts' : label;

  int get _changesCount => widget.changesCount ?? _git?.data?.files.length ?? 0;

  Widget _segPill(bool reading) {
    final changes = _changesCount;
    final reduced = reduceMotion(context);
    Widget btn(_SideTab target, String label, int count) {
      final on = !reading && _tab == target;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            widget.onClearReadout?.call();
            setState(() => _tab = target);
          },
          child: AnimatedContainer(
            duration: reduced ? Duration.zero : Motion.fast,
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on
                  ? AppColors.fg1.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(R.pill),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  style: sans(13,
                      weight: on ? W.label : W.body,
                      color: on ? AppColors.fg1 : AppColors.fg3)),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(R.pill),
                  ),
                  child: Text('$count',
                      style: mono(11, color: AppColors.accent)),
                ),
              ],
            ]),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.tint1,
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(_SideTab.files, 'Files', 0),
        btn(_SideTab.changes, 'Changes', changes),
      ]),
    );
  }

  Widget _readoutChip(RightTab r) {
    final on = r.key == widget.activeReadout;
    final compact = widget.readouts.length > 2 && !on;
    if (compact) {
      return Tooltip(
        message: _short(r.label),
        child: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(R.md),
            onTap: () => widget.onSelectReadout?.call(r),
            child: SizedBox(
              width: 28,
              height: 28,
              child: Center(
                  child: AppIcon(r.icon, size: 14, color: AppColors.fg3)),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Material(
        color: on ? AppColors.tint2 : Colors.transparent,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.md),
          onTap: () => widget.onSelectReadout?.call(r),
          child: Container(
            height: 28,
            padding: const EdgeInsets.fromLTRB(9, 0, 5, 0),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_short(r.label),
                  style: sans(12, color: on ? AppColors.fg1 : AppColors.fg4)),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => widget.onCloseReadout?.call(r),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: AppIcon('x', size: 11, color: AppColors.fg4),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _panelHeader(bool reading) {
    final readout = _readout;
    return Container(
      height: 44,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _segPill(reading),
              for (final r in widget.readouts) _readoutChip(r),
            ]),
          ),
        ),
        if (readout != null && widget.onExpandReadout != null)
          IconBtn(
            'maximize-2',
            size: 28,
            iconSize: 14,
            tooltip: 'Open as tab',
            onTap: () => widget.onExpandReadout!(readout),
          ),
      ]),
    );
  }

  Widget _panelBody() {
    final readout = _readout;
    if (readout != null && widget.readoutBody != null) {
      return KeyedSubtree(
        key: ValueKey(readout.key),
        child: widget.readoutBody!(readout),
      );
    }
    if (widget.workspacePath.isEmpty) return const SizedBox();
    if (_tab == _SideTab.changes) {
      return GitDiffSidebarPanel(
        key: ValueKey('git-${widget.workspacePath}'),
        client: widget.client,
        workspacePath: widget.workspacePath,
        sessionId: widget.sessionId,
        onOpenDiff: widget.onOpenDiff,
        showHeader: false,
      );
    }
    return FileTreeSidebarPanel(
      key: ValueKey('files-${widget.workspacePath}'),
      client: widget.client,
      workspacePath: widget.workspacePath,
      onOpenFile: widget.onOpenFile,
      showHeader: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final terms = host?.terms ?? const [];
    final open = _termsOpen && terms.isNotEmpty;
    final readout = _readout;
    final header = MouseRegion(
      cursor:
          terms.isEmpty ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: terms.isEmpty ? null : () => setState(() => _termsOpen = !open),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            AppIcon('terminal', size: 14, color: AppColors.fg3),
            const SizedBox(width: 8),
            Text('Terminals', style: sans(12, color: AppColors.fg3)),
            if (terms.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text('${terms.length}', style: mono(11, color: AppColors.fg4)),
            ],
            const Spacer(),
            AppIcon(open ? 'chevron-down' : 'chevron-right',
                size: 12, color: AppColors.fg3),
          ]),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader(readout != null),
        Expanded(child: _panelBody()),
        Container(height: 1, color: AppColors.line.withValues(alpha: 0.65)),
        header,
        if (open)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(children: [
                for (var i = 0; i < terms.length; i++)
                  _TermTreeRow(
                    title: terms[i].title,
                    alive: terms[i].alive,
                    selected: i == host!.focus,
                    onTap: () => host.focusTerm(terms[i].id),
                    onClose: () => host.closeTerm(terms[i].id),
                  ),
              ]),
            ),
          ),
      ],
    );
  }
}

class _TermTreeRow extends StatefulWidget {
  const _TermTreeRow({
    required this.title,
    required this.alive,
    required this.selected,
    required this.onTap,
    required this.onClose,
  });

  final String title;
  final bool alive;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  State<_TermTreeRow> createState() => _TermTreeRowState();
}

class _TermTreeRowState extends State<_TermTreeRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          color: on || _hover ? AppColors.tint3 : Colors.transparent,
          padding: const EdgeInsets.fromLTRB(24, 5, 14, 5),
          child: Row(children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.alive ? AppColors.ok : AppColors.fg4,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, color: on ? AppColors.fg1 : AppColors.fg2)),
            ),
            const SizedBox(width: 8),
            Text(widget.alive ? 'running' : 'idle',
                style: mono(11, color: AppColors.fg4)),
            if (_hover) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: widget.onClose,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: AppIcon('x', size: 11, color: AppColors.fg3),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
