import 'package:flutter/material.dart';

import '../api.dart';
import '../desktop_layout.dart';
import '../models.dart';
import '../platform.dart';
import '../settings_form.dart';
import '../swr.dart';
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

class UsageScreen extends StatefulWidget {
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
  State<UsageScreen> createState() => _UsageScreenState();
}

enum _Period { day, week, month, all }

extension on _Period {
  String get label => switch (this) {
        _Period.day => 'Today',
        _Period.week => '7 days',
        _Period.month => '30 days',
        _Period.all => 'All time',
      };

  DateTime? get since {
    final now = DateTime.now();
    return switch (this) {
      _Period.day => DateTime(now.year, now.month, now.day),
      _Period.week => now.subtract(const Duration(days: 7)),
      _Period.month => now.subtract(const Duration(days: 30)),
      _Period.all => null,
    };
  }
}

class _UsageScreenState extends State<UsageScreen> {
  // Desktop loads its own series; only the phone layout reads this.
  late Swr<UsageSummary>? _usageSwr = kMobile ? _watch() : null;
  Swr<UsageSummary> get _usage => _usageSwr!;
  _Period _period = _Period.all;

  Swr<UsageSummary> _watch() => Swr<UsageSummary>(
        client: widget.client,
        key: 'usage:${_period.name}',
        fetch: () => widget.client.getUsage(since: _period.since),
        revalidateOn: (e) =>
            const {'idle', 'done', 'error'}.contains(e['kind']),
        onChange: () {
          if (mounted) setState(() {});
        },
        debounce: const Duration(seconds: 2),
      );

  @override
  void dispose() {
    _usageSwr?.dispose();
    super.dispose();
  }

  void _refresh() => _usage.refresh();

  void _setPeriod(_Period period) {
    if (period == _period) return;
    setState(() {
      _period = period;
      _usage.dispose();
      _usageSwr = _watch();
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final data = kMobile ? _usage.data : null;
    final Widget content;
    if (!kMobile) {
      content = UsageDesktopView(client: widget.client);
    } else if (data == null && _usage.error == null) {
      content = kMobile
          ? Padding(
              padding: EdgeInsets.symmetric(vertical: S.of(48)),
              child: const Center(child: Spinner(size: 18)),
            )
          : const SettingsGroup(children: [SettingsRow(label: 'Loading usage…')]);
    } else if (data == null) {
      content = kMobile
          ? Padding(
              padding: EdgeInsets.symmetric(vertical: S.s24),
              child: Column(children: [
                Text('Unable to load usage',
                    style: sans(13, color: AppColors.fg1)),
                SizedBox(height: S.s6),
                Text('${_usage.error}',
                    textAlign: TextAlign.center,
                    style: mono(11, color: AppColors.fg3)),
                SizedBox(height: S.of(10)),
                Btn('Retry', small: true, onTap: _refresh),
              ]),
            )
          : SettingsGroup(children: [
              SettingsRow(
                label: 'Unable to load usage',
                sub: '${_usage.error}',
                danger: true,
                trailing: Btn('Retry',
                    small: true,
                    variant: BtnVariant.secondary,
                    onTap: _refresh),
              ),
            ]);
    } else if (data.providers.isEmpty) {
      content = kMobile
          ? Padding(
              padding: EdgeInsets.symmetric(vertical: S.s32),
              child: Text('No model calls in this period.',
                  textAlign: TextAlign.center, style: TS.meta()),
            )
          : const SettingsGroup(children: [
              SettingsRow(label: 'No model calls in this period.')
            ]);
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final p in data.providers) _ProviderSection(provider: p),
        ],
      );
    }

    final Widget body;
    if (kMobile) {
      body = ListView(
        padding: EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, S.s40),
        children: [
          _PeriodTabs(value: _period, onChanged: _setPeriod),
          SizedBox(height: S.of(18)),
          AnimatedSwitcher(
            duration: Motion.quick,
            child: KeyedSubtree(
              key: ValueKey(data == null
                  ? (_usage.error == null ? 'loading' : 'error')
                  : 'data:${_period.name}'),
              child: content,
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(S.s4, S.s2, S.s4, 0),
            child: Text(
              'Every model call is recorded against the provider and model that served it. Input includes cached tokens; rate limits come from each provider\'s own reports.',
              style: sans(13, height: 1.5, color: AppColors.fg4),
            ),
          ),
        ],
      );
    } else {
      final column = content;
      body = widget.embedded
          ? column
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(S.s16, S.s4, S.s16, S.s40),
              child: column);
    }

    if (widget.embedded) {
      if (widget.onBack == null) return body;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (kMobile)
            SettingsHeader(
                title: 'Usage', compact: true, onBack: widget.onBack!)
          else
            NavBackRow(title: 'Usage', onBack: widget.onBack!),
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

class _ProviderSection extends StatelessWidget {
  final UsageProvider provider;
  const _ProviderSection({required this.provider});

  @override
  Widget build(BuildContext context) {
    final hasTokens = provider.totalTokens > 0;
    final sessions =
        '${provider.sessions} session${provider.sessions == 1 ? '' : 's'}';
    final calls = '${provider.calls} call${provider.calls == 1 ? '' : 's'}';
    final models = provider.models.where((m) => m.model.isNotEmpty).toList();
    final radius = BorderRadius.circular(kMobile ? R.lg : R.card);

    return Container(
      margin: EdgeInsets.only(bottom: kMobile ? S.s12 : S.s12),
      padding: EdgeInsets.fromLTRB(S.s12, S.of(10), S.s12, S.s12),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: radius,
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(usageProviderTitle(provider.provider),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(14, weight: FontWeight.w500, color: AppColors.fg1)),
            ),
            if (hasTokens)
              Text(fmtSi(provider.totalTokens),
                  style: mono(13, color: AppColors.fg1)),
          ]),
          Padding(
            padding: EdgeInsets.only(top: S.s2, bottom: S.s6),
            child: Text(
              provider.model.isNotEmpty && models.isEmpty
                  ? '$sessions · $calls · ${provider.model}'
                  : '$sessions · $calls',
              style: sans(12, color: AppColors.fg3, tabular: true),
            ),
          ),
          if (provider.rateLimits.isNotEmpty)
            for (final r in provider.rateLimits) UsageRateRow(rate: r)
          else
            Text(
              switch (provider.rateLimitsSupported) {
                true => 'No rate-limit data yet',
                false => 'This provider does not report rate limits',
                null => 'Rate limits appear after the next turn',
              },
              style: sans(12, color: AppColors.fg3),
            ),
          // One quiet line instead of a metric grid; the total is in the header.
          if (provider.promptTokens + provider.completionTokens > 0)
            Padding(
              padding: EdgeInsets.only(top: S.s6),
              child: Text(
                'Input ${fmtSi(provider.promptTokens)} · cached '
                '${fmtSi(provider.cacheReadTokens)} · output '
                '${fmtSi(provider.completionTokens)}',
                style: sans(12, color: AppColors.fg4, tabular: true),
              ),
            ),
          for (final m in models)
            Padding(
              padding: EdgeInsets.only(top: S.s8),
              child: Row(children: [
                Expanded(
                  child: Text(m.model,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(12, color: AppColors.fg2)),
                ),
                Text('${fmtSi(m.totalTokens)} · ${m.calls}×',
                    style: mono(12, color: AppColors.fg4)),
              ]),
            ),
        ],
      ),
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
    final label = Text(title, style: sans(12, color: AppColors.fg2));
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
          SizedBox(width: 110, child: label),
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

class _PeriodTabs extends StatelessWidget {
  final _Period value;
  final ValueChanged<_Period> onChanged;
  const _PeriodTabs({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (kMobile) {
      return Container(
        padding: EdgeInsets.all(S.of(3)),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(R.of(11)),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(children: [
          for (final p in _Period.values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(p),
                child: AnimatedContainer(
                  duration: Motion.quick,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p == value ? AppColors.surface3 : Colors.transparent,
                    borderRadius: BorderRadius.circular(R.md),
                  ),
                  child: Text(
                    p.label,
                    style: sans(
                      13,
                      weight:
                          p == value ? FontWeight.w500 : FontWeight.w400,
                      color: p == value ? AppColors.fg1 : AppColors.fg3,
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );
    }
    return Container(
      padding: EdgeInsets.all(S.s2),
      decoration: BoxDecoration(
        color: AppColors.tint1,
        borderRadius: BorderRadius.circular(R.of(9)),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final p in _Period.values)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(p),
              child: AnimatedContainer(
                duration: Motion.quick,
                height: 26,
                padding: EdgeInsets.symmetric(horizontal: S.of(10)),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p == value ? AppColors.tint2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(R.of(7)),
                ),
                child: Text(
                  p.label,
                  style: sans(
                    12,
                    weight: p == value ? FontWeight.w500 : FontWeight.w400,
                    color: p == value ? AppColors.fg1 : AppColors.fg3,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
