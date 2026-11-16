import 'package:flutter/material.dart';

import '../api.dart';
import '../chat/chat_info.dart' show DockedInfoNav;
import '../mochi.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

/// Opens the avatar and colour picker for an agent; the two are stored
/// separately, and each previews the other's current choice.
Future<void> showAgentAppearance(
    BuildContext context, DaemonClient client, String agentId, String name,
    {Offset? point}) {
  final nav = DockedInfoNav.maybeOf(context);
  if (nav != null) {
    nav.push(
        'Appearance',
        (_) => AgentAppearancePicker(
            client: client, agentId: agentId, onDone: nav.pop));
    return Future<void>.value();
  }
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

/// The character grid. Picking one saves and updates live without closing;
/// [onDone] closes the panel.
class AgentAppearancePicker extends StatelessWidget {
  const AgentAppearancePicker({
    super.key,
    required this.client,
    required this.agentId,
    required this.onDone,
  });

  static const desktopWidth = 6 * 40.0 + 5 * 6 + 24;

  final DaemonClient client;
  final String agentId;
  final VoidCallback onDone;

  Future<void> _pickCharacter(BuildContext context, String? id) async {
    final before = agentCharacterFor(agentId);
    setRememberedAgentCharacter(agentId, id);
    try {
      await client.setAgentCharacter(agentId, id);
      // Clearing resolves to the daemon's stable default, which only a refetch knows.
      if (id == null) await client.coordinationAgents();
    } catch (_) {
      setRememberedAgentCharacter(agentId, before);
      if (context.mounted) {
        toast(context, 'Could not change character', danger: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: agentCharacters,
      builder: (context, chars, _) {
        final current = chars[agentId];
        final gap = kMobile ? 8.0 : 6.0;
        final target = kMobile ? 52.0 : 40.0;
        final radius = BorderRadius.circular(R.of(kMobile ? 12 : 8));

        final grid = LayoutBuilder(builder: (context, box) {
          final cols = ((box.maxWidth + gap) / (target + gap)).floor().clamp(1, 12);
          final cell = (box.maxWidth - (cols - 1) * gap) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var i = 1; i <= 36; i++)
                _cell(i.toString().padLeft(2, '0'), cell, radius, current),
            ],
          );
        });

        return Padding(
          padding: kMobile
              ? EdgeInsets.fromLTRB(M.gutter, S.s4, M.gutter, S.s12)
              : EdgeInsets.all(S.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s8),
                child: Text('Character', style: sans(13, color: AppColors.fg3)),
              ),
              grid,
              SizedBox(height: S.s12),
              Row(
                children: [
                  Btn('Use default',
                      variant: BtnVariant.ghost,
                      small: true,
                      onTap: () => _pickCharacter(context, null)),
                  const Spacer(),
                  Btn('Done', small: true, onTap: onDone),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _cell(String id, double size, BorderRadius radius, String? current) {
    final sel = id == current;
    final tint =
        CharacterRoster.current?.character(id)?.color ?? AppColors.accent;
    return Tooltip(
      message: 'Character $id',
      waitDuration: const Duration(milliseconds: 400),
      child: Builder(
        builder: (context) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _pickCharacter(context, id),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: sel ? tint.withValues(alpha: 0.13) : AppColors.surface2,
              borderRadius: radius,
              border: Border.all(
                  color: sel ? tint : AppColors.lineStrong, width: sel ? 1.5 : 1),
            ),
            child: Center(
              child: AgentCharacter(id, size: size - 14, staggerKey: id),
            ),
          ),
        ),
      ),
    );
  }
}
