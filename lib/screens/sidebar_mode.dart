import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';
import '../widgets.dart' show AppIcon;

/// Desktop sidebar: sessions first (agents in the rail) or agents first.
final sidebarAgentsFirst = ValueNotifier<bool>(false);
const _agentsFirstPref = 'desktop_sidebar_agents_first';

Future<void> loadSidebarAgentsFirst() async {
  final prefs = await SharedPreferences.getInstance();
  sidebarAgentsFirst.value = prefs.getBool(_agentsFirstPref) ?? false;
}

void setSidebarAgentsFirst(bool agents) {
  if (sidebarAgentsFirst.value == agents) return;
  sidebarAgentsFirst.value = agents;
  SharedPreferences.getInstance()
      .then((p) => p.setBool(_agentsFirstPref, agents));
}

/// Two-way switch in the sidebar header: sessions or agents first.
class SidebarModeSwitch extends StatelessWidget {
  const SidebarModeSwitch({super.key});

  static const double _cell = 26;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: sidebarAgentsFirst,
      builder: (context, agents, _) => Container(
        height: _cell + 4,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.line),
        ),
        child: Stack(children: [
          AnimatedPositioned(
            duration: Motion.base,
            curve: Curves.easeOutCubic,
            left: agents ? _cell : 0,
            top: 0,
            child: Container(
              width: _cell,
              height: _cell,
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(7),
              ),
            ),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            _cellBtn('list', 'Sessions first', !agents, false,
                const ValueKey('sidebar-mode-sessions')),
            _cellBtn('agent', 'Agents first', agents, true,
                const ValueKey('sidebar-mode-agents')),
          ]),
        ]),
      ),
    );
  }

  Widget _cellBtn(String icon, String tip, bool on, bool agents, Key key) =>
      Tooltip(
        message: tip,
        child: Semantics(
          button: true,
          selected: on,
          label: tip,
          child: GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            onTap: () => setSidebarAgentsFirst(agents),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: SizedBox.square(
                dimension: _cell,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: Motion.quick,
                    child: AppIcon(icon,
                        key: ValueKey('$icon-$on'),
                        size: 14,
                        color: on ? AppColors.fg1 : AppColors.fg4),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// Cross-moves the sessions list out to the right while the agent list
/// arrives from the rail's side, so the rail reads as widening into it.
class SidebarModeSwap extends StatefulWidget {
  const SidebarModeSwap({
    super.key,
    required this.agentsFirst,
    required this.sessions,
    required this.agents,
  });

  final bool agentsFirst;
  final Widget sessions;
  final WidgetBuilder agents;

  @override
  State<SidebarModeSwap> createState() => _SidebarModeSwapState();
}

class _SidebarModeSwapState extends State<SidebarModeSwap>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
    reverseDuration: Motion.page,
    value: widget.agentsFirst ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant SidebarModeSwap old) {
    super.didUpdateWidget(old);
    if (old.agentsFirst != widget.agentsFirst) {
      widget.agentsFirst ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = reduce ? (widget.agentsFirst ? 1.0 : 0.0) : _c.value;
        final out = Curves.easeInCubic.transform((t / 0.7).clamp(0.0, 1.0));
        final inn =
            Curves.easeOutCubic.transform(((t - 0.2) / 0.8).clamp(0.0, 1.0));
        return ClipRect(
          child: Stack(fit: StackFit.expand, children: [
            if (t < 1)
              IgnorePointer(
                ignoring: widget.agentsFirst,
                child: Opacity(
                  opacity: 1 - out,
                  child: Transform.translate(
                    offset: Offset(60 * out, 0),
                    child: widget.sessions,
                  ),
                ),
              ),
            if (t > 0)
              IgnorePointer(
                ignoring: !widget.agentsFirst,
                child: Opacity(
                  opacity: inn,
                  child: Transform.translate(
                    offset: Offset(-52 * (1 - inn), 0),
                    child: widget.agents(context),
                  ),
                ),
              ),
          ]),
        );
      },
    );
  }
}
