import 'package:flutter/material.dart';

import '../../chat/agent_cluster.dart';
import '../../mochi.dart';
import '../../models.dart';
import '../../quiet.dart';
import '../../tap_detector.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../../mobile_kit.dart';

/// Phone Agents Home and All agents building blocks (spec B, HM-02 to HM-04).
/// Every height is a minimum; text never sits in a fixed box.

const double kGutter = 20;

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

/// One segment of the connected filter group. Unselected segments share 8
/// inner corners with their neighbours; the selected one is a full pill in
/// the primary ink. A trailing number in [label] reads as a quieter count.
class StateChip extends StatelessWidget {
  const StateChip(this.label, this.selected, this.onTap,
      {super.key, this.amberDot = false, this.fill});
  final String label;
  final bool selected, amberDot;
  final VoidCallback onTap;
  final Color? fill;

  static final _count = RegExp(r'^(.*\S)\s+(\d+)$');

  @override
  Widget build(BuildContext context) {
    final pos = _ChipPos.of(context);
    const outer = Radius.circular(18);
    final inner = Radius.circular(kAndroidLook ? 6 : 8);
    final radius = selected
        ? const BorderRadius.all(outer)
        : BorderRadius.horizontal(
            left: pos.first ? outer : inner, right: pos.last ? outer : inner);
    final m = _count.firstMatch(label);
    final fg = selected ? MK.onPrimary : AppColors.fg2;
    return clampedScale(
      context,
      Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // 44 target around the 36 segment.
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minHeight: 36),
              padding: EdgeInsets.only(left: amberDot ? 10 : 14, right: 14),
              decoration: BoxDecoration(
                color: selected ? AppColors.fg1 : (fill ?? AppColors.surface2),
                borderRadius: radius,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (amberDot) ...[
                  Container(
                      key: const ValueKey('chip-amber-dot'),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          color: quietAmber, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                ],
                Text.rich(
                    TextSpan(children: [
                      TextSpan(text: m == null ? label : m.group(1)),
                      if (m != null)
                        TextSpan(
                            text: '  ${m.group(2)}',
                            style: sans(13.5,
                                weight: W.body,
                                color: selected
                                    ? MK.onPrimary.withValues(alpha: 0.6)
                                    : AppColors.fg4)),
                    ]),
                    maxLines: 1,
                    style: sans(13.5, weight: W.label, color: fg)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChipPos extends InheritedWidget {
  const _ChipPos(
      {required this.first, required this.last, required super.child});
  final bool first, last;
  static _ChipPos of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<_ChipPos>() ??
      const _ChipPos(first: true, last: true, child: SizedBox.shrink());
  @override
  bool updateShouldNotify(_ChipPos old) =>
      old.first != first || old.last != last;
}

/// The connected filter group: scrolls sideways, never wraps.
class ChipRow extends StatelessWidget {
  const ChipRow({super.key, required this.chips, this.gap});
  final List<Widget> chips;

  /// Ignored beyond the design's 2 (4 on Android); kept for callers.
  final double? gap;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: kGutter),
        child: Row(children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) SizedBox(width: kAndroidLook ? 4 : 2),
            _ChipPos(
                first: i == 0, last: i == chips.length - 1, child: chips[i]),
          ],
        ]),
      );
}

/// Section label: 13 fg3 at the gutter (14 medium fg2 on Android).
class HomeLabel extends StatelessWidget {
  const HomeLabel(this.text, {super.key, this.top = 22, this.trailing});
  final String text;
  final double top;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Padding(
          // A 48 tall trailing target eats into the padding so the label keeps its place.
          padding: EdgeInsets.fromLTRB(kAndroidLook ? 28 : kGutter,
              trailing == null ? top : (top - 15).clamp(0, top),
              kAndroidLook ? 28 : kGutter, trailing == null ? 6 : 0),
          child: Row(children: [
            Expanded(
                child: Text(text,
                    style: kAndroidLook
                        ? sans(14, weight: W.label, color: AppColors.fg2)
                        : sans(13, color: AppColors.fg3))),
            if (trailing != null) trailing!,
          ]),
        ),
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
                child: Text(label, style: sans(13, color: AppColors.fg2)),
              ),
            ),
          ),
        ),
      );
}

/// One agent as the Home grid shows it.
class AgentCardData {
  const AgentCardData(this.agent, this.status, this.line,
      {this.working = false});
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
        label: [data.agent.shortName, data.status, data.line]
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
              Text(data.agent.shortName,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style:
                      sans(14, weight: FontWeight.w500, color: AppColors.fg1)),
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

/// Agents as a sideways row of working tiles.
class AgentGrid extends StatelessWidget {
  const AgentGrid({super.key, required this.cards, required this.onOpen});
  final List<AgentCardData> cards;
  final void Function(CoordinationAgent a) onOpen;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              MkWorkingTile(
                avatar: AgentMochi(cards[i].agent.id, size: 44),
                name: cards[i].agent.shortName,
                subtitle:
                    cards[i].line.isNotEmpty ? cards[i].line : cards[i].status,
                working: cards[i].working,
                needsYou: cards[i].status == 'Needs you',
                onTap: () => onOpen(cards[i].agent),
              ),
            ],
          ]),
        ),
      );
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
    this.markSize = 40,
    this.subStyleSize = 13.5,
    this.hairline = true,
    this.subColor,
    this.minHeight = 60,
    this.gap = 12,
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
      label: [
        title,
        if (sub != null) sub!,
        if (sub2 != null) sub2!,
        if (time != null) time!
      ].join(', '),
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
                                  style: mkRowTitle())),
                          if (time != null && inline) ...[
                            const SizedBox(width: 8),
                            Text(time!, style: mkTime()),
                          ],
                        ]),
                        if (time != null && !inline)
                          Text(time!, style: mkTime()),
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
                height: 0.5,
                child: ColoredBox(color: MK.hairline)),
        ]),
      ),
    );
  }
}

Widget agentFace(String id, double size) =>
    ClipOval(child: AgentMochi(id, size: size));

/// Group mark: a surface2 disc with the people glyph, no outline.
Widget groupMark(double size, {double radius = 10.1}) => Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        shape: BoxShape.circle,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
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
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
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

/// One item of the Needs you list.
class AskCardData {
  const AskCardData(
      {required this.agentId,
      required this.name,
      required this.time,
      required this.text,
      required this.onTap,
      this.primary,
      this.secondary,
      this.onPrimary,
      this.onSecondary});
  final String agentId, name, time, text;
  final VoidCallback onTap;

  /// Answer pills; without them the card offers one Open pill.
  final String? primary, secondary;
  final VoidCallback? onPrimary, onSecondary;
}

/// Needs you: each ask as prose with its two answers, one under another.
/// Asks are never folded away.
class AskPager extends StatelessWidget {
  const AskPager({super.key, required this.items});
  final List<AskCardData> items;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            KeyedSubtree(
              key: ValueKey(i == 0 ? 'ask-card' : 'ask-card-$i'),
              child: MkAskCard(
                avatar: AgentMochi(items[i].agentId, size: 28),
                who: items[i].name,
                time: items[i].time,
                question:
                    items[i].text.isEmpty ? 'Waiting on you' : items[i].text,
                primary: items[i].primary ?? 'Open',
                secondary: items[i].secondary,
                onPrimary: items[i].onPrimary ?? items[i].onTap,
                onSecondary: items[i].onSecondary,
                onOpen: items[i].onTap,
              ),
            ),
          ],
        ]),
      );
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
        // The kit bar: no rule on Android, a hairline on iPhone.
        decoration: BoxDecoration(
            border: kAndroidLook
                ? null
                : Border(
                    bottom: BorderSide(color: AppColors.border, width: 0.5))),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: kAndroidLook ? 64 : 52),
          child: Row(children: [
            BarIcon(kAndroidLook ? 'arrow-left' : 'chevron-left', 'Back',
                onBack ?? () => Navigator.maybePop(context)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(
                              kAndroidLook &&
                                      (subtitle == null || subtitle!.isEmpty)
                                  ? 22
                                  : titleSize + (kAndroidLook ? 2 : 0),
                              weight: kAndroidLook ? W.label : FontWeight.w500,
                              color: AppColors.fg1)),
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
                  child:
                      AppIcon(icon, size: 20, color: color ?? AppColors.fg1))),
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
      {super.key,
      required this.labels,
      required this.index,
      required this.onTap});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            border:
                Border(bottom: BorderSide(color: AppColors.border, width: 1))),
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
                      child: Stack(
                          alignment: Alignment.center,
                          fit: StackFit.expand,
                          children: [
                            Center(
                                child: Text(labels[i],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: sans(14,
                                        weight: i == index
                                            ? FontWeight.w500
                                            : FontWeight.w400,
                                        color: i == index
                                            ? AppColors.fg1
                                            : AppColors.fg3))),
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
