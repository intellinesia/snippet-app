import 'package:flutter/material.dart';

import '../../agent_character.dart';
import '../../api.dart';
import '../../chat/signal_row.dart' show prettyModel, prettyProfile;
import '../../models.dart';
import '../../tap_detector.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'agents_home.dart';

// Cards and segments sit 16 in from the screen edge on the board.
const double _inset = 16;

/// Create agent (HM-11). Name and Role are sent as the build prompt; the
/// daemon's build call takes no profile or channel fields.
class PhoneCreateAgentPage extends StatefulWidget {
  const PhoneCreateAgentPage({super.key, required this.client});
  final DaemonClient client;

  @override
  State<PhoneCreateAgentPage> createState() => _PhoneCreateAgentPageState();
}

class _PhoneCreateAgentPageState extends State<PhoneCreateAgentPage> {
  final _name = TextEditingController(), _role = TextEditingController();
  String _character = '01';
  List<String> _characters = const [];
  Map<String, InferenceProfile> _profiles = const {};
  String? _profile;
  bool _wake = false, _reach = true, _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    CharacterRoster.load().then((r) {
      if (mounted) setState(() => _characters = r.characters.keys.take(12).toList());
    }).catchError((_) {});
    widget.client.getConfig().then((c) {
      if (mounted) setState(() => _profiles = {for (final p in c.profiles) p.name: p});
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty;

  String _profileLabel(String k) {
    final m = (_profiles[k]?.model ?? '').trim();
    return m.isNotEmpty ? prettyModel(m) : prettyProfile(k);
  }

  Future<void> _create() async {
    if (!_valid || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final name = _name.text.trim(), role = _role.text.trim();
    final prompt = role.length >= 12
        ? role
        : '$name: ${role.isEmpty ? 'a general purpose agent' : role}, working as a named member of the crew.';
    try {
      await widget.client.buildCoordinationAgent(prompt,
          nickname: name, character: _character);
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

  Future<void> _pickProfile() async {
    final pick = await showAppSheet<String>(
      context,
      title: 'Inference profile',
      maxHeight: 560,
      child: Builder(
        builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
          for (final k in _profiles.keys)
            MarkRow(
              mark: AppIcon('sliders', size: 20, color: AppColors.fg2),
              markSize: 20,
              title: _profileLabel(k),
              hairline: false,
              minHeight: 48,
              onTap: () => Navigator.of(ctx).pop(k),
            ),
        ]),
      ),
    );
    if (pick != null && mounted) setState(() => _profile = pick);
  }

  Widget _field(String label, Widget child) => Padding(
        padding: const EdgeInsets.fromLTRB(_inset, 0, _inset, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(label,
                  style: sans(11, weight: FontWeight.w500, color: AppColors.fg3))),
          child,
        ]),
      );

  Widget _box({required Widget child, VoidCallback? onTap}) => TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
              color: AppColors.surface1, borderRadius: BorderRadius.circular(12)),
          child: child,
        ),
      );

  Widget _text(TextEditingController c, String hint) => _box(
        child: TextField(
          controller: c,
          onChanged: (_) => setState(() {}),
          cursorColor: AppColors.fg1,
          style: sans(15, color: AppColors.fg1),
          decoration: InputDecoration.collapsed(
              hintText: hint, hintStyle: sans(15, color: AppColors.fg4)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final pk = _profile;
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        child: Column(children: [
          const PushedBar(title: 'New agent'),
          Expanded(
            child: ListView(padding: const EdgeInsets.only(top: 16), children: [
              _field('Name', _text(_name, 'Name')),
              _field('Role', _text(_role, 'What it is for')),
              _field(
                  'Inference profile',
                  _box(
                    onTap: _profiles.isEmpty ? null : _pickProfile,
                    child: Row(children: [
                      Expanded(
                          child: Text(
                              pk == null ? 'Default' : _profileLabel(pk),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(15, color: AppColors.fg1))),
                      AppIcon('chevron-down', size: 20, color: AppColors.fg2),
                    ]),
                  )),
              const HomeLabel('Appearance', top: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _inset),
                child: LayoutBuilder(builder: (context, c) {
                  final cell = c.maxWidth / 6;
                  return Wrap(children: [
                    for (final id in _characters)
                      Semantics(
                        button: true,
                        selected: id == _character,
                        label: 'Character $id',
                        excludeSemantics: true,
                        child: TapDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => _character = id),
                          child: SizedBox(
                            width: cell,
                            height: 48 > cell ? 48 : cell,
                            child: Center(
                              child: Container(
                                width: id == _character ? 48 : 44,
                                height: id == _character ? 48 : 44,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: id == _character
                                        ? Border.all(color: AppColors.fg2, width: 2)
                                        : null),
                                child: ClipOval(
                                    child: AgentCharacter(id, size: 40, staggerKey: id)),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]);
                }),
              ),
              const SizedBox(height: 8),
              SwitchRow('Wake on schedule', _wake, (v) => setState(() => _wake = v)),
              SwitchRow('Reach me on phone', _reach, (v) => setState(() => _reach = v)),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(_inset),
                  child: Text(_error!, style: sans(13, color: AppColors.fg2)),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(_inset, 8, _inset, 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (!_valid)
                Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('Add a name', style: sans(12, color: AppColors.fg3))),
              Semantics(
                button: true,
                enabled: _valid,
                label: 'Create',
                excludeSemantics: true,
                child: TapDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _valid ? _create : null,
                  child: Container(
                    key: const ValueKey('create-button'),
                    constraints: const BoxConstraints(minHeight: 48),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: _valid ? AppColors.fg1 : AppColors.surface3,
                        borderRadius: BorderRadius.circular(24)),
                    child: Text(_busy ? 'Creating' : 'Create',
                        style: sans(14,
                            weight: FontWeight.w500,
                            color: _valid ? AppColors.bg : AppColors.fg4)),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
