import 'package:flutter/material.dart';

import '../api.dart';
import '../desktop_layout.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell_nav.dart';
import 'usage_desktop.dart';

String usageProviderTitle(String id) => switch (id.toLowerCase()) {
      'anthropic' => 'Anthropic',
      'claude-code' || 'claude_code' => 'Claude Code',
      'openai' => 'OpenAI',
      'chatgpt' => 'ChatGPT',
      'gemini' || 'google' => 'Gemini',
      'xai' || 'grok' => 'xAI',
      'openrouter' => 'OpenRouter',
      'antigravity' => 'Antigravity',
      'devin' => 'Devin',
      _ => id.isEmpty ? 'Provider' : id,
    };

String usageWindowTitle(RateWindow r) {
  final base = switch (r.windowMinutes) {
    300 => '5-hour window',
    180 => '3-hour window',
    60 => 'Hourly window',
    1440 => 'Daily window',
    10080 => 'Weekly window',
    43200 => 'Monthly window',
    _ => rateWindowLabel(r.windowMinutes),
  };
  return (r.label == null || r.label!.isEmpty) ? base : '${r.label} · $base';
}

class UsageScreen extends StatelessWidget {
  final DaemonClient client;
  final bool embedded;
  final VoidCallback? onBack;

  const UsageScreen({
    super.key,
    required this.client,
    this.embedded = false,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    // One view for both layouts: phone only narrows its columns.
    final content = UsageDesktopView(client: client);
    final body = embedded && !kMobile
        ? content
        : SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, S.s40),
            child: content);

    if (embedded) {
      if (onBack == null) return body;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (kMobile)
            SettingsHeader(title: 'Usage', compact: true, onBack: onBack!)
          else
            NavBackRow(title: 'Usage', onBack: onBack!),
          Expanded(child: body),
        ],
      );
    }
    return Scaffold(
      body: Column(children: [
        SnAppBar(
            title: 'Usage',
            compact: true,
            onBack: () => Navigator.pop(context)),
        Expanded(child: body),
      ]),
    );
  }
}

class UsageRateRow extends StatelessWidget {
  final RateWindow rate;
  const UsageRateRow({super.key, required this.rate});

  @override
  Widget build(BuildContext context) {
    final title = usageWindowTitle(rate);
    final reset = rateResetLabel(rate.resetsAt);
    final label = Text(title,
        maxLines: kMobile ? null : 1,
        overflow: kMobile ? null : TextOverflow.ellipsis,
        style: sans(12, color: AppColors.fg2));
    if (rate.isExpired) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: S.s4),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label,
              Text('Rolled over · awaiting the next report',
                  style: sans(11, color: AppColors.fg3)),
            ]),
      );
    }

    final used = rate.usedPercent.clamp(0, 100).toDouble();
    final color = used >= 85 ? AppColors.danger : AppColors.accent;

    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: S.of(3)),
      child: Row(children: [
          // Long plan names ("Pro plan · Daily window") need room on one line.
          SizedBox(width: kMobile ? 110 : 168, child: label),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(R.of(3)),
              child: SizedBox(
                height: 4,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: AppColors.tint3),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (used / 100).clamp(0.0, 1.0),
                      child: Container(color: color),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: S.s8),
          SizedBox(
            width: 40,
            child: Text(
              '${used.round()}%',
              textAlign: TextAlign.right,
              style: mono(12, color: AppColors.fg3),
            ),
          ),
        ]),
    );
    // The reset time stays one hover or long-press away.
    return reset == null ? row : Tooltip(message: reset, child: row);
  }
}
