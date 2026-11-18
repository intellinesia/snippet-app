import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

/// Anchored popover for setting the session goal: what to work toward, who
/// works on it, and how a goal runs.
class GoalPopover extends StatefulWidget {
  final void Function(String text) onSet;

  /// The agent that will drive the goal, named in the header and the help line.
  final String? agentName;
  const GoalPopover({super.key, required this.onSet, this.agentName});

  @override
  State<GoalPopover> createState() => _GoalPopoverState();
}

class _GoalPopoverState extends State<GoalPopover> {
  final _ctl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _ctl.text.trim();
    if (t.isEmpty) return;
    widget.onSet(t);
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.agentName ?? '').trim();
    final who = name.isEmpty ? 'The agent' : name;
    final ready = _ctl.text.trim().isNotEmpty;
    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.enter,
            meta: kMacOS, control: !kMacOS): _submit,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.maybePop(context),
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            AppIcon('goal', size: 14, color: AppColors.fg3),
            SizedBox(width: S.s8),
            Text('Set a goal',
                style: sans(13, weight: W.title, color: AppColors.fg1)),
            const Spacer(),
            if (name.isNotEmpty)
              Text('for $name', style: sans(12, color: AppColors.fg4)),
          ]),
          SizedBox(height: S.s12),
          AppField(
            controller: _ctl,
            hint: 'What should $who work toward?',
            autofocus: true,
            minLines: 2,
            maxLines: 5,
          ),
          SizedBox(height: S.s8),
          Text(
              '$who keeps working, turn after turn, until it is met or you '
              'end it. Interrupting pauses it.',
              style: sans(12, height: 1.45, color: AppColors.fg4)),
          SizedBox(height: S.s12),
          Row(children: [
            if (!kMobile)
              Text(kMacOS ? '\u2318\u21b5' : 'Ctrl \u21b5',
                  style: mono(11, color: AppColors.fg4)),
            const Spacer(),
            if (!kMobile) ...[
              Btn('Cancel',
                  variant: BtnVariant.ghost,
                  small: true,
                  onTap: () => Navigator.pop(context)),
              SizedBox(width: S.s6),
            ],
            Btn('Start goal', small: true, onTap: ready ? _submit : null),
          ]),
        ],
      ),
    );
  }
}

/// Keeps a swiped-away tab mounted so its WebSocket attach and scroll position
/// survive switching between tabs.
class ShellKeepAlive extends StatefulWidget {
  final Widget child;
  final bool keep;
  const ShellKeepAlive({super.key, required this.child, this.keep = true});
  @override
  State<ShellKeepAlive> createState() => _ShellKeepAliveState();
}

class _ShellKeepAliveState extends State<ShellKeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keep;
  @override
  void didUpdateWidget(covariant ShellKeepAlive oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keep != widget.keep) updateKeepAlive();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    super.build(context);
    return widget.child;
  }
}

/// Small green pulsing dot indicating a running session.
class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key});

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      if (_ctrl.isAnimating) _ctrl.stop();
      _ctrl.value = 1;
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: FadeTransition(
        opacity: _ctrl.drive(Tween(begin: 0.4, end: 1.0)),
        child: Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: AppColors.ok,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
