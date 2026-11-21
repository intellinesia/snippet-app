import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../swr.dart';
import '../theme.dart';
import '../widgets.dart';
import '../pull_refresh.dart';
import '../platform.dart';

/// Background processes the agent started (dev servers, tunnels, a browser) via
/// `bash {background:true}`. Lists them from /bg with a live status, a log tail,
/// and a stop button. Revalidates when the daemon reports a process change.
class ProcessesScreen extends StatefulWidget {
  final DaemonClient client;
  final String sessionId;
  final VoidCallback? onClose;

  /// Renders only the list (no scaffold or header) for the Activity panel.
  final bool embedded;
  const ProcessesScreen(
      {super.key,
      required this.client,
      required this.sessionId,
      this.onClose,
      this.embedded = false});
  @override
  State<ProcessesScreen> createState() => _ProcessesScreenState();
}

class _ProcessesScreenState extends State<ProcessesScreen> {
  List<Map<String, dynamic>>? _procs;
  bool _loading = true;
  String? _error;
  String? _openLogId;
  String _log = '';
  bool _logLoading = false;
  late final Swr<List<Map<String, dynamic>>> _list;

  @override
  void initState() {
    super.initState();
    _list = Swr<List<Map<String, dynamic>>>(
      client: widget.client,
      key: 'bg:${widget.sessionId}',
      fetch: () => widget.client.bgList(widget.sessionId),
      revalidateOn: (e) => e['kind'] == 'process',
      onChange: _sync,
    );
    _procs = _list.data;
    _loading = _procs == null;
  }

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) => _list.refresh();

  void _sync() {
    if (!mounted) return;
    final p = _list.data;
    setState(() {
      _procs = p ?? _procs;
      _loading = _list.loading;
      _error = p == null && _list.error != null ? '${_list.error}' : null;
      if (p != null &&
          _openLogId != null &&
          !p.any((e) => '${e['id']}' == _openLogId)) {
        _openLogId = null;
      }
    });
  }

  final Set<String> _stopping = {};

  Future<void> _kill(String id) async {
    setState(() => _stopping.add(id));
    try {
      await widget.client.bgKill(widget.sessionId, id);
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
    await _load(silent: true);
    if (mounted) setState(() => _stopping.remove(id));
  }

  Future<void> _toggleLog(String id) async {
    if (_openLogId == id) {
      setState(() {
        _openLogId = null;
        _log = '';
      });
      return;
    }
    setState(() {
      _openLogId = id;
      _log = '';
      _logLoading = true;
    });
    try {
      final t = await widget.client.bgLog(widget.sessionId, id);
      if (mounted && _openLogId == id) {
        setState(() {
          _log = t;
          _logLoading = false;
        });
      }
    } catch (e) {
      if (mounted && _openLogId == id) {
        setState(() {
          _log = '$e';
          _logLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final procs = _procs ?? const [];
    if (widget.embedded) {
      Widget note(String t, {bool danger = false}) => Padding(
          padding: EdgeInsets.symmetric(vertical: S.s8),
          child: Text(t,
              style:
                  sans(13, color: danger ? AppColors.danger : AppColors.fg4)));
      if (_loading) return const Center(child: DelayedSpinner(size: 16));
      if (_error != null) return note(_error!, danger: true);
      if (procs.isEmpty) return note('No background processes');
      return _card(procs);
    }
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          if (kMobile)
            SnAppBar(
              title: 'Processes',
              titleSize: 14,
              compact: true,
              onBack: widget.onClose ?? () => Navigator.pop(context),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(children: [
                Text('Processes',
                    style: sans(kMobile ? 20 : 16,
                        weight: FontWeight.w600, color: AppColors.fg1)),
                const SizedBox(width: 8),
                if (procs.isNotEmpty)
                  Text('${procs.length}',
                      style: mono(11, color: AppColors.fg4)),
                const Spacer(),
                IconBtn('x',
                    size: 28,
                    iconSize: 14,
                    tooltip: 'Close',
                    onTap: widget.onClose ?? () => Navigator.pop(context)),
              ]),
            ),
          if (_loading)
            const Expanded(child: Center(child: DelayedSpinner()))
          else if (_error != null)
            Expanded(
                child: EmptyState(
                    icon: 'alert-triangle',
                    title: "Couldn't load",
                    body: _error!))
          else if (procs.isEmpty)
            const Expanded(
                child: EmptyState(
                    icon: 'processes',
                    title: 'No background processes',
                    body:
                        'Long-running jobs the agent starts (servers, tunnels) show up here.'))
          else
            Expanded(
                child: PullToRefresh(
                    onRefresh: () => _load(),
                    child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.all(S.s16),
                        children: [
                          _card(procs),
                        ]))),
        ]),
      ),
    );
  }

  Widget _card(List<Map<String, dynamic>> procs) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(R.lg),
          border: kMobile ? Border.all(color: AppColors.line) : null,
        ),
        child: Column(children: [
          for (var i = 0; i < procs.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: AppColors.line),
            _row(procs[i]),
          ],
        ]),
      );

  Widget _row(Map<String, dynamic> p) {
    final id = '${p['id'] ?? ''}';
    final cmd = '${p['command'] ?? ''}'.replaceAll('\n', ' ');
    final pid = p['pid'] ?? 0;
    final running = p['running'] == true && !_stopping.contains('${p['id']}');
    final status = p['status'] as String?;
    final failed = !running && status != null && status != '0';
    final statusLabel = running
        ? 'running'
        : switch (status) {
            '0' => 'exited (ok)',
            'signal' => 'killed',
            final c? when c.isNotEmpty => 'exited ($c)',
            _ => 'exited',
          };
    final open = _openLogId == id;
    final dotFg = running
        ? toneColors(Tone.ok).$1
        : failed
            ? AppColors.danger
            : AppColors.fg4;
    return Padding(
      padding: EdgeInsets.fromLTRB(S.s12, S.s8, S.s12, S.s8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dotFg, shape: BoxShape.circle)),
          SizedBox(width: S.s8),
          Expanded(
            child: Text(cmd,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: kMobile
                    ? TS.code(AppColors.fg1)
                    : mono(12.5, color: AppColors.fg1)),
          ),
          if (!kMobile) ...[
            _ChipBtn(open ? 'Hide log' : 'Log', () => _toggleLog(id)),
            if (running) ...[
              SizedBox(width: S.s6),
              _ChipBtn('Stop', () => _kill(id), danger: true),
            ],
          ],
        ]),
        SizedBox(height: kMobile ? S.s6 : 0),
        Row(children: [
          if (!kMobile) const SizedBox(width: 16),
          Expanded(
            child: Text(running ? 'running · pid $pid' : statusLabel,
                style: TS.meta(failed ? AppColors.danger : AppColors.fg3)),
          ),
          if (kMobile) ...[
            _ChipBtn(open ? 'Hide log' : 'Log', () => _toggleLog(id)),
            if (running) ...[
              SizedBox(width: S.s8),
              _ChipBtn('Stop', () => _kill(id)),
            ],
          ],
        ]),
        if (open) ...[
          SizedBox(height: S.s8),
          Container(
            constraints: const BoxConstraints(maxHeight: 240),
            width: double.infinity,
            padding: EdgeInsets.all(S.s12),
            decoration: BoxDecoration(
                color: kMobile ? AppColors.canvas : AppColors.bg,
                borderRadius: BorderRadius.circular(R.md)),
            child: _logLoading
                ? const Center(child: DelayedSpinner(size: 16))
                : SingleChildScrollView(
                    child: SelectableText(
                        _log.trim().isEmpty ? '(empty)' : _log,
                        style: TS.codeSmall(AppColors.fg2))),
          ),
        ],
      ]),
    );
  }
}

/// Pill drawn at 30px (28 on desktop) inside a 44px hit area, as in the shots.
class _ChipBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool danger;
  const _ChipBtn(this.label, this.onTap, {this.danger = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: kMobile ? 44 : 32,
          child: Center(
            child: Container(
              height: kMobile ? 30 : 28,
              padding: EdgeInsets.symmetric(horizontal: S.s12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: AppColors.surface3,
                  borderRadius:
                      BorderRadius.circular(kMobile ? R.pill : R.of(6))),
              child: Text(label,
                  style: sans(kMobile ? 13 : 12,
                      weight: kMobile ? W.strong : null,
                      color: danger ? AppColors.danger : AppColors.fg2)),
            ),
          ),
        ),
      );
}
