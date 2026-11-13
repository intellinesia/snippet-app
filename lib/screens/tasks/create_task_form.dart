import 'package:flutter/material.dart';

import '../../api.dart';
import '../../mochi.dart';
import '../../models.dart';
import '../../platform.dart';
import '../../theme.dart';
import '../../widgets.dart';

/// A new task goes to Mission Control as a request: it files the task, picks
/// or starts the session, and offers it to the chosen agent.
class CreateTaskForm extends StatefulWidget {
  const CreateTaskForm({
    super.key,
    required this.client,
    this.onCreated,
  });
  final DaemonClient client;
  final VoidCallback? onCreated;

  @override
  State<CreateTaskForm> createState() => _CreateTaskFormState();
}

class _CreateTaskFormState extends State<CreateTaskForm> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  List<CoordinationAgent> _agents = const [];
  String? _agentId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAgents();
  }

  Future<void> _loadAgents() async {
    try {
      final all = await widget.client.coordinationAgents();
      if (!mounted) return;
      setState(() => _agents = [
            for (final a in all)
              if (!a.isMissionControl) a
          ]);
    } catch (_) {}
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  String _name(CoordinationAgent a) =>
      a.displayName.trim().isEmpty ? a.id : a.displayName.trim();

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give the task a title.');
      return;
    }
    final agent = _agents.where((a) => a.id == _agentId).firstOrNull;
    final briefing = _description.text.trim();
    final body = [
      'New task from the Tasks board. File it, then pick or start the session '
          'it should run in and offer it to the agent.',
      '',
      'Title: $title',
      'Agent: ${agent == null ? 'your call' : '${_name(agent)} (${agent.id})'}',
      if (briefing.isNotEmpty) ...['', 'Briefing:', briefing],
    ].join('\n');
    setState(() {
      _busy = true;
      _error = null;
    });
    final root = Navigator.of(context, rootNavigator: true).context;
    try {
      await widget.client.sendAgentMessage(
        toAgentId: 'mission-control',
        body: body,
        idempotencyKey: 'new-task-${title.hashCode}-${DateTime.now().minute}',
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = "Couldn't reach Mission Control: $e";
        });
      }
      return;
    }
    if (!mounted) return;
    if (widget.onCreated != null) {
      widget.onCreated!();
    } else {
      Navigator.of(context).pop(true);
    }
    if (root.mounted) toast(root, 'Sent to Mission Control');
  }

  Widget _agentChip({
    required String id,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _busy ? null : onTap,
          child: SizedBox(
            width: 64,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedContainer(
                duration: Motion.fast,
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.fg1.withValues(alpha: 0.06),
                  border: Border.all(
                    color: selected ? AppColors.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Center(child: AgentMochi(id, size: 24)),
              ),
              const SizedBox(height: S.s6),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: sans(11,
                      color: selected ? AppColors.fg1 : AppColors.fg3)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            kMobile ? 16 : 12, 4, kMobile ? 16 : 12, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppField(
              controller: _title,
              label: 'Title',
              hint: 'Ship the coordinator panel',
              autofocus: true,
            ),
            const SizedBox(height: S.s16),
            Text('Who',
                style: sans(12, weight: W.label, color: AppColors.fg3)),
            const SizedBox(height: S.s8),
            SizedBox(
              height: 66,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _agentChip(
                    id: 'mission-control',
                    label: 'MC picks',
                    selected: _agentId == null,
                    onTap: () => setState(() => _agentId = null),
                  ),
                  for (final a in _agents)
                    _agentChip(
                      id: a.id,
                      label: _name(a),
                      selected: _agentId == a.id,
                      onTap: () => setState(() => _agentId = a.id),
                    ),
                ],
              ),
            ),
            const SizedBox(height: S.s16),
            AppField(
              controller: _description,
              label: 'Briefing',
              hint: 'Goal, what done looks like, and the context it needs.',
              minLines: 4,
              maxLines: 8,
            ),
            if (_error != null) ...[
              const SizedBox(height: S.s8),
              Text(_error!, style: sans(12, color: AppColors.danger)),
            ],
            const SizedBox(height: S.s12),
            Text(
              'Mission Control files it, picks or starts the session, and '
              'hands it over.',
              style: sans(12, color: AppColors.fg4, height: 1.45),
            ),
            const SizedBox(height: S.s12),
            Btn(
              _busy ? 'Sending…' : 'Send to Mission Control',
              full: true,
              disabled: _busy,
              icon: 'send',
              onTap: _submit,
            ),
          ],
        ),
      );
}
