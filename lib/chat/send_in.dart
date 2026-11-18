import 'package:flutter/material.dart';

/// A message you just sent rises from the composer into its place in the
/// transcript, like a messaging app. Plays once, when first built.
class SendIn extends StatefulWidget {
  const SendIn({super.key, required this.child, this.play = true});

  final Widget child;

  /// Only the first build animates; later rebuilds keep the settled state.
  final bool play;

  @override
  State<SendIn> createState() => _SendInState();
}

class _SendInState extends State<SendIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 360));

  @override
  void initState() {
    super.initState();
    if (widget.play) {
      _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: curve,
      child: widget.child,
      builder: (_, child) {
        final t = curve.value;
        return Opacity(
          opacity: (t * 2.5).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 80 * (1 - t)),
            child: Transform.scale(
              scale: 0.9 + 0.1 * t,
              alignment: Alignment.bottomRight,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
