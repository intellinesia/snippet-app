import 'dart:convert';

import 'package:flutter/material.dart';
import '../glass.dart';
import 'package:flutter/services.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api.dart';
import '../mobile_kit.dart';
import '../mochi.dart' show AgentCharacter;
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

const _badLink =
    "That doesn't look like a snippet link. It starts with https:// and ends with ?token=…";

/// Accepts `https://host?token=…` or JSON `{url, token}`.
(String, String)? parseConnection(String raw) {
  raw = raw.trim();
  final uri = Uri.tryParse(raw);
  if (uri != null &&
      uri.scheme.startsWith('http') &&
      (uri.queryParameters['token'] ?? '').isNotEmpty) {
    final token = uri.queryParameters['token']!;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return ('${uri.scheme}://${uri.host}$port', token);
  }
  try {
    final m = jsonDecode(raw);
    if (m is Map && m['url'] is String && m['token'] is String) {
      return (m['url'] as String, m['token'] as String);
    }
  } catch (_) {}
  return null;
}

/// Compact desktop "Connect a machine" dialog (phones use the full-screen
/// scanner flow). Natural height; Esc dismisses, Enter submits. Yields the
/// verified [Instance].
Future<Instance?> showAddMachineDialog(BuildContext context) {
  return showGeneralDialog<Instance>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'add-machine',
    barrierColor: AppColors.modalScrim,
    transitionDuration: Motion.fast,
    pageBuilder: (_, __, ___) => const Center(child: _AddMachineDialog()),
    transitionBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Motion.enter);
      return ModalGlass(
        child: FadeTransition(
          opacity: curved,
          child: ScaleTransition(
              scale: Tween(begin: 0.98, end: 1.0).animate(curved),
              child: child),
        ),
      );
    },
  );
}

class _AddMachineDialog extends StatefulWidget {
  const _AddMachineDialog();
  @override
  State<_AddMachineDialog> createState() => _AddMachineDialogState();
}

class _AddMachineDialogState extends State<_AddMachineDialog> {
  final _paste = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _paste.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  Future<void> _connect(String raw) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final parsed = parseConnection(raw);
      if (parsed == null) {
        setState(() {
          _error = _badLink;
          _busy = false;
        });
        return;
      }
      final (url, token) = parsed;
      final cfg = await DaemonClient(url, token).getConfig();
      final name = cfg.hostname.isNotEmpty ? cfg.hostname : hostOf(url);
      if (mounted) {
        Navigator.pop(context, Instance(name: name, url: url, token: token));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not connect: $e';
          _busy = false;
        });
      }
    }
  }

  static const _command = 'snippet serve --enable';
  bool _copied = false;

  void _copyCommand() {
    Clipboard.setData(const ClipboardData(text: _command));
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  BoxDecoration get _plate => BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(R.of(7)),
        border: Border.all(color: AppColors.paneLine, width: AppColors.hairline),
      );

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final canConnect = _paste.text.trim().isNotEmpty && !_busy;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(R.of(10)),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: 420,
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.of(10)),
              border: Border.all(color: AppColors.paneLine, width: AppColors.hairline),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Connect a machine',
                            style: sans(13.5,
                                weight: W.strong, color: AppColors.fg1)),
                        const SizedBox(height: 3),
                        Text('Link this app to another computer running Snippet.',
                            style: sans(12, color: AppColors.fg3)),
                      ],
                    ),
                  ),
                  IconBtn('x',
                      size: 26,
                      iconSize: 13,
                      tooltip: 'Close',
                      onTap: () => Navigator.pop(context)),
                ]),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _StepLabel('1', 'Run this on that computer'),
                      const SizedBox(height: 8),
                      Container(
                        height: 36,
                        padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
                        decoration: _plate,
                        child: Row(children: [
                          Text(r'$', style: mono(12.5, color: AppColors.fg4)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SelectableText(_command,
                                maxLines: 1,
                                style: mono(12.5, color: AppColors.fg1)),
                          ),
                          IconBtn(_copied ? 'check' : 'copy',
                              size: 28,
                              iconSize: 13,
                              tooltip: _copied ? 'Copied' : 'Copy command',
                              onTap: _copyCommand),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      const _StepLabel('2', 'Paste the link it prints'),
                      const SizedBox(height: 8),
                      Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.centerLeft,
                        decoration: _plate,
                        child: TextField(
                          controller: _paste,
                          autofocus: true,
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
                          onSubmitted: (v) => _connect(v),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(_error!,
                            style: sans(12,
                                height: 1.4, color: AppColors.danger)),
                      ],
                      const SizedBox(height: 16),
                      Row(children: [
                        AppIcon('lock', size: 12, color: AppColors.fg4),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('The link and its token stay on this device',
                              style: sans(12, color: AppColors.fg4)),
                        ),
                        Btn(_busy ? 'Connecting…' : 'Connect',
                            small: true,
                            disabled: !canConnect,
                            onTap: canConnect ? () => _connect(_paste.text) : null),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A numbered step label — gives the two-step flow an order instead of two
/// unlabelled blocks stacked with equal weight.
class _StepLabel extends StatelessWidget {
  const _StepLabel(this.step, this.text);
  final String step;
  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Row(children: [
      Container(
        width: 16,
        height: 16,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(R.pill),
        ),
        child:
            Text(step, style: sans(10, weight: W.label, color: AppColors.fg2)),
      ),
      SizedBox(width: S.s8),
      Text(text, style: sans(12.5, color: AppColors.fg2)),
    ]);
  }
}

/// Full-screen "Add machine": a live QR scanner on phones (desktop shows an
/// instruction block instead), plus a fixed paste-a-connection-string bar at
/// the bottom. Pops with the verified [Instance].
enum _Mode { intro, scan, paste }

class AddInstanceScreen extends StatefulWidget {
  const AddInstanceScreen({super.key});
  @override
  State<AddInstanceScreen> createState() => _AddInstanceScreenState();
}

class _AddInstanceScreenState extends State<AddInstanceScreen>
    with WidgetsBindingObserver {
  final _paste = TextEditingController();
  PermissionStatus? _perm;
  _Mode _mode = _Mode.intro;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kMobile) {
      Permission.camera
          .request()
          .then((s) => mounted ? setState(() => _perm = s) : null);
    }
    _paste.addListener(() => setState(() {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kMobile) return;
    if (state == AppLifecycleState.resumed) {
      Permission.camera.status.then(
          (s) => (mounted && s != _perm) ? setState(() => _perm = s) : null);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _paste.dispose();
    super.dispose();
  }

  Future<void> _connect(String raw) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final parsed = parseConnection(raw);
      if (parsed == null) {
        setState(() {
          _error = _badLink;
          _busy = false;
        });
        return;
      }
      final (url, token) = parsed;
      final client = DaemonClient(url, token);
      final cfg = await client.getConfig();
      final name = cfg.hostname.isNotEmpty ? cfg.hostname : hostOf(url);
      if (mounted) {
        Navigator.pop(context, Instance(name: name, url: url, token: token));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not connect: $e';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final a = kAndroidLook;
    final title = switch (_mode) {
      _Mode.intro => '',
      _Mode.scan => 'Scan QR code',
      _Mode.paste => 'Paste a link',
    };
    return PopScope(
      canPop: _mode == _Mode.intro,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _mode = _Mode.intro);
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: a ? 64 : 52,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: a ? 4 : 12),
                child: Row(children: [
                  MkIconButton(
                      icon: _mode == _Mode.intro
                          ? 'x'
                          : (a ? 'arrow-left' : 'chevron-left'),
                      label: _mode == _Mode.intro ? 'Close' : 'Back',
                      onTap: () => _mode == _Mode.intro
                          ? Navigator.pop(context)
                          : setState(() {
                              _mode = _Mode.intro;
                              _error = null;
                            })),
                  Expanded(
                    child: Text(title,
                        textAlign: a ? TextAlign.start : TextAlign.center,
                        style: a
                            ? sans(22, weight: W.label, color: AppColors.fg1)
                            : sans(16.5,
                                weight: FontWeight.w600, color: AppColors.fg1)),
                  ),
                  const SizedBox(width: 44),
                ]),
              ),
            ),
            Expanded(
              child: switch (_mode) {
                _Mode.intro => _intro(),
                _Mode.scan => _scanPage(),
                _Mode.paste => _pastePage(),
              },
            ),
          ]),
        ),
      ),
    );
  }

  static const _command = 'snippet serve --enable';

  Widget _intro() => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Spacer(flex: 2),
          const Center(child: AgentCharacter('01', size: 120)),
          const SizedBox(height: 22),
          Semantics(
            header: true,
            child: Text('Connect a machine',
                textAlign: TextAlign.center,
                style: display(26, weight: FontWeight.w600, color: AppColors.fg1)),
          ),
          const SizedBox(height: 10),
          Text('Run this on your computer, then scan the code it shows.',
              textAlign: TextAlign.center,
              style: sans(15, height: 1.45, color: AppColors.fg3)),
          const Spacer(flex: 2),
          Container(
            height: 52,
            padding: const EdgeInsets.only(left: 16),
            decoration: BoxDecoration(
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Expanded(
                child: SelectableText(_command,
                    maxLines: 1, style: mono(14, color: AppColors.fg1)),
              ),
              MkIconButton(
                  icon: 'copy',
                  label: 'Copy command',
                  bare: true,
                  size: a48,
                  onTap: () {
                    Clipboard.setData(const ClipboardData(text: _command));
                    toast(context, 'Copied');
                  }),
            ]),
          ),
          const Spacer(flex: 3),
          MkBigButton('Scan QR code',
              icon: 'scan', onTap: () => setState(() => _mode = _Mode.scan)),
          const SizedBox(height: 10),
          MkBigButton('Paste a link',
              icon: 'link',
              secondary: true,
              onTap: () => setState(() => _mode = _Mode.paste)),
        ]),
      );

  double get a48 => kAndroidLook ? 48 : 44;

  Widget _scanPage() => ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(MK.cardRadius),
              child: _scanArea(),
            ),
          ),
          const SizedBox(height: 16),
          Text.rich(
            TextSpan(style: sans(14, color: AppColors.fg3), children: [
              const TextSpan(text: 'Point at the code from '),
              TextSpan(text: _command, style: mono(13, color: AppColors.fg2)),
            ]),
            textAlign: TextAlign.center,
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            Center(child: MkMorph(size: 20, color: AppColors.fg2)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                textAlign: TextAlign.center,
                style: sans(13, color: AppColors.danger)),
          ],
        ],
      );

  Widget _pastePage() {
    final empty = _paste.text.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Paste the link from $_command.',
            style: sans(15, height: 1.45, color: AppColors.fg3)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(14)),
          child: TextField(
            controller: _paste,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            style: mono(13.5, color: AppColors.fg1),
            cursorColor: AppColors.fg1,
            onSubmitted: _connect,
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: 'https://…?token=…',
              hintStyle: mono(13.5, color: AppColors.fg4),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: sans(13, color: AppColors.danger)),
        ],
        const Spacer(),
        MkBigButton(_busy ? 'Connecting' : 'Connect',
            onTap: empty || _busy ? null : () => _connect(_paste.text)),
      ]),
    );
  }

  Widget _scanArea() {
    final perm = _perm;
    if (perm == null) {
      return ColoredBox(
          color: AppColors.surface1,
          child: Center(child: MkMorph(size: 22, color: AppColors.fg3)));
    }
    if (!perm.isGranted) {
      final permanent = perm.isPermanentlyDenied || perm.isRestricted;
      return ColoredBox(
        color: AppColors.surface1,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(S.s32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                      color: AppColors.surface2,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(R.card)),
                  child: AppIcon('camera-off', size: 26, color: AppColors.fg3)),
              SizedBox(height: S.s12),
              Text('Camera access needed',
                  style:
                      TS.sectionTitle()),
              SizedBox(height: S.s8),
              ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 250),
                  child: Text(
                      'Grant camera access to scan the QR code, or paste the link below.',
                      textAlign: TextAlign.center,
                      style: TS.meta())),
              SizedBox(height: S.s16),
              Btn('Grant camera access',
                  variant: BtnVariant.secondary, icon: 'camera', onTap: () {
                if (permanent) {
                  openAppSettings();
                } else {
                  Permission.camera
                      .request()
                      .then((s) => mounted ? setState(() => _perm = s) : null);
                }
              }),
            ]),
          ),
        ),
      );
    }
    // Rounded viewport, Claude-card style, with the scan reticle + caption inside.
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.lg),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(R.lg),
        child:
            Stack(alignment: Alignment.center, fit: StackFit.expand, children: [
          ReaderWidget(
            showScannerOverlay: false,
            showGallery: false,
            tryHarder: true,
            tryInverted: true,
            cropPercent: 0.7,
            scanDelay: const Duration(milliseconds: 300),
            onScan: (code) {
              final raw = code.text;
              if (code.isValid && raw != null && raw.trim().isNotEmpty) {
                _connect(raw);
              }
            },
          ),
          const IgnorePointer(child: Center(child: _Reticle())),
        ]),
      ),
    );
  }
}

class _Reticle extends StatefulWidget {
  const _Reticle();
  @override
  State<_Reticle> createState() => _ReticleState();
}

class _ReticleState extends State<_Reticle>
    with SingleTickerProviderStateMixin {
  /// Eager, in initState — see `_StatusDotState`: a lazy `late final` makes
  /// `dispose` the first access if `build` never ran, which throws on a dead
  /// element.
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2600))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _corner(Alignment a) {
    final top = a.y < 0, left = a.x < 0;
    return Align(
      alignment: a,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          border: Border(
            top: top
                ? BorderSide(color: AppColors.accent, width: 3)
                : BorderSide.none,
            bottom: !top
                ? BorderSide(color: AppColors.accent, width: 3)
                : BorderSide.none,
            left: left
                ? BorderSide(color: AppColors.accent, width: 3)
                : BorderSide.none,
            right: !left
                ? BorderSide(color: AppColors.accent, width: 3)
                : BorderSide.none,
          ),
          borderRadius: BorderRadius.only(
            topLeft: top && left ? Radius.circular(R.md) : Radius.zero,
            topRight: top && !left ? Radius.circular(R.md) : Radius.zero,
            bottomLeft:
                !top && left ? Radius.circular(R.md) : Radius.zero,
            bottomRight:
                !top && !left ? Radius.circular(R.md) : Radius.zero,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return SizedBox(
      width: 232,
      height: 232,
      child: Stack(children: [
        _corner(Alignment.topLeft),
        _corner(Alignment.topRight),
        _corner(Alignment.bottomLeft),
        _corner(Alignment.bottomRight),
        AnimatedBuilder(
          animation: _c,
          builder: (_, __) => Positioned(
            left: 8,
            right: 8,
            top: 8 + _c.value * 216,
            child: Container(
                height: 2,
                decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(R.pill),
                    boxShadow: [
                      BoxShadow(color: AppColors.accent, blurRadius: 12)
                    ])),
          ),
        ),
      ]),
    );
  }
}
