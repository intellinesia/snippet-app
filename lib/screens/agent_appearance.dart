import 'package:flutter/material.dart';

import '../api.dart';
import '../mochi.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

/// Opens the avatar and colour picker for an agent; the two are stored
/// separately, and each previews the other's current choice.
Future<void> showAgentAppearance(
    BuildContext context, DaemonClient client, String agentId, String name,
    {Offset? point}) {
  if (kMobile) {
    return showAppSheet<void>(
      context,
      title: '$name appearance',
      maxHeight: 640,
      child: Builder(
        builder: (ctx) => AgentAppearancePicker(
          client: client,
          agentId: agentId,
          onDone: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }
  return showPointPopover<void>(
    context,
    point: point,
    width: AgentAppearancePicker.desktopWidth,
    maxHeight: 560,
    child: Builder(
      builder: (ctx) => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 560),
        child: SingleChildScrollView(
          child: AgentAppearancePicker(
            client: client,
            agentId: agentId,
            onDone: () => Navigator.of(ctx).pop(),
          ),
        ),
      ),
    ),
  );
}

/// The avatar and colour grids in one panel. Picking either updates live
/// without closing; [onDone] closes the panel.
class AgentAppearancePicker extends StatelessWidget {
  const AgentAppearancePicker({
    super.key,
    required this.client,
    required this.agentId,
    required this.onDone,
  });

  static const desktopWidth = 4 * 40.0 + 3 * 2 + 24;

  final DaemonClient client;
  final String agentId;
  final VoidCallback onDone;

  Future<void> _pickShape(BuildContext context, MascotShape shape) async {
    final before = agentShapes.value[agentId];
    final value = shape == MascotShape.mochi ? null : shape.name;
    setRememberedAgentShape(agentId, value);
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
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: agentShapes,
      builder: (context, _, __) => ValueListenableBuilder<Map<String, String>>(
        valueListenable: agentColors,
        builder: (context, colors, __) {
          final color = mochiColorFor(agentId);
          final shape = mascotShapeFor(agentId);
          final custom = colors.containsKey(agentId);
          final icon = kMobile ? 40.0 : 26.0;
          final gap = kMobile ? 6.0 : 2.0;

          final shapeGrid = Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final s in MascotShape.values)
                _cell(
                    s.name[0].toUpperCase() + s.name.substring(1),
                    s == shape,
                    () => _pickShape(context, s),
                    MochiIcon(color: color, size: icon, shape: s)),
            ],
          );

          final colourGrid = Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final (label, c) in mochiPalette)
                _cell(label, c == color, () => _pickColor(context, c),
                    MochiIcon(color: c, size: icon, shape: shape)),
            ],
          );

          return Padding(
            padding: kMobile
                ? const EdgeInsets.fromLTRB(M.gutter, 4, M.gutter, 12)
                : const EdgeInsets.all(S.s12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SectionLabel('Avatar'),
                const SizedBox(height: S.s4),
                shapeGrid,
                const SizedBox(height: S.s16),
                const SectionLabel('Colour'),
                const SizedBox(height: S.s4),
                colourGrid,
                const SizedBox(height: S.s12),
                Row(
                  children: [
                    if (custom)
                      Btn('Use default',
                          variant: BtnVariant.ghost,
                          small: true,
                          onTap: () => _pickColor(context, null)),
                    const Spacer(),
                    Btn('Done', small: true, onTap: onDone),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
