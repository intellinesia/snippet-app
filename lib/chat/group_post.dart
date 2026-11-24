import 'package:flutter/material.dart';

import '../mochi.dart';
import '../tap_detector.dart';
import '../theme.dart';

/// Face, name and time, shown once above a run of one agent's posts.
class GroupPostHeader extends StatelessWidget {
  const GroupPostHeader({
    super.key,
    required this.agentId,
    required this.name,
    this.time,
    this.lead = false,
  });

  final String agentId;
  final String name;
  final String? time;
  final bool lead;

  /// The face column: posts below it indent by this much.
  static const double face = 24;
  static const double indent = face + 8;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: S.s4),
        child: Row(children: [
          ClipRRect(
              borderRadius: BorderRadius.circular(R.of(7)),
              child: AgentMochi(agentId, size: face)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(14, weight: W.label, color: AppColors.fg1)),
          ),
          if (lead) ...[
            const SizedBox(width: 6),
            Text('lead', style: sans(12, color: AppColors.fg3)),
          ],
          if (time != null) ...[
            const SizedBox(width: 8),
            Text(time!, style: sans(12, color: AppColors.fg3, tabular: true)),
          ],
        ]),
      );
}

const int _capLines = 8;
const int _capChars = 480;

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

/// Prose that stops after a few lines with a 44pt Show more underneath.
class CappedProse extends StatefulWidget {
  const CappedProse({super.key, required this.body, required this.builder});

  final String body;
  final Widget Function(String text) builder;

  @override
  State<CappedProse> createState() => _CappedProseState();
}

class _CappedProseState extends State<CappedProse> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
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
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 94),
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              child: Text(_open ? 'Show less' : 'Show more',
                  style: sans(13, weight: W.label, color: AppColors.fg2)),
            ),
          ),
        ),
      ],
    );
  }
}
