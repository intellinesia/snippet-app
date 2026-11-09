import 'package:flutter/material.dart';

import '../api.dart';
import '../mochi.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

enum AgentAppearancePart { avatar, colour }

/// Opens the avatar or the colour picker for an agent; the two are stored
/// separately, and each previews the other's current choice.
Future<void> showAgentAppearance(BuildContext context, DaemonClient client,
    String agentId, String name, AgentAppearancePart part,
    {Offset? point}) {
  final picker = _Picker(client: client, agentId: agentId, part: part);
  if (kMobile) {
    return showAppSheet<void>(context,
        title: part == AgentAppearancePart.avatar
            ? '$name avatar'
            : '$name colour',
        child: picker);
  }
  final overlay = Overlay.of(context, rootOverlay: true)
      .context
      .findRenderObject() as RenderBox?;
  final box = context.findRenderObject() as RenderBox?;
  if (overlay == null) return Future.value();
  final screen = overlay.size;
  final at = point != null
      ? overlay.globalToLocal(point)
      : box != null
          ? box.localToGlobal(Offset(0, box.size.height + 6), ancestor: overlay)
          : screen.center(Offset.zero);
  const w = _Picker.desktopWidth;
  final left = at.dx.clamp(8.0, screen.width - w - 8);
  final top = at.dy.clamp(8.0, screen.height - 140);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    transitionDuration: Motion.fast,
    pageBuilder: (ctx, _, __) => Stack(children: [
      Positioned(
        left: left,
        top: top,
        width: w,
        child: Material(
          color: AppColors.surface2,
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppColors.border2),
          ),
          clipBehavior: Clip.antiAlias,
          child: picker,
        ),
      ),
    ]),
    transitionBuilder: (_, animation, __, child) {
      final curve = CurvedAnimation(parent: animation, curve: Motion.enter);
      return FadeTransition(
        opacity: curve,
        child: ScaleTransition(
          alignment: Alignment.topLeft,
          scale: Tween(begin: 0.96, end: 1.0).animate(curve),
          child: child,
        ),
      );
    },
  );
}

/// The avatar or colour grid on its own, for hosts that supply the surface:
/// [onDone] runs after a choice instead of popping the route.
class AgentAppearancePicker extends _Picker {
  const AgentAppearancePicker(
      {super.key,
      required super.client,
      required super.agentId,
      required super.part,
      required VoidCallback super.onDone});
}

class _Picker extends StatelessWidget {
  const _Picker(
      {super.key,
      required this.client,
      required this.agentId,
      required this.part,
      this.onDone});

  final VoidCallback? onDone;

  void _done(BuildContext context) =>
      onDone != null ? onDone!() : Navigator.pop(context);

  static const desktopWidth = 4 * 40.0 + 3 * 2 + 16;

  final DaemonClient client;
  final String agentId;
  final AgentAppearancePart part;

  Future<void> _pickShape(BuildContext context, MascotShape shape) async {
    final before = agentShapes.value[agentId];
    final value = shape == MascotShape.mochi ? null : shape.name;
    setRememberedAgentShape(agentId, value);
    _done(context);
    try {
      await client.setAgentShape(agentId, value);
    } catch (_) {
      setRememberedAgentShape(agentId, before);
      if (context.mounted) {
        toast(context, 'Could not change avatar', danger: true);
      }
    }
  }

  Future<void> _pickColor(BuildContext context, Color? color) async {
    final before = agentColors.value[agentId];
    final hex = color == null ? null : colorHex(color);
    setRememberedAgentColor(agentId, hex);
    _done(context);
    try {
      await client.setAgentColor(agentId, hex);
    } catch (_) {
      setRememberedAgentColor(agentId, before);
      if (context.mounted) {
        toast(context, 'Could not change colour', danger: true);
      }
    }
  }

  Widget _cell(String label, bool selected, VoidCallback onTap, Widget icon) {
    final radius = BorderRadius.circular(kMobile ? 12 : 8);
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: selected ? AppColors.surface3 : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          hoverColor: AppColors.surface3,
          onTap: onTap,
          child: SizedBox.square(
            dimension: kMobile ? 56.0 : 40.0,
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = mochiColorFor(agentId);
    final shape = mascotShapeFor(agentId);
    final custom = agentColors.value.containsKey(agentId);
    final icon = kMobile ? 40.0 : 26.0;
    final gap = kMobile ? 6.0 : 2.0;
    final avatar = part == AgentAppearancePart.avatar;
    final grid = Wrap(
      spacing: gap,
      runSpacing: gap,
      children: avatar
          ? [
              for (final s in MascotShape.values)
                _cell(
                    s.name[0].toUpperCase() + s.name.substring(1),
                    s == shape,
                    () => _pickShape(context, s),
                    MochiIcon(color: color, size: icon, shape: s)),
            ]
          : [
              for (final (label, c) in mochiPalette)
                _cell(label, c == color, () => _pickColor(context, c),
                    MochiIcon(color: c, size: icon, shape: shape)),
            ],
    );
    final reset = !avatar && custom;
    if (kMobile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(M.gutter, 4, M.gutter, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            grid,
            if (reset) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Btn('Use default',
                    small: true, onTap: () => _pickColor(context, null)),
              ),
            ],
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          grid,
          if (reset) ...[
            const SizedBox(height: 4),
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _pickColor(context, null),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: Text('Use default',
                      style: sans(12, color: AppColors.fg3)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
