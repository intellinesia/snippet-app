import 'package:flutter/material.dart';

import '../theme.dart';
import 'agent_cluster.dart';
import '../mochi.dart';

/// Desktop empty chat: who you are talking to, centred in the pane.
class ChatEmptyIntro extends StatelessWidget {
  const ChatEmptyIntro({
    super.key,
    required this.ids,
    required this.name,
    this.purpose = '',
    required this.note,
  });

  final List<String> ids;
  final String name;
  final String purpose;
  final String note;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ids.length > 1
                ? AgentCluster(ids: ids, size: 56)
                : AgentMochi(ids.isEmpty ? '' : ids.first, size: 56),
            const SizedBox(height: 12),
            Text(name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(17, weight: FontWeight.w500, color: AppColors.fg1)),
            if (purpose.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(purpose,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, height: 1.5, color: AppColors.fg3)),
            ],
            const SizedBox(height: 10),
            Text(note,
                textAlign: TextAlign.center,
                style: sans(12.5, color: AppColors.fg4)),
          ]),
        ),
      ),
    );
  }
}
