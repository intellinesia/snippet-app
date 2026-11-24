import 'package:flutter/material.dart';

import '../mochi.dart';
import '../theme.dart';
import '../widgets.dart';
import 'chat_style.dart';

/// The group mark (G1): the lead face with a member count badge.
///
/// A single id is a plain disc; two or more show the first face and the
/// count of everyone in the group, you included, in a small s3 badge.
class AgentCluster extends StatelessWidget {
  const AgentCluster(
      {super.key, required this.ids, required this.size, this.count});

  final List<String> ids;
  final double size;

  /// Members shown on the badge; defaults to the agents plus you.
  final int? count;

  @override
  Widget build(BuildContext context) {
    if (ids.length < 2) {
      return AgentDisc(id: ids.isEmpty ? '' : ids.first, size: size);
    }
    final n = count ?? ids.length + 1;
    return Semantics(
      label: 'Group, $n members',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
              child: ClipOval(child: AgentMochi(ids.first, size: size))),
          if (size >= 20)
            Positioned(
                right: -size * 0.06,
                bottom: -size * 0.06,
                child: _CountBadge(count: n, size: size)),
        ]),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.size});

  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    final d = (size * 0.42).clamp(12.0, 20.0);
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        color: AppColors.surface3,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.bg, width: 2),
      ),
      alignment: Alignment.center,
      child: Text('$count',
          maxLines: 1,
          style: sans(d * 0.55, weight: W.label, color: AppColors.fg1)),
    );
  }
}

/// The quiet group mark: a rounded square with the people glyph in fg2.
class GroupGlyph extends StatelessWidget {
  const GroupGlyph({super.key, required this.size, this.ids, this.count});
  final double size;

  /// The group's agents: with them the glyph is the G1 face plus count.
  final List<String>? ids;
  final int? count;

  @override
  Widget build(BuildContext context) => (ids?.length ?? 0) >= 2
      ? AgentCluster(ids: ids!, size: size, count: count)
      : Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.of(size * 0.3)),
        ),
        child: AppIcon('users', size: size * 0.57, color: AppColors.fg2),
      );
}
