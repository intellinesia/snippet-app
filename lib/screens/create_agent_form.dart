import 'package:flutter/material.dart';

import '../agent_character.dart';
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
/// Starter agents offered by the form and the phone Agents tab.
const agentStarters =
    <({String title, String summary, String prompt, String character})>[
  (
    title: 'Code reviewer',
    summary: 'Reads pull requests and flags risks',
    prompt:
        'A code reviewer that reads pull requests, flags risks and suggests fixes without pushing.',
    character: '05'
  ),
  (
    title: 'Release manager',
    summary: 'Builds, tests and ships releases',
    prompt:
        'A release manager that builds, tests and ships releases, and writes the notes.',
    character: '09'
  ),
  (
    title: 'Research scout',
    summary: 'Searches the web and summarises, with sources',
    prompt:
        'A research scout that searches the web and summarises what matters, with sources.',
    character: '03'
  ),
  (
    title: 'Docs writer',
    summary: 'Keeps the README and guides in step with the code',
    prompt:
        'A docs writer that keeps the README and guides in step with the code, in British English.',
    character: '07'
  ),
];

class CreateAgentForm extends StatefulWidget {
  const CreateAgentForm(
      {super.key,
      required this.client,
      this.initialPrompt,
      this.initialCharacter});

  final DaemonClient client;
  final String? initialPrompt;
  final String? initialCharacter;

  @override
  State<CreateAgentForm> createState() => _CreateAgentFormState();
}

class _CreateAgentFormState extends State<CreateAgentForm> {
  final _prompt = TextEditingController();
  final _nickname = TextEditingController();
  final _promptFocus = FocusNode();
  bool _busy = false;
  String? _error;
  String _character = '01';
  List<String> _characters = const [];

  @override
  void initState() {
    super.initState();
    _character = widget.initialCharacter ?? _character;
    final seed = widget.initialPrompt?.trim() ?? '';
    if (seed.isNotEmpty) {
      _prompt.text = seed;
      _lastPrompt = seed;
    }
    _nickname.addListener(() => setState(() {}));
    _prompt.addListener(_promptChanged);
    CharacterRoster.load().then((r) {
      if (mounted) setState(() => _characters = r.characters.keys.toList());
    }).catchError((_) {});
  }

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
      await widget.client.buildCoordinationAgent(prompt,
          nickname: _nickname.text.trim(), character: _character);
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

  static final _starters = [
    for (final st in agentStarters) (st.title, st.prompt),
  ];

  void _start(String text) {
    _prompt.text = text;
    _prompt.selection = TextSelection.collapsed(offset: text.length);
    setState(() => _error = null);
  }

  String _lastPrompt = '';

  /// Rebuilds only when the text changes, so the chosen starter stays marked.
  void _promptChanged() {
    if (_prompt.text == _lastPrompt) return;
    _lastPrompt = _prompt.text;
    setState(() {});
  }

  Widget _picker() {
    final h = kMobile ? 50.0 : 30.0;
    return SizedBox(
      height: h,
      child: LayoutBuilder(builder: (context, box) {
        // Six cells fill the row; the rest scroll.
        final gap = kMobile ? S.s8 : 6.0;
        final cell = (box.maxWidth - 5 * gap) / 6;
        return ListView.separated(
          key: const ValueKey('character-picker'),
          scrollDirection: Axis.horizontal,
          itemCount: _characters.length,
          separatorBuilder: (_, __) => SizedBox(width: gap),
          itemBuilder: (_, i) {
            final id = _characters[i];
            final sel = id == _character;
            final tint = CharacterRoster.current?.character(id)?.color ??
                AppColors.accent;
            return Semantics(
              button: true,
              selected: sel,
              label: 'Character $id',
              child: GestureDetector(
                key: ValueKey('character-$id'),
                behavior: HitTestBehavior.opaque,
                onTap: _busy ? null : () => setState(() => _character = id),
                child: Container(
                  width: cell,
                  decoration: BoxDecoration(
                    color:
                        sel ? tint.withValues(alpha: 0.13) : AppColors.surface2,
                    borderRadius: BorderRadius.circular(R.of(kMobile ? 12 : 8)),
                    border: Border.all(
                        color: sel ? tint : AppColors.lineStrong,
                        width: sel ? 1.5 : 1),
                  ),
                  child: Center(
                    child: AgentCharacter(id,
                        size: kMobile ? h - 14 : 26, staggerKey: id),
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fs = kMobile ? 15.0 : 13.0;
    final roomy = MediaQuery.sizeOf(context).height >= 700;
    final name = _nickname.text.trim();
    final stage = roomy ? (kMobile ? 120.0 : 84.0) : 48.0;
    Widget label(String t) => Padding(
          padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s4),
          child: Text(t, style: sans(13, color: AppColors.fg3)),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: SizedBox.square(
            dimension: stage,
            child: AgentCharacter(_character,
                key: const ValueKey('agent-stage'),
                size: stage,
                state: AgentCharacterState.waiting,
                staggerKey: 'new-agent'),
          ),
        ),
        SizedBox(height: S.s8),
        _picker(),
        SizedBox(height: S.of(14)),
        label('What it does'),
        FieldWell(
          child: Padding(
            padding: EdgeInsets.fromLTRB(S.of(14), S.s12, S.of(14), S.s12),
            child: TextField(
              controller: _prompt,
              focusNode: _promptFocus,
              autofocus: true,
              minLines: roomy ? 3 : 2,
              maxLines: roomy ? 5 : 4,
              cursorColor: AppColors.accent,
              style: sans(fs, height: 1.5, color: AppColors.fg1),
              decoration: InputDecoration.collapsed(
                hintText:
                    'A security reviewer that inspects repos without changing them.',
                hintStyle: sans(fs, height: 1.5, color: AppColors.fg4),
              ),
            ),
          ),
        ),
        SizedBox(height: S.s12),
        label('Name'),
        FieldWell(
          child: Padding(
            padding:
                EdgeInsets.symmetric(horizontal: S.of(14), vertical: S.of(10)),
            child: TextField(
              controller: _nickname,
              cursorColor: AppColors.accent,
              style: sans(fs, color: AppColors.fg1),
              decoration: InputDecoration.collapsed(
                hintText: 'Optional',
                hintStyle: sans(fs, color: AppColors.fg4),
              ),
            ),
          ),
        ),
        if (roomy) ...[
          SizedBox(height: S.s16),
          Text('Start from', style: sans(13, color: AppColors.fg3)),
          SizedBox(height: S.s8),
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
                    padding: EdgeInsets.symmetric(horizontal: S.s12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(R.of(16)),
                      border: Border.all(
                          color: _prompt.text == text
                              ? AppColors.accent
                              : AppColors.lineStrong),
                    ),
                    child: Center(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(13,
                              color: _prompt.text == text
                                  ? AppColors.fg1
                                  : AppColors.fg2)),
                    ),
                  ),
                ),
              ),
          ]),
        ],
        if (_error != null) ...[
          SizedBox(height: S.s12),
          Text(_error!, style: sans(13, color: AppColors.danger)),
        ],
        SizedBox(height: S.of(18)),
        // Full width on phones; a trailing button on desktop.
        Align(
          alignment: Alignment.centerRight,
          child: Btn(
            _busy
                ? 'Starting build…'
                : (name.isEmpty ? 'Build agent' : 'Build $name'),
            full: kMobile,
            small: !kMobile,
            disabled: _busy,
            icon: 'sparkles',
            onTap: _submit,
          ),
        ),
      ],
    );
  }
}
