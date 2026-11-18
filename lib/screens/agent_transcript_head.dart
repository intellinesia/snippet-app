import 'package:flutter/material.dart';

import '../mochi.dart';
import '../theme.dart';
import '../widgets.dart';

/// Desktop: an agent's identity at the top of its transcript, shared by the
/// agent thread and the Mission Control tab.
class AgentTranscriptHead extends StatelessWidget {
  const AgentTranscriptHead({
    super.key,
    required this.agentId,
    required this.name,
    this.purpose = '',
    this.model = '',
    this.provider,
    this.meta = '',
    this.actions = const [],
  });

  final String agentId;
  final String name;
  final String purpose;
  final String model;
  final String? provider;
  final String meta;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(0, S.s12, 0, S.of(18)),
      margin: EdgeInsets.only(bottom: S.s4),
      decoration: BoxDecoration(
          border: Border(
              bottom:
                  BorderSide(color: AppColors.fg1.withValues(alpha: 0.07)))),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(R.of(12)),
          child: AgentMochi(agentId, size: 52),
        ),
        SizedBox(width: S.of(14)),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(18,
                        weight: FontWeight.w600, color: AppColors.fg1)),
                if (purpose.isNotEmpty)
                  Text(purpose,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, color: AppColors.fg3)),
                if (model.isNotEmpty || meta.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: S.s4),
                    child: Row(children: [
                      if (model.isNotEmpty) ...[
                        ProviderLogo(provider,
                            size: 12,
                            color: providerLogoIsColour(provider)
                                ? null
                                : AppColors.fg3),
                        SizedBox(width: S.s4),
                        Flexible(
                          child: Text(model,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(11.5, color: AppColors.fg4)),
                        ),
                      ],
                      if (model.isNotEmpty && meta.isNotEmpty)
                        SizedBox(width: S.of(10)),
                      if (meta.isNotEmpty)
                        Text(meta, style: sans(11.5, color: AppColors.fg4)),
                    ]),
                  ),
              ]),
        ),
        if (actions.isNotEmpty) SizedBox(width: S.s12),
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) SizedBox(width: S.s4),
          actions[i],
        ],
      ]),
    );
  }
}
