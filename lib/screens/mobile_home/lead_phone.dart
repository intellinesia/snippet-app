import 'package:flutter/material.dart';

import '../../tap_detector.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'agents_home.dart';

/// Home card for Lead (HM-09): 72 high minimum, avatar 40, name, count, chevron.
class LeadHomeCard extends StatelessWidget {
  const LeadHomeCard({super.key, required this.running, required this.onTap});
  final int running;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final line = '$running ${running == 1 ? 'delegation' : 'delegations'} running';
    return Padding(
      padding: const EdgeInsets.fromLTRB(kGutter, 16, kGutter, 0),
      child: Semantics(
        button: true,
        label: 'Lead, $line',
        excludeSemantics: true,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            key: const ValueKey('lead-card'),
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border, width: 1)),
            child: Row(children: [
              agentFace('lead', 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Lead',
                          style: sans(15, weight: FontWeight.w500, color: AppColors.fg1)),
                      Text(line, style: sans(13, color: AppColors.fg3)),
                    ]),
              ),
              AppIcon('chevron-right', size: 16, color: AppColors.fg3),
            ]),
          ),
        ),
      ),
    );
  }
}

class Delegation {
  const Delegation(this.agentId, this.name, this.task, this.state);
  final String agentId, name, task, state;
}

/// Delegations card (HM-09): header, then rows with avatar 28, name, task and
/// a state word. State is text, never colour.
class DelegationsCard extends StatelessWidget {
  const DelegationsCard({super.key, required this.items});
  final List<Delegation> items;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: kGutter),
        child: Container(
          key: const ValueKey('delegations'),
          decoration: BoxDecoration(
              color: AppColors.surface1, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Text('Delegations  ${items.length}',
                  style: sans(12, weight: FontWeight.w500, color: AppColors.fg2)),
            ),
            for (final d in items)
              Container(
                key: ValueKey('delegation-${d.agentId}'),
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Row(children: [
                  agentFace(d.agentId, 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(14, weight: FontWeight.w500, color: AppColors.fg1)),
                          Text(d.task,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(12, color: AppColors.fg3)),
                        ]),
                  ),
                  const SizedBox(width: 8),
                  Text(d.state, style: sans(12, color: AppColors.fg2)),
                ]),
              ),
            const SizedBox(height: 6),
          ]),
        ),
      );
}

/// "Heard" line under a user bubble: icon 16 fg3 and a quoted 12/400 line.
class HeardLine extends StatelessWidget {
  const HeardLine(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(17, 4, kGutter, 4),
        child: Row(children: [
          AppIcon('mic', size: 16, color: AppColors.fg3),
          const SizedBox(width: 6),
          Expanded(
              child: Text('Heard: "$text"',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, color: AppColors.fg3))),
        ]),
      );
}

/// Right-aligned user bubble, max 0.69 of the content width.
class LeadUserBubble extends StatelessWidget {
  const LeadUserBubble(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: kGutter),
        child: LayoutBuilder(
          builder: (context, c) => Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: c.maxWidth * 0.69),
              child: Container(
                key: const ValueKey('lead-user-bubble'),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(14)),
                child: Text(text, style: sans(15, color: AppColors.fg1)),
              ),
            ),
          ),
        ),
      );
}

/// Lead reply: avatar 24 and name, then the text at the gutter, no bubble.
class LeadReply extends StatelessWidget {
  const LeadReply(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: kGutter),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            agentFace('lead', 24),
            const SizedBox(width: 8),
            Text('Lead', style: sans(13, weight: FontWeight.w500, color: AppColors.fg1)),
          ]),
          const SizedBox(height: 6),
          SizedBox(
              width: double.infinity,
              child: Text(text, style: sans(15, color: AppColors.fg1))),
        ]),
      );
}
