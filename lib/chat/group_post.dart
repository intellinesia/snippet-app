import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../mochi.dart';
import '../platform.dart';
import '../tap_detector.dart';
import '../theme.dart';
import 'run_head.dart';

/// Face, name and time, shown once above a run of one agent's posts.
class GroupPostHeader extends StatelessWidget {
  const GroupPostHeader({
    super.key,
    required this.agentId,
    required this.name,
    this.mascot,
    this.time,
    this.muted = false,
  });

  final String agentId;
  final String name;

  /// MSG-03 muted sender (desktop): name fg2 plus the Muted pill.
  final bool muted;

  /// The mascot's name, read out before the agent: "Buddy, Snippet, 09:31".
  final String? mascot;
  final String? time;

  /// The face column: posts below it indent by this much.
  static const double face = 24;

  /// Kept as a constant for the existing screen contract. Transcript rows
  /// built with [SoftLane] get the x+36 desktop column intrinsically.
  static const double indent = 0;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        container: true,
        label: [
          if (mascot != null) mascot!,
          name,
          if (time != null) time!,
          if (muted && !kMobile) 'Muted',
        ].join(', '),
        excludeSemantics: true,
        child: kMobile ? _phone() : _desk(),
      );

  Widget _phone() => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          ClipRRect(
              borderRadius: BorderRadius.circular(R.of(6)),
              child: AgentMochi(agentId, size: face)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(13, weight: W.label, color: AppColors.fg1)),
          ),
          if (time != null) ...[
            const SizedBox(width: 8),
            Text(time!, style: sans(11.5, color: AppColors.fg3, tabular: true)),
          ],
        ]),
      );

  // MSG-03: avatar 24, name 13/500 fg1 at x+36, time 11/400 fg3 after it.
  Widget _desk() => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: SizedBox(
          height: face,
          child: Row(children: [
            ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: AgentMochi(agentId, size: face)),
            const SizedBox(width: kSoftIndent - face),
            Flexible(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13,
                      height: 18 / 13,
                      weight: FontWeight.w500,
                      color: muted ? AppColors.fg2 : AppColors.fg1)),
            ),
            if (time != null) ...[
              const SizedBox(width: 6),
              Text(time!, style: sans(11, color: AppColors.fg3, tabular: true)),
            ],
            if (muted) ...[
              const SizedBox(width: 8),
              const MutedPill(),
            ],
          ]),
        ),
      );
}

const int _capLines = 8;
const int _capChars = 520;

/// The preview of a long post, or null when it fits.
String? groupPostPreview(String body) {
  final text = body.trim();
  final lines = text.split('\n');
  if (lines.length <= _capLines && text.length <= _capChars) return null;
  var out = lines.take(_capLines).join('\n');
  if (out.length > _capChars) {
    final cut = out.lastIndexOf(RegExp(r'\s'), _capChars);
    out = out.substring(0, cut > _capChars ~/ 2 ? cut : _capChars);
  }
  out = out.trimRight();
  if (RegExp(r'^\s*```', multiLine: true).allMatches(out).length.isOdd) {
    out = '$out\n```';
  }
  return '$out…';
}

/// Prose that stops after a few lines with a Show more underneath: phone
/// 3 lines and a 48pt text button, desktop 8 body lines (MSG-02/03) and a
/// 28-high secondary button.
class CappedProse extends StatefulWidget {
  const CappedProse({super.key, required this.body, required this.builder});

  final String body;
  final Widget Function(String text) builder;

  @override
  State<CappedProse> createState() => _CappedProseState();
}

/// Desktop clamp: eight 19pt body lines.
const double kPostClampHeight = 8 * 19;

class _CappedProseState extends State<CappedProse> {
  bool _open = false;
  bool _overflows = false;

  void _report(bool overflows) {
    if (overflows == _overflows) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && overflows != _overflows) {
        setState(() => _overflows = overflows);
      }
    });
  }

  Widget _desk() {
    final body = widget.builder(widget.body);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_open)
          body
        else
          _LineClamp(
              maxHeight: kPostClampHeight, onOverflow: _report, child: body),
        if (_overflows)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: ChatButton(
              label: _open ? 'Show less' : 'Show more (8+ lines)',
              onTap: () => setState(() => _open = !_open),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!kMobile) return _desk();
    final preview = groupPostPreview(widget.body);
    if (preview == null) return widget.builder(widget.body);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        widget.builder(_open ? widget.body : preview),
        TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _open = !_open),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.surface3,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_open ? 'Show less' : 'Show more',
                  style: sans(13, weight: FontWeight.w500, color: AppColors.fg2)),
            ]),
          ),
        ),
      ],
    );
  }
}

/// Lays its child out at full height, shows at most [maxHeight] of it and
/// reports whether anything was cut.
class _LineClamp extends SingleChildRenderObjectWidget {
  const _LineClamp(
      {required this.maxHeight, required this.onOverflow, super.child});

  final double maxHeight;
  final ValueChanged<bool> onOverflow;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLineClamp(maxHeight, onOverflow);

  @override
  void updateRenderObject(BuildContext context, _RenderLineClamp r) => r
    ..maxHeight = maxHeight
    ..onOverflow = onOverflow;
}

class _RenderLineClamp extends RenderProxyBox {
  _RenderLineClamp(this._maxHeight, this.onOverflow);

  double _maxHeight;
  ValueChanged<bool> onOverflow;
  bool _cut = false;

  set maxHeight(double v) {
    if (v == _maxHeight) return;
    _maxHeight = v;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.smallest;
      return;
    }
    c.layout(constraints.copyWith(maxHeight: double.infinity),
        parentUsesSize: true);
    _cut = c.size.height > _maxHeight + 0.5;
    size = constraints
        .constrain(Size(c.size.width, _cut ? _maxHeight : c.size.height));
    onOverflow(_cut);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_cut) return super.paint(context, offset);
    layer = context.pushClipRect(
        needsCompositing, offset, Offset.zero & size, super.paint,
        oldLayer: layer as ClipRectLayer?);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      (Offset.zero & size).contains(position) &&
      super.hitTestChildren(result, position: position);
}
