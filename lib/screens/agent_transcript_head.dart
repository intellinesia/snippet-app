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
    this.stateIcon,
    this.stateText = '',
    this.model = '',
    this.provider,
    this.workspace = '',
    this.meta = '',
    this.actions = const [],
  });

  final String agentId;
  final String name;

  /// Group members; two or more draw a stacked cluster.
  final List<String>? agentIds;
  final String purpose;
  final Widget? stateIcon;
  final String stateText;
  final String model;
  final String? provider;
  final String workspace;
  final String meta;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final ids = agentIds ?? const <String>[];
    final avatar = ids.length > 1
        ? AgentCluster(ids: ids, size: 40)
        : ClipRRect(
            borderRadius: BorderRadius.circular(R.of(12)),
            child: AgentMochi(agentId, size: 40),
          );
    final fine = sans(12, color: AppColors.fg2);
    final hasLine2 = stateIcon != null ||
        stateText.isNotEmpty ||
        model.isNotEmpty ||
        workspace.isNotEmpty ||
        meta.isNotEmpty;
    final parts = <Widget>[
      if (stateText.isNotEmpty) Text(stateText, style: fine),
      if (model.isNotEmpty)
        Row(mainAxisSize: MainAxisSize.min, children: [
          ProviderLogo(provider ?? model, size: 12, color: AppColors.fg2),
          SizedBox(width: S.s4),
          Text(model, style: fine),
        ]),
      if (workspace.isNotEmpty) Text(workspace, style: fine),
      if (meta.isNotEmpty) Text(meta, style: fine),
    ];
    return Container(
      padding: EdgeInsets.fromLTRB(0, S.s8, 0, S.of(18)),
      margin: EdgeInsets.only(bottom: S.s4),
      decoration: BoxDecoration(
          border: Border(
              bottom:
                  BorderSide(color: AppColors.fg1.withValues(alpha: 0.06)))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        avatar,
        SizedBox(width: S.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      sans(20, weight: FontWeight.w500, color: AppColors.fg1)),
              if (purpose.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: S.s2),
                  child: Text(purpose,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, color: AppColors.fg3)),
                ),
              if (hasLine2)
                Padding(
                  padding: EdgeInsets.only(top: S.s4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (stateIcon != null) ...[
                        stateIcon!,
                        SizedBox(width: S.s6),
                      ],
                      Expanded(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 2,
                          children: [
                            for (var i = 0; i < parts.length; i++) ...[
                              if (i > 0) Text('\u00b7', style: fine),
                              parts[i],
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        for (var i = 0; i < actions.length; i++) ...[
          SizedBox(width: i > 0 ? S.s4 : S.s12),
          actions[i],
        ],
      ]),
    );
  }
}
