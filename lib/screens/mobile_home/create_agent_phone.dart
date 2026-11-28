import 'package:flutter/material.dart';

import '../../agent_character.dart';
import '../../api.dart';
import '../../chat/signal_row.dart' show prettyModel, prettyProfile;
import '../../mobile_kit.dart';
import '../../models.dart';
import '../../tap_detector.dart';
import '../../theme.dart';

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
      if (mounted) {
        setState(() => _characters = r.characters.keys.take(12).toList());
      }
    }).catchError((_) {});
    widget.client.getConfig().then((c) {
      if (mounted) {
        setState(() => _profiles = {for (final p in c.profiles) p.name: p});
      }
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
    final pick = await showMkSheet<String>(
      context,
      title: 'Inference profile',
      builder: (ctx) => MkGroup(flush: true, children: [
        for (final k in _profiles.keys)
          MkGroupRow(
            icon: 'sliders',
            label: _profileLabel(k),
            chevron: false,
            onTap: () => Navigator.of(ctx).pop(k),
          ),
      ]),
    );
    if (pick != null && mounted) setState(() => _profile = pick);
  }

  Widget _box({required Widget child}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(16)),
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
      child: MkPage(
        title: 'New agent',
        onBack: () => Navigator.of(context).pop(),
        bottomClearance: false,
        slivers: [
          SliverList(
            delegate: SliverChildListDelegate([
              const MkSection('Name'),
              _text(_name, 'Name'),
              const MkSection('Role'),
              _text(_role, 'What it is for'),
              MkGroup(header: 'Model', children: [
                MkGroupRow(
                  icon: 'sliders',
                  label: 'Inference profile',
                  value: pk == null ? 'Default' : _profileLabel(pk),
                  onTap: _profiles.isEmpty ? null : _pickProfile,
                ),
              ]),
              const MkSection('Appearance'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
                                        ? Border.all(
                                            color: AppColors.fg2, width: 2)
                                        : null),
                                child: ClipOval(
                                    child: AgentCharacter(id,
                                        size: 40, staggerKey: id)),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]);
                }),
              ),
              MkGroup(header: 'Contact', children: [
                MkGroupRow(
                  icon: 'clock',
                  label: 'Wake on schedule',
                  chevron: false,
                  trailing: MkToggle(
                      value: _wake,
                      label: 'Wake on schedule',
                      onChanged: (v) => setState(() => _wake = v)),
                ),
                MkGroupRow(
                  icon: 'phone',
                  label: 'Reach me on phone',
                  chevron: false,
                  trailing: MkToggle(
                      value: _reach,
                      label: 'Reach me on phone',
                      onChanged: (v) => setState(() => _reach = v)),
                ),
              ]),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
                  child: Text(_error!, style: sans(13, color: AppColors.fg2)),
                ),
              if (!_valid)
                Padding(
                    padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
                    child: Text('Add a name',
                        style: sans(13, color: AppColors.fg3))),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: MkPill(_busy ? 'Creating' : 'Create',
                    key: const ValueKey('create-button'),
                    expand: true,
                    tone: MkPillTone.primary,
                    onTap: _valid ? _create : null),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
