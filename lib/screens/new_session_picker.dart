import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../desktop_pick.dart';
import '../glass.dart' show ModalGlass;
import '../mochi.dart';
import '../models.dart';
import '../settings_form.dart';
import '../platform.dart';
import '../pull_refresh.dart';
import '../theme.dart';
import '../widgets.dart';
import 'lead/lead_state.dart' show isDedicatedLeadSession;
import 'mobile_chrome.dart';
import '../chat_scene.dart' show SceneBackdrop;
import '../chat/signal_row.dart'
    show agentDisplayName, prettyModel, prettyProfile;
import '../tap_detector.dart';

/// New-session composer on phones, with folder browsing tucked into a sheet.
class NewSessionPicker extends StatefulWidget {
  const NewSessionPicker({
    super.key,
    required this.client,
    required this.machineLabel,
    required this.onOpenFolder,
    this.onStart,
    this.startPath,
    this.onClose,
  });

  final DaemonClient client;

  /// Which machine these folders live on — identity, not a switcher.
  final String machineLabel;

  /// Fallback start when [onStart] is not wired yet.
  final Future<void> Function(String folder, WorkspaceMode workspace)
      onOpenFolder;

  /// Start a conversation in `folder` with the typed prompt and attachments.
  final Future<void> Function(
    String folder,
    WorkspaceMode workspace,
    String? profile,
    String text,
    List<PickedLocalFile> attachments,
  )? onStart;

  /// Initial folder path, or null to default to the daemon's home directory.
  final String? startPath;

  /// Absent when the host owns navigation.
  final VoidCallback? onClose;

  @override
  State<NewSessionPicker> createState() => _NewSessionPickerState();
}

class _NewSessionPickerState extends State<NewSessionPicker> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final List<PickedLocalFile> _attachments = [];

  String? _folder;
  String? _homePath;
  RepoWorktrees? _repo;
  WorkspaceMode _mode = WorkspaceMode.worktree;
  Worktree? _existing;
  List<InferenceProfile> _profiles = const [];
  String? _profile;

  /// `profile` goes to POST /sessions only when the user picked one; the
  /// default follows whatever the daemon resolves.
  bool _profileExplicit = false;
  List<String> _recentFolders = const [];
  bool _starting = false;
  int _repoRun = 0;

  @override
  void initState() {
    super.initState();
    _folder = widget.startPath;
    _input.addListener(() => setState(() {}));
    _loadInitialFolder();
    _loadProfiles();
    _loadRecentFolders();
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadInitialFolder() async {
    final initial = widget.startPath;
    if (initial != null && initial.isNotEmpty) {
      _loadRepo(initial);
    }
    try {
      final res = await widget.client.fs(initial);
      if (!mounted) return;
      final learnedHome = (initial == null || initial.isEmpty) &&
          res.path.isNotEmpty &&
          _homePath == null;
      setState(() {
        if (learnedHome) _homePath = res.path;
        if (_folder == null || _folder!.isEmpty) _folder = res.path;
      });
      if (_folder != null && _folder!.isNotEmpty && _repo == null) {
        _loadRepo(_folder!);
      }
    } catch (_) {}
  }

  Future<void> _loadProfiles() async {
    try {
      final cfg = await widget.client.getConfig();
      if (!mounted) return;
      setState(() {
        _profiles = cfg.profiles;
        _profile =
            cfg.active ?? cfg.profiles.where((p) => p.active).firstOrNull?.name;
      });
    } catch (_) {}
  }

  Future<void> _loadRecentFolders() async {
    try {
      final all = await widget.client.sessions();
      if (!mounted) return;
      final sorted = [...all]
        ..sort((a, b) => b.lastActive.compareTo(a.lastActive));
      final seen = <String>{};
      final folders = <String>[];
      for (final s in sorted) {
        if (isDedicatedLeadSession(s.id)) continue;
        final f = s.projectFolder;
        if (f.isEmpty || !seen.add(f)) continue;
        folders.add(f);
        if (folders.length >= 3) break;
      }
      setState(() => _recentFolders = folders);
    } catch (_) {}
  }

  Future<void> _loadRepo(String path, {Worktree? keepExisting}) async {
    final run = ++_repoRun;
    RepoWorktrees? repo;
    try {
      repo = await widget.client.worktrees(path);
    } catch (_) {}
    if (!mounted || run != _repoRun) return;
    final hasRepo = repo?.repo != null;
    setState(() {
      _repo = hasRepo ? repo : null;
      _existing = hasRepo ? keepExisting : null;
      if (!hasRepo) {
        _mode = WorkspaceMode.folder;
      } else if (keepExisting == null && _existing == null) {
        _mode = WorkspaceMode.worktree;
      }
    });
  }

  void _selectFolder(String folder) {
    setState(() {
      _folder = folder;
      _existing = null;
      _repo = null;
    });
    _loadRepo(folder);
  }

  String _labelForFolder(String? path) {
    if (path == null || path.isEmpty) return 'Choose folder';
    if (_homePath != null && _homePath!.isNotEmpty && path == _homePath) {
      return 'Home';
    }
    return lastPathSegment(path, ifEmpty: path);
  }

  Future<void> _openFolderSheet() async {
    final result = await showFolderBrowserSheet(
      context,
      client: widget.client,
      startPath: _existing?.path ?? _folder ?? widget.startPath,
      homePath: _homePath,
      initialMode: _mode,
      initialExisting: _existing,
    );
    if (result == null || !mounted) return;
    setState(() {
      _folder = result.folder;
      _mode = result.mode;
      _existing = result.existing;
      if (result.homePath != null && _homePath == null) {
        _homePath = result.homePath;
      }
    });
    await _loadRepo(result.folder, keepExisting: result.existing);
    if (mounted) {
      setState(
          () => _mode = _repo == null ? WorkspaceMode.folder : result.mode);
    }
  }

  Future<void> _pickExisting(BuildContext anchor) async {
    final worktrees = _repo?.worktrees ?? const <Worktree>[];
    if (worktrees.isEmpty) return;
    final picked = await showAppMenu<String>(
      context,
      anchor: anchor,
      minWidth: 260,
      maxWidth: 380,
      items: [
        appMenuHeading<String>('Existing worktrees'),
        for (final w in worktrees)
          appMenuRow<String>(
            value: w.path,
            icon: 'git-branch',
            label: w.branch ?? lastPathSegment(w.path, ifEmpty: w.path),
            description: w.path,
            selected: _existing?.path == w.path,
          ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() {
      _existing = worktrees.firstWhere((w) => w.path == picked);
      _mode = WorkspaceMode.folder;
    });
  }

  Future<void> _pickProfile(BuildContext anchor) async {
    if (_profiles.isEmpty) return;
    final picked = await showAppMenu<String>(
      context,
      anchor: anchor,
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
      });
    }
  }

  Future<void> _onAttachTap() async {
    if (!kMobile) {
      await _addPickedFiles();
      return;
    }
    final choice = await showAppSheet<String>(
      context,
      title: 'Add context',
      child: Row(children: [
        _attachOption('camera', 'Camera', 'camera'),
        SizedBox(width: S.s8),
        _attachOption('image', 'Photos', 'photos'),
        SizedBox(width: S.s8),
        _attachOption('file', 'Files', 'files'),
      ]),
    );
    if (!mounted || choice == null) return;
    if (choice == 'camera') {
      final x = await ImagePicker().pickImage(
          source: ImageSource.camera, imageQuality: 85, maxWidth: 2200);
      if (x != null && mounted) {
        setState(() =>
            _attachments.add(PickedLocalFile(name: x.name, path: x.path)));
      }
    } else if (choice == 'photos') {
      final xs =
          await ImagePicker().pickMultiImage(imageQuality: 85, maxWidth: 2200);
      if (xs.isNotEmpty && mounted) {
        setState(() => _attachments.addAll(
            xs.map((x) => PickedLocalFile(name: x.name, path: x.path))));
      }
    } else if (choice == 'files') {
      await _addPickedFiles();
    }
  }

  Future<void> _addPickedFiles() async {
    try {
      final files = await pickLocalFiles();
      if (files.isNotEmpty && mounted) {
        setState(() => _attachments.addAll(files));
      }
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  Widget _attachOption(String icon, String label, String value) => Expanded(
        child: Material(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.of(14)),
          child: InkWell(
            borderRadius: BorderRadius.circular(R.of(14)),
            onTap: () => Navigator.of(context).pop(value),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: S.s16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AppIcon(icon, size: 22, color: AppColors.fg1),
                SizedBox(height: S.s6),
                Text(label, style: TS.label(AppColors.fg2)),
              ]),
            ),
          ),
        ),
      );

  Future<void> _start() async {
    final text = _input.text.trim();
    final attachments = List<PickedLocalFile>.from(_attachments);
    if (_starting) return;
    if (text.isEmpty && attachments.isEmpty) return;
    final folder = _existing?.path ?? _folder;
    if (folder == null || folder.isEmpty) {
      await _openFolderSheet();
      return;
    }
    final mode = _repo == null ? WorkspaceMode.folder : _mode;
    setState(() => _starting = true);
    try {
      if (widget.onStart != null) {
        await widget.onStart!(folder, mode, _profileExplicit ? _profile : null,
            text, attachments);
      } else {
        await widget.onOpenFolder(folder, mode);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _starting = false);
        toast(context, '$e', danger: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final current = _profiles.where((p) => p.name == _profile).firstOrNull;
    final canSend = !_starting &&
        (_input.text.trim().isNotEmpty || _attachments.isNotEmpty);
    return _body(current, canSend);
  }

  Widget _body(InferenceProfile? current, bool canSend) {
    final agent = agentDisplayName('snippet');
    return Scaffold(
      backgroundColor: AppColors.bg,
      resizeToAvoidBottomInset: true,
      body: SceneBackdrop(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(M.gutter, S.of(10), M.gutter, 0),
                child: Row(children: [
                  RoundBtn(
                    icon: 'x',
                    size: 44,
                    iconSize: 20,
                    tooltip: 'Close',
                    onTap: widget.onClose ?? () => Navigator.maybePop(context),
                  ),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(M.gutter, S.s4, M.gutter, S.s16),
                  child: Center(
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: Grouped.contentMaxWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(child: AgentMochi('snippet', size: 96)),
                          SizedBox(height: S.s12),
                          Text('What are we making?',
                              textAlign: TextAlign.center,
                              style: sans(Grouped.heroSize,
                                  weight: W.strong,
                                  spacing: -0.3,
                                  height: kMobile ? 30 / 24 : 26 / 20,
                                  color: AppColors.fg1)),
                          SizedBox(height: S.s4),
                          Text('$agent starts a new session',
                              textAlign: TextAlign.center,
                              style: Grouped.subStyle()),
                          SizedBox(height: 20),
                          _phoneComposer(),
                          SizedBox(height: Grouped.sectionGap),
                          _recentGroup(),
                          if (current != null) _modelGroup(current),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(M.gutter, S.s8, M.gutter, S.s12),
                child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(maxWidth: Grouped.contentMaxWidth),
                    child: _phoneStart(canSend),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _phoneStart(bool canSend) => Tooltip(
        message: 'Start',
        child: Material(
          color: canSend ? AppColors.accentFill : Grouped.row,
          borderRadius: BorderRadius.circular(kMobile ? 26 : 22),
          child: InkWell(
            borderRadius: BorderRadius.circular(kMobile ? 26 : 22),
            onTap: canSend ? _start : null,
            child: SizedBox(
              height: kMobile ? 52 : 44,
              child: Center(
                child: _starting
                    ? Spinner(size: 18, color: AppColors.accentFg)
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        AppIcon('arrow-up',
                            size: 20,
                            color:
                                canSend ? AppColors.accentFg : AppColors.fg4),
                        SizedBox(width: S.s8),
                        Text('Start',
                            style: sans(kMobile ? 17 : 15,
                                weight: W.label,
                                color: canSend
                                    ? AppColors.accentFg
                                    : AppColors.fg4)),
                      ]),
              ),
            ),
          ),
        ),
      );

  Widget _phoneChip(String icon, String label, {VoidCallback? onTap}) {
    final radius = BorderRadius.circular(kMobile ? 18 : 16);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: HitArea(
          alignment: Alignment.center,
          child: Container(
            height: kMobile ? 36 : 32,
            padding: EdgeInsets.symmetric(horizontal: S.s12),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                  AppColors.fg1.withValues(alpha: 0.06), Grouped.row),
              borderRadius: radius,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon(icon, size: kMobile ? 18 : 16, color: AppColors.fg2),
              SizedBox(width: S.s8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(kMobile ? 15 : 13, color: AppColors.fg2)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _phoneComposer() {
    final repo = _repo != null;
    final worktree = _existing == null && _mode == WorkspaceMode.worktree;
    final existingLabel = _existing == null
        ? null
        : (_existing!.branch ??
            lastPathSegment(_existing!.path, ifEmpty: _existing!.path));
    return Container(
      decoration: BoxDecoration(
        color: Grouped.row,
        borderRadius: BorderRadius.circular(Grouped.radiusEnd),
      ),
      padding: EdgeInsets.fromLTRB(S.s16, S.s16, S.s12, S.s12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _input,
            focusNode: _focus,
            minLines: 3,
            maxLines: 8,
            cursorColor: AppColors.accent,
            style: sans(kMobile ? 17 : 15,
                height: kMobile ? 24 / 17 : 22 / 15, color: AppColors.fg1),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.only(right: S.s4),
              hintText: 'Ask, build, or type / for commands',
              hintStyle: sans(kMobile ? 17 : 15,
                  height: kMobile ? 24 / 17 : 22 / 15, color: AppColors.fg2),
            ),
          ),
          if (_attachments.isNotEmpty) ...[
            SizedBox(height: S.s8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < _attachments.length; i++)
                  _attachmentChip(i, _attachments[i]),
              ],
            ),
          ],
          SizedBox(height: S.s12),
          Row(children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _phoneChip('folder', _labelForFolder(_folder),
                      onTap: _openFolderSheet),
                  if (repo && existingLabel != null)
                    Builder(
                      builder: (anchor) => _phoneChip(
                          'git-branch', existingLabel,
                          onTap: () => _pickExisting(anchor)),
                    )
                  else if (repo)
                    _phoneChip(
                        'git-branch', worktree ? 'New worktree' : 'This folder',
                        onTap: () => setState(() => _mode = worktree
                            ? WorkspaceMode.folder
                            : WorkspaceMode.worktree)),
                ],
              ),
            ),
            Tooltip(
              message: 'Add context',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _onAttachTap,
                child: SizedBox(
                  width: M.minTarget,
                  height: M.minTarget,
                  child: Center(
                      child: AppIcon('plus',
                          size: kMobile ? 22 : 18, color: AppColors.fg1)),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _modelGroup(InferenceProfile current) => Builder(
        builder: (anchor) => SettingsGroup(children: [
          SettingsRow(
            label: 'Model',
            icon: 'cpu',
            value: current.model.trim().isNotEmpty
                ? prettyModel(current.model)
                : prettyProfile(current.name),
            chevron: true,
            onTap: () => _pickProfile(anchor),
          ),
        ]),
      );

  String _shortPath(String path) {
    final home = _homePath;
    if (home != null && home.isNotEmpty && path.startsWith('$home/')) {
      return '~${path.substring(home.length)}';
    }
    return path;
  }

  Widget _recentGroup() {
    final rows = <Widget>[
      for (final folder in _recentFolders)
        SettingsRow(
          label: _labelForFolder(folder),
          sub: _shortPath(folder),
          subMaxLines: 1,
          icon: 'folder',
          trailing: folder == _folder && _existing == null
              ? AppIcon('check', size: Grouped.icon, color: AppColors.fg1)
              : null,
          onTap: () => _selectFolder(folder),
        ),
      SettingsRow(
        label: 'Choose folder',
        icon: 'folder-open',
        chevron: true,
        onTap: _openFolderSheet,
      ),
    ];
    return SettingsGroup(
      header: _recentFolders.isEmpty ? null : 'Recent folders',
      children: rows,
    );
  }

  Widget _attachmentChip(int index, PickedLocalFile file) => Container(
        height: 26,
        padding: EdgeInsets.fromLTRB(S.of(9), 0, S.s4, 0),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.of(13)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(12, color: AppColors.fg2),
            ),
          ),
          SizedBox(width: S.s4),
          TapDetector(
            onTap: () => setState(() => _attachments.removeAt(index)),
            child: SizedBox(
              width: 20,
              height: 20,
              child: Center(
                child: AppIcon('x', size: 12, color: AppColors.fg3),
              ),
            ),
          ),
        ]),
      );
}

typedef FolderPickResult = ({
  String folder,
  WorkspaceMode mode,
  Worktree? existing,
  String? homePath,
});

Future<FolderPickResult?> showFolderBrowserSheet(
  BuildContext context, {
  required DaemonClient client,
  String? startPath,
  String? homePath,
  WorkspaceMode initialMode = WorkspaceMode.folder,
  Worktree? initialExisting,
  List<String> recentFolders = const [],
  double rowMinHeight = 52,
  bool showWorkspaceChoice = true,
  bool? phone,
}) {
  final isPhone = phone ?? kMobile;
  final safeTop = math.max(
    MediaQuery.paddingOf(context).top,
    MediaQuery.viewPaddingOf(context).top,
  );
  Widget browser() => _FolderBrowserSheet(
        client: client,
        startPath: startPath,
        homePath: homePath,
        initialMode: initialMode,
        initialExisting: initialExisting,
        recentFolders: recentFolders,
        rowMinHeight: rowMinHeight,
        showWorkspaceChoice: showWorkspaceChoice,
        forcePhone: isPhone,
        topInset: safeTop,
      );
  return isPhone
      ? showModalBottomSheet<FolderPickResult>(
          context: context,
          backgroundColor: Colors.transparent,
          barrierColor: AppColors.scrim,
          isScrollControlled: true,
          useSafeArea: false,
          sheetAnimationStyle: sheetMotion,
          builder: (_) => browser(),
        )
      : showDialog<FolderPickResult>(
          context: context,
          barrierColor: AppColors.modalScrim,
          builder: (_) => ModalGlass(
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding:
                  EdgeInsets.symmetric(horizontal: S.s40, vertical: S.s24),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 580, maxHeight: 620),
                child: browser(),
              ),
            ),
          ),
        );
}

class _FolderBrowserSheet extends StatefulWidget {
  const _FolderBrowserSheet({
    required this.client,
    this.startPath,
    this.homePath,
    required this.initialMode,
    this.initialExisting,
    this.recentFolders = const [],
    this.rowMinHeight = 52,
    this.showWorkspaceChoice = true,
    this.forcePhone = false,
    this.topInset = 0,
  });

  final DaemonClient client;
  final String? startPath;
  final String? homePath;
  final WorkspaceMode initialMode;
  final Worktree? initialExisting;
  final List<String> recentFolders;
  final double rowMinHeight;
  final bool showWorkspaceChoice;
  final bool forcePhone;
  final double topInset;

  @override
  State<_FolderBrowserSheet> createState() => _FolderBrowserSheetState();
}

class _FolderBrowserSheetState extends State<_FolderBrowserSheet> {
  FsListing? _listing;
  late String? _homePath = widget.homePath;
  bool _loading = true;
  String? _error;
  RepoWorktrees? _repo;
  late WorkspaceMode _mode = widget.initialMode;
  late Worktree? _existing = widget.initialExisting;
  String? _busy;
  int _run = 0;
  final ScrollController _crumbScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _go(widget.startPath);
  }

  @override
  void dispose() {
    _crumbScroll.dispose();
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
      setState(() {
        _listing = res;
        if ((path == null || path.isEmpty) && _homePath == null) {
          _homePath = res.path;
        }
        _loading = false;
      });
      _loadRepo(res.path, id);
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

  Future<void> _loadRepo(String path, int run) async {
    RepoWorktrees? repo;
    try {
      repo = await widget.client.worktrees(path);
    } catch (_) {}
    if (!mounted || run != _run) return;
    setState(() {
      _repo = repo?.repo == null ? null : repo;
      if (_repo == null) {
        _mode = WorkspaceMode.folder;
        _existing = null;
      } else if (_existing != null &&
          !_repo!.worktrees.any((w) => w.path == _existing!.path)) {
        _existing = null;
      }
    });
  }

  Future<void> _pickExisting(BuildContext anchor) async {
    final worktrees = _repo?.worktrees ?? const <Worktree>[];
    final picked = await showAppMenu<String>(
      context,
      anchor: anchor,
      minWidth: 260,
      maxWidth: 380,
      items: [
        appMenuHeading<String>('Existing worktrees'),
        for (final w in worktrees)
          appMenuRow<String>(
            value: w.path,
            icon: 'git-branch',
            label: w.branch ?? lastPathSegment(w.path, ifEmpty: w.path),
            description: w.path,
            selected: _existing?.path == w.path,
          ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() {
      _existing = worktrees.firstWhere((w) => w.path == picked);
      _mode = WorkspaceMode.folder;
    });
  }

  List<FsEntry> get _dirs => _sorted(true);
  List<FsEntry> get _files => _sorted(false);

  List<FsEntry> _sorted(bool dirs) {
    final entries = _listing?.entries ?? const <FsEntry>[];
    final all = [
      for (final e in entries)
        if (e.isDir == dirs) e
    ];
    all.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return all;
  }

  String get _here => _listing?.path ?? '';

  bool get _atHome =>
      _homePath == null || _homePath!.isEmpty || _here == _homePath;

  String get _hereName => _here.isEmpty || _atHome
      ? 'Home'
      : lastPathSegment(_here, ifEmpty: _here);

  List<_Crum> get _crumbs {
    final home = _homePath;
    final here = _here;
    if (here.isEmpty) return const [];
    if (home == null || home.isEmpty) return [_Crum('Home', here)];
    final crumbs = <_Crum>[_Crum('Home', home)];
    if (here == home) return crumbs;
    if (!here.startsWith('$home/')) {
      return [...crumbs, _Crum(_hereName, here)];
    }
    var acc = home;
    for (final part in here.substring(home.length + 1).split('/')) {
      if (part.isEmpty) continue;
      acc = '$acc/$part';
      crumbs.add(_Crum(part, acc));
    }
    return crumbs;
  }

  void _confirm() {
    final existing = _existing;
    final path = existing?.path ?? _here;
    if (path.isEmpty) return;
    final mode = _repo == null ? WorkspaceMode.folder : _mode;
    Navigator.of(context).pop((
      folder: path,
      mode: mode,
      existing: existing,
      homePath: _homePath,
    ));
  }

  String? _sanitizeRel(String raw) {
    final parts = raw
        .split('/')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty && p != '.')
        .toList();
    if (parts.isEmpty) return null;
    if (parts.any((p) => p == '..')) return null;
    return parts.join('/');
  }

  Future<void> _newFolder() => _create(isDir: true);
  Future<void> _newFile() => _create(isDir: false);

  Future<void> _create({required bool isDir}) async {
    final dir = _here;
    if (dir.isEmpty) return;
    final name = await promptText(
      context,
      title: isDir ? 'New folder' : 'New file',
      hint: isDir ? 'name, or path/in/one/go' : 'name, or path/in/one.go',
      saveLabel: 'Create',
    );
    if (name == null || !mounted) return;
    final rel = _sanitizeRel(name);
    if (rel == null) {
      toast(context, 'Enter a name, with no leading / or ..', danger: true);
      return;
    }
    setState(() => _busy = 'Creating…');
    try {
      final path = '$dir/$rel';
      if (isDir) {
        await widget.client.mkdir(path);
      } else {
        await widget.client.writeFile(path, '');
      }
      if (!mounted) return;
      setState(() => _busy = null);
      await _go(dir);
      if (mounted) toast(context, 'Created $rel');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      toast(context, '$e', danger: true);
    }
  }

  Future<void> _upload() async {
    final dir = _here;
    if (dir.isEmpty) return;
    List<PickedLocalFile> files;
    try {
      files = await pickLocalFiles();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
      return;
    }
    if (files.isEmpty) return;
    var done = 0;
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      if (mounted) {
        setState(() => _busy = 'Uploading ${i + 1}/${files.length}…');
      }
      try {
        await widget.client
            .uploadFile(await f.readAsBytes(), name: f.name, dir: dir);
        done++;
      } catch (e) {
        if (mounted) toast(context, '${f.name}: $e', danger: true);
      }
    }
    if (!mounted) return;
    setState(() => _busy = null);
    if (done > 0) {
      await _go(dir);
      if (mounted) toast(context, 'Uploaded $done file${done == 1 ? '' : 's'}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (kMobile || widget.forcePhone) return _mobileBuild(media);
    final limit = (media.size.height * 0.84).clamp(320.0, 680.0);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
              kMobile ? M.gutter : S.s20,
              kMobile ? S.s4 : S.of(14),
              kMobile ? S.s8 : S.s12,
              kMobile ? S.s6 : S.s12),
          child: Row(children: [
            Expanded(
              child: Text('Choose folder',
                  style: kMobile
                      ? TS.sectionTitle()
                      : sans(14.5, weight: W.strong, color: AppColors.fg1)),
            ),
            IconBtn('x',
                size: kMobile ? M.minTarget : 28,
                iconSize: kMobile ? 18 : 14,
                tooltip: 'Close',
                onTap: () => Navigator.of(context).pop()),
          ]),
        ),
        if (!kMobile) Divider(height: 1, thickness: 1, color: AppColors.line),
        if (_error != null)
          Expanded(child: _errorState())
        else ...[
          if (!kMobile) SizedBox(height: S.s8),
          _breadcrumbs(),
          Expanded(
            child: _loading && _listing == null
                ? const Center(child: Spinner(size: 20))
                : PullToRefresh(
                    onRefresh: () async => _go(_here),
                    child: _folderList(),
                  ),
          ),
          if (_repo != null) _workspaceChoice(),
          _actionBar(kMobile ? media.padding.bottom : 0),
        ],
      ],
    );
    if (!kMobile) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(R.card),
          border: Border.all(color: AppColors.glassBorder),
          boxShadow: overlayShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(type: MaterialType.transparency, child: content),
      );
    }
    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: Material(
        type: MaterialType.transparency,
        child: AppSheetSurface(
          color: AppColors.bg,
          child: SizedBox(height: limit, child: content),
        ),
      ),
    );
  }

  // Spec DL-05: large sheet, header, path line, folder rows, pinned Select.
  String get _pathLine {
    final parts = _here.split('/').where((p) => p.isNotEmpty).toList();
    final t = parts.join(' / ');
    if (t.length <= 44) return t;
    return '${t.substring(0, 18)} \u2026 ${t.substring(t.length - 22)}';
  }

  String get _selectLabel {
    if (widget.showWorkspaceChoice &&
        (_existing != null ||
            (_repo != null && _mode == WorkspaceMode.worktree))) {
      return _confirmLabel;
    }
    return 'Select ${_here.isEmpty ? 'folder' : lastPathSegment(_here, ifEmpty: _here)}';
  }

  Widget _mobileBuild(MediaQueryData media) {
    final topInset = widget.topInset > 0
        ? widget.topInset
        : math.max(media.padding.top, media.viewPadding.top);
    final height = media.size.height - (topInset + 16);
    final dirs = _dirs;
    final hasParent = _here.isNotEmpty && _here != '/';
    final parent = hasParent
        ? (_listing?.parent ??
            (_here.substring(0, _here.lastIndexOf('/')).isEmpty
                ? '/'
                : _here.substring(0, _here.lastIndexOf('/'))))
        : null;
    Widget row(String icon, String name, VoidCallback? onTap,
            {bool last = false}) =>
        InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppColors.surface2,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: widget.rowMinHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 28, 8),
              child: Row(children: [
                SizedBox(
                    width: 20,
                    child: AppIcon(icon, size: 20, color: AppColors.fg2)),
                const SizedBox(width: 4),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 0),
                    child: Text(name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: sans(15, color: AppColors.fg1)),
                  ),
                ),
                AppIcon('chevron-right', size: 16, color: AppColors.fg3),
              ]),
            ),
          ),
        );
    Widget rule() => Container(
        height: 1,
        margin: const EdgeInsets.only(left: 44, right: 16),
        color: AppColors.line);
    final items = <Widget>[
      if (parent != null)
        row('arrow-up', '..', _busy == null ? () => _go(parent) : null),
      for (final d in dirs) ...[
        if (parent != null || d != dirs.first) rule(),
        row('folder', d.name, _busy == null ? () => _go(d.path) : null),
      ],
    ];
    Widget list;
    if (_error != null) {
      list = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(children: [
          Expanded(
              child: Text("Can't open this folder",
                  style: sans(13, color: AppColors.fg2))),
          TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => _go(widget.startPath),
              child: Text('Retry',
                  style:
                      sans(14, weight: FontWeight.w500, color: AppColors.fg1))),
        ]),
      );
    } else if (_loading && _listing == null) {
      list = const ListSkeleton(rows: 6, subtitle: false);
    } else if (dirs.isEmpty) {
      list = ListView(children: [
        ...items,
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
                child: Text('No folders here',
                    style: sans(13, color: AppColors.fg2)))),
      ]);
    } else {
      list = PullToRefresh(
          onRefresh: () async => _go(_here), child: ListView(children: items));
    }
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        height: height,
        child: AppSheetSurface(
          expand: true,
          color: AppColors.surface1,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 56,
              child: Row(children: [
                const SizedBox(width: 20),
                Expanded(
                    child: Text('Choose folder',
                        style: sans(16,
                            weight: FontWeight.w500, color: AppColors.fg1))),
                IconBtn('plus',
                    size: 48,
                    iconSize: 20,
                    tooltip: 'Add here',
                    onTap:
                        (_listing == null || _busy != null) ? null : _addMenu),
                IconBtn('x',
                    size: 48,
                    iconSize: 20,
                    tooltip: 'Close',
                    onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 8),
              ]),
            ),
            if (_here.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(_pathLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12, color: AppColors.fg3)),
              ),
            if (widget.recentFolders.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    for (var i = 0; i < widget.recentFolders.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Material(
                        color: widget.recentFolders[i] == _here
                            ? AppColors.surface3
                            : AppColors.surface2,
                        borderRadius: BorderRadius.circular(kMobile ? 22 : R.of(7)),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(kMobile ? 22 : R.of(7)),
                          splashFactory: NoSplash.splashFactory,
                          onTap: _busy == null
                              ? () => _go(widget.recentFolders[i])
                              : null,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 44),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AppIcon('folder',
                                        size: 16, color: AppColors.fg2),
                                    const SizedBox(width: 6),
                                    Text(
                                      lastPathSegment(widget.recentFolders[i],
                                          ifEmpty: widget.recentFolders[i]),
                                      maxLines: 1,
                                      style: sans(13, color: AppColors.fg2),
                                    ),
                                  ]),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
            Expanded(child: list),
            if (widget.showWorkspaceChoice && _repo != null) _workspaceChoice(),
            Padding(
              padding:
                  EdgeInsets.fromLTRB(16, 12, 16, 16 + media.padding.bottom),
              child: Material(
                color: AppColors.fg1,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: (_here.isEmpty || _busy != null) ? null : _confirm,
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    child: Text(_busy ?? _selectLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(15,
                            weight: FontWeight.w500, color: AppColors.bg)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _breadcrumbs() {
    final crumbs = _crumbs;
    return Container(
      margin: EdgeInsets.fromLTRB(M.gutter, S.s2, M.gutter, S.s8),
      padding: EdgeInsets.only(left: S.of(14), right: S.s4),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.of(24)),
        border: Border.all(color: AppColors.fg1.withValues(alpha: 0.08)),
      ),
      child: Row(children: [
        AppIcon(_atHome ? 'home' : 'folder', size: 16, color: AppColors.fg3),
        SizedBox(width: S.s6),
        Expanded(
          child: SizedBox(
            height: M.minTarget,
            child: ListView.separated(
              controller: _crumbScroll,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(vertical: S.s4),
              itemCount: crumbs.length,
              separatorBuilder: (_, __) => Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: S.s2),
                  child:
                      AppIcon('chevron-right', size: 12, color: AppColors.fg3),
                ),
              ),
              itemBuilder: (_, i) {
                final c = crumbs[i];
                final last = i == crumbs.length - 1;
                return Center(
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(R.of(18)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(R.sm),
                      onTap: last ? null : () => _go(c.path),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: S.s6, vertical: S.s6),
                        child: Text(
                          c.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: last
                              ? TS.label(AppColors.fg1)
                              : TS
                                  .label(AppColors.fg3)
                                  .copyWith(fontWeight: weightFor(W.body)),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (!_atHome) ...[
          SizedBox(width: S.s4),
          IconBtn('home',
              size: M.minTarget,
              iconSize: 17,
              tooltip: 'Home',
              onTap: () => _go(_homePath)),
        ],
      ]),
    );
  }

  Widget _folderList() {
    final dirs = _dirs;
    final files = _files;
    if (dirs.isEmpty && files.isEmpty) {
      return ListView(
        padding: EdgeInsets.symmetric(vertical: S.of(44)),
        children: [
          Text('This folder is empty.',
              textAlign: TextAlign.center, style: TS.meta()),
        ],
      );
    }
    if (kMobile) {
      return ListView(
        padding: EdgeInsets.fromLTRB(M.gutter, S.s4, M.gutter, S.s12),
        children: [
          if (dirs.isNotEmpty)
            GroupedTiles(children: [
              for (final d in dirs)
                SettingsRow(
                  label: d.name,
                  icon: 'folder',
                  chevron: true,
                  onTap: _busy == null ? () => _go(d.path) : null,
                ),
            ]),
          if (dirs.isNotEmpty && files.isNotEmpty) SizedBox(height: S.s12),
          if (files.isNotEmpty)
            GroupedTiles(children: [
              for (final f in files) SettingsRow(label: f.name, icon: 'file'),
            ]),
        ],
      );
    }
    final rows = <Widget>[
      for (final d in dirs) _folderRow(d),
      if (dirs.isNotEmpty && files.isNotEmpty) SizedBox(height: S.s6),
      for (final f in files) _fileRow(f),
    ];
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(M.gutter, S.s4, M.gutter, S.of(10)),
      itemCount: rows.length,
      itemBuilder: (_, i) => rows[i],
    );
  }

  Widget _fileRow(FsEntry e) => Container(
        height: 40,
        padding: EdgeInsets.symmetric(horizontal: S.s4),
        child: Row(children: [
          SizedBox(
              width: 22,
              child: Center(
                  child: AppIcon('file', size: 16, color: AppColors.fg4))),
          SizedBox(width: S.s12),
          Expanded(
            child: Text(e.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TS.ui(AppColors.fg3)),
          ),
        ]),
      );

  Widget _folderRow(FsEntry e) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(R.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.sm),
          hoverColor: AppColors.surface2,
          onTap: _busy == null ? () => _go(e.path) : null,
          child: Container(
            height: 48,
            padding: EdgeInsets.symmetric(horizontal: S.s4),
            child: Row(children: [
              SizedBox(
                  width: 22,
                  child: Center(
                      child:
                          AppIcon('folder', size: 19, color: AppColors.fg3))),
              SizedBox(width: S.s12),
              Expanded(
                child: Text(e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TS.rowTitle()),
              ),
              AppIcon('chevron-right', size: 14, color: AppColors.fg3),
            ]),
          ),
        ),
      );

  void _addMenu() => showAppSheet(context,
      title: 'Add to $_hereName',
      subtitle: '',
      child: SheetActions([
        SheetAction('folder-plus', 'New folder', () {
          Navigator.pop(context);
          _newFolder();
        }, tile: true),
        SheetAction('file-plus', 'New file', () {
          Navigator.pop(context);
          _newFile();
        }, tile: true),
        SheetAction('upload', 'Upload', () {
          Navigator.pop(context);
          _upload();
        }, tile: true),
      ]));

  Widget _actionBar(double bottomPad) => Container(
        padding:
            EdgeInsets.fromLTRB(M.gutter, S.s8, M.gutter, S.of(10) + bottomPad),
        decoration: BoxDecoration(
          color: AppColors.bg,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(children: [
          RoundBtn(
              icon: 'plus',
              size: 48,
              tooltip: 'Add here',
              onTap: (_listing == null || _busy != null) ? null : _addMenu),
          SizedBox(width: S.s8),
          Expanded(
            child: Material(
              color: AppColors.accentFill,
              borderRadius: BorderRadius.circular(R.of(24)),
              child: InkWell(
                borderRadius: BorderRadius.circular(R.of(24)),
                onTap: (_here.isEmpty || _busy != null) ? null : _confirm,
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_busy != null)
                        Spinner(size: 14, color: AppColors.accentFg)
                      else
                        AppIcon('folder', size: 15, color: AppColors.accentFg),
                      SizedBox(width: S.s8),
                      Flexible(
                        child: Text(
                          _busy ?? _confirmLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TS.label(AppColors.accentFg),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ]),
      );

  String get _confirmLabel {
    final existing = _existing;
    if (existing != null) {
      return 'Use ${existing.branch ?? lastPathSegment(existing.path, ifEmpty: existing.path)}';
    }
    if (_repo != null && _mode == WorkspaceMode.worktree) {
      return 'Use $_hereName in new worktree';
    }
    return 'Use $_hereName';
  }

  Widget _workspaceChoice() {
    final worktrees = _repo?.worktrees ?? const <Worktree>[];
    Widget option(
            String icon, String label, bool selected, VoidCallback? onTap) =>
        Expanded(
          child: Material(
            color: selected
                ? (kMobile
                    ? Color.alphaBlend(
                        AppColors.fg1.withValues(alpha: 0.08), Grouped.row)
                    : AppColors.surface3)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(R.of(kMobile ? 16 : 18)),
            child: InkWell(
              borderRadius: BorderRadius.circular(R.sm),
              onTap: _busy != null ? null : onTap,
              child: SizedBox(
                height: 38,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!kMobile) ...[
                      AppIcon(icon,
                          size: 14,
                          color: onTap == null
                              ? AppColors.fg4
                              : (selected ? AppColors.fg1 : AppColors.fg3)),
                      SizedBox(width: S.s6),
                    ],
                    Flexible(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TS.label(onTap == null
                              ? AppColors.fg4
                              : (selected ? AppColors.fg1 : AppColors.fg3))),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    return Container(
      color: AppColors.bg,
      padding: EdgeInsets.fromLTRB(M.gutter, S.of(10), M.gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (kMobile)
            const SettingsSectionLabel('Works in')
          else ...[
            Text('Works in', style: TS.caption()),
            SizedBox(height: S.s6),
          ],
          Container(
            padding: EdgeInsets.all(S.s4),
            decoration: BoxDecoration(
              color: kMobile ? Grouped.row : AppColors.surface1,
              borderRadius: BorderRadius.circular(R.of(22)),
              border: kMobile
                  ? null
                  : Border.all(color: AppColors.fg1.withValues(alpha: 0.08)),
            ),
            child: Row(children: [
              option(
                'git-branch',
                'New worktree',
                _existing == null && _mode == WorkspaceMode.worktree,
                () => setState(() {
                  _mode = WorkspaceMode.worktree;
                  _existing = null;
                }),
              ),
              option(
                'folder',
                'This folder',
                _existing == null && _mode == WorkspaceMode.folder,
                () => setState(() {
                  _mode = WorkspaceMode.folder;
                  _existing = null;
                }),
              ),
              Builder(
                builder: (ctx) => option(
                  'layers',
                  _existing == null
                      ? 'Existing${worktrees.isEmpty ? '' : ' (${worktrees.length})'}'
                      : (_existing!.branch ??
                          lastPathSegment(_existing!.path,
                              ifEmpty: _existing!.path)),
                  _existing != null,
                  worktrees.isEmpty ? null : () => _pickExisting(ctx),
                ),
              ),
            ]),
          ),
          const SettingsFootnote(
              'A new worktree keeps this session off main until you merge it.'),
        ],
      ),
    );
  }

  Widget _errorState() => Center(
        child: Padding(
          padding: EdgeInsets.all(S.s24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AppIcon('wifi-off', size: 22, color: AppColors.fg4),
            SizedBox(height: S.s12),
            Text(_error!,
                textAlign: TextAlign.center,
                style: sans(12, color: AppColors.fg3, height: 1.45)),
            SizedBox(height: S.of(14)),
            Btn('Retry', small: true, onTap: () => _go(widget.startPath)),
          ]),
        ),
      );
}

class _Crum {
  const _Crum(this.label, this.path);
  final String label;
  final String path;
}
