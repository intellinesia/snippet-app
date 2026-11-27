import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../desktop_pick.dart';
import '../diff_counts.dart';
import '../local_service.dart';
import '../mochi.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'add_instance.dart' show parseConnection;
import 'new_session_draft.dart';
import 'welcome_art.dart';

/// Overlay a sidebar-toggle on the welcome/empty states when the sidebar is collapsed.
class ShellWithMenu extends StatelessWidget {
  final VoidCallback? onMenu;
  final Widget child;

  const ShellWithMenu({super.key, required this.onMenu, required this.child});

  @override
  Widget build(BuildContext context) {
    if (onMenu == null) return child;
    return Stack(children: [
      child,
      Positioned(
        top: 6,
        left: 6,
        child: IconBtn(
          'sidebar',
          size: kMobile ? 44 : 38,
          iconSize: kMobile ? 25 : 19,
          tooltip: 'Sidebar',
          onTap: onMenu,
        ),
      ),
    ]);
  }
}

Future<Instance> _defaultConnect(String raw) async {
  final parsed = parseConnection(raw);
  if (parsed == null) {
    throw 'That is not a valid link. Run snippet serve --status on the other computer.';
  }
  final (url, token) = parsed;
  final cfg = await DaemonClient(url, token).getConfig();
  return Instance(
      name: cfg.hostname.isNotEmpty ? cfg.hostname : Uri.parse(url).host,
      url: url,
      token: token);
}

Future<Instance?> _defaultProbe() =>
    localInstance(timeout: const Duration(milliseconds: 900));

class ShellWelcomeView extends StatefulWidget {
  final VoidCallback onAddInstance;
  final ValueChanged<Instance>? onConnected;
  final Future<Instance> Function(String raw) connectRemote;
  final Future<Instance?> Function() probeLocal;
  final Future<bool> Function() probeRunning;
  final Future<InstallResult> Function(
      void Function(InstallStage stage, String detail) onStage) install;
  final bool Function() binaryInstalled;
  final Duration recheck;

  const ShellWelcomeView({
    super.key,
    required this.onAddInstance,
    this.onConnected,
    this.connectRemote = _defaultConnect,
    this.probeLocal = _defaultProbe,
    this.probeRunning = localServiceUp,
    this.install = installLocalService,
    this.binaryInstalled = localBinaryInstalled,
    this.recheck = const Duration(seconds: 3),
  });

  @override
  State<ShellWelcomeView> createState() => _ShellWelcomeViewState();
}

class _ShellWelcomeViewState extends State<ShellWelcomeView>
    with SingleTickerProviderStateMixin {
  Instance? _found;
  bool _runningUnreadable = false;
  bool _installed = false;
  bool _installing = false;
  InstallStage _stage = InstallStage.download;
  String _detail = '';
  String? _error;
  Instance? _pending;
  Timer? _timer;
  late final AnimationController _clock;
  final _paste = TextEditingController();
  bool _remoteBusy = false;
  String? _remoteError;

  @override
  void initState() {
    super.initState();
    _clock =
        AnimationController(vsync: this, duration: const Duration(seconds: 9));
    _clock.repeat();
    // Both the desktop and phone layouts gate Connect on the field's text.
    _paste.addListener(() {
      if (mounted) setState(() {});
    });
    if (!kMobile) {
      _installed = widget.binaryInstalled();
      _probe();
      _timer = Timer.periodic(widget.recheck, (_) => _probe());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clock.dispose();
    _paste.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    if (_installing || _found != null || _pending != null) return;
    final i = await widget.probeLocal();
    final up = i != null || await widget.probeRunning();
    if (!mounted) return;
    setState(() {
      _found = i;
      _runningUnreadable = i == null && up;
      if (i != null) _timer?.cancel();
    });
  }

  Future<void> _connectRemote(String raw) async {
    if (_remoteBusy || raw.trim().isEmpty) return;
    setState(() {
      _remoteBusy = true;
      _remoteError = null;
    });
    try {
      final inst = await widget.connectRemote(raw.trim());
      if (mounted) widget.onConnected?.call(inst);
    } catch (e) {
      if (mounted) {
        setState(() {
          _remoteBusy = false;
          _remoteError =
              '$e'.startsWith('That is not') ? '$e' : 'Could not connect: $e';
        });
      }
    }
  }

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _error = null;
      _stage = _installed ? InstallStage.start : InstallStage.download;
      _detail = '';
    });
    final r = await widget.install((s, d) {
      if (mounted) {
        setState(() {
          _stage = s;
          _detail = d;
        });
      }
    });
    if (!mounted) return;
    if (r.instance != null && r.autoStart) {
      widget.onConnected?.call(r.instance!);
    } else if (r.instance != null) {
      setState(() {
        _installing = false;
        _pending = r.instance;
      });
    } else {
      setState(() {
        _installing = false;
        _error = r.error;
      });
    }
  }

  Widget _progress() {
    final stages = [
      if (!_installed) ...[
        (InstallStage.download, 'Download'),
        (InstallStage.install, 'Install'),
      ],
      (InstallStage.start, 'Start the service'),
      (InstallStage.connect, 'Connect'),
    ];
    return Column(children: [
      for (final (s, label) in stages)
        _StageRow(
          label: label,
          detail: s == _stage ? _detail : '',
          state: s.index < _stage.index
              ? _StageState.done
              : s == _stage
                  ? _StageState.active
                  : _StageState.pending,
        ),
    ]);
  }

  Widget _label(String text) => Padding(
        padding: EdgeInsets.only(bottom: S.s8),
        child: Text(text,
            textAlign: TextAlign.left,
            style: sans(12.5, weight: W.label, color: AppColors.fg2)),
      );

  Text _body(String text) => Text(text,
      textAlign: TextAlign.left,
      style: sans(12, height: 1.45, color: AppColors.fg3));

  Widget _localControls() {
    if (_found != null) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 7,
            height: 7,
            decoration:
                BoxDecoration(color: AppColors.ok, shape: BoxShape.circle),
          ),
          SizedBox(width: S.s8),
          Text('Snippet is running here',
              style: sans(13, color: AppColors.fg1)),
          SizedBox(width: S.s8),
          Flexible(
            child: Text(_found!.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(11, color: AppColors.fg4)),
          ),
        ]),
        SizedBox(height: S.s12),
        Btn('Connect',
            small: true, onTap: () => widget.onConnected?.call(_found!)),
      ]);
    }
    if (_pending != null) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label('Not set to start automatically'),
        _body('It works now, but stops when this computer restarts. '
            'To fix that, run:'),
        SizedBox(height: S.of(10)),
        const _CommandBox(enableCommand),
        SizedBox(height: S.s12),
        Btn('Continue',
            small: true, onTap: () => widget.onConnected?.call(_pending!)),
      ]);
    }
    if (_installing) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label('Setting up'),
        Align(alignment: Alignment.centerLeft, child: _progress()),
      ]);
    }
    if (_runningUnreadable) {
      return _body('Snippet is running here, but this app cannot read its '
          'link. Run snippet serve --status and paste the link below.');
    }
    if (!canInstallLocalService) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _body('Run these in a terminal. This screen picks the service up '
            'as soon as it is running.'),
        SizedBox(height: S.of(10)),
        if (!_installed) ...[
          const _CommandBox(installCommand),
          SizedBox(height: S.s6),
        ],
        const _CommandBox(enableCommand),
      ]);
    }
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_installed) ...[
        _body('Snippet is installed but not running.'),
        SizedBox(height: S.s12),
      ],
      if (_error != null) ...[
        Text(_error!,
            textAlign: TextAlign.left,
            style: sans(12, height: 1.45, color: AppColors.danger)),
        SizedBox(height: S.s8),
        const _CommandBox(installCommand),
        SizedBox(height: S.s12),
      ],
      Btn(
          _error != null
              ? 'Try again'
              : _installed
                  ? 'Start the service'
                  : 'Install',
          small: true,
          icon: _installed ? null : 'download',
          onTap: _install),
    ]);
  }

  Widget _remoteControls() {
    final canConnect = !_remoteBusy && _paste.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(R.of(7)),
            border: Border.all(color: AppColors.paneLine),
          ),
          child: TextField(
            controller: _paste,
            style: mono(12.5, color: AppColors.fg1),
            cursorColor: AppColors.fg1,
            textAlignVertical: TextAlignVertical.center,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: 'https://…?token=…',
              hintStyle: mono(12.5, color: AppColors.fg4),
            ),
            onSubmitted: _connectRemote,
          ),
        ),
        SizedBox(height: S.s8),
        if (_remoteError != null)
          Text(_remoteError!,
              style: sans(12, height: 1.4, color: AppColors.danger))
        else
          SelectableText.rich(
            TextSpan(
                style: sans(12, height: 1.45, color: AppColors.fg4),
                children: [
                  const TextSpan(text: 'On that computer: '),
                  TextSpan(
                      text: enableCommand,
                      style: mono(11.5, color: AppColors.fg3)),
                  const TextSpan(text: ', then '),
                  TextSpan(
                      text: 'snippet serve --status',
                      style: mono(11.5, color: AppColors.fg3)),
                ]),
          ),
        SizedBox(height: S.s12),
        Row(children: [
          Expanded(
            child: Text('The link and its token stay on this device',
                style: sans(12, color: AppColors.fg4)),
          ),
          Btn(_remoteBusy ? 'Connecting…' : 'Connect',
              small: true,
              disabled: !canConnect,
              onTap: canConnect ? () => _connectRemote(_paste.text) : null),
        ]),
      ],
    );
  }


  Widget _sectionTitle(String text) => Text(text,
      style: sans(12.5, weight: W.label, color: AppColors.fg2));

  Widget _sectionBody(String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(text, style: sans(12, height: 1.45, color: AppColors.fg3)),
      );

  Widget _desktop() => LayoutBuilder(
        builder: (_, box) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minHeight: (box.maxHeight - 64)
                    .clamp(0.0, double.infinity)
                    .toDouble()),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const AgentMochi('snippet', size: 18),
                  SizedBox(width: S.s8),
                  Text('Snippet needs a service',
                      style: sans(13.5,
                          weight: W.strong,
                          color: Color.lerp(
                              AppColors.fg1, AppColors.fg2, 0.3))),
                ]),
                SizedBox(height: S.s8),
                Text(
                  'Snippet does its work in a small service that runs on a '
                  'computer or server. This app is your window onto it.',
                  textAlign: TextAlign.center,
                  style: sans(12, height: 1.45, color: AppColors.fg3),
                ),
                SizedBox(height: S.s24),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  decoration: BoxDecoration(
                    color: AppColors.surface1,
                    borderRadius: BorderRadius.circular(R.of(10)),
                    border: Border.all(color: AppColors.paneLine),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _sectionTitle('On this computer'),
                      _sectionBody('Install the service here. It runs in the '
                          'background, starts with your computer, and your work '
                          'stays on this machine.'),
                      SizedBox(height: S.s12),
                      _localControls(),
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: S.s16),
                        child: Container(height: 1, color: AppColors.paneLine),
                      ),
                      _sectionTitle('On another computer'),
                      _sectionBody('Already running Snippet on a server or '
                          'another machine? Paste its link and work with it '
                          'from here.'),
                      SizedBox(height: S.s12),
                      _remoteControls(),
                    ],
                  ),
                ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _wideButton(String label, String icon, VoidCallback? onTap) =>
      Pressable(
        enabled: onTap != null,
        child: Material(
          color: AppColors.accentFill,
          borderRadius: BorderRadius.circular(R.md),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(R.md),
            child: SizedBox(
              height: kMobile ? 50 : 42,
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                AppIcon(icon, size: 16, color: AppColors.accentFg),
                SizedBox(width: S.s8),
                Text(label,
                    style: sans(kMobile ? 15 : 13,
                        weight: W.label, color: AppColors.accentFg)),
              ]),
            ),
          ),
        ),
      );

  Widget _phone() => LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(S.s24, S.s8, S.s24, S.s32),
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: 460, minHeight: box.maxHeight - 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 200,
                  child: PlugArt(time: _clock, hover: 0.5),
                ),
                SizedBox(height: S.s8),
                Text('Connect to your computer',
                    textAlign: TextAlign.center, style: display(24)),
                SizedBox(height: S.of(10)),
                Text(
                  'Snippet does its work in a small service that runs on a '
                  'computer or server. This app is your window onto it.',
                  textAlign: TextAlign.center,
                  style: sans(14, height: 1.5, color: AppColors.fg3),
                ),
                SizedBox(height: S.of(28)),
                _wideButton('Scan QR code', 'scan', widget.onAddInstance),
                SizedBox(height: S.of(18)),
                Row(children: [
                  Expanded(
                      child: Container(height: 1, color: AppColors.border)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: S.s12),
                    child: Text('or paste its link',
                        style: sans(13, color: AppColors.fg4)),
                  ),
                  Expanded(
                      child: Container(height: 1, color: AppColors.border)),
                ]),
                SizedBox(height: S.of(18)),
                Row(children: [
                  Expanded(
                      child: AppField(
                          controller: _paste,
                          mono: true,
                          hint: 'https://\u2026?token=\u2026',
                          onSubmitted: _connectRemote)),
                  SizedBox(width: S.s8),
                  PillBtn('Connect',
                      onTap: _remoteBusy || _paste.text.trim().isEmpty
                          ? null
                          : () => _connectRemote(_paste.text)),
                ]),
                if (_remoteError != null) ...[
                  SizedBox(height: S.of(10)),
                  Text(_remoteError!,
                      textAlign: TextAlign.center,
                      style: sans(13, height: 1.4, color: AppColors.danger)),
                ],
                SizedBox(height: S.s32),
                Container(
                  padding: EdgeInsets.all(S.of(18)),
                  decoration: BoxDecoration(
                    color: AppColors.surface1,
                    borderRadius: BorderRadius.circular(R.lg),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Not running yet? On your computer:',
                          style:
                              sans(13, weight: W.label, color: AppColors.fg1)),
                      SizedBox(height: S.of(14)),
                      const _WelcomeStep(
                          n: '1', title: 'Install', command: installCommand),
                      SizedBox(height: S.of(14)),
                      const _WelcomeStep(
                          n: '2', title: 'Start it', command: enableCommand),
                      SizedBox(height: S.of(14)),
                      const _WelcomeStep(
                        n: '3',
                        title: 'Show its link and QR code',
                        command: 'snippet serve --status',
                        note: 'Prints the link and a QR code to scan.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return ColoredBox(
      color: kMobile ? AppColors.pageBg : AppColors.bg,
      child: kMobile ? _phone() : _desktop(),
    );
  }
}

enum _StageState { done, active, pending }

class _StageRow extends StatelessWidget {
  const _StageRow({required this.label, required this.state, this.detail = ''});
  final String label;
  final String detail;
  final _StageState state;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final lead = switch (state) {
      _StageState.done => AppIcon('check', size: 14, color: AppColors.ok),
      _StageState.active => SizedBox(
          width: 14,
          height: 14,
          child: Spinner(size: 14, color: AppColors.accent)),
      _StageState.pending => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border2, width: 1.5),
          )),
    };
    return Padding(
      padding: EdgeInsets.symmetric(vertical: S.s4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 18, height: 18, child: Center(child: lead)),
        SizedBox(width: S.s8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: sans(13,
                      color: state == _StageState.pending
                          ? AppColors.fg4
                          : AppColors.fg1)),
              if (detail.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: S.of(3)),
                  child: Text(detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(11, color: AppColors.fg3)),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _CommandBox extends StatelessWidget {
  const _CommandBox(this.command);
  final String command;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(S.s12, S.s6, S.s4, S.s6),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(kMobile ? R.sm : R.of(7)),
          border:
              Border.all(color: kMobile ? AppColors.border : AppColors.paneLine),
        ),
        child: Row(children: [
          Expanded(
            child: SelectableText(command,
                style: kMobile
                    ? mono(12, color: AppColors.fg1)
                    : mono(12.5, color: AppColors.fg2)),
          ),
          IconBtn('copy', size: 28, iconSize: 13, tooltip: 'Copy', onTap: () {
            Clipboard.setData(ClipboardData(text: command));
            toast(context, 'Copied');
          }),
        ]),
      );
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep(
      {required this.n, required this.title, this.command, this.note});
  final String n;
  final String title;
  final String? command;
  final String? note;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(R.pill),
        ),
        child: Text(n, style: sans(12, weight: W.label, color: AppColors.fg2)),
      ),
      SizedBox(width: S.s12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.only(top: S.s2),
              child: Text(title,
                  style: sans(kMobile ? 14 : 13, color: AppColors.fg1)),
            ),
            if (command != null) ...[
              SizedBox(height: S.s8),
              _CommandBox(command!),
            ],
            if (note != null) ...[
              SizedBox(height: S.s6),
              Text(note!, style: sans(12, height: 1.4, color: AppColors.fg4)),
            ],
          ],
        ),
      ),
    ]);
  }
}

class ShellRecentPlaceholder extends StatelessWidget {
  final List<SessionInfo>? sessions;
  final bool sessionsLoading;
  final void Function(String id, String title, String? profile) onOpenSession;

  /// Desktop empty state: with a [client] and [onStart] the placeholder is a
  /// composer that starts a session; without them it is the plain list.
  final DaemonClient? client;
  final String machineLabel;
  final Future<void> Function(
      String folder, WorkspaceMode mode, String? profile, String text)? onStart;
  final Future<void> Function(
      String folder,
      WorkspaceMode mode,
      String? profile,
      String text,
      List<PickedLocalFile> files)? onStartWithFiles;

  const ShellRecentPlaceholder({
    super.key,
    required this.sessions,
    required this.sessionsLoading,
    required this.onOpenSession,
    this.client,
    this.machineLabel = '',
    this.onStart,
    this.onStartWithFiles,
  });

  Widget _pickUp(BuildContext context) {
    final list = (sessions ?? const <SessionInfo>[]).take(4).toList();
    Widget key(String t) => Container(
          constraints: const BoxConstraints(minWidth: 18),
          height: 18,
          padding: EdgeInsets.symmetric(horizontal: S.s4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: AppColors.surface3,
              borderRadius: BorderRadius.circular(R.of(4))),
          child: Text(t, style: sans(10.5, color: AppColors.fg3)),
        );
    final mod = kMacOS ? '\u2318' : 'Ctrl';
    Widget hint(List<String> keys, String label) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          for (final k in keys) ...[key(k), SizedBox(width: S.s2)],
          SizedBox(width: S.s6),
          Text(label, style: sans(11.5, color: AppColors.fg4)),
        ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (list.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.only(top: S.s32, bottom: S.s6),
            child: Row(children: [
              Text('Pick up where you left off',
                  style: sans(11.5, weight: W.label, color: AppColors.fg4)),
              const Spacer(),
              key(mod),
              SizedBox(width: S.s2),
              key('K'),
              SizedBox(width: S.s6),
              Text('for everything else',
                  style: sans(11.5, color: AppColors.fg4)),
            ]),
          ),
          for (final s in list)
            Padding(
              padding: EdgeInsets.only(bottom: S.s2),
              child: Material(
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(R.of(8)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(R.of(8)),
                  onTap: () => onOpenSession(s.id, s.title, s.profile),
                  child: Container(
                    height: 36,
                    padding: EdgeInsets.symmetric(horizontal: S.of(14)),
                    child: Row(children: [
                      AgentMochi(s.displayAgentId ?? 'snippet', size: 14),
                      SizedBox(width: S.of(10)),
                      Expanded(
                        child: Row(children: [
                          Flexible(
                            child: Text(
                                s.title.isEmpty ? '(untitled)' : s.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: sans(13, color: AppColors.fg1)),
                          ),
                          SizedBox(width: S.s8),
                          Flexible(
                            child: Text(
                                lastPathSegment(s.projectFolder,
                                    ifEmpty: s.projectFolder),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: sans(12, color: AppColors.fg4)),
                          ),
                        ]),
                      ),
                      Text(relativeTime(s.lastActive),
                          style: sans(11.5, color: AppColors.fg4)),
                    ]),
                  ),
                ),
              ),
            ),
        ],
        SizedBox(height: S.s24),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          hint([mod, 'N'], 'new session'),
          SizedBox(width: S.s20),
          hint([mod, '1'], 'Lead'),
          SizedBox(width: S.s20),
          hint([mod, 'B'], 'sidebar'),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = client;
    final start = onStart;
    if (!kMobile && c != null && start != null) {
      return NewSessionDraft(
        client: c,
        machineLabel: machineLabel,
        onStart: start,
        onStartWithFiles: onStartWithFiles,
        layout: NewSessionLayout.hero,
        recentSessions: sessions,
        footer: _pickUp(context),
      );
    }
    final list = (sessions ?? const <SessionInfo>[]).take(8).toList();
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: S.s20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.symmetric(vertical: S.s24),
            children: [
              Text('Recent sessions', style: display(kMobile ? 24 : 20)),
              SizedBox(height: S.s6),
              Text(
                'Pick up where you left off, or start a new chat from Browse.',
                style: sans(12, height: 1.4, color: AppColors.fg3),
              ),
              SizedBox(height: S.of(18)),
              if (sessionsLoading && sessions == null)
                Center(
                  child: Padding(
                    padding: EdgeInsets.all(S.s16),
                    child: Spinner(size: 20, color: AppColors.fg3),
                  ),
                )
              else if (list.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: S.s16),
                  child: Text(
                    'No sessions yet.',
                    style: TS.meta(),
                  ),
                )
              else
                ...list.map(
                  (s) => Padding(
                    padding: EdgeInsets.only(bottom: S.s8),
                    child: AppCard(
                      onTap: () => onOpenSession(s.id, s.title, s.profile),
                      padding:
                          EdgeInsets.fromLTRB(S.of(14), S.s12, S.s12, S.s12),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.title.isEmpty ? '(untitled)' : s.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: sans(13, color: AppColors.fg1),
                              ),
                              SizedBox(height: S.of(3)),
                              Text(
                                lastPathSegment(s.projectFolder,
                                    ifEmpty: s.projectFolder),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: mono(10, color: AppColors.fg3),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: S.s8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              relativeTime(s.lastActive),
                              style: mono(10, color: AppColors.fg3),
                            ),
                            DiffCounts(s, size: 10.5),
                          ],
                        ),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
