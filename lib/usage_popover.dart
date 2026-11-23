import 'package:flutter/material.dart';

import 'api.dart';
import 'models.dart';
import 'screens/usage.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> showUsagePopover(BuildContext anchor, DaemonClient client) =>
    showAnchoredPanel<void>(
      anchor,
      width: 340,
      maxHeight: 440,
      above: true,
      child: _UsagePopover(client: client),
    );

class _UsagePopover extends StatefulWidget {
  const _UsagePopover({required this.client});

  final DaemonClient client;

  @override
  State<_UsagePopover> createState() => _UsagePopoverState();
}

class _UsagePopoverState extends State<_UsagePopover> {
  late final Future<UsageSummary> _usage = widget.client.getUsage();

  @override
  Widget build(BuildContext context) => FutureBuilder<UsageSummary>(
        future: _usage,
        builder: (context, snap) {
          final Widget body;
          if (snap.connectionState != ConnectionState.done) {
            body = Padding(
              padding: EdgeInsets.symmetric(vertical: S.of(22)),
              child: Center(child: Spinner(size: 14)),
            );
          } else if (snap.hasError) {
            body = _note('Could not load usage.');
          } else {
            final rows = <Widget>[];
            final seen = <String>{};
            for (final p in snap.data!.providers) {
              final live = p.rateLimits.where((r) => !r.isExpired).toList();
              if (live.isEmpty || !seen.add(p.provider)) continue;
              rows.add(_provider(p.provider, live));
            }
            body = rows.isEmpty
                ? _note('No rate limits reported yet.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: rows);
          }
          return Padding(
            padding: EdgeInsets.fromLTRB(S.s6, S.s4, S.s6, S.s6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(0, S.s2, 0, S.s8),
                  child: Text('Usage',
                      style: sans(12, color: AppColors.fg4, spacing: 0.4)),
                ),
                body,
              ],
            ),
          );
        },
      );

  Widget _note(String text) => Padding(
        padding: EdgeInsets.symmetric(vertical: S.of(10)),
        child: Text(text, style: sans(13, color: AppColors.fg4)),
      );

  Widget _provider(String id, List<RateWindow> windows) => Padding(
        padding: EdgeInsets.only(bottom: S.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(usageProviderTitle(id),
                style: sans(13, color: AppColors.fg1, weight: W.label)),
            SizedBox(height: S.s6),
            for (final r in windows) _window(r),
          ],
        ),
      );

  Widget _window(RateWindow r) {
    final used = (r.usedPercent.clamp(0, 100)) / 100;
    final color = r.leftPercent < 20 ? AppColors.danger : AppColors.accent;
    final reset = rateResetLabel(r.resetsAt);
    return Padding(
      padding: EdgeInsets.only(bottom: S.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(usageWindowTitle(r),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, color: AppColors.fg3)),
            ),
            Text('${r.usedPercent.round()}% used',
                style: sans(11, color: AppColors.fg3)),
          ]),
          SizedBox(height: S.of(5)),
          ClipRRect(
            borderRadius: BorderRadius.circular(R.of(2)),
            child: SizedBox(
              height: 4,
              child: Stack(children: [
                ColoredBox(
                    color: AppColors.line, child: const SizedBox.expand()),
                FractionallySizedBox(
                  widthFactor: used.toDouble(),
                  child: ColoredBox(color: color, child: const SizedBox.expand()),
                ),
              ]),
            ),
          ),
          if (reset != null) ...[
            SizedBox(height: S.s4),
            Text(reset, style: sans(11, color: AppColors.fg4)),
          ],
        ],
      ),
    );
  }
}
