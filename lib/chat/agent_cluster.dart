import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'chat_style.dart';

/// An iMessage-style cluster of agent discs inside a circle of [size].
///
/// One id is a single disc; two overlap diagonally; three or more sit in a
/// triangle, and past three members the last slot counts the rest as '+N'.
class AgentCluster extends StatelessWidget {
  const AgentCluster({super.key, required this.ids, required this.size});

  final List<String> ids;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (ids.length < 2) {
      return AgentDisc(id: ids.isEmpty ? '' : ids.first, size: size);
    }
    if (ids.length == 2) {
      final d = size * 0.62;
      return SizedBox.square(
        dimension: size,
        child: Stack(children: [
          Positioned(left: 0, top: 0, child: AgentDisc(id: ids[0], size: d)),
          Positioned(
              right: 0,
              bottom: 0,
              child: AgentDisc(id: ids[1], size: d, ring: true)),
        ]),
      );
    }
    final d = size * 0.5;
    final overflow = ids.length > 3;
    Widget slot(int i) {
      if (overflow && i == 2) return _MoreDisc(count: ids.length - 2, size: d);
      return AgentDisc(id: ids[i], size: d, ring: i > 0);
    }

    return SizedBox.square(
      dimension: size,
      child: Stack(children: [
        Positioned(left: size * 0.25, top: size * 0.04, child: slot(0)),
        Positioned(left: 0, top: size * 0.46, child: slot(1)),
        Positioned(left: size * 0.5, top: size * 0.46, child: slot(2)),
      ]),
    );
  }
}

class _MoreDisc extends StatelessWidget {
  const _MoreDisc({required this.count, required this.size});

  final int count;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: avatarDecoration(size,
            color: AppColors.surface3,
            side: BorderSide(color: readingBg, width: 2)),
        alignment: Alignment.center,
        child: Text('+$count',
            maxLines: 1,
            style: sans(11, weight: W.label, color: AppColors.fg2)),
      );
}

/// The quiet group mark: a rounded square with the people glyph in fg2.
class GroupGlyph extends StatelessWidget {
  const GroupGlyph({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
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
