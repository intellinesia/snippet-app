import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../desktop_pick.dart';
import '../mochi.dart';
import '../models.dart';
import '../platform.dart';
import '../pull_refresh.dart';
import '../theme.dart';
import '../widgets.dart';
import 'mission_control/mission_control_state.dart' show isDedicatedMcSession;
import 'mobile_chrome.dart';

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
  String? _branch;
  WorkspaceMode _mode = WorkspaceMode.worktree;
  Worktree? _existing;
  List<InferenceProfile> _profiles = const [];
  String? _profile;
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
        _profile = cfg.active ??
            cfg.profiles.where((p) => p.active).firstOrNull?.name;
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
        if (isDedicatedMcSession(s.id)) continue;
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
    final main = repo == null
        ? null
        : repo.worktrees.where((w) => w.path == repo!.repo).firstOrNull ??
            repo.worktrees.firstOrNull;
    setState(() {
      _repo = hasRepo ? repo : null;
      _branch = hasRepo ? main?.branch : null;
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
      _branch = null;
    });
    _loadRepo(folder);
  }

  bool get _atHome =>
      _homePath != null && _homePath!.isNotEmpty && _folder == _homePath;

  String _labelForFolder(String? path) {
    if (path == null || path.isEmpty) return 'Choose folder';
    if (_homePath != null && _homePath!.isNotEmpty && path == _homePath) {
      return 'Home';
    }
    return lastPathSegment(path, ifEmpty: path);
  }

  String get _displayBranch => _existing?.branch ?? _branch ?? '';

  Future<void> _openFolderSheet() async {
    final result = await showModalBottomSheet<_FolderPickResult>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      isScrollControlled: true,
      useSafeArea: false,
      sheetAnimationStyle: sheetMotion,
      builder: (_) => _FolderBrowserSheet(
        client: widget.client,
        startPath: _existing?.path ?? _folder ?? widget.startPath,
        homePath: _homePath,
        initialMode: _mode,
        initialExisting: _existing,
      ),
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
      setState(() => _mode = _repo == null ? WorkspaceMode.folder : result.mode);
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
    if (picked != null && mounted) setState(() => _profile = picked);
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
        const SizedBox(width: S.s8),
        _attachOption('image', 'Photos', 'photos'),
        const SizedBox(width: S.s8),
        _attachOption('file', 'Files', 'files'),
      ]),
    );
    if (!mounted || choice == null) return;
    if (choice == 'camera') {
      final x = await ImagePicker()
          .pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2200);
      if (x != null && mounted) {
        setState(() => _attachments.add(PickedLocalFile(name: x.name, path: x.path)));
      }
    } else if (choice == 'photos') {
      final xs = await ImagePicker()
          .pickMultiImage(imageQuality: 85, maxWidth: 2200);
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
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.of(context).pop(value),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AppIcon(icon, size: 22, color: AppColors.fg1),
                const SizedBox(height: 6),
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
        await widget.onStart!(folder, mode, _profile, text, attachments);
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
    return Scaffold(
      backgroundColor: AppColors.bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(M.gutter, 10, M.gutter, 0),
              child: Row(children: [
                RoundBtn(
                  icon: 'chevron-left',
                  size: 40,
                  iconSize: 20,
                  tooltip: 'Back',
                  onTap: widget.onClose ?? () => Navigator.maybePop(context),
                ),
              ]),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: M.gutter),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: box.maxHeight,
                      minWidth: box.maxWidth - 2 * M.gutter,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const DottedMochi(width: 170),
                        const SizedBox(height: 10),
                        Text(
                          'What are we making?',
                          textAlign: TextAlign.center,
                          style: sans(24,
                              weight: W.body,
                              spacing: -0.5,
                              color: AppColors.fg1),
                        ),
                        if (_recentFolders.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 2),
                                child: Text('Recent',
                                    style: sans(12, color: AppColors.fg4)),
                              ),
                              for (final folder in _recentFolders)
                                _recentFolderChip(folder),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(M.gutter, 8, M.gutter, 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 660),
                  child: _composerCard(current, canSend),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recentFolderChip(String folder) {
    final selected = folder == _folder && _existing == null;
    final radius = BorderRadius.circular(14);
    return Material(
      color: selected ? AppColors.surface2 : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: () => _selectFolder(folder),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  _labelForFolder(folder),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12.5,
                      color: selected ? AppColors.fg1 : AppColors.fg3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _composerCard(InferenceProfile? current, bool canSend) {
    final showBranch = _repo != null && _displayBranch.isNotEmpty;
    final hasWorktrees = (_repo?.worktrees.length ?? 0) > 0;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _folderChip(),
                if (showBranch)
                  Builder(
                    builder: (anchor) => _chip(
                      'git-branch',
                      _displayBranch,
                      onTap: hasWorktrees ? () => _pickExisting(anchor) : null,
                    ),
                  ),
                if (_repo != null) _worktreeToggle(),
              ],
            ),
          ),
          TextField(
            controller: _input,
            focusNode: _focus,
            minLines: 2,
            maxLines: 6,
            cursorColor: AppColors.accent,
            style: sans(16, height: 1.45, color: AppColors.fg1),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              hintText: 'Ask, build, or type / for commands',
              hintStyle: sans(16, color: AppColors.fg4),
            ),
          ),
          if (_attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < _attachments.length; i++)
                    _attachmentChip(i, _attachments[i]),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            child: Row(children: [
              Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _onAttachTap,
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: Center(
                      child: AppIcon('plus', size: 17, color: AppColors.fg3),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (current != null)
                Builder(
                  builder: (anchor) => Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(15),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(15),
                      onTap: () => _pickProfile(anchor),
                      child: Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          ProviderLogo(current.provider, size: 13),
                          const SizedBox(width: 6),
                          Text(current.name,
                              style: sans(13, color: AppColors.fg2)),
                          const SizedBox(width: 4),
                          AppIcon('chevron-down',
                              size: 11, color: AppColors.fg3),
                        ]),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              Tooltip(
                message: 'Start',
                child: Material(
                  color: canSend ? AppColors.accentFill : AppColors.surface2,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: canSend ? _start : null,
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: Center(
                        child: _starting
                            ? Spinner(size: 14, color: AppColors.accentFg)
                            : AppIcon(
                                'arrow-up',
                                size: 16,
                                color: canSend
                                    ? AppColors.accentFg
                                    : AppColors.fg4,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _folderChip() => Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: _openFolderSheet,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon('folder', size: 13, color: AppColors.fg2),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  _labelForFolder(_folder),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(14, color: AppColors.fg2),
                ),
              ),
              const SizedBox(width: 4),
              AppIcon('chevron-down', size: 11, color: AppColors.fg3),
            ]),
          ),
        ),
      );

  Widget _chip(String icon, String label, {VoidCallback? onTap}) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onTap,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon(icon, size: 13, color: AppColors.fg3),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(14, color: AppColors.fg3),
                ),
              ),
            ]),
          ),
        ),
      );

  Widget _worktreeToggle() {
    final on = _mode == WorkspaceMode.worktree;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => setState(() {
          _mode = on ? WorkspaceMode.folder : WorkspaceMode.worktree;
          if (_mode == WorkspaceMode.worktree) _existing = null;
        }),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 22,
              height: 13,
              padding: const EdgeInsets.all(2),
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: on
                    ? AppColors.accent.withValues(alpha: 0.35)
                    : AppColors.surface3,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: on ? AppColors.accent : AppColors.fg4,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Worktree',
              style: sans(14, color: on ? AppColors.fg2 : AppColors.fg4),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _attachmentChip(int index, PickedLocalFile file) => Container(
        height: 26,
        padding: const EdgeInsets.fromLTRB(9, 0, 4, 0),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(13),
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
          const SizedBox(width: 4),
          GestureDetector(
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

typedef _FolderPickResult = ({
  String folder,
  WorkspaceMode mode,
  Worktree? existing,
  String? homePath,
});

class _FolderBrowserSheet extends StatefulWidget {
  const _FolderBrowserSheet({
    required this.client,
    this.startPath,
    this.homePath,
    required this.initialMode,
    this.initialExisting,
  });

  final DaemonClient client;
  final String? startPath;
  final String? homePath;
  final WorkspaceMode initialMode;
  final Worktree? initialExisting;

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
    final limit = (media.size.height * 0.84).clamp(320.0, 680.0);
    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: Material(
        type: MaterialType.transparency,
        child: AppSheetSurface(
          color: AppColors.bg,
          child: SizedBox(
            height: limit,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(M.gutter, 4, 8, 6),
                  child: Row(children: [
                    Expanded(
                      child: Text('Choose folder', style: TS.sectionTitle()),
                    ),
                    IconBtn('x',
                        size: M.minTarget,
                        iconSize: 18,
                        tooltip: 'Close',
                        onTap: () => Navigator.of(context).pop()),
                  ]),
                ),
                if (_error != null)
                  Expanded(child: _errorState())
                else ...[
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
                  _actionBar(media.padding.bottom),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _breadcrumbs() {
    final crumbs = _crumbs;
    return Container(
      margin: const EdgeInsets.fromLTRB(M.gutter, 2, M.gutter, 8),
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.fg1.withValues(alpha: 0.08)),
      ),
      child: Row(children: [
        AppIcon(_atHome ? 'home' : 'folder', size: 16, color: AppColors.fg3),
        const SizedBox(width: 6),
        Expanded(
          child: SizedBox(
            height: M.minTarget,
            child: ListView.separated(
              controller: _crumbScroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: crumbs.length,
              separatorBuilder: (_, __) => Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child:
                      AppIcon('chevron-right', size: 12, color: AppColors.fg4),
                ),
              ),
              itemBuilder: (_, i) {
                final c = crumbs[i];
                final last = i == crumbs.length - 1;
                return Center(
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(R.sm),
                      onTap: last ? null : () => _go(c.path),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 6),
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
          const SizedBox(width: 4),
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
        padding: const EdgeInsets.symmetric(vertical: 44),
        children: [
          Text('This folder is empty.',
              textAlign: TextAlign.center, style: TS.meta()),
        ],
      );
    }
    final rows = <Widget>[
      for (final d in dirs) _folderRow(d),
      if (dirs.isNotEmpty && files.isNotEmpty) const SizedBox(height: 6),
      for (final f in files) _fileRow(f),
    ];
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(M.gutter, 4, M.gutter, 10),
      itemCount: rows.length,
      itemBuilder: (_, i) => rows[i],
    );
  }

  Widget _fileRow(FsEntry e) => Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(children: [
          SizedBox(
              width: 22,
              child:
                  Center(child: AppIcon('file', size: 16, color: AppColors.fg4))),
          const SizedBox(width: S.s12),
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
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(children: [
              SizedBox(
                  width: 22,
                  child: Center(
                      child: AppIcon('folder',
                          size: 19, color: AppColors.fg3))),
              const SizedBox(width: S.s12),
              Expanded(
                child: Text(e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TS.rowTitle()),
              ),
              AppIcon('chevron-right', size: 14, color: AppColors.fg4),
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
        padding: EdgeInsets.fromLTRB(
            M.gutter, 8, M.gutter, 10 + bottomPad),
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
          const SizedBox(width: 8),
          Expanded(
            child: Material(
              color: AppColors.accentFill,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
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
                      const SizedBox(width: 8),
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
    Widget option(String icon, String label, bool selected, VoidCallback? onTap) =>
        Expanded(
          child: Material(
            color: selected ? AppColors.surface3 : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(R.sm),
              onTap: _busy != null ? null : onTap,
              child: SizedBox(
                height: 38,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppIcon(icon,
                        size: 14,
                        color: onTap == null
                            ? AppColors.fg4
                            : (selected ? AppColors.fg1 : AppColors.fg3)),
                    const SizedBox(width: 6),
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
      padding: const EdgeInsets.fromLTRB(M.gutter, 10, M.gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Works in', style: TS.caption()),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.fg1.withValues(alpha: 0.08)),
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
        ],
      ),
    );
  }

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AppIcon('wifi-off', size: 22, color: AppColors.fg4),
            const SizedBox(height: 12),
            Text(_error!,
                textAlign: TextAlign.center,
                style: sans(12, color: AppColors.fg3, height: 1.45)),
            const SizedBox(height: 14),
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
