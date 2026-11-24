import 'package:flutter/material.dart';

import '../../api.dart';
import '../../tap_detector.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'agents_home.dart';

/// Lead autonomy (HM-10): Ask / Plan / Act, per-tool overrides, daily summary.
/// Reads `mode`, `tool_overrides` and `summary` from GET /lead/autonomy and
/// writes `mode` through POST /lead/autonomy. Rows whose data the daemon does
/// not send are hidden.
class AutonomyPhonePage extends StatefulWidget {
  const AutonomyPhonePage({super.key, required this.client});
  final DaemonClient client;

  @override
  State<AutonomyPhonePage> createState() => _AutonomyPhonePageState();
}

const _modes = ['ask', 'plan', 'act'];
const _explain = {
  'ask': 'Lead asks you before it acts.',
  'plan': 'Lead shows a plan and waits for approval.',
  'act': 'Lead acts on its own and tells you afterwards.',
};

class _AutonomyPhonePageState extends State<AutonomyPhonePage> {
  Map<String, dynamic>? _a;

  @override
  void initState() {
    super.initState();
    _a = widget.client.cachedLeadAutonomy();
    widget.client.leadAutonomy().then((a) {
      if (mounted) setState(() => _a = a);
    }).catchError((_) {});
  }

  String get _mode {
    final m = '${_a?['mode'] ?? 'ask'}'.toLowerCase();
    return _modes.contains(m) ? m : 'ask';
  }

  Future<void> _set(String m) async {
    final before = _a;
    setState(() => _a = {...?_a, 'mode': m});
    try {
      final a = await widget.client.leadSetAutonomy({'mode': m});
      if (mounted) setState(() => _a = a);
    } catch (_) {
      if (mounted) setState(() => _a = before);
    }
  }

  @override
  Widget build(BuildContext context) {
    final overrides = (_a?['tool_overrides'] is Map)
        ? Map<String, dynamic>.from(_a!['tool_overrides'] as Map)
        : const <String, dynamic>{};
    final sum = _a?['summary'];
    final summary = sum is Map
        ? '${sum['rounds'] ?? 0} rounds   ${sum['asked'] ?? 0} asked   ${sum['failed'] ?? 0} failed'
        : null;
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        child: Column(children: [
          const PushedBar(title: 'Autonomy', subtitle: 'Lead'),
          Expanded(
            child: ListView(
                padding: const EdgeInsets.only(top: 16, bottom: 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: kGutter),
                    child: Container(
                      key: const ValueKey('autonomy-seg'),
                      constraints: const BoxConstraints(minHeight: 48),
                      decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        for (final m in _modes)
                          Expanded(
                            child: Semantics(
                              button: true,
                              selected: m == _mode,
                              label: '${m[0].toUpperCase()}${m.substring(1)}',
                              excludeSemantics: true,
                              child: TapDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _set(m),
                                child: SizedBox(
                                    key: ValueKey('seg-$m'),
                                    height: 48,
                                    child: Padding(
                                        padding: const EdgeInsets.all(2),
                                        child: Container(
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                              color: m == _mode
                                                  ? AppColors.surface3
                                                  : null,
                                              borderRadius:
                                                  BorderRadius.circular(22)),
                                          child: Text(
                                              '${m[0].toUpperCase()}${m.substring(1)}',
                                              style: sans(15,
                                                  weight: FontWeight.w500,
                                                  color: m == _mode
                                                      ? AppColors.fg1
                                                      : AppColors.fg2)),
                                        ))),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 0),
                    child: Text(_explain[_mode]!,
                        style: sans(13, color: AppColors.fg3)),
                  ),
                  if (overrides.isNotEmpty) ...[
                    const HomeLabel('Per-tool overrides', top: 24),
                    for (final e in overrides.entries)
                      Semantics(
                        label: '${e.key}, ${e.value}',
                        excludeSemantics: true,
                        child: Container(
                          key: ValueKey('override-${e.key}'),
                          constraints: const BoxConstraints(minHeight: 48),
                          padding:
                              const EdgeInsets.symmetric(horizontal: kGutter),
                          child: Row(children: [
                            Expanded(
                                child: Text(e.key,
                                    style: sans(15, color: AppColors.fg1))),
                            Text(
                                '${e.value}'.replaceFirstMapped(
                                    RegExp(r'^.'), (m) => m[0]!.toUpperCase()),
                                style: sans(13,
                                    weight: FontWeight.w500,
                                    color: AppColors.fg2)),
                            const SizedBox(width: 6),
                            AppIcon('chevron-right',
                                size: 16, color: AppColors.fg3),
                          ]),
                        ),
                      ),
                  ],
                  if (summary != null)
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(kGutter, 24, kGutter, 0),
                      child:
                          Text(summary, style: sans(12, color: AppColors.fg3)),
                    ),
                ]),
          ),
        ]),
      ),
    );
  }
}
