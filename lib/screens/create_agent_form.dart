import 'package:flutter/material.dart';

import '../api.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

/// Describe an agent in prose; the runtime researches and builds it.
///
/// ONE form, two hosts: Mission Control's agent directory presents it as a
/// sheet, and the shell's agents panel opens it as a popover under its "+".
/// It lives here rather than inside either host because a second copy is how
/// the two drift — the panel briefly grew its own variant that could not even
/// enable its submit button.
///
/// The prompt field is deliberately the whole form. The daemon takes only
/// `{prompt}` and derives name, handle and capabilities itself, so
/// exposing those as inputs would offer controls it ignores.
class CreateAgentForm extends StatefulWidget {
  const CreateAgentForm({super.key, required this.client});

  final DaemonClient client;

  @override
  State<CreateAgentForm> createState() => _CreateAgentFormState();
}

class _CreateAgentFormState extends State<CreateAgentForm> {
  final _prompt = TextEditingController();
  final _nickname = TextEditingController();
  final _promptFocus = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nickname.dispose();
    _promptFocus.dispose();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final prompt = _prompt.text.trim();
    // Validated here, not by disabling the button: `AppField` exposes no
    // `onChanged`, so a disabled-by-length budget could never rebuild as you
    // type and the button would stay dead.
    if (prompt.length < 12) {
      setState(() => _error = 'Describe the agent you want it to become.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client
          .buildCoordinationAgent(prompt, nickname: _nickname.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  static const _starters = [
    ('Code reviewer',
        'A code reviewer that reads pull requests, flags risks and suggests fixes without pushing.'),
    ('Release manager',
        'A release manager that builds, tests and ships releases, and writes the notes.'),
    ('Research scout',
        'A research scout that searches the web and summarises what matters, with sources.'),
    ('Docs writer',
        'A docs writer that keeps the README and guides in step with the code, in British English.'),
  ];

  void _start(String text) {
    _prompt.text = text;
    _prompt.selection = TextSelection.collapsed(offset: text.length);
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final fs = kMobile ? 15.0 : 13.0;
    final roomy = MediaQuery.sizeOf(context).height >= 700;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Describe the job. Snippet picks the name, model and skills, then builds it.',
          style: sans(13, height: 1.45, color: AppColors.fg3),
        ),
        const SizedBox(height: 14),
        FieldWell(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: TextField(
                controller: _prompt,
                focusNode: _promptFocus,
                autofocus: true,
                minLines: roomy ? 4 : 2,
                maxLines: roomy ? 6 : 4,
                cursorColor: AppColors.accent,
                style: sans(fs, height: 1.5, color: AppColors.fg1),
                decoration: InputDecoration.collapsed(
                  hintText:
                      'A security reviewer that inspects repos without changing them.',
                  hintStyle: sans(fs, height: 1.5, color: AppColors.fg4),
                ),
              ),
            ),
            Container(height: 1, color: AppColors.lineStrong),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Text('Name', style: sans(13, color: AppColors.fg3)),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _nickname,
                    textAlign: TextAlign.end,
                    cursorColor: AppColors.accent,
                    style: sans(13, color: AppColors.fg1),
                    decoration: InputDecoration.collapsed(
                      hintText: 'Optional',
                      hintStyle: sans(13, color: AppColors.fg4),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
        if (roomy) ...[
        const SizedBox(height: 16),
        Text('Start from', style: sans(13, color: AppColors.fg3)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (label, text) in _starters)
            Pressable(
              kind: PressKind.button,
              radius: 16,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _busy ? null : () => _start(text),
                child: Container(
                  constraints: BoxConstraints(minHeight: kMobile ? 34 : 28),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.lineStrong),
                  ),
                  child: Center(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13, color: AppColors.fg2)),
                  ),
                ),
              ),
            ),
        ]),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: sans(13, color: AppColors.danger)),
        ],
        const SizedBox(height: 18),
        Btn(
          _busy ? 'Starting build…' : 'Build agent',
          full: true,
          small: !kMobile,
          disabled: _busy,
          icon: 'sparkles',
          onTap: _submit,
        ),
      ],
    );
  }
}
