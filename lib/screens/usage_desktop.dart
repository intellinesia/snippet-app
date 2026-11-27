import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../settings_form.dart';
import '../swr.dart';
import '../theme.dart';
import '../widgets.dart';
import 'usage.dart';

enum _Range { day, week, month, all }

enum _Split { total, providers, models }

extension on _Range {
  String get label => switch (this) {
        _Range.day => '24h',
        _Range.week => '7d',
        _Range.month => '30d',
        _Range.all => 'All time',
      };

  /// Bucket starts, oldest first; each bucket runs to the next start or now.
  List<DateTime> get starts {
    final now = DateTime.now();
    switch (this) {
      case _Range.day:
        final hour = DateTime(now.year, now.month, now.day, now.hour);
        return [for (var i = 23; i >= 0; i--) hour.subtract(Duration(hours: i))];
      case _Range.week:
      case _Range.month:
        final n = this == _Range.week ? 7 : 30;
        final today = DateTime(now.year, now.month, now.day);
        return [for (var i = n - 1; i >= 0; i--) DateTime(today.year, today.month, today.day - i)];
      case _Range.all:
        final today = DateTime(now.year, now.month, now.day);
        final monday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
        return [for (var i = 11; i >= 0; i--) DateTime(monday.year, monday.month, monday.day - 7 * i)];
    }
  }
}

class _Bucket {
  final DateTime start;
  final Map<String, int> providers;
  final Map<String, int> models;
  _Bucket(this.start, this.providers, this.models);
  int get total => providers.values.fold(0, (a, b) => a + b);
}

class _Series {
  final UsageSummary summary;
  final List<_Bucket> buckets;
  _Series(this.summary, this.buckets);
}

Map<String, int> _byProvider(UsageSummary s) {
  final out = <String, int>{};
  for (final p in s.providers) {
    out.update(usageProviderTitle(p.provider), (v) => v + p.totalTokens, ifAbsent: () => p.totalTokens);
  }
  return out;
}

Map<String, int> _byModel(UsageSummary s) {
  final out = <String, int>{};
  for (final p in s.providers) {
    final named = p.models.where((m) => m.model.isNotEmpty).toList();
    if (named.isEmpty) {
      final k = p.model.isNotEmpty ? p.model : usageProviderTitle(p.provider);
      out.update(k, (v) => v + p.totalTokens, ifAbsent: () => p.totalTokens);
    }
    for (final m in named) {
      out.update(m.model, (v) => v + m.totalTokens, ifAbsent: () => m.totalTokens);
    }
  }
  return out;
}

Map<String, int> _minus(Map<String, int> a, Map<String, int> b) => {
      for (final e in a.entries) e.key: math.max(0, e.value - (b[e.key] ?? 0)),
    };

/// The daemon only filters by `since`, so per-bucket totals are differences
/// of cumulative totals taken at each bucket start.
Future<_Series> _loadSeries(DaemonClient client, _Range range) async {
  final starts = range.starts;
  final cumulative = List<UsageSummary?>.filled(starts.length, null);
  const batch = 6;
  for (var i = 0; i < starts.length; i += batch) {
    final end = math.min(i + batch, starts.length);
    final got = await Future.wait([
      for (var j = i; j < end; j++) client.getUsage(since: starts[j]),
    ]);
    for (var j = i; j < end; j++) {
      cumulative[j] = got[j - i];
    }
  }
  final summary = range == _Range.all ? await client.getUsage() : cumulative.first!;
  final buckets = <_Bucket>[];
  for (var i = 0; i < starts.length; i++) {
    final here = cumulative[i]!;
    final next = i + 1 < starts.length ? cumulative[i + 1]! : null;
    final p = _byProvider(here);
    final m = _byModel(here);
    buckets.add(_Bucket(
      starts[i],
      next == null ? p : _minus(p, _byProvider(next)),
      next == null ? m : _minus(m, _byModel(next)),
    ));
  }
  return _Series(summary, buckets);
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _day(DateTime d) => '${d.day} ${_months[d.month - 1]}';
String _hour(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:00';

List<Color> get _palette => [
      AppColors.accent,
      AppColors.ok,
      AppColors.run,
      AppColors.danger,
      Color.lerp(AppColors.accent, AppColors.fg3, 0.55)!,
      AppColors.fg4,
    ];

/// Desktop usage: range chips, a token chart, rate limits and a breakdown.
class UsageDesktopView extends StatefulWidget {
  final DaemonClient client;
  const UsageDesktopView({super.key, required this.client});

  @override
  State<UsageDesktopView> createState() => _UsageDesktopViewState();
}

class _UsageDesktopViewState extends State<UsageDesktopView> {
  _Range _range = _Range.week;
  _Split _split = _Split.total;
  late Swr<_Series> _series = _watch();

  Swr<_Series> _watch() => Swr<_Series>(
        client: widget.client,
        key: 'usage-desktop:${_range.name}',
        fetch: () => _loadSeries(widget.client, _range),
        revalidateOn: (e) => const {'idle', 'done'}.contains(e['kind']),
        onChange: () {
          if (mounted) setState(() {});
        },
        dedupe: const Duration(seconds: 30),
        debounce: const Duration(seconds: 10),
      );

  @override
  void dispose() {
    _series.dispose();
    super.dispose();
  }

  void _setRange(_Range r) {
    if (r == _range) return;
    setState(() {
      _range = r;
      _series.dispose();
      _series = _watch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = _series.data;
    final children = <Widget>[
      Row(children: [
        for (final r in _Range.values) ...[
          _Chip(label: r.label, selected: r == _range, onTap: () => _setRange(r)),
          SizedBox(width: S.s6),
        ],
        const Spacer(),
        if (_series.entry.validating) const Spinner(size: 12),
      ]),
      SizedBox(height: S.s12),
    ];
    if (data == null && _series.error != null) {
      children.add(SettingsGroup(children: [
        SettingsRow(
          label: 'Unable to load usage',
          sub: '${_series.error}',
          danger: true,
          trailing: Btn('Retry',
              small: true,
              variant: BtnVariant.secondary,
              onTap: () => _series.refresh()),
        ),
      ]));
    } else if (data == null) {
      children.add(const SettingsGroup(children: [SettingsRow(label: 'Loading usage…')]));
    } else {
      children.add(_ChartCard(
        range: _range,
        split: _split,
        onSplit: (s) => setState(() => _split = s),
        series: data,
      ));
      final limited = data.summary.providers.where((p) => p.rateLimits.isNotEmpty).toList();
      if (limited.isNotEmpty) {
        children
          ..add(SizedBox(height: S.s16))
          ..add(_RateCard(providers: limited));
      }
      children
        ..add(SizedBox(height: S.s16))
        ..add(_Breakdown(summary: data.summary));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: Motion.quick,
            height: 28,
            padding: EdgeInsets.symmetric(horizontal: S.of(10)),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.surface3 : AppColors.surface2,
              borderRadius: BorderRadius.circular(R.of(7)),
            ),
            child: Text(label,
                style: sans(12,
                    weight: selected ? FontWeight.w500 : FontWeight.w400,
                    color: selected ? AppColors.fg1 : AppColors.fg3)),
          ),
        ),
      );
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  const _Card({required this.child, this.padding});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding ?? EdgeInsets.all(S.s16),
        decoration: BoxDecoration(
          color: kMobile ? AppColors.surface1 : Grouped.row,
          borderRadius:
              BorderRadius.circular(kMobile ? R.lg : Grouped.radiusEnd),
        ),
        child: child,
      );
}

class _ChartCard extends StatefulWidget {
  final _Range range;
  final _Split split;
  final ValueChanged<_Split> onSplit;
  final _Series series;
  const _ChartCard({required this.range, required this.split, required this.onSplit, required this.series});

  @override
  State<_ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<_ChartCard> {
  int? _hover;

  @override
  void didUpdateWidget(covariant _ChartCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.range != widget.range) _hover = null;
  }

  String _bucketLabel(DateTime d) => switch (widget.range) {
        _Range.day => _hour(d),
        _Range.all => 'Week of ${_day(d)}',
        _ => _day(d),
      };

  @override
  Widget build(BuildContext context) {
    final buckets = widget.series.buckets;
    final keys = <String>[];
    final colours = <String, Color>{};
    if (widget.split != _Split.total) {
      final sums = <String, int>{};
      for (final b in buckets) {
        final src = widget.split == _Split.providers ? b.providers : b.models;
        for (final e in src.entries) {
          sums.update(e.key, (v) => v + e.value, ifAbsent: () => e.value);
        }
      }
      final ranked = sums.entries.where((e) => e.value > 0).toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final palette = _palette;
      for (var i = 0; i < ranked.length && i < palette.length - 1; i++) {
        keys.add(ranked[i].key);
        colours[ranked[i].key] = palette[i];
      }
      if (ranked.length > keys.length) colours['Other'] = palette.last;
    }

    List<(Color, int)> stack(_Bucket b) {
      if (widget.split == _Split.total) return [(AppColors.accent, b.total)];
      final src = widget.split == _Split.providers ? b.providers : b.models;
      final out = <(Color, int)>[for (final k in keys) (colours[k]!, src[k] ?? 0)];
      final rest = src.entries.where((e) => !keys.contains(e.key)).fold(0, (a, e) => a + e.value);
      if (rest > 0) out.add((colours['Other'] ?? AppColors.fg4, rest));
      return out;
    }

    final chartTotal = buckets.fold(0, (a, b) => a + b.total);
    final hovered = _hover == null ? null : buckets[_hover!];
    final first = buckets.first.start;
    final range = widget.range == _Range.day
        ? '${_day(first)} ${_hour(first)} to now'
        : '${_day(first)} to ${_day(DateTime.now())}';

    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(hovered == null ? 'Tokens' : _bucketLabel(hovered.start),
                  style: sans(12, color: AppColors.fg3)),
              SizedBox(height: S.s2),
              Text(fmtSi(hovered?.total ?? chartTotal),
                  style: mono(22, weight: FontWeight.w500, height: 1.2, color: AppColors.fg1)),
              SizedBox(height: S.s2),
              Text(range, style: sans(12, color: AppColors.fg4)),
            ]),
          ),
          _Segmented(value: widget.split, onChanged: widget.onSplit),
        ]),
        SizedBox(height: S.s16),
        SizedBox(
          height: 180,
          child: LayoutBuilder(builder: (context, c) {
            const axis = 40.0;
            final plotW = math.max(1.0, c.maxWidth - axis);
            int? indexAt(Offset p) {
              final x = p.dx - axis;
              if (x < 0) return null;
              final i = (x / plotW * buckets.length).floor();
              return i >= 0 && i < buckets.length ? i : null;
            }

            return MouseRegion(
              onHover: (e) => setState(() => _hover = indexAt(e.localPosition)),
              onExit: (_) => setState(() => _hover = null),
              child: CustomPaint(
                size: Size(c.maxWidth, c.maxHeight),
                painter: _BarsPainter(
                  stacks: [for (final b in buckets) stack(b)],
                  hover: _hover,
                  axis: axis,
                  grid: AppColors.line,
                  label: mono(10.5, color: AppColors.fg4),
                  hoverFill: AppColors.tint1,
                ),
              ),
            );
          }),
        ),
        SizedBox(height: S.s6),
        Padding(
          padding: const EdgeInsets.only(left: 40),
          child: Row(children: [
            Text(_bucketLabel(buckets.first.start).replaceFirst('Week of ', ''),
                style: mono(10.5, color: AppColors.fg4)),
            const Spacer(),
            if (buckets.length > 2)
              Text(_bucketLabel(buckets[buckets.length ~/ 2].start).replaceFirst('Week of ', ''),
                  style: mono(10.5, color: AppColors.fg4)),
            const Spacer(),
            Text(_bucketLabel(buckets.last.start).replaceFirst('Week of ', ''),
                style: mono(10.5, color: AppColors.fg4)),
          ]),
        ),
        if (colours.isNotEmpty) ...[
          SizedBox(height: S.s12),
          Wrap(spacing: S.s16, runSpacing: S.s6, children: [
            for (final e in colours.entries)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: e.value, borderRadius: BorderRadius.circular(2)),
                ),
                SizedBox(width: S.s6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(e.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, color: AppColors.fg3)),
                ),
              ]),
          ]),
        ],
      ]),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final List<List<(Color, int)>> stacks;
  final int? hover;
  final double axis;
  final Color grid;
  final TextStyle label;
  final Color hoverFill;
  _BarsPainter({
    required this.stacks,
    required this.hover,
    required this.axis,
    required this.grid,
    required this.label,
    required this.hoverFill,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final peak = stacks.fold(0, (a, s) => math.max(a, s.fold(0, (x, e) => x + e.$2)));
    final top = _niceCeil(peak);
    final plotW = size.width - axis;
    final h = size.height - 1;
    final line = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = h - h * i / 3;
      canvas.drawLine(Offset(axis, y + 0.5), Offset(size.width, y + 0.5), line);
      final tp = TextPainter(
        text: TextSpan(text: fmtSi((top * i / 3).round()), style: label),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(axis - 8 - tp.width, (y - tp.height / 2).clamp(0, size.height - tp.height)));
    }
    if (stacks.isEmpty) return;
    final slot = plotW / stacks.length;
    final barW = math.max(2.0, math.min(28.0, slot * 0.62));
    for (var i = 0; i < stacks.length; i++) {
      final x0 = axis + slot * i;
      if (i == hover) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x0, 0, slot, h), const Radius.circular(4)),
          Paint()..color = hoverFill,
        );
      }
      if (top == 0) continue;
      final x = x0 + (slot - barW) / 2;
      var y = h;
      final parts = stacks[i].where((e) => e.$2 > 0).toList();
      for (var j = 0; j < parts.length; j++) {
        final ph = h * parts[j].$2 / top;
        final rect = Rect.fromLTWH(x, y - ph, barW, ph);
        final last = j == parts.length - 1;
        canvas.drawRRect(
          RRect.fromRectAndCorners(rect,
              topLeft: last ? const Radius.circular(2) : Radius.zero,
              topRight: last ? const Radius.circular(2) : Radius.zero),
          Paint()..color = parts[j].$1,
        );
        y -= ph;
      }
    }
  }

  static int _niceCeil(int v) {
    if (v <= 0) return 0;
    final mag = math.pow(10, (math.log(v) / math.ln10).floor()).toInt();
    for (final m in const [1, 2, 3, 5, 10]) {
      if (v <= m * mag) return m * mag;
    }
    return 10 * mag;
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.hover != hover || old.stacks != stacks || old.grid != grid;
}

class _Segmented extends StatelessWidget {
  final _Split value;
  final ValueChanged<_Split> onChanged;
  const _Segmented({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.all(S.s2),
        decoration: BoxDecoration(
          color: AppColors.tint1,
          borderRadius: BorderRadius.circular(R.of(8)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final s in _Split.values)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(s),
                child: AnimatedContainer(
                  duration: Motion.quick,
                  height: 24,
                  padding: EdgeInsets.symmetric(horizontal: S.of(10)),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: s == value ? AppColors.tint3 : Colors.transparent,
                    borderRadius: BorderRadius.circular(R.of(6)),
                  ),
                  child: Text(
                    switch (s) {
                      _Split.total => 'Total',
                      _Split.providers => 'Providers',
                      _Split.models => 'Models',
                    },
                    style: sans(12,
                        weight: s == value ? FontWeight.w500 : FontWeight.w400,
                        color: s == value ? AppColors.fg1 : AppColors.fg3),
                  ),
                ),
              ),
            ),
        ]),
      );
}

class _RateCard extends StatelessWidget {
  final List<UsageProvider> providers;
  const _RateCard({required this.providers});

  @override
  Widget build(BuildContext context) => _Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Rate limits', style: sans(13, weight: FontWeight.w500, color: AppColors.fg1)),
          for (final p in providers) ...[
            SizedBox(height: S.s12),
            Text(usageProviderTitle(p.provider), style: sans(12, color: AppColors.fg3)),
            SizedBox(height: S.s4),
            for (final r in p.rateLimits) UsageRateRow(rate: r),
          ],
        ]),
      );
}

class _Breakdown extends StatelessWidget {
  final UsageSummary summary;
  const _Breakdown({required this.summary});

  @override
  Widget build(BuildContext context) {
    final providers = [...summary.providers]..sort((a, b) => b.totalTokens.compareTo(a.totalTokens));
    final total = math.max(1, providers.fold(0, (a, p) => a + p.totalTokens));
    String share(int v) {
      final pct = v * 100 / total;
      return pct >= 10 || pct == 0 ? '${pct.round()}%' : '${pct.toStringAsFixed(1)}%';
    }

    Widget row(String item, int tokens, int calls,
        {bool group = false, bool header = false}) {
      final style = header
          ? sans(12, color: AppColors.fg4)
          : group
              ? sans(13, weight: FontWeight.w500, color: AppColors.fg1)
              : sans(13, color: AppColors.fg2);
      final num = header ? style : mono(13, color: group ? AppColors.fg1 : AppColors.fg2);
      return Container(
        height: header ? 32 : 36,
        padding: EdgeInsets.only(left: group || header ? S.s12 : S.s24, right: S.s12),
        decoration: BoxDecoration(
          color: group ? AppColors.tint1 : null,
          border: header ? null : Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(children: [
          Expanded(
            child: Text(item, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
          ),
          SizedBox(width: kMobile ? 64 : 96, child: Text(header ? 'Tokens' : fmtSi(tokens), textAlign: TextAlign.right, style: num)),
          SizedBox(width: kMobile ? 44 : 72, child: Text(header ? 'Calls' : '$calls', textAlign: TextAlign.right, style: num)),
          SizedBox(width: kMobile ? 48 : 64, child: Text(header ? 'Share' : share(tokens), textAlign: TextAlign.right, style: num)),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: EdgeInsets.only(left: S.s4, bottom: S.s8),
        child: Text('Breakdown', style: sans(13, weight: FontWeight.w500, color: AppColors.fg1)),
      ),
      _Card(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Grouped.radiusEnd),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            row('Item', 0, 0, header: true),
            if (providers.isEmpty)
              Container(
                height: 44,
                alignment: Alignment.centerLeft,
                padding: EdgeInsets.symmetric(horizontal: S.s12),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
                child: Text('No model calls in this period.', style: sans(13, color: AppColors.fg3)),
              ),
            for (final p in providers) ...[
              row(usageProviderTitle(p.provider), p.totalTokens, p.calls, group: true),
              for (final m in [...p.models.where((m) => m.model.isNotEmpty)]
                ..sort((a, b) => b.totalTokens.compareTo(a.totalTokens)))
                row(m.model, m.totalTokens, m.calls),
            ],
          ]),
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(S.s4, S.s8, S.s4, 0),
        child: Text(
          'Every model call is recorded against the provider and model that served it. Input includes cached tokens; rate limits come from each provider\'s own reports.',
          style: sans(12, height: 1.5, color: AppColors.fg4),
        ),
      ),
    ]);
  }
}
