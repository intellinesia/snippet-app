import 'dart:convert';

import 'package:flutter/material.dart';
import '../glass.dart';
import 'package:flutter/services.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api.dart';
import '../desktop_layout.dart';
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

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final canConnect = _paste.text.trim().isNotEmpty && !_busy;
    return Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(R.card),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: 420,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(R.card),
          border: Border.all(color: AppColors.border2),
        ),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: badge, title, dismiss. The close is here rather than
              // relying on Esc alone, so the dialog has a visible exit.
              Padding(
                padding: EdgeInsets.fromLTRB(S.of(18), S.s16, S.of(10), 0),
                child: Row(children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(R.sm),
                    ),
                    child: AppIcon('plus', size: 15, color: AppColors.accent),
                  ),
                  SizedBox(width: S.of(11)),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Connect a machine', style: display(kMobile ? 16 : 14)),
                          SizedBox(height: S.s2),
                          Text('Link this app to a computer running snippet',
                              style: TS.caption()),
                        ]),
                  ),
                  IconBtn('x',
                      size: 32,
                      iconSize: 16,
                      tooltip: 'Close',
                      onTap: () => Navigator.pop(context)),
                ]),
              ),
              SizedBox(height: S.s16),
              // Step one: the command, on its own line with a copy affordance.
              // It is something to run elsewhere, not to read in passing.
              Padding(
                padding: EdgeInsets.symmetric(horizontal: S.of(18)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _StepLabel('1', 'Run this on that computer'),
                      SizedBox(height: S.s8),
                      Container(
                        padding: EdgeInsets.fromLTRB(S.of(11), S.of(9), S.s6, S.of(9)),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(R.sm),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(children: [
                          AppIcon('terminal', size: 13, color: AppColors.fg3),
                          SizedBox(width: S.of(9)),
                          Expanded(
                            child: Text('snippet serve --enable',
                                style: mono(12, color: AppColors.fg1)),
                          ),
                          IconBtn('copy',
                              size: 28,
                              iconSize: 13,
                              tooltip: 'Copy command', onTap: () {
                            Clipboard.setData(
                                const ClipboardData(text: 'snippet serve --enable'));
                            toast(context, 'Command copied');
                          }),
                        ]),
                      ),
                    ]),
              ),
              SizedBox(height: S.s16),
              // Step two: paste what it prints.
              Padding(
                padding: EdgeInsets.symmetric(horizontal: S.of(18)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _StepLabel('2', 'Paste the link it prints'),
                      SizedBox(height: S.s8),
                      AppField(
                          controller: _paste,
                          mono: true,
                          autofocus: true,
                          hint: 'https://…?token=…',
                          onSubmitted: _connect),
                    ]),
              ),
              if (_error != null) ...[
                SizedBox(height: S.s12),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: S.of(18)),
                  child: Row(children: [
                    AppIcon('alert-triangle',
                        size: 13, color: AppColors.danger),
                    SizedBox(width: S.of(7)),
                    Expanded(
                      child: Text(_error!,
                          style:
                              sans(11, height: 1.4, color: AppColors.danger)),
                    ),
                  ]),
                ),
              ],
              SizedBox(height: S.of(18)),
              // Footer: status on the left, the action on the right.
              Container(
                padding: EdgeInsets.fromLTRB(S.of(18), S.s12, S.of(18), S.of(14)),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Row(children: [
                  if (_busy) ...[
                    Spinner(size: 13, color: AppColors.fg3),
                    SizedBox(width: S.of(9)),
                    Text('Connecting…', style: TS.meta()),
                  ] else
                    Text('Connection stays on this device',
                        style: TS.caption()),
                  const Spacer(),
                  Btn('Connect',
                      small: true,
                      onTap: canConnect ? () => _connect(_paste.text) : null),
                ]),
              ),
            ]),
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
            Text(step, style: sans(11, weight: W.label, color: AppColors.fg3)),
      ),
      SizedBox(width: S.s8),
      Text(text, style: sans(11, weight: W.label, color: AppColors.fg2)),
    ]);
  }
}

/// Full-screen "Add machine": a live QR scanner on phones (desktop shows an
/// instruction block instead), plus a fixed paste-a-connection-string bar at
/// the bottom. Pops with the verified [Instance].
class AddInstanceScreen extends StatefulWidget {
  const AddInstanceScreen({super.key});
  @override
  State<AddInstanceScreen> createState() => _AddInstanceScreenState();
}

class _AddInstanceScreenState extends State<AddInstanceScreen>
    with WidgetsBindingObserver {
  final _paste = TextEditingController();
  PermissionStatus? _perm;
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
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          SettingsHeader(
              title: 'Add machine',
              compact: true,
              onBack: () => Navigator.pop(context)),
          // Phone-only screen now (desktop uses the compact dialog above).
          Expanded(child: _body()),
        ]),
      ),
    );
  }

  Widget _body() {
    final empty = _paste.text.trim().isEmpty;
    return ListView(
      padding: EdgeInsets.fromLTRB(S.s16, S.s8, S.s16,
          S.s24 + MediaQuery.of(context).padding.bottom),
      children: [
        // The viewport and its caption share one card, as in the mockup.
        Container(
          padding: EdgeInsets.all(S.s16),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(children: [
            Center(
              child: SizedBox(
                width: 248,
                height: 248,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(R.md),
                  child: _scanArea(),
                ),
              ),
            ),
            SizedBox(height: S.s12),
            Text.rich(
              TextSpan(style: sans(13, color: AppColors.fg3), children: [
                const TextSpan(text: 'Scan the QR from '),
                TextSpan(
                    text: 'snippet serve --enable',
                    style: mono(13, color: AppColors.fg2)),
              ]),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
        SizedBox(height: S.s16),
        AppField(
            label: 'Paste the link from snippet serve',
            controller: _paste,
            mono: true,
            hint: 'https://…?token=…',
            onSubmitted: _connect),
        if (_error != null) ...[
          SizedBox(height: S.s8),
          Text(_error!, style: sans(12, color: AppColors.danger)),
        ],
        SizedBox(height: S.s16),
        Btn(_busy ? 'Connecting…' : 'Connect',
            full: true,
            disabled: empty || _busy,
            onTap: () => _connect(_paste.text)),
      ],
    );
  }

  Widget _scanArea() {
    final perm = _perm;
    if (perm == null) {
      return ColoredBox(
          color: AppColors.surface1,
          child: Center(child: DelayedSpinner(size: 22)));
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
