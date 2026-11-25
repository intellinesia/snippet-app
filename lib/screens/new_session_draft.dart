import '../quiet.dart' show QuietHand;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../desktop_pick.dart';
import '../mochi.dart';
import '../platform.dart';
import '../models.dart';
import '../theme.dart';
import '../tap_detector.dart';
import '../widgets.dart';
import 'spec_bar.dart';

/// `sheet` is the new-session dialog body; `hero` is the empty-state composer
/// with its settings as chips.
enum NewSessionLayout { sheet, hero, phone }

enum _Wt { fresh, here, existing }

class NewSessionDraft extends StatefulWidget {
  const NewSessionDraft({
    super.key,
    required this.client,
    required this.machineLabel,
    required this.onStart,
    this.folder,
    this.source,
    this.recentSessions,
    this.onOpenSession,
    this.layout = NewSessionLayout.sheet,
    this.onCancel,
    this.onStartWithFiles,
    this.footer,
  });

  final DaemonClient client;
  final String machineLabel;
  final String? folder;

  /// The session this draft was opened from, for folder/branch/profile prefill.
  final SessionInfo? source;

  /// Pool the recent folders come from; fetched from the daemon when null.
  final List<SessionInfo>? recentSessions;
  final ValueChanged<String>? onOpenSession;
  final NewSessionLayout layout;

  /// Close/Cancel in the sheet; both are hidden when null.
  final VoidCallback? onCancel;

  /// When set, "Add context" is offered and picked files are passed here
  /// instead of [onStart].
  final Future<void> Function(
      String folder,
      WorkspaceMode mode,
      String? profile,
      String text,
      List<PickedLocalFile> files)? onStartWithFiles;

  /// Shown under the hero composer (the pick-up-where-you-left-off list).
  final Widget? footer;
  final Future<void> Function(
      String folder, WorkspaceMode mode, String? profile, String text) onStart;

  @override
  State<NewSessionDraft> createState() => _NewSessionDraftState();
}

class _NewSessionDraftState extends State<NewSessionDraft> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _folderKey = GlobalKey();
  String? _folder;
  _Wt _wt = _Wt.fresh;
  Worktree? _existing;
  List<Worktree> _worktrees = const [];
  bool _isRepo = false;
  List<InferenceProfile> _profiles = const [];
  List<CoordinationAgent> _agents = const [];
  String? _profile;

  /// The agent the draft starts as; its profile is the default model.
  String _agentId = 'snippet';
  String? _agentProfile;

  /// Only an explicit pick (or a pinned source session) is sent to the daemon;
  /// following the agent's profile means omitting `profile`.
  bool _profileExplicit = false;
  bool _starting = false;

  /// Why the last start failed; the message in the box is kept.
  String? _startError;
  List<SessionInfo>? _recentPool;
  final List<PickedLocalFile> _files = [];

  bool get _sheet => widget.layout == NewSessionLayout.sheet;
  bool get _phone => widget.layout == NewSessionLayout.phone;

  @override
  void initState() {
    super.initState();
    final sourceFolder = widget.source?.projectFolder ?? '';
    _folder = widget.folder ?? (sourceFolder.isEmpty ? null : sourceFolder);
    _agentId = widget.source?.displayAgentId ?? 'snippet';
    _input.addListener(() => setState(() {}));
    _loadRepo();
    _loadProfiles();
    _loadRecents();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  CoordinationAgent? get _agent =>
      _agents.where((a) => a.id == _agentId).firstOrNull;

  String get _agentName => _agent?.displayName ?? _agentLabel(_agentId);

  static String _agentLabel(String id) =>
      id.isEmpty ? 'Agent' : id[0].toUpperCase() + id.substring(1);

  Future<void> _loadProfiles() async {
    try {
      final cfg = await widget.client.getConfig();
      List<CoordinationAgent> agents = const [];
      try {
        agents = await widget.client.coordinationAgents();
      } catch (_) {}
      if (!mounted) return;
      final agent = agents.where((a) => a.id == _agentId).firstOrNull;
      bool known(String? name) =>
          name != null && cfg.profiles.any((p) => p.name == name);
      final pinned =
          known(widget.source?.profile) ? widget.source!.profile : null;
      final agentProfile = known(agent?.profile) ? agent!.profile : null;
      setState(() {
        _profiles = cfg.profiles;
        _agents = agents;
        _profile = pinned ??
            agentProfile ??
            cfg.active ??
            cfg.profiles.where((p) => p.active).firstOrNull?.name;
        _profileExplicit = pinned != null;
        _agentProfile = _profileExplicit ? null : agentProfile;
      });
    } catch (_) {}
  }

  Future<void> _loadRepo() async {
    final f = _folder;
    if (f == null || f.isEmpty) {
      setState(() {
        _isRepo = false;
        _worktrees = const [];
      });
      return;
    }
    try {
      final r = await widget.client.worktrees(f);
      if (!mounted || _folder != f) return;
      setState(() {
        _isRepo = r.repo != null;
        _worktrees = r.worktrees;
        if (!_isRepo) {
          _wt = _Wt.here;
          _existing = null;
        } else if (_wt == _Wt.existing &&
            !_worktrees.any((w) => w.path == _existing?.path)) {
          _wt = _Wt.fresh;
          _existing = null;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _isRepo = false);
    }
  }

  Future<void> _loadRecents() async {
    if (widget.recentSessions != null || _recentPool != null) return;
    try {
      final all = await widget.client.sessions();
      if (mounted) setState(() => _recentPool = all);
    } catch (_) {}
  }

  List<SessionInfo> get _pool =>
      widget.recentSessions ?? _recentPool ?? const <SessionInfo>[];

  List<String> get _recentFolders {
    final sorted = [..._pool]
      ..sort((a, b) => b.lastActive.compareTo(a.lastActive));
    final out = <String>[];
    for (final s in sorted) {
      final f = s.projectFolder;
      if (f.isNotEmpty && !out.contains(f)) out.add(f);
      if (out.length == 6) break;
    }
    return out;
  }

  int _sessionsIn(String path) => _pool.where((s) => s.folder == path).length;

  Future<void> _pickFolder() async {
    final anchor = _folderKey.currentContext;
    final choice = await _showFolderQuick(
      context,
      anchor: anchor,
      folder: _folder,
      recents: _recentFolders,
      worktrees: _isRepo ? _worktrees : const [],
      sessionsIn: _sessionsIn,
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _FolderChoice(:final worktree?):
        setState(() {
          _wt = _Wt.existing;
          _existing = worktree;
        });
      case _FolderChoice(:final path?):
        _setFolder(path);
      case _FolderChoice(browse: true, :final create):
        final picked = await _showFolderPopover(
          context,
          anchor: _folderKey.currentContext,
          client: widget.client,
          startPath: _folder,
          startCreating: create,
        );
        if (picked != null && mounted) _setFolder(picked);
      default:
    }
    if (mounted) _focus.requestFocus();
  }

  void _setFolder(String path) {
    setState(() {
      _folder = path;
      _existing = null;
      if (_wt == _Wt.existing) _wt = _Wt.fresh;
    });
    _loadRepo();
  }

  Future<void> _addFiles() async {
    try {
      final files = await pickLocalFiles();
      if (files.isNotEmpty && mounted) setState(() => _files.addAll(files));
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  Future<void> _start() async {
    final text = _input.text.trim();
    if (_starting) return;
    final folder =
        _existing != null && _wt == _Wt.existing ? _existing!.path : _folder;
    if (folder == null || folder.isEmpty) {
      await _pickFolder();
      return;
    }
    if (text.isEmpty) return;
    final mode = _isRepo && _wt == _Wt.fresh
        ? WorkspaceMode.worktree
        : WorkspaceMode.folder;
    final profile = _profileExplicit ? _profile : null;
    setState(() {
      _starting = true;
      _startError = null;
    });
    try {
      final withFiles = widget.onStartWithFiles;
      if (withFiles != null) {
        await withFiles(folder, mode, profile, text, List.of(_files));
      } else {
        await widget.onStart(folder, mode, profile, text);
      }
    } catch (e) {
      if (mounted)
        setState(() => _startError = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _pickProfile(BuildContext anchor) async {
    if (_profiles.isEmpty) return;
    final picked = await showAppMenu<String>(
      context,
      anchor: anchor,
      below: _sheet,
      minWidth: 260,
      maxWidth: 360,
      items: [
        appMenuHeading<String>('Inference profile'),
        for (final p in _profiles)
          appMenuRow<String>(
            value: p.name,
            icon: 'provider:${p.provider}',
            label: p.name,
            description: '${p.provider} · ${p.model}',
            selected: p.name == _profile,
          ),
      ],
    );
    if (picked != null && mounted) {
      setState(() {
        _profile = picked;
        _profileExplicit = true;
        _agentProfile = null;
      });
    }
  }

  Future<void> _pickAgent(BuildContext anchor) async {
    if (_agents.isEmpty) return;
    final picked = await showAppMenu<String>(
      context,
      anchor: anchor,
      below: _sheet,
      minWidth: 220,
      maxWidth: 300,
      items: [
        for (final a in _agents.where((a) => a.kind != 'group'))
          appMenuRow<String>(
            value: a.id,
            leading: AgentMochi(a.id, size: 16),
            label: a.displayName,
            selected: a.id == _agentId,
          ),
      ],
    );
    if (picked == null || !mounted || picked == _agentId) return;
    final agent = _agents.firstWhere((a) => a.id == picked);
    final profile =
        _profiles.any((p) => p.name == agent.profile) ? agent.profile : null;
    setState(() {
      _agentId = picked;
      if (profile != null) {
        _profile = profile;
        _profileExplicit = picked != 'snippet';
        _agentProfile = picked == 'snippet' ? profile : null;
      }
    });
  }

  Future<void> _pickWorktree(BuildContext anchor) async {
    final picked = await showAppMenu<Object>(
      context,
      anchor: anchor,
      minWidth: 240,
      maxWidth: 320,
      items: [
        appMenuRow<Object>(
            value: _Wt.fresh,
            icon: 'git-branch',
            label: 'New worktree',
            selected: _wt == _Wt.fresh),
        appMenuRow<Object>(
            value: _Wt.here,
            icon: 'folder',
            label: 'This folder',
            selected: _wt == _Wt.here),
        if (_isRepo && _worktrees.isNotEmpty) ...[
          appMenuHeading<Object>('Existing worktrees'),
          for (final w in _worktrees)
            appMenuRow<Object>(
                value: w,
                icon: 'git-branch',
                label: _wtName(w),
                selected: _wt == _Wt.existing && _existing?.path == w.path),
        ],
      ],
    );
    if (!mounted) return;
    setState(() {
      if (picked is _Wt) {
        _wt = picked;
        _existing = null;
      } else if (picked is Worktree) {
        _wt = _Wt.existing;
        _existing = picked;
      }
    });
  }

  String _wtName(Worktree w) =>
      (w.branch ?? '').isNotEmpty ? w.branch! : lastPathSegment(w.path);

  // Hero chip: quiet ghost button, as the mockup's `.btn.sm.gh`.
  /// The latest sessions in the chosen folder, for picking one back up.
  List<SessionInfo> get _recents {
    final f = _folder;
    if (f == null || f.isEmpty) return const [];
    final matches = _pool
        .where((s) => s.projectFolder == f || s.folder == f)
        .toList()
      ..sort((a, b) => b.lastActive.compareTo(a.lastActive));
    return matches.take(4).toList();
  }

  Widget _recentMark(SessionInfo s) {
    final agent = s.displayAgentId?.trim() ?? '';
    if (agent.isNotEmpty) return AgentMochi(agent, size: 14);
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.fg4),
    );
  }

  Widget _recentChip(SessionInfo s) {
    final radius = BorderRadius.circular(R.of(10));
    return Material(
      color: AppColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: AppColors.line),
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: () => widget.onOpenSession?.call(s.id),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _recentMark(s),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(s.title.isEmpty ? '(untitled)' : s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TS.label(AppColors.fg2)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _chip(Widget? lead, String label, {VoidCallback? onTap, Key? key}) =>
      Material(
        key: key,
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.of(5)),
          side: BorderSide(color: AppColors.border2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.of(5)),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 24),
            padding: EdgeInsets.symmetric(horizontal: S.of(9), vertical: 3),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (lead != null) ...[lead, SizedBox(width: S.s6)],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12, color: AppColors.fg2)),
              ),
              SizedBox(width: S.s4),
              AppIcon('chevron-down', size: 10, color: AppColors.fg3),
            ]),
          ),
        ),
      );

  Widget _sendButton(bool canSend) => Material(
        color: canSend ? AppColors.accentFill : AppColors.surface3,
        borderRadius: BorderRadius.circular(R.of(8)),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.of(8)),
          onTap: canSend ? _start : null,
          child: SizedBox(
            width: 30,
            height: 30,
            child: Center(
              child: _starting
                  ? const Spinner(size: 14)
                  : AppIcon('arrow-up',
                      size: 15,
                      color: canSend ? AppColors.accentFg : AppColors.fg3),
            ),
          ),
        ),
      );

  Widget _field(String label, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: sans(11.5, weight: W.label, color: AppColors.fg3)),
          SizedBox(height: S.s6),
          child,
        ],
      );

  Widget _select(
          {Key? key,
          Widget? lead,
          required String label,
          String? hint,
          bool on = false,
          VoidCallback? onTap}) =>
      Material(
        key: key,
        color: AppColors.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.of(8)),
          side: BorderSide(color: on ? AppColors.fg3 : AppColors.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.of(8)),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 34),
            padding: EdgeInsets.symmetric(horizontal: S.of(10), vertical: 6),
            child: Row(children: [
              if (lead != null) ...[lead, SizedBox(width: S.s8)],
              Expanded(
                child: Row(children: [
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13, color: AppColors.fg1)),
                  ),
                  if (hint != null && hint.isNotEmpty) ...[
                    SizedBox(width: S.s8),
                    Flexible(
                      child: Text(hint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(12, color: AppColors.fg3)),
                    ),
                  ],
                ]),
              ),
              SizedBox(width: S.s6),
              AppIcon('chevron-down', size: 12, color: AppColors.fg3),
            ]),
          ),
        ),
      );

  Widget _segmented(List<(String, String?, bool, VoidCallback?)> items) =>
      Container(
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.of(8)),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(children: [
          for (final (label, icon, on, tap) in items)
            Expanded(
              child: Material(
                color: on ? AppColors.surface3 : Colors.transparent,
                borderRadius: BorderRadius.circular(R.of(6)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(R.of(6)),
                  onTap: tap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Center(
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (icon != null) ...[
                          AppIcon(icon,
                              size: 13,
                              color: on ? AppColors.fg1 : AppColors.fg3),
                          SizedBox(width: S.s6),
                        ],
                        Flexible(
                          child: Text(label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(12.5,
                                  color: on ? AppColors.fg1 : AppColors.fg3)),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );

  Widget _fileChip(int i) => Container(
        constraints: const BoxConstraints(minHeight: 24),
        padding: EdgeInsets.fromLTRB(S.of(7), 2, S.s4, 2),
        decoration: BoxDecoration(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(R.of(5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AppIcon('file', size: 11, color: AppColors.fg3),
          SizedBox(width: S.s6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(_files[i].name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(11.5, color: AppColors.fg2)),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(R.of(4)),
            onTap: () => setState(() => _files.removeAt(i)),
            child: Padding(
              padding: EdgeInsets.all(S.s4),
              child: AppIcon('x', size: 10, color: AppColors.fg3),
            ),
          ),
        ]),
      );

  Widget _messageBox(bool sheet) => TextField(
        controller: _input,
        focusNode: _focus,
        minLines: sheet ? 3 : 2,
        maxLines: 10,
        style: sans(sheet ? 16 : 15, height: 1.5, color: AppColors.fg1),
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: 'Ask, build, or type / for commands',
          hintStyle: sans(sheet ? 16 : 15, color: AppColors.fg3),
        ),
      );

  Widget _agentMark() => AgentMochi(_agentId, size: 14);

  String get _folderLabel => _folder == null
      ? 'Choose folder'
      : lastPathSegment(_folder!, ifEmpty: _folder!);

  String get _worktreeLabel => switch (_wt) {
        _Wt.fresh => 'New worktree',
        _Wt.here => 'This folder',
        _Wt.existing => _existing == null ? 'Existing' : _wtName(_existing!),
      };

  InferenceProfile? get _current =>
      _profiles.where((p) => p.name == _profile).firstOrNull;

  /// The start failed (W4): say so plainly, keep the message, offer retry and
  /// choosing another agent as secondary outlined buttons.
  Widget _startFailure(String why) => Padding(
        padding: EdgeInsets.only(bottom: S.s16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const QuietHand(size: 16),
          SizedBox(width: S.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$_agentName did not start',
                    style: sans(14, weight: W.label, color: AppColors.fg1)),
                SizedBox(height: S.s2),
                Text('$why Your message is kept.',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, color: AppColors.fg2)),
                SizedBox(height: S.s12),
                Wrap(
                  spacing: S.s8,
                  runSpacing: S.s8,
                  children: [
                    Btn('Try again',
                        small: true,
                        variant: BtnVariant.outline,
                        onTap: _start),
                    Builder(
                      builder: (a) => Btn('Choose another agent',
                          small: true,
                          variant: BtnVariant.outline,
                          onTap: () => _pickAgent(a)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ]),
      );

  /// Who this session goes to: face, name and one meta line.
  Widget _identity() {
    final where = [
      if (_folder != null) _folderLabel,
      if (_folder != null) _worktreeLabel,
    ].join(' \u00b7 ');
    return Row(children: [
      ClipRRect(
          borderRadius: BorderRadius.circular(R.of(10)),
          child: AgentMochi(_agentId, size: 40)),
      SizedBox(width: S.s12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_agentName,
                style: sans(20, weight: W.label, color: AppColors.fg1)),
            Row(children: [
              if (_starting) ...[
                const Spinner(size: 12),
                SizedBox(width: S.s6),
              ],
              Flexible(
                child: Text(
                    _starting
                        ? (where.isEmpty ? 'Starting' : 'Starting on $where')
                        : (where.isEmpty ? 'Choose a folder to start' : where),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, color: AppColors.fg3)),
              ),
            ]),
          ],
        ),
      ),
    ]);
  }

  /// While the session opens, the message shows as sent and waits for the agent.
  Widget _sentMessage() => Padding(
        padding: EdgeInsets.only(bottom: S.s16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: S.s16, vertical: S.s12),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(R.of(16)),
            ),
            child: Text(_input.text.trim(),
                style: sans(15, height: 1.35, color: AppColors.fg1)),
          ),
          SizedBox(height: S.s4),
          Text('Sends when $_agentName is ready',
              style: sans(12, color: AppColors.fg3)),
        ]),
      );

  Widget _hero() {
    final canSend = !_starting && _input.text.trim().isNotEmpty;
    final current = _current;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Center(
            child: Padding(
              padding: EdgeInsets.fromLTRB(S.s32, S.s24, S.s32, 70),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _identity(),
                      SizedBox(height: S.s24),
                      if (_starting && _input.text.trim().isNotEmpty)
                        _sentMessage(),
                      if (_startError != null) _startFailure(_startError!),
                      if (!_starting)
                        Container(
                          padding: EdgeInsets.fromLTRB(
                              S.of(16), S.of(14), S.of(10), S.s8),
                          decoration: BoxDecoration(
                            color: AppColors.surface1,
                            borderRadius: BorderRadius.circular(R.lg),
                            border: Border.all(color: AppColors.border2),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              CallbackShortcuts(
                                bindings: {
                                  const SingleActivator(
                                      LogicalKeyboardKey.enter): _start,
                                },
                                child: _messageBox(false),
                              ),
                              SizedBox(height: S.s8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: Wrap(
                                      spacing: S.s4,
                                      runSpacing: S.s4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        _chip(
                                            AppIcon('folder',
                                                size: 12, color: AppColors.fg3),
                                            _folderLabel,
                                            key: _folderKey,
                                            onTap: _pickFolder),
                                        Builder(
                                          builder: (a) => _chip(
                                              _agentMark(), _agentName,
                                              onTap: () => _pickAgent(a)),
                                        ),
                                        if (current != null)
                                          Builder(
                                            builder: (a) => _chip(
                                                null, current.name,
                                                onTap: () => _pickProfile(a)),
                                          ),
                                        Builder(
                                          builder: (a) => _chip(
                                              AppIcon('git-branch',
                                                  size: 12,
                                                  color: AppColors.fg3),
                                              _worktreeLabel,
                                              onTap: () => _pickWorktree(a)),
                                        ),
                                        for (var i = 0; i < _files.length; i++)
                                          _fileChip(i),
                                      ],
                                    ),
                                  ),
                                  if (widget.onStartWithFiles != null)
                                    IconBtn('paperclip',
                                        size: 28,
                                        iconSize: 15,
                                        tooltip: 'Add context',
                                        onTap: _addFiles),
                                  SizedBox(width: S.s4),
                                  _sendButton(canSend),
                                ],
                              ),
                            ],
                          ),
                        ),
                      if (!_starting)
                        Padding(
                          padding: EdgeInsets.only(top: S.s8, left: S.s12),
                          child: Text(
                              'Enter sends \u00b7 Shift Enter for a new line \u00b7 @ names another agent',
                              style: sans(12, color: AppColors.fg3)),
                        ),
                      if (widget.footer != null)
                        widget.footer!
                      else if (widget.onOpenSession != null &&
                          _recents.isNotEmpty) ...[
                        SizedBox(height: S.of(14)),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 2),
                              child: Text('Recent',
                                  style: TS.caption(AppColors.fg3)),
                            ),
                            for (final s in _recents) _recentChip(s),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetCard() {
    final canSend = !_starting && _input.text.trim().isNotEmpty;
    final current = _current;
    final hint = switch (_wt) {
      _Wt.fresh =>
        'A new worktree keeps this session off the main checkout until you merge it.',
      _Wt.here => 'The session edits this folder directly.',
      _Wt.existing => 'The session continues in the chosen worktree.',
    };
    return Container(
      width: 680,
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border2),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 50,
              offset: const Offset(0, 18)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(S.s20, S.of(14), S.of(14), 0),
              child: Row(children: [
                Text('New session',
                    style: sans(15, weight: W.label, color: AppColors.fg1)),
                SizedBox(width: S.of(10)),
                Expanded(
                  child: Text(
                      widget.machineLabel.isEmpty
                          ? ''
                          : 'on ${widget.machineLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, color: AppColors.fg3)),
                ),
                if (widget.onCancel != null)
                  IconBtn('x',
                      size: 28,
                      iconSize: 14,
                      tooltip: 'Close',
                      onTap: widget.onCancel),
              ]),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(S.s20, S.of(14), S.s20, 0),
              child: Container(
                constraints: const BoxConstraints(minHeight: 132),
                padding:
                    EdgeInsets.fromLTRB(S.of(14), S.of(14), S.of(14), S.of(10)),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(R.md),
                  border: Border.all(color: AppColors.border2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CallbackShortcuts(
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.enter,
                            meta: true): _start,
                        const SingleActivator(LogicalKeyboardKey.enter,
                            control: true): _start,
                      },
                      child: _messageBox(true),
                    ),
                    SizedBox(height: S.s12),
                    Wrap(
                      spacing: S.s6,
                      runSpacing: S.s6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (widget.onStartWithFiles != null)
                          Material(
                            color: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(R.of(5)),
                              side: BorderSide(color: AppColors.border2),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(R.of(5)),
                              onTap: _addFiles,
                              child: Container(
                                constraints: const BoxConstraints(minHeight: 24),
                                padding: EdgeInsets.symmetric(
                                    horizontal: S.of(9), vertical: 3),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AppIcon('paperclip',
                                          size: 12, color: AppColors.fg2),
                                      SizedBox(width: S.s6),
                                      Text('Add context',
                                          style: sans(12,
                                              weight: W.label,
                                              color: AppColors.fg1)),
                                    ]),
                              ),
                            ),
                          ),
                        for (var i = 0; i < _files.length; i++) _fileChip(i),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_startError != null)
              Padding(
                padding: EdgeInsets.fromLTRB(S.s20, S.s12, S.s20, 0),
                child: _startFailure(_startError!),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(S.s20, S.s16, S.s20, 0),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  flex: 125,
                  child: _field(
                    'Works in',
                    _select(
                      key: _folderKey,
                      lead: AppIcon('folder', size: 14, color: AppColors.fg2),
                      label: _folderLabel,
                      hint: _folder == null ? null : _parentLabel(_folder!),
                      onTap: _pickFolder,
                    ),
                  ),
                ),
                SizedBox(width: S.s12),
                Expanded(
                  flex: 100,
                  child: _field(
                    'Agent',
                    Builder(
                      builder: (a) => _select(
                        lead: _agentMark(),
                        label: _agentName,
                        onTap: () => _pickAgent(a),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: S.s12),
                Expanded(
                  flex: 100,
                  child: _field(
                    'Model',
                    Builder(
                      builder: (a) => _select(
                        label: current?.name ?? '...',
                        hint: _agentProfile != null ? 'default' : null,
                        onTap: () => _pickProfile(a),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(S.s20, S.s12, S.s20, 0),
              child: Row(children: [
                Expanded(
                  flex: 125,
                  child: _field(
                    'Worktree',
                    _segmented([
                      (
                        'New',
                        'git-branch',
                        _wt == _Wt.fresh,
                        _isRepo ? () => setState(() => _wt = _Wt.fresh) : null
                      ),
                      (
                        'This folder',
                        null,
                        _wt == _Wt.here,
                        () => setState(() {
                              _wt = _Wt.here;
                              _existing = null;
                            })
                      ),
                      (
                        'Existing',
                        null,
                        _wt == _Wt.existing,
                        _isRepo && _worktrees.isNotEmpty
                            ? () => _pickExistingWorktree()
                            : null
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(S.s20, S.s8, S.s20, 0),
              child: Text(
                  _isRepo ? hint : 'This folder is not a git repository.',
                  style: sans(12, color: AppColors.fg3)),
            ),
            SizedBox(height: S.s16),
            Container(
              padding: EdgeInsets.fromLTRB(S.s20, S.of(18), S.of(14), S.of(14)),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Row(children: [
                Text(kMacOS ? '⌘↵ to start' : 'Ctrl ↵ to start',
                    style: sans(12, color: AppColors.fg3)),
                const Spacer(),
                if (widget.onCancel != null) ...[
                  Btn('Cancel',
                      variant: BtnVariant.secondary, onTap: widget.onCancel),
                  SizedBox(width: S.s8),
                ],
                Btn(_starting ? 'Starting' : 'Start session',
                    disabled: !canSend, onTap: _start),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickExistingWorktree() async {
    final box = _folderKey.currentContext;
    final picked = await showAppMenu<Worktree>(
      context,
      anchor: box,
      below: true,
      minWidth: 280,
      maxWidth: 360,
      items: [
        for (final w in _worktrees)
          appMenuRow<Worktree>(
            value: w,
            icon: 'git-branch',
            label: _wtName(w),
            trailing: _sessionsIn(w.path) == 0
                ? null
                : '${_sessionsIn(w.path)} sessions',
            selected: _existing?.path == w.path,
          ),
      ],
    );
    if (picked != null && mounted) {
      setState(() {
        _wt = _Wt.existing;
        _existing = picked;
      });
    }
  }

  /// SE-05 phone page: bar B, then one 16 radius card with the context chips
  /// (36 visual, 44 hit), the prompt and the Start row.
  Widget _phoneCard() {
    final canSend = !_starting && _input.text.trim().isNotEmpty;
    final current = _current;
    Widget pill(String icon, String label, VoidCallback onTap, {Key? key}) =>
        Semantics(
          key: key,
          button: true,
          label: label,
          child: ExcludeSemantics(
            child: TapDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(18)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      AppIcon(icon, size: 16, color: AppColors.fg2),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(12.5, color: AppColors.fg1)),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        );
    final profileLabel = current?.name ?? _agentName;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SpecBar(
              title: 'New session',
              onBack: widget.onCancel ?? () => Navigator.of(context).maybePop()),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Container(
                constraints: const BoxConstraints(minHeight: 330),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                decoration: BoxDecoration(
                    color: AppColors.surface1,
                    borderRadius: BorderRadius.circular(16)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 44,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            pill('folder', _folderLabel, _pickFolder,
                                key: _folderKey),
                            const SizedBox(width: 6),
                            Builder(
                                builder: (a) => pill('sliders', profileLabel,
                                    () => _pickProfile(a))),
                          ],
                        ),
                      ),
                      if (_startError != null) _startFailure(_startError!),
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                            minHeight: 120, maxHeight: 200),
                        child: TextField(
                          controller: _input,
                          focusNode: _focus,
                          minLines: 5,
                          maxLines: null,
                          style: sans(15, height: 1.5, color: AppColors.fg1),
                          cursorColor: AppColors.fg1,
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            hintText: 'What should it do?',
                            hintStyle: sans(15, color: AppColors.fg3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(children: [
                        if (widget.onStartWithFiles != null)
                          Semantics(
                            button: true,
                            label: 'Add context',
                            child: ExcludeSemantics(
                              child: TapDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _addFiles,
                                child: SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: Center(
                                        child: AppIcon('plus',
                                            size: 20, color: AppColors.fg2))),
                              ),
                            ),
                          ),
                        const Spacer(),
                        Semantics(
                          button: true,
                          enabled: canSend,
                          label: 'Start',
                          child: ExcludeSemantics(
                            child: TapDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: canSend ? _start : null,
                              child: Container(
                                width: 120,
                                height: 48,
                                decoration: BoxDecoration(
                                    color: canSend
                                        ? AppColors.fg1
                                        : AppColors.surface3,
                                    borderRadius: BorderRadius.circular(10)),
                                child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _starting
                                          ? const Spinner(size: 14)
                                          : AppIcon('arrow-right',
                                              size: 16,
                                              color: canSend
                                                  ? AppColors.bg
                                                  : AppColors.fg3),
                                      const SizedBox(width: 6),
                                      Text('Start',
                                          style: sans(14,
                                              weight: W.label,
                                              color: canSend
                                                  ? AppColors.bg
                                                  : AppColors.fg3)),
                                    ]),
                              ),
                            ),
                          ),
                        ),
                      ]),
                    ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_phone) return _phoneCard();
    if (!_sheet) return _hero();
    return CallbackShortcuts(
      bindings: {
        if (widget.onCancel != null)
          const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel!,
      },
      child: Container(
        color: Colors.black.withValues(alpha: 0.45),
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 110, bottom: 24),
          child: _sheetCard(),
        ),
      ),
    );
  }
}

String _parentLabel(String path) {
  final i = path.lastIndexOf('/');
  var parent = i > 0 ? path.substring(0, i) : '/';
  parent = parent.replaceFirst(RegExp(r'^/(home|Users)/[^/]+'), '~');
  return parent.isEmpty ? '~' : parent;
}

class _FolderChoice {
  const _FolderChoice(
      {this.path, this.worktree, this.browse = false, this.create = false});
  final String? path;
  final Worktree? worktree;
  final bool browse;
  final bool create;
}

Future<_FolderChoice?> _showFolderQuick(
  BuildContext context, {
  required BuildContext? anchor,
  required String? folder,
  required List<String> recents,
  required List<Worktree> worktrees,
  required int Function(String path) sessionsIn,
}) {
  final screen = MediaQuery.sizeOf(context);
  const width = 300.0;
  var left = (screen.width - width) / 2;
  var top = 220.0;
  final box = anchor?.findRenderObject() as RenderBox?;
  if (box != null) {
    final origin = box.localToGlobal(Offset.zero);
    left = origin.dx
        .clamp(12.0, (screen.width - width - 12).clamp(12.0, double.infinity));
    top = origin.dy + box.size.height + 6;
  }
  return showGeneralDialog<_FolderChoice>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Choose folder',
    barrierColor: Colors.transparent,
    transitionDuration: Motion.quick,
    pageBuilder: (ctx, _, __) => Stack(children: [
      Positioned(
        left: left,
        top: top,
        width: width,
        child: _FolderQuick(
          folder: folder,
          recents: recents,
          worktrees: worktrees,
          sessionsIn: sessionsIn,
        ),
      ),
    ]),
    transitionBuilder: (ctx, anim, _, child) {
      final c = CurvedAnimation(parent: anim, curve: Motion.enter);
      return FadeTransition(
        opacity: c,
        child: ScaleTransition(
          alignment: Alignment.topLeft,
          scale: Tween(begin: 0.97, end: 1.0).animate(c),
          child: child,
        ),
      );
    },
  );
}

class _FolderQuick extends StatefulWidget {
  const _FolderQuick({
    required this.folder,
    required this.recents,
    required this.worktrees,
    required this.sessionsIn,
  });
  final String? folder;
  final List<String> recents;
  final List<Worktree> worktrees;
  final int Function(String) sessionsIn;

  @override
  State<_FolderQuick> createState() => _FolderQuickState();
}

class _FolderQuickState extends State<_FolderQuick> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Widget _row(String icon, String label,
      {String? trailing,
      bool selected = false,
      bool mono_ = false,
      Color? color,
      required _FolderChoice choice}) {
    return InkWell(
      borderRadius: BorderRadius.circular(R.sm),
      onTap: () => Navigator.of(context).pop(choice),
      child: Container(
        height: 30,
        padding: EdgeInsets.symmetric(horizontal: S.s8),
        decoration: BoxDecoration(
          color: selected ? AppColors.surface2 : Colors.transparent,
          borderRadius: BorderRadius.circular(R.sm),
        ),
        child: Row(children: [
          AppIcon(icon, size: 14, color: color ?? AppColors.fg3),
          SizedBox(width: S.of(10)),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono_
                    ? mono(12.5, color: color ?? AppColors.fg1)
                    : sans(12.5, color: color ?? AppColors.fg1)),
          ),
          if (trailing != null)
            Text(trailing, style: sans(11, color: AppColors.fg4)),
          if (selected) AppIcon('check', size: 13, color: AppColors.fg2),
        ]),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: EdgeInsets.fromLTRB(S.s8, S.s8, S.s8, S.s4),
        child:
            Text(text, style: sans(11, weight: W.label, color: AppColors.fg4)),
      );

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim().toLowerCase();
    bool match(String s) => q.isEmpty || s.toLowerCase().contains(q);
    final recents = [
      for (final f in widget.recents)
        if (match(lastPathSegment(f, ifEmpty: f))) f
    ];
    final trees = [
      for (final w in widget.worktrees)
        if (match(w.branch ?? lastPathSegment(w.path))) w
    ];
    return Container(
      padding: EdgeInsets.all(S.s6),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border2),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 50,
              offset: const Offset(0, 18)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 30,
              margin: EdgeInsets.fromLTRB(S.s2, S.s2, S.s2, S.s6),
              padding: EdgeInsets.only(left: S.of(10), right: S.s8),
              decoration: BoxDecoration(
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(R.of(8)),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(children: [
                AppIcon('search', size: 13, color: AppColors.fg4),
                SizedBox(width: S.s8),
                Expanded(
                  child: TextField(
                    controller: _query,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    style: sans(12.5, color: AppColors.fg1),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Find a folder',
                      hintStyle: sans(12.5, color: AppColors.fg4),
                    ),
                  ),
                ),
              ]),
            ),
            if (recents.isNotEmpty) ...[
              _label('Recent folders'),
              for (final f in recents)
                _row('folder', lastPathSegment(f, ifEmpty: f),
                    selected: f == widget.folder,
                    choice: _FolderChoice(path: f)),
            ],
            if (trees.isNotEmpty) ...[
              _label('Existing worktrees'),
              for (final w in trees)
                _row('git-branch', w.branch ?? lastPathSegment(w.path),
                    mono_: true,
                    trailing: widget.sessionsIn(w.path) == 0
                        ? null
                        : '${widget.sessionsIn(w.path)} sessions',
                    choice: _FolderChoice(worktree: w)),
            ],
            Container(
              height: 1,
              margin: EdgeInsets.symmetric(vertical: S.s6),
              color: AppColors.line,
            ),
            _row('folder', 'Choose folder…',
                color: AppColors.fg2,
                choice: const _FolderChoice(browse: true)),
            _row('plus', 'New folder',
                color: AppColors.fg2,
                choice: const _FolderChoice(browse: true, create: true)),
          ],
        ),
      ),
    );
  }
}

Future<String?> _showFolderPopover(
  BuildContext context, {
  required BuildContext? anchor,
  required DaemonClient client,
  String? startPath,
  bool startCreating = false,
}) {
  final screen = MediaQuery.sizeOf(context);
  const width = 340.0;
  var left = (screen.width - width) / 2;
  var top = 220.0;
  final box = anchor?.findRenderObject() as RenderBox?;
  if (box != null) {
    final origin = box.localToGlobal(Offset.zero);
    left = origin.dx
        .clamp(12.0, (screen.width - width - 12).clamp(12.0, double.infinity));
    top = origin.dy + box.size.height + 6;
  }
  final maxHeight = (screen.height - top - 16).clamp(220.0, 360.0);
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Choose folder',
    barrierColor: Colors.transparent,
    transitionDuration: Motion.quick,
    pageBuilder: (ctx, _, __) => Stack(children: [
      Positioned(
        left: left,
        top: top,
        width: width,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: _FolderPopover(
              client: client,
              startPath: startPath,
              startCreating: startCreating),
        ),
      ),
    ]),
    transitionBuilder: (ctx, anim, _, child) {
      final c = CurvedAnimation(parent: anim, curve: Motion.enter);
      return FadeTransition(
        opacity: c,
        child: ScaleTransition(
          alignment: Alignment.topLeft,
          scale: Tween(begin: 0.97, end: 1.0).animate(c),
          child: child,
        ),
      );
    },
  );
}

class _FolderPopover extends StatefulWidget {
  const _FolderPopover(
      {required this.client, this.startPath, this.startCreating = false});
  final DaemonClient client;
  final String? startPath;
  final bool startCreating;

  @override
  State<_FolderPopover> createState() => _FolderPopoverState();
}

class _FolderPopoverState extends State<_FolderPopover> {
  final _crumbScroll = ScrollController();
  final _newFolderCtrl = TextEditingController();
  FsListing? _listing;
  String? _homePath;
  bool _loading = true;
  String? _error;
  bool _creating = false;
  bool _busy = false;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _creating = widget.startCreating;
    _go(widget.startPath);
  }

  @override
  void dispose() {
    _crumbScroll.dispose();
    _newFolderCtrl.dispose();
    super.dispose();
  }

  Future<void> _go(String? path) async {
    final id = ++_run;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.client.fs(path);
      if (!mounted || id != _run) return;
      final learnHome = _homePath == null &&
          (path == null || path.isEmpty) &&
          res.path.isNotEmpty;
      setState(() {
        if (learnHome) _homePath = res.path;
        _listing = res;
        _loading = false;
      });
      if (_homePath == null && path != null && path.isNotEmpty) {
        _learnHome();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _crumbScroll.hasClients) {
          _crumbScroll.jumpTo(_crumbScroll.position.maxScrollExtent);
        }
      });
    } catch (e) {
      if (!mounted || id != _run) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _learnHome() async {
    try {
      final res = await widget.client.fs(null);
      if (mounted && _homePath == null && res.path.isNotEmpty) {
        setState(() => _homePath = res.path);
      }
    } catch (_) {}
  }

  String get _here => _listing?.path ?? '';

  bool get _atHome =>
      _homePath != null && _homePath!.isNotEmpty && _here == _homePath;

  String get _hereName => _here.isEmpty
      ? 'folder'
      : (_atHome ? '~' : lastPathSegment(_here, ifEmpty: _here));

  String get _displayPath {
    final home = _homePath;
    if (home != null && home.isNotEmpty) {
      if (_here == home) return '~';
      if (_here.startsWith('$home/')) {
        return '~/${_here.substring(home.length + 1)}';
      }
    }
    return _here;
  }

  List<FsEntry> get _dirs {
    final entries = _listing?.entries ?? const <FsEntry>[];
    final all = [
      for (final e in entries)
        if (e.isDir) e
    ];
    all.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return all;
  }

  List<({String label, String path})> get _crumbs {
    final home = _homePath;
    final here = _here;
    if (here.isEmpty) return const [];
    if (home != null &&
        home.isNotEmpty &&
        (here == home || here.startsWith('$home/'))) {
      final out = <({String label, String path})>[(label: '~', path: home)];
      if (here == home) return out;
      var acc = home;
      for (final part in here.substring(home.length + 1).split('/')) {
        if (part.isEmpty) continue;
        acc = '$acc/$part';
        out.add((label: part, path: acc));
      }
      return out;
    }
    final parts = here.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return [(label: '/', path: '/')];
    final out = <({String label, String path})>[];
    var acc = '';
    for (final part in parts) {
      acc = '$acc/$part';
      out.add((label: part, path: acc));
    }
    return out;
  }

  Future<void> _submitNewFolder() async {
    final raw = _newFolderCtrl.text.trim();
    if (raw.isEmpty || _here.isEmpty || _busy) return;
    final parts = raw
        .split('/')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty && p != '.')
        .toList();
    if (parts.isEmpty || parts.any((p) => p == '..')) return;
    final target = '$_here/${parts.join('/')}';
    setState(() => _busy = true);
    try {
      await widget.client.mkdir(target);
      if (!mounted) return;
      _newFolderCtrl.clear();
      setState(() {
        _creating = false;
        _busy = false;
      });
      await _go(target);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, '$e', danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final crumbs = _crumbs;
    final dirs = _dirs;
    final parent = _listing?.parent;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassSurface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.42),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(R.lg),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 38,
              padding: EdgeInsets.fromLTRB(S.of(10), 0, S.s6, 0),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Row(children: [
                if (!_atHome && parent != null && parent.isNotEmpty)
                  IconBtn('chevron-left',
                      size: 24,
                      iconSize: 14,
                      tooltip: 'Up one folder',
                      onTap: _loading ? null : () => _go(parent)),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _crumbScroll,
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (var i = 0; i < crumbs.length; i++) ...[
                        if (i > 0)
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: S.s2),
                            child: Text('/',
                                style: mono(12, color: AppColors.fg4)),
                          ),
                        InkWell(
                          borderRadius: BorderRadius.circular(R.of(5)),
                          onTap: i == crumbs.length - 1
                              ? null
                              : () => _go(crumbs[i].path),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: S.of(5), vertical: S.of(3)),
                            child: Text(
                              crumbs[i].label,
                              style: sans(
                                13,
                                weight: i == crumbs.length - 1
                                    ? FontWeight.w500
                                    : FontWeight.w400,
                                color: i == crumbs.length - 1
                                    ? AppColors.fg1
                                    : AppColors.fg3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ]),
                  ),
                ),
                IconBtn(
                  _creating ? 'x' : 'folder-plus',
                  size: 26,
                  iconSize: 14,
                  tooltip: _creating ? 'Cancel' : 'New folder',
                  onTap: _here.isEmpty
                      ? null
                      : () => setState(() {
                            _creating = !_creating;
                            _newFolderCtrl.clear();
                          }),
                ),
              ]),
            ),
            if (_creating)
              Container(
                padding: EdgeInsets.fromLTRB(S.of(10), S.s6, S.s8, S.s6),
                decoration: BoxDecoration(
                  color: AppColors.surface1,
                  border: Border(bottom: BorderSide(color: AppColors.line)),
                ),
                child: Row(children: [
                  AppIcon('folder-plus', size: 14, color: AppColors.fg3),
                  SizedBox(width: S.s8),
                  Expanded(
                    child: TextField(
                      controller: _newFolderCtrl,
                      autofocus: true,
                      style: sans(13, color: AppColors.fg1),
                      onSubmitted: (_) => _submitNewFolder(),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'New folder name',
                        hintStyle: sans(13, color: AppColors.fg4),
                      ),
                    ),
                  ),
                  SizedBox(width: S.s6),
                  InkWell(
                    borderRadius: BorderRadius.circular(R.sm),
                    onTap: _busy ? null : _submitNewFolder,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: S.s8, vertical: S.s4),
                      decoration: BoxDecoration(
                        color: AppColors.surface3,
                        borderRadius: BorderRadius.circular(R.sm),
                      ),
                      child: Text(_busy ? '…' : 'Create',
                          style: sans(12,
                              weight: FontWeight.w500, color: AppColors.fg1)),
                    ),
                  ),
                ]),
              ),
            Flexible(
              child: _loading && _listing == null
                  ? const SizedBox(
                      height: 140,
                      child: Center(child: Spinner(size: 16)),
                    )
                  : _error != null
                      ? Padding(
                          padding: EdgeInsets.all(S.s20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!,
                                  textAlign: TextAlign.center,
                                  style: sans(12, color: AppColors.fg3)),
                              SizedBox(height: S.of(10)),
                              Btn('Retry',
                                  small: true,
                                  onTap: () => _go(widget.startPath)),
                            ],
                          ),
                        )
                      : dirs.isEmpty
                          ? SizedBox(
                              height: 96,
                              child: Center(
                                child: Text('No subfolders',
                                    style: sans(13, color: AppColors.fg4)),
                              ),
                            )
                          : SizedBox(
                              height: (dirs.length.clamp(1, _creating ? 5 : 7) *
                                      32.0) +
                                  12,
                              child: ListView.builder(
                                padding: EdgeInsets.all(S.s6),
                                itemExtent: 32,
                                itemCount: dirs.length,
                                itemBuilder: (ctx, i) {
                                  final e = dirs[i];
                                  return InkWell(
                                    borderRadius:
                                        BorderRadius.circular(R.of(7)),
                                    onTap: () => _go(e.path),
                                    child: Container(
                                      height: 32,
                                      padding: EdgeInsets.symmetric(
                                          horizontal: S.s8),
                                      child: Row(children: [
                                        AppIcon('folder',
                                            size: 15, color: AppColors.fg3),
                                        SizedBox(width: S.of(9)),
                                        Expanded(
                                          child: Text(
                                            e.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style:
                                                sans(13, color: AppColors.fg1),
                                          ),
                                        ),
                                        AppIcon('chevron-right',
                                            size: 14, color: AppColors.fg4),
                                      ]),
                                    ),
                                  );
                                },
                              ),
                            ),
            ),
            Container(
              height: 40,
              padding: EdgeInsets.fromLTRB(S.s12, 0, S.s8, 0),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(
                    _displayPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(12, color: AppColors.fg3),
                  ),
                ),
                SizedBox(width: S.s8),
                Material(
                  color: _here.isEmpty ? AppColors.surface2 : AppColors.fg1,
                  borderRadius: BorderRadius.circular(R.of(13)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(R.of(13)),
                    onTap: _here.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(_here),
                    child: Container(
                      height: 26,
                      padding: EdgeInsets.symmetric(horizontal: S.of(11)),
                      alignment: Alignment.center,
                      child: Text(
                        'Use $_hereName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12,
                            weight: FontWeight.w500,
                            color:
                                _here.isEmpty ? AppColors.fg4 : AppColors.bg),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
