import 'package:flutter/material.dart';

import '../../api.dart';
import '../../mobile_kit.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../phone_agent_page.dart' show shortPath;
import '../session_coordination_cards.dart' show CardMarkdownBody;

/// An agent's board on phone: what it dispatched, reported and noted.
class PhoneAgentBoardPage extends StatefulWidget {
  const PhoneAgentBoardPage({
    super.key,
    required this.client,
    required this.agentId,
    required this.agentName,
    this.onOpenSession,
  });
  final DaemonClient client;
  final String agentId;
  final String agentName;
  final void Function(String sessionId)? onOpenSession;

  @override
  State<PhoneAgentBoardPage> createState() => _PhoneAgentBoardPageState();
}

const _automatic = 'Automatic, the session wrote no report: ';

class _PhoneAgentBoardPageState extends State<PhoneAgentBoardPage> {
  String _filter = 'all';
  List<BoardEntry>? _rows;
  Set<String> _awaiting = const {};
  final Map<String, BoardEntry> _reports = {};
  bool _failed = false;
  int _load = 0;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final n = ++_load;
    setState(() {
      _rows = null;
      _failed = false;
    });
    try {
      final page = await widget.client.agentBoardPage(
        widget.agentId,
        kind: _filter == 'all' || _filter == 'waiting' ? null : _filter,
        outstanding: _filter == 'waiting',
        limit: 100,
      );
      if (!mounted || n != _load) return;
      setState(() {
        // Automatic progress pings drown the real entries in All.
        _rows = _filter == 'all'
            ? [
                for (final e in page.entries)
                  if (!(e.kind == 'progress' &&
                      e.summary.startsWith(_automatic)))
                    e
              ]
            : page.entries;
        _awaiting = page.awaiting.toSet();
        for (final e in page.entries) {
          final id = e.correlationId;
          if (e.kind == 'reported' && id != null) _reports[id] = e;
        }
      });
    } catch (_) {
      if (mounted && n == _load) setState(() => _failed = true);
    }
  }

  static (String, String) _look(BoardEntry e) => switch (e.kind) {
        'dispatched' => ('send', 'Dispatched'),
        'reported' => ('check-circle', 'Reported'),
        'progress' => ('activity', 'Progress'),
        'noted' => ('file-text', 'Noted'),
        _ => ('file-text', e.kind),
      };

  /// The summary without the automatic prefix or the leading task id.
  static String _summary(BoardEntry e) {
    var text = e.summary.startsWith(_automatic)
        ? e.summary.substring(_automatic.length)
        : e.summary;
    final id = e.correlationId;
    if (id != null && text.startsWith(id)) {
      text =
          text.substring(id.length).replaceFirst(RegExp(r'^\s*[—:-]\s*'), '');
      if (text.isNotEmpty) text = text[0].toUpperCase() + text.substring(1);
    }
    return text.replaceAll(RegExp(r'[*_`#>]'), '').trim();
  }

  static String _ago(String raw) {
    final t = DateTime.tryParse(raw);
    if (t == null) return '';
    return relativeTime(t.millisecondsSinceEpoch ~/ 1000);
  }

  bool _waiting(BoardEntry e) =>
      e.kind == 'dispatched' && _awaiting.contains(e.correlationId);

  void _open(BoardEntry e) {
    final look = _look(e);
    final report = e.kind == 'dispatched' ? _reports[e.correlationId] : null;
    final session = e.sessionId;
    final meta = [
      _ago(e.createdAt),
      if (e.workspace != null) shortPath(e.workspace!),
    ].where((x) => x.isNotEmpty).join(' · ');
    showMkSheet<void>(
      context,
      title: look.$2,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (meta.isNotEmpty)
              Text(meta, style: sans(13, color: AppColors.fg3)),
            const SizedBox(height: 12),
            CardMarkdownBody(
                body: e.summary.startsWith(_automatic)
                    ? e.summary.substring(_automatic.length)
                    : e.summary,
                collapsible: false),
            if (report != null) ...[
              const SizedBox(height: 20),
              Text('Reported back ${_ago(report.createdAt)}',
                  style: sans(13, weight: W.label, color: AppColors.fg2)),
              const SizedBox(height: 6),
              CardMarkdownBody(body: report.summary, collapsible: false),
            ] else if (_waiting(e)) ...[
              const SizedBox(height: 16),
              Text('No report has come back yet.',
                  style: sans(14, color: AppColors.fg2)),
            ],
            if (session != null && widget.onOpenSession != null) ...[
              const SizedBox(height: 20),
              MkBigButton('Open session', secondary: true, onTap: () {
                Navigator.of(sheet).pop();
                widget.onOpenSession!(session);
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _note(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Text(text, style: sans(14, color: AppColors.fg3)));

  List<Widget> _body() {
    final rows = _rows;
    if (_failed) return [_note('Could not load the board.')];
    if (rows == null) return [_note('Loading')];
    if (rows.isEmpty) {
      return [
        _note(_filter == 'waiting'
            ? 'Nothing waiting on a report'
            : 'Nothing on the board yet')
      ];
    }
    return [
      const SizedBox(height: 8),
      MkList(children: [
        for (var i = 0; i < rows.length; i++)
          MkRow(
            key: ValueKey('board-${rows[i].id}'),
            title: _summary(rows[i]).isEmpty
                ? _look(rows[i]).$2
                : _summary(rows[i]),
            subtitle: [
              _waiting(rows[i]) ? 'Dispatched, waiting' : _look(rows[i]).$2,
              if (rows[i].workspace != null) shortPath(rows[i].workspace!),
            ].join(' · '),
            time: _ago(rows[i].createdAt),
            leading: AppIcon(_look(rows[i]).$1, size: 22, color: AppColors.fg2),
            divider: i < rows.length - 1,
            onTap: () => _open(rows[i]),
          ),
      ]),
    ];
  }

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.bg,
        child: MkPage(
          title: 'Board',
          onBack: () => Navigator.of(context).pop(),
          bottomClearance: false,
          onRefresh: _fetch,
          filters: MkFilterGroup<String>(
            selected: _filter,
            onSelect: (v) {
              if (v == _filter) return;
              _filter = v;
              _fetch();
            },
            options: const [
              MkFilter('all', 'All'),
              MkFilter('waiting', 'Waiting'),
              MkFilter('dispatched', 'Dispatched'),
              MkFilter('reported', 'Reported'),
              MkFilter('noted', 'Noted'),
              MkFilter('progress', 'Progress'),
            ],
          ),
          slivers: [
            SliverList(delegate: SliverChildListDelegate(_body())),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      );
}
