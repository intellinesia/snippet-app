import 'package:flutter/material.dart';

import '../chat/agent_cluster.dart';
import '../mochi.dart';
import '../theme.dart';
import '../widgets.dart';

/// Desktop: a chat's identity at the start of its history, shared by agent
/// threads, group threads and the Lead tab. It scrolls away.
class AgentTranscriptHead extends StatelessWidget {
  const AgentTranscriptHead({
    super.key,
    required this.agentId,
    required this.name,
    this.agentIds,
    this.purpose = '',
    this.model = '',
    this.provider,
    this.meta = '',
    this.actions = const [],
  });

  final String agentId;
  final String name;

  /// Group members; two or more draw a stacked cluster.
  final List<String>? agentIds;
  final String purpose;
  final String model;
  final String? provider;
  final String meta;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final ids = agentIds ?? const <String>[];
    final avatar = ids.length > 1
        ? AgentCluster(ids: ids, size: 48)
        : ClipRRect(
            borderRadius: BorderRadius.circular(R.of(12)),
            child: AgentMochi(agentId, size: 48),
          );
    final fine = sans(12, color: AppColors.fg4);
    return Container(
      padding: EdgeInsets.fromLTRB(0, S.s8, 0, S.of(18)),
      margin: EdgeInsets.only(bottom: S.s4),
      decoration: BoxDecoration(
          border: Border(
              bottom:
                  BorderSide(color: AppColors.fg1.withValues(alpha: 0.06)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            avatar,
            const Spacer(),
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) SizedBox(width: S.s4),
              actions[i],
            ],
          ]),
          SizedBox(height: S.s12),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(20, weight: FontWeight.w500, color: AppColors.fg1)),
          if (purpose.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: S.s2),
              child: Text(purpose,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, color: AppColors.fg3)),
            ),
          if (model.isNotEmpty || meta.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: S.s4),
              child: Row(children: [
                if (model.isNotEmpty) ...[
                  ProviderLogo(provider,
                      size: 12, color: AppColors.fg3),
                  SizedBox(width: S.s4),
                  Flexible(
                    child: Text(model,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: fine),
                  ),
                ],
                if (model.isNotEmpty && meta.isNotEmpty)
                  Text(' · ', style: fine),
                if (meta.isNotEmpty) Text(meta, style: fine),
              ]),
            ),
        ],
      ),
    );
  }
}
