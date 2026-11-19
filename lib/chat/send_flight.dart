import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../diagnostics.dart';
import 'send_in.dart';

/// Remembers where the composer's text field was when the user pressed send,
/// so the sent bubble's text can travel from there into the transcript.
class SendFlight {
  static Rect? _from;
  static DateTime? _at;

  /// Call just before the field is cleared.
  static void arm(GlobalKey fieldKey) {
    final box = fieldKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    _from = box.localToGlobal(Offset.zero) & box.size;
    _at = DateTime.now();
    Diag.crumb('send flight armed');
  }

  static Rect? take() {
    final from = _from;
    final at = _at;
    _from = null;
    _at = null;
    if (from == null || at == null) return null;
    return DateTime.now().difference(at).inSeconds > 8 ? null : from;
  }
}

/// Wraps a freshly sent bubble. The real bubble stays hidden while a copy of
/// its text flies from the input field to its final spot, then fades in.
/// Without a known start (a resend, a reconnect) it rises in instead.
class SendFlightTarget extends StatefulWidget {
  const SendFlightTarget({super.key, required this.child});

  final Widget child;

  @override
  State<SendFlightTarget> createState() => _SendFlightTargetState();
}

class _SendFlightTargetState extends State<SendFlightTarget>
    with SingleTickerProviderStateMixin {
  final _box = GlobalKey();
  late final AnimationController _c;
  Rect? _from;
  OverlayEntry? _entry;
  bool _flying = false;

  @override
  void initState() {
    super.initState();
    // Created up front: dispose runs for the rise fallback too.
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 460));
    _from = SendFlight.take();
    Diag.crumb('send flight target ${_from == null ? 'rise' : 'fly'}');
    if (_from != null) {
      _flying = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _launch());
    }
  }

  RenderObject? _textObject() {
    RenderObject? found;
    void visit(RenderObject o) {
      if (found != null) return;
      if (o is RenderParagraph || o is RenderEditable) {
        found = o;
        return;
      }
      o.visitChildren(visit);
    }

    final root = _box.currentContext?.findRenderObject();
    if (root != null) visit(root);
    return found;
  }

  Rect? _rectOf(RenderObject o) {
    if (o is RenderBox && o.attached && o.hasSize) {
      return o.localToGlobal(Offset.zero) & o.size;
    }
    return null;
  }

  void _launch() {
    if (!mounted) return;
    final target = _textObject();
    final from = _from;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (target == null ||
        from == null ||
        overlay == null ||
        MediaQuery.disableAnimationsOf(context)) {
      setState(() => _flying = false);
      return;
    }
    final InlineSpan? span = target is RenderParagraph
        ? target.text
        : target is RenderEditable
            ? target.text
            : null;
    final scaler = target is RenderParagraph
        ? target.textScaler
        : (target as RenderEditable).textScaler;
    final first = _rectOf(target);
    if (span == null || first == null) {
      setState(() => _flying = false);
      return;
    }
    final startLeft = from.left + 16;
    final startTop = from.center.dy - first.height / 2;
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    _entry = OverlayEntry(
      builder: (_) => AnimatedBuilder(
        animation: curve,
        builder: (_, __) {
          final end = _rectOf(target) ?? first;
          final t = curve.value;
          final pos = Offset.lerp(Offset(startLeft, startTop), end.topLeft, t)!;
          final fade = t < 0.8 ? 1.0 : (1 - (t - 0.8) / 0.2).clamp(0.0, 1.0);
          return Positioned(
            left: pos.dx,
            top: pos.dy,
            width: end.width,
            child: IgnorePointer(
              child: Opacity(
                opacity: fade,
                child: RichText(text: span, textScaler: scaler),
              ),
            ),
          );
        },
      ),
    );
    overlay.insert(_entry!);
    Diag.crumb('send flight launched');
    _c.forward().whenComplete(() {
      _entry?.remove();
      _entry = null;
      if (mounted) setState(() => _flying = false);
    });
  }

  @override
  void dispose() {
    if (_entry != null) Diag.crumb('send flight cut short');
    _entry?.remove();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_from == null) return SendIn(child: widget.child);
    if (!_flying) return KeyedSubtree(key: _box, child: widget.child);
    return KeyedSubtree(
      key: _box,
      child: AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (_, child) => Opacity(
          opacity: ((_c.value - 0.55) / 0.45).clamp(0.0, 1.0),
          child: child,
        ),
      ),
    );
  }
}
