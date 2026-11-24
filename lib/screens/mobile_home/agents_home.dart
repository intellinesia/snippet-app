import 'package:flutter/material.dart';

import '../../chat/agent_cluster.dart';
import '../../mochi.dart';
import '../../models.dart';
import '../../quiet.dart';
import '../../tap_detector.dart';
import '../../theme.dart';
import '../../widgets.dart';

/// Phone Agents Home and All agents building blocks (spec B, HM-02 to HM-04).
/// Every height is a minimum; text never sits in a fixed box.

const double kGutter = 16;

/// Chip and tab labels clamp the scaler at 1.35 (spec A section 0).
Widget clampedScale(BuildContext context, Widget child, {double max = 1.35}) {
  final mq = MediaQuery.of(context);
  final s = mq.textScaler.scale(10) / 10;
  if (s <= max) return child;
  return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.linear(max)), child: child);
}

bool bigText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) / 10 >= 1.35;

/// State chip: 44 high, radius 22, label plus 32 wide, optional amber dot.
class StateChip extends StatelessWidget {
  const StateChip(this.label, this.selected, this.onTap,
      {super.key, this.amberDot = false, this.fill});
  final String label;
  final bool selected, amberDot;
  final VoidCallback onTap;
  final Color? fill;

  @override
  Widget build(BuildContext context) => clampedScale(
        context,
        Semantics(
          button: true,
          selected: selected,
          label: label,
          excludeSemantics: true,
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              height: 44,
              padding: EdgeInsets.only(left: amberDot ? 8 : 16, right: 16),
              decoration: BoxDecoration(
                color: selected ? AppColors.fg1 : (fill ?? AppColors.surface1),
                borderRadius: BorderRadius.circular(22),
                border: selected || fill != null
                    ? null
                    : Border.all(color: AppColors.border, width: 1),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (amberDot) ...[
                  Container(
                      key: const ValueKey('chip-amber-dot'),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          color: quietAmber, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                ],
                Text(label,
                    maxLines: 1,
                    style: sans(13,
                        weight: selected ? FontWeight.w500 : FontWeight.w400,
                        color: selected ? AppColors.bg : AppColors.fg2)),
              ]),
            ),
          ),
        ),
      );
}

/// The chip row: scrolls sideways, never wraps.
class ChipRow extends StatelessWidget {
  const ChipRow({super.key, required this.chips, this.gap = 8});
  final List<Widget> chips;
  final double gap;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: kGutter),
        child: Row(children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            chips[i],
          ],
        ]),
      );
}

/// 12/500 fg3 section label at the gutter.
class HomeLabel extends StatelessWidget {
  const HomeLabel(this.text, {super.key, this.top = 24, this.trailing});
  final String text;
  final double top;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(kGutter, top, kGutter, 8),
        child: Row(children: [
          Expanded(
              child: Text(text,
                  style: sans(12, weight: FontWeight.w500, color: AppColors.fg3))),
          if (trailing != null) trailing!,
        ]),
      );
}

/// A 48 high text button at the gutter (Show n more).
class TextLink extends StatelessWidget {
  const TextLink(this.label, this.onTap, {super.key, this.left = kGutter});
  final String label;
  final VoidCallback onTap;
  final double left;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: left, right: kGutter),
                child: Text(label,
                    style: sans(13, color: AppColors.fg2)),
              ),
            ),
          ),
        ),
      );
}

/// One agent as the Home grid shows it.
class AgentCardData {
  const AgentCardData(this.agent, this.status, this.line, {this.working = false});
  final CoordinationAgent agent;

  /// "Working · 5m", "Idle".
  final String status;

  /// The task or last message, one line.
  final String line;
  final bool working;
}

class AgentCard extends StatelessWidget {
  const AgentCard({super.key, required this.data, required this.onTap});
  final AgentCardData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: [data.agent.displayName, data.status, data.line]
            .where((e) => e.isNotEmpty)
            .join(', '),
        excludeSemantics: true,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 138),
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
            decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border, width: 1),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ClipOval(child: AgentMochi(data.agent.id, size: 64)),
              const SizedBox(height: 5),
              Text(data.agent.displayName,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: sans(14, weight: FontWeight.w500, color: AppColors.fg1)),
              const SizedBox(height: 2),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                AppIcon(data.working ? 'circle' : 'check-circle',
                    size: 14, color: AppColors.fg2),
                const SizedBox(width: 4),
                Flexible(
                    child: Text(data.status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(11.5, color: AppColors.fg2))),
              ]),
              if (data.line.isNotEmpty)
                Text(data.line,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: sans(11.5, color: AppColors.fg3)),
            ]),
          ),
        ),
      );
}

/// Two columns (one at 1.35x and above) of [AgentCard], 10 apart.
class AgentGrid extends StatelessWidget {
  const AgentGrid({super.key, required this.cards, required this.onOpen});
  final List<AgentCardData> cards;
  final void Function(CoordinationAgent a) onOpen;

  @override
  Widget build(BuildContext context) {
    final cols = bigText(context) ? 1 : 2;
    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += cols) {
      final slice = cards.skip(i).take(cols).toList();
      rows.add(Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var j = 0; j < cols; j++) ...[
              if (j > 0) const SizedBox(width: 10),
              Expanded(
                  child: j < slice.length
                      ? AgentCard(
                          data: slice[j],
                          onTap: () => onOpen(slice[j].agent))
                      : const SizedBox.shrink()),
            ],
          ]),
        ),
      ));
    }
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: kGutter),
        child: Column(children: rows));
  }
}

/// A full-bleed list row: mark at x16, text at x62, hairline x62 to width-16.
class MarkRow extends StatelessWidget {
  const MarkRow({
    super.key,
    required this.mark,
    required this.title,
    this.sub,
    this.sub2,
    this.time,
    this.trailing,
    this.onTap,
    this.markSize = 36,
    this.subStyleSize = 13,
    this.hairline = true,
    this.subColor,
    this.minHeight = 56,
    this.gap = 10,
  });
  final Widget mark;
  final double gap;
  final double markSize;
  final String title;
  final String? sub, sub2, time;
  final Widget? trailing;
  final VoidCallback? onTap;
  final double subStyleSize, minHeight;
  final Color? subColor;
  final bool hairline;

  @override
  Widget build(BuildContext context) {
    final inline = !bigText(context);
    final textInset = kGutter + markSize + gap;
    return Semantics(
      button: onTap != null,
      label: [title, if (sub != null) sub!, if (sub2 != null) sub2!, if (time != null) time!]
          .join(', '),
      excludeSemantics: true,
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(kGutter, 10, kGutter, 10),
              child: Row(children: [
                SizedBox(width: markSize, height: markSize, child: mark),
                SizedBox(width: gap),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: sans(15,
                                      weight: FontWeight.w500,
                                      color: AppColors.fg1))),
                          if (time != null && inline) ...[
                            const SizedBox(width: 8),
                            Text(time!,
                                style: sans(12, color: AppColors.fg3)),
                          ],
                        ]),
                        if (time != null && !inline)
                          Text(time!, style: sans(12, color: AppColors.fg3)),
                        if (sub != null && sub!.isNotEmpty)
                          Text(sub!,
                              maxLines: inline ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: sans(subStyleSize,
                                  color: subColor ?? AppColors.fg3)),
                        if (sub2 != null && sub2!.isNotEmpty)
                          Text(sub2!,
                              maxLines: inline ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: sans(12, color: AppColors.fg3)),
                      ]),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ]),
            ),
          ),
          if (hairline)
            Positioned(
                left: textInset,
                right: kGutter,
                bottom: 0,
                height: 1,
                child: ColoredBox(color: AppColors.border)),
        ]),
      ),
    );
  }
}

Widget agentFace(String id, double size) =>
    ClipOval(child: AgentMochi(id, size: size));

/// Square group mark: radius 10.1 at 36, hairline border, glyph fg2.
Widget groupMark(double size, {double radius = 10.1}) => Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: AppIcon('users', size: size > 40 ? 22 : 20, color: AppColors.fg2),
    );

/// Footer card: two 48 high halves split by a 1 x 30 hairline.
class HomeFooter extends StatelessWidget {
  const HomeFooter(
      {super.key, required this.onAll, this.finished = 0, this.onFinished});
  final VoidCallback? onAll;
  final int finished;
  final VoidCallback? onFinished;

  Widget _half(String label, Color c, VoidCallback? onTap, {Widget? icon}) =>
      Expanded(
        child: Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (icon != null) ...[icon, const SizedBox(width: 8)],
                  Flexible(
                      child: Text(label,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: sans(13, color: c))),
                ]),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: kGutter),
        child: Container(
          key: const ValueKey('home-footer'),
          constraints: const BoxConstraints(minHeight: 50),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              _half('All agents', AppColors.fg1, onAll,
                  icon: AppIcon('users', size: 20, color: AppColors.fg1)),
              if (finished > 0) ...[
                Container(width: 1, height: 30, color: AppColors.border),
                _half('$finished finished today', AppColors.fg2, onFinished),
              ],
            ]),
          ),
        ),
      );
}

/// One item of the Needs you pager.
class AskCardData {
  const AskCardData(
      {required this.agentId,
      required this.name,
      required this.time,
      required this.text,
      required this.onTap});
  final String agentId, name, time, text;
  final VoidCallback onTap;
}

/// Needs you pager (HM-03): one amber-bordered card, a second peeking.
class AskPager extends StatefulWidget {
  const AskPager({super.key, required this.items});
  final List<AskCardData> items;

  @override
  State<AskPager> createState() => _AskPagerState();
}

class _AskPagerState extends State<AskPager> {
  int _i = 0;
  PageController? _c;
  double _vf = 1;

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  Widget _card(AskCardData a) => Semantics(
        button: true,
        label: '${a.name}, Needs you, ${a.text}',
        excludeSemantics: true,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: a.onTap,
          child: Container(
            key: const ValueKey('ask-card'),
            constraints: const BoxConstraints(minHeight: 82),
            decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: quietAmber, width: 1),
            ),
            child: Stack(children: [
              Positioned(
                  left: 0,
                  top: 4,
                  bottom: 4,
                  width: 2,
                  child: ColoredBox(color: quietAmber)),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
                child: Row(children: [
                  agentFace(a.agentId, 44),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(a.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: sans(15,
                                        weight: FontWeight.w500,
                                        color: AppColors.fg1))),
                            const SizedBox(width: 8),
                            Text(a.time,
                                style: sans(12, color: AppColors.fg3)),
                          ]),
                          Row(children: [
                            Container(
                                width: 6,
                                height: 6,
                                margin: const EdgeInsets.only(left: 1),
                                decoration: BoxDecoration(
                                    color: quietAmber,
                                    shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Text('Needs you',
                                style: sans(12,
                                    weight: FontWeight.w500,
                                    color: quietAmber)),
                          ]),
                          if (a.text.isNotEmpty)
                            Text(a.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: sans(13, color: AppColors.fg2)),
                        ]),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      );

  /// Tallest card: padding, name, Needs you line and the question measured.
  double _height(BuildContext context, List<AskCardData> items, double cardW) {
    final scaler = MediaQuery.textScalerOf(context);
    final textW = cardW - 2 - 10 - 44 - 10 - 16;
    var h = 82.0;
    for (final a in items) {
      final tp = TextPainter(
        text: TextSpan(text: a.text, style: sans(13)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 2,
      )..layout(maxWidth: textW);
      final head = TextPainter(
        text: TextSpan(text: 'Name', style: sans(15, weight: FontWeight.w500)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      final dotLine = TextPainter(
        text: TextSpan(text: 'Needs you', style: sans(12)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      final need = 22 + head.height + dotLine.height + (a.text.isEmpty ? 0 : tp.height);
      if (need > h) h = need;
    }
    return h;
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final many = items.length > 1;
    return LayoutBuilder(builder: (context, c) {
      // Card 361 at 393 with an 8 gap: the next card peeks into the right gutter.
      final viewport = c.maxWidth - kGutter;
      final page = viewport - kGutter + 8;
      final vf = many ? (page / viewport).clamp(0.5, 1.0) : 1.0;
      if (_c == null || _vf != vf) {
        _c?.dispose();
        _c = PageController(viewportFraction: vf, initialPage: _i);
        _vf = vf;
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (many)
          Padding(
            padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 6),
            child: Text('${_i + 1} of ${items.length}',
                textAlign: TextAlign.right,
                style: sans(12, color: AppColors.fg3)),
          ),
        Padding(
          padding: const EdgeInsets.only(left: kGutter),
          child: many
              ? SizedBox(
                  height: _height(context, items, page - 8),
                  child: PageView(
                    controller: _c!,
                    padEnds: false,
                    clipBehavior: Clip.none,
                    onPageChanged: (i) => setState(() => _i = i),
                    children: [
                      for (final a in items)
                        Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _card(a)),
                    ],
                  ))
              : _card(items.first),
        ),
        if (many)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ExcludeSemantics(
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < items.length; i++)
                  Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                          color: i == _i ? AppColors.fg1 : AppColors.fg3,
                          shape: BoxShape.circle)),
              ]),
            ),
          ),
      ]);
    });
  }
}

/// GroupGlyph re-export keeps callers off the chat import.
Widget groupGlyphFor(GroupSummary g, double size) =>
    GroupGlyph(size: size, ids: g.agentIds, count: g.members.length);


/// Pushed bar type B (SH-10): 48 x 48 back at x0, title 16/500 and optional
/// subtitle at x56, trailing 48 x 48 icon targets, hairline at the bottom.
class PushedBar extends StatelessWidget {
  const PushedBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions = const [],
    this.titleSize = 16,
  });
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final double titleSize;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border, width: 1))),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(children: [
            BarIcon('chevron-left', 'Back', onBack ?? () => Navigator.maybePop(context)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(titleSize,
                              weight: FontWeight.w500, color: AppColors.fg1)),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Text(subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: sans(12.5, color: AppColors.fg3)),
                    ]),
              ),
            ),
            ...actions,
            if (actions.isEmpty) const SizedBox(width: 8),
          ]),
        ),
      );
}

/// A 48 x 48 icon target with a 20 glyph.
class BarIcon extends StatelessWidget {
  const BarIcon(this.icon, this.label, this.onTap, {super.key, this.color});
  final String icon, label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                  child: AppIcon(icon, size: 20, color: color ?? AppColors.fg1))),
        ),
      );
}

/// Spec switch: 40 x 20 track, 14 knob, 48 x 48 hit area. On fill fg1, off surface3.
class SpecSwitch extends StatelessWidget {
  const SpecSwitch(
      {super.key, required this.value, required this.onChanged, this.label});
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) => Semantics(
        toggled: value,
        label: label,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Container(
                width: 40,
                height: 20,
                padding: const EdgeInsets.all(3),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                decoration: BoxDecoration(
                    color: value ? AppColors.fg1 : AppColors.surface3,
                    borderRadius: BorderRadius.circular(10)),
                child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                        color: value ? AppColors.bg : AppColors.fg3,
                        shape: BoxShape.circle)),
              ),
            ),
          ),
        ),
      );
}

/// A 48 high row: label left, trailing right, optional hairline.
class SwitchRow extends StatelessWidget {
  const SwitchRow(this.label, this.value, this.onChanged,
      {super.key, this.sub});
  final String label;
  final String? sub;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.only(left: kGutter, right: 4),
          child: Row(children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(label, style: sans(15, color: AppColors.fg1)),
                  if (sub != null)
                    Text(sub!, style: sans(12, color: AppColors.fg3)),
                ])),
            SpecSwitch(value: value, onChanged: onChanged, label: label),
          ]),
        ),
      );
}

/// Equal-width text tabs: 48 high, 14/500 selected, 2 high fg1 underline 14
/// in from each edge of the selected tab, hairline under the row.
class SpecTabs extends StatelessWidget {
  const SpecTabs(
      {super.key, required this.labels, required this.index, required this.onTap});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border, width: 1))),
        child: clampedScale(
          context,
          Row(children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: i == index,
                  label: '${labels[i]} tab, ${i + 1} of ${labels.length}',
                  excludeSemantics: true,
                  child: TapDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(i),
                    child: Container(
                      key: ValueKey('tab-$i'),
                      height: 48,
                      alignment: Alignment.center,
                      child: Stack(alignment: Alignment.center, fit: StackFit.expand, children: [
                        Center(child: Text(labels[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(14,
                                weight: i == index ? FontWeight.w500 : FontWeight.w400,
                                color: i == index ? AppColors.fg1 : AppColors.fg3))),
                        if (i == index)
                          Positioned(
                              left: 14,
                              right: 14,
                              bottom: 0,
                              height: 2,
                              child: ColoredBox(
                                  key: const ValueKey('tab-underline'),
                                  color: AppColors.fg1)),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      );
}
