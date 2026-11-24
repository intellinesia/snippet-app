import 'package:flutter/material.dart';

import '../platform.dart';
import '../theme.dart';
import '../widgets.dart' show AppIcon;
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
    this.suggestions = const [],
    this.onSuggest,
  });

  final List<String> ids;
  final String name;
  final String purpose;
  final String note;

  /// Phone: rows that drop a starter into the composer as a draft.
  final List<String> suggestions;
  final ValueChanged<String>? onSuggest;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    if (kMobile) return _phone();
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

  Widget _phone() => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 56),
          ids.length > 1
              ? AgentCluster(ids: ids, size: 64)
              : AgentMochi(ids.isEmpty ? '' : ids.first, size: 64),
          const SizedBox(height: 14),
          Text(name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: sans(20, weight: FontWeight.w500, color: AppColors.fg1)),
          if (purpose.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(purpose,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: sans(14, height: 1.45, color: AppColors.fg3)),
            ),
          ],
          const SizedBox(height: 24),
          for (final text in suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Semantics(
                button: true,
                label: text,
                excludeSemantics: true,
                child: Material(
                  color: AppColors.surface1,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onSuggest == null ? null : () => onSuggest!(text),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        child: Row(children: [
                          AppIcon('sparkles', size: 20, color: AppColors.fg3),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(text,
                                style: sans(14, color: AppColors.fg2)),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (suggestions.isEmpty)
            Text(note,
                textAlign: TextAlign.center,
                style: sans(12.5, color: AppColors.fg3)),
        ]),
      );
}
