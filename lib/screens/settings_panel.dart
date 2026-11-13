import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api.dart';
import '../models.dart';
import '../notifications.dart';
import '../panel.dart';
import '../platform.dart';
import '../settings_form.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'add_instance.dart';
import 'inference_profiles.dart';
import 'recurring.dart';
import 'routing_screen.dart';
import 'shell_nav.dart';
import 'usage.dart';
import 'vault.dart';
import 'voice_screen.dart';
import 'web_search_screen.dart';
import 'accounts_screen.dart';
import '../motion.dart';
import '../window_background.dart';
import 'dart:io' show File;
import 'package:file_picker/file_picker.dart';
import '../desktop_layout.dart';
import '../wake_models.dart';
import 'memory_screen.dart';
import 'wakes_screen.dart';

/// Rows for the machine popover/sheet: live dot (re-pinged on open), label,
/// host, trailing overflow. Pops itself before invoking any callback.
class MachineList extends StatefulWidget {
  final List<Instance> instances;
  final Instance? active;
  final Map<String, bool> health;
  final void Function(Instance) onSelect;
  final VoidCallback onAdd;
  final void Function(Instance) onManage;
  final bool switchOnly;

  const MachineList({
    super.key,
    required this.instances,
    required this.active,
    required this.health,
    required this.onSelect,
    required this.onAdd,
    required this.onManage,
    this.switchOnly = false,
  });

  @override
  State<MachineList> createState() => _MachineListState();
}

class _MachineListState extends State<MachineList> {
  late final Map<String, bool> _h = {...widget.health};

  @override
  void initState() {
    super.initState();
    for (final i in widget.instances) {
      DaemonClient(i.url, i.token).health().then((ok) {
        if (mounted && _h[i.url] != ok) setState(() => _h[i.url] = ok);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    if (kMobile) {
      return ListGroup(children: [...widget.instances.map(_row), _addRow()]);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...widget.instances.map(_row),
        if (!widget.switchOnly) ...[
          Divider(height: 13, thickness: 1, color: AppColors.border),
          _addRow(),
        ],
      ],
    );
  }

  Widget _row(Instance i) {
    final selected = i.url == widget.active?.url;
    final ok = _h[i.url];
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        widget.onSelect(i);
      },
      onLongPress: widget.switchOnly
          ? null
          : () {
              Navigator.pop(context);
              widget.onManage(i);
            },
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            S.s12, kMobile ? S.s8 : S.s6, S.s2, kMobile ? S.s8 : S.s6),
        child: Row(children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: ok == true ? AppColors.ok : AppColors.fg4,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: kMobile
                      ? TS.rowTitle(AppColors.fg1)
                      : TS.ui(AppColors.fg1)),
              const SizedBox(height: S.s2),
              Text(hostOf(i.url),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TS.codeSmall(AppColors.fg3)),
            ]),
          ),
          if (selected) AppIcon('check', size: 16, color: AppColors.accent),
          if (!widget.switchOnly)
            IconBtn('more-vertical', size: 32, iconSize: 16, tooltip: 'Manage',
                onTap: () {
              Navigator.pop(context);
              widget.onManage(i);
            }),
        ]),
      ),
    );
  }

  Widget _addRow() {
    return Pressable(
      child: InkWell(
        onTap: () {
          Navigator.pop(context);
          widget.onAdd();
        },
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              S.s12, kMobile ? 14 : 8, S.s12, kMobile ? 14 : 8),
          child: Row(children: [
            SizedBox(
              width: kMobile ? 8 : 16,
              height: 16,
              child: OverflowBox(
                maxWidth: 16,
                maxHeight: 16,
                child: AppIcon('plus', size: 16, color: AppColors.accent),
              ),
            ),
            const SizedBox(width: 10),
            Text('Add machine', style: TS.label(AppColors.accent)),
          ]),
        ),
      ),
    );
  }
}

enum SettingsPage {
  general,
  appearance,
  models,
  routing,
  memory,
  usage,
  vault,
  scheduled,
  wakes,
  voice,
  webSearch,
  accounts,
}

/// Settings dialog: Zed-style sidebar + content pane. Models / vault /
/// scheduled swap in-place so they never stack a second dialog.
class SettingsPanel extends StatefulWidget {
  final DaemonClient client;
  final List<Instance> instances;
  final Instance? active;
  final void Function(Instance) onRemove;
  final void Function(Instance, String)? onRename;
  final void Function(Instance)? onSelect;
  final void Function(Instance)? onAdd;
  final VoidCallback onClose;

  /// True when hosted INSIDE the phone home under the floating bar, rather than
  /// presented as its own dialog/drawer.
  final bool embedded;

  /// Phone drill-down. Null shows the section list; a value shows that section.
  ///
  /// Owned by the SHELL, not by this widget: the back handler and the bar's
  /// visibility both need to read it, and neither can see inside here.
  final SettingsPage? section;
  final ValueChanged<SettingsPage?>? onSection;

  final SettingsPage? createOnOpen;
  final VoidCallback? onCreateHandled;
  final SettingsPage? initialPage;

  const SettingsPanel({
    super.key,
    required this.client,
    required this.instances,
    required this.active,
    required this.onRemove,
    this.onRename,
    this.onSelect,
    this.onAdd,
    required this.onClose,
    this.embedded = false,
    this.section,
    this.onSection,
    this.createOnOpen,
    this.onCreateHandled,
    this.initialPage,
  });

  @override
  State<SettingsPanel> createState() => SettingsPanelState();
}

class SettingsPanelState extends State<SettingsPanel> {
  late final List<Instance> _instances = [...widget.instances];

  Future<void> _saveInstances(
      void Function(List<Instance> items) change) async {
    final items = await _updateStoredInstances(change);
    if (!mounted) return;
    setState(() => _instances
      ..clear()
      ..addAll(items));
  }

  void _syncInstances(List<Instance> items) {
    if (!_instancesMatch(_instances, items)) {
      _instances
        ..clear()
        ..addAll(items);
    }
  }

  bool _notif = false;
  bool _notifBusy = false;
  final GlobalKey<VaultScreenState> _vaultKey = GlobalKey<VaultScreenState>();
  final GlobalKey<InferenceProfilesScreenState> _modelsKey =
      GlobalKey<InferenceProfilesScreenState>();
  final GlobalKey<RecurringScreenState> _recurringKey =
      GlobalKey<RecurringScreenState>();
  final GlobalKey<SettingsSectionViewState> _deskSectionKey =
      GlobalKey<SettingsSectionViewState>();

  bool _addingMachine = false;
  final TextEditingController _addMachinePaste = TextEditingController();
  bool _addMachineBusy = false;
  String? _addMachineError;

  // Phone home row values, fetched once and shown beside the chevrons.
  int? _profileCount;
  int? _vaultCount;
  int? _usageTokens;
  bool? _ambientOn;
  int? _liveCount;

  String? _renamingUrl;
  final TextEditingController _renameController = TextEditingController();

  late SettingsPage _page = widget.initialPage ?? SettingsPage.general;

  /// Phone drill-down, read from the shell. Desktop uses `_page` + the chip
  /// strip instead, so this is only consulted when `kMobile && embedded`.
  SettingsPage? get _mobileSection => widget.section;

  /// True when the last move through Settings went deeper, rather than back out
  /// of a section. Sets the slide direction between sections the same way the
  /// shell does between destinations. Captured from the PREVIOUS widget in
  /// `didUpdateWidget`, because that value is gone by the time `build` runs.
  bool _sectionForward = true;

  @override
  void didUpdateWidget(covariant SettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.section?.index ?? -1;
    final after = widget.section?.index ?? -1;
    if (before != after) _sectionForward = after > before;
    if (widget.createOnOpen != oldWidget.createOnOpen) _scheduleCreate();
    _syncInstances(widget.instances);
  }

  void _scheduleCreate() {
    final page = widget.createOnOpen;
    if (page == null) return;
    Future.delayed(Motion.base, () {
      if (!mounted || widget.createOnOpen != page) return;
      widget.onCreateHandled?.call();
      if (!kMobile) {
        _deskSectionKey.currentState?.triggerCreate(page);
        return;
      }
      switch (page) {
        case SettingsPage.general:
          _addMachine();
        case SettingsPage.models:
          _modelsKey.currentState?.addProfile();
        case SettingsPage.vault:
          _vaultKey.currentState?.add();
        case SettingsPage.scheduled:
          _recurringKey.currentState?.add();
        case SettingsPage.appearance:
        case SettingsPage.usage:
        case SettingsPage.wakes:
        case SettingsPage.memory:
        case SettingsPage.routing:
        case SettingsPage.voice:
        case SettingsPage.webSearch:
        case SettingsPage.accounts:
          break;
      }
    });
  }

  static const _nav = [
    (SettingsPage.general, 'server', 'General'),
    (SettingsPage.models, 'sparkles', 'Profiles'),
    (SettingsPage.routing, 'route', 'Routing'),
    (SettingsPage.accounts, 'users', 'Accounts'),
    (SettingsPage.usage, 'gauge', 'Usage'),
    (SettingsPage.memory, 'book-marked', 'Memory'),
    (SettingsPage.scheduled, 'calendar-clock', 'Scheduled'),
    (SettingsPage.wakes, 'repeat', 'Wakes'),
    (SettingsPage.vault, 'lock', 'Vault'),
    (SettingsPage.voice, 'mic', 'Voice'),
    (SettingsPage.webSearch, 'globe', 'Web search'),
    (SettingsPage.appearance, 'sliders', 'Appearance'),
  ];

  static const _navGroups = {
    SettingsPage.general: 'Connection',
    SettingsPage.models: 'Models',
    SettingsPage.memory: 'Agents',
    SettingsPage.appearance: 'Appearance',
  };

  @override
  void initState() {
    super.initState();
    _addMachinePaste.addListener(() => setState(() {}));
    notificationsEnabled().then((v) {
      if (mounted) setState(() => _notif = v);
    });
    _scheduleCreate();
    _loadMobileValues();
    modelsRevision.addListener(_onModelsChanged);
  }

  void _onModelsChanged() => _loadMobileValues();

  @override
  void dispose() {
    modelsRevision.removeListener(_onModelsChanged);
    _addMachinePaste.dispose();
    _renameController.dispose();
    super.dispose();
  }

  Future<void> _loadMobileValues() async {
    final client = widget.client;
    try {
      final cfg = await client.getConfig();
      if (mounted) setState(() => _profileCount = cfg.profiles.length);
    } catch (_) {}
    try {
      final names = await client.vaultList();
      if (mounted) setState(() => _vaultCount = names.length);
    } catch (_) {}
    try {
      final week =
          await client.getUsage(since: DateTime.now().subtract(const Duration(days: 7)));
      if (mounted) {
        setState(() =>
            _usageTokens = week.providers.fold<int>(0, (n, p) => n + p.totalTokens));
      }
    } catch (_) {}
    try {
      final ambient = await client.getAmbientSettings();
      if (mounted) setState(() => _ambientOn = ambient.enabled);
    } catch (_) {}
    try {
      final sessions = await client.sessions();
      if (mounted) {
        setState(() => _liveCount = sessions
            .where((s) =>
                !s.settled &&
                s.status != 'waiting_for_input' &&
                sessionIsActive(s.status))
            .length);
      }
    } catch (_) {}
  }

  Future<void> _toggleNotif(bool v) async {
    setState(() => _notifBusy = true);
    final err = await setNotificationsEnabled(v);
    if (!mounted) return;
    setState(() {
      _notifBusy = false;
      _notif = err == null ? v : _notif;
    });
    if (err != null) toast(context, err);
  }

  Future<void> _confirmRemove(Instance inst) async {
    if (!await _confirmRemoveInstance(context, inst)) return;
    widget.onRemove(inst);
    if (mounted) {
      setState(() => _instances.removeWhere((e) => e.url == inst.url));
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    // Phone + embedded in the home: open INLINE, not behind a drill-down.
    final drill = kMobile && widget.embedded;
    if (drill) {
      return Material(
        // Same surface as the other phone destinations (chats, agents). This was
        // `surface1`, one step lighter, which made Settings read as a different
        // app the moment you tapped into it.
        color: AppColors.bg,
        child: CardGroupScope(
          child: SafeArea(
            bottom: false,
            child: AnimatedSwitcher(
              duration: Motion.base,
              reverseDuration: Motion.fast,
              switchInCurve: Motion.enter,
              switchOutCurve: Motion.exit,
              // `StackFit.expand`, not the default centered `Stack`: these are
              // full-body screens, and loose constraints would let each one
              // shrink-wrap into the middle of the transition.
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                children: [...previous, if (current != null) current],
              ),
              transitionBuilder: (child, anim) {
                final dx = _sectionForward ? 0.06 : -0.06;
                return FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position:
                        Tween<Offset>(begin: Offset(dx, 0), end: Offset.zero)
                            .animate(anim),
                    child: child,
                  ),
                );
              },
              // Keyed so entering a section and leaving it are two different
              // children — the switcher only animates a genuine change of screen.
              child: KeyedSubtree(
                key: ValueKey(_mobileSection?.name ?? 'home'),
                child: _mobileSection == null
                    ? _mobileSettingsHome()
                    : _mobileSectionPage(),
              ),
            ),
          ),
        ),
      );
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: AppColors.paneBg,
          child: LayoutBuilder(builder: (context, c) {
            if (c.maxWidth >= 560) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 210,
                    decoration: BoxDecoration(
                      color: AppColors.tint1,
                      border: Border(right: BorderSide(color: AppColors.line)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          height: 56,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          alignment: Alignment.centerLeft,
                          child: Text('Settings',
                              style: sans(15,
                                  weight: W.strong, color: AppColors.fg1)),
                        ),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                            children: [
                              for (final (page, icon, label) in _nav) ...[
                                if (_navGroups[page] != null)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        10, 14, 10, 4),
                                    child: Text(_navGroups[page]!.toUpperCase(),
                                        style: TS.overline()),
                                  ),
                                _settingsNavRow(page, icon, label),
                              ],
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 10, 16, 16),
                          child: Row(children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: AppColors.ok,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.active?.label.isNotEmpty == true
                                    ? widget.active!.label
                                    : 'Connected',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TS.caption(),
                              ),
                            ),
                          ]),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: _desktopContent()),
                ],
              );
            }
            return Column(children: [
              Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.tint1,
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(children: [
                  Text('Settings', style: TS.label(AppColors.fg1)),
                ]),
              ),
              SizedBox(height: 44, child: _navChips()),
              Divider(height: 1, color: AppColors.border),
              Expanded(child: _desktopContent()),
            ]);
          }),
        ),
      ),
    );
  }

  /// Phone settings HOME.
  ///
  /// The 32px rounded tile every settings row leads with (v5 `.pgi .ico`).
  Widget _settingsIconTile(String icon, {Color? color}) => Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: AppColors.tint2,
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: Center(
          child: AppIcon(icon, size: 16, color: color ?? AppColors.fg2),
        ),
      );

  /// One v5 settings row: icon tile, label, optional right-hand value, chevron.
  Widget _settingsRow(
    String label,
    String icon, {
    String? value,
    SettingsPage? page,
  }) =>
      _V5SettingsRow(
        label: label,
        leading: _settingsIconTile(icon),
        value: value,
        onTap: page == null ? null : () => widget.onSection?.call(page),
      );

  /// v5 `.plb`: a quiet 13px group caption, indented past the card edge.
  Widget _settingsGroupLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(S.s16, S.s16, 0, S.s4),
        child: Text(text, style: sans(13, color: AppColors.fg3)),
      );

  Widget _mobileSettingsHome() {
    final active = widget.active;
    final tm = ThemeManager.instance;
    final name = active?.label.trim() ?? '';
    final live = _liveCount;
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, S.s40),
      children: [
        ListGroup(children: [
          _V5SettingsRow(
            label: name.isEmpty ? 'No machine yet' : name,
            subtitle: active == null
                ? 'Add one to begin'
                : 'Connected${live == null ? '' : ' · $live live'}',
            leading: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.tint2,
                borderRadius: BorderRadius.circular(R.md),
              ),
              child: Center(
                child: Icon(LucideIcons.laptop,
                    size: 17, color: AppColors.ok),
              ),
            ),
            onTap: () => widget.onSection?.call(SettingsPage.general),
          ),
        ]),
        _settingsGroupLabel('General'),
        ListGroup(children: [
          _settingsRow('Inference profiles', 'cpu',
              page: SettingsPage.models,
              value: _profileCount?.toString()),
          _settingsRow('Routing', 'route', page: SettingsPage.routing),
          _settingsRow('Accounts', 'users', page: SettingsPage.accounts),
          _settingsRow('Usage', 'gauge',
              page: SettingsPage.usage,
              value: _usageTokens == null
                  ? null
                  : '${fmtSi(_usageTokens!)} this week'),
          ApprovalsRow(client: widget.client),
          if (kCanNotify) _notifRow(),
        ]),
        _settingsGroupLabel('Agents'),
        ListGroup(children: [
          _settingsRow('Memory', 'book-marked', page: SettingsPage.memory),
          _settingsRow('Vault', 'lock',
              page: SettingsPage.vault,
              value: _vaultCount?.toString()),
          _settingsRow('Wakes', 'repeat', page: SettingsPage.wakes),
          _settingsRow('Voice', 'mic',
              page: SettingsPage.voice,
              value: _ambientOn == null
                  ? null
                  : _ambientOn!
                      ? 'Listening'
                      : 'Off'),
          _settingsRow('Scheduled', 'calendar-clock',
              page: SettingsPage.scheduled),
          _settingsRow('Web search', 'globe', page: SettingsPage.webSearch),
        ]),
        _settingsGroupLabel('Appearance'),
        ListenableBuilder(
          listenable: ThemeManager.instance,
          builder: (context, _) {
            final accent = tm.customAccent;
            return ListGroup(children: [
              _settingsRow(
                'Theme and accent',
                'sliders',
                page: SettingsPage.appearance,
                value: accent == null
                    ? tm.baseTheme.label
                    : '${tm.baseTheme.label} · ${accent.name}',
              ),
            ]);
          },
        ),
      ],
    );
  }

  /// One phone settings section.
  Widget _mobileSectionPage() {
    final section = _mobileSection!;
    void back() => widget.onSection?.call(null);
    return switch (section) {
      SettingsPage.general => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsHeader(
              title: 'Machines',
              compact: true,
              onBack: back,
              actions: [
                IconBtn('plus',
                    size: 40,
                    iconSize: 18,
                    tooltip: 'Add machine',
                    onTap: _addMachine),
              ],
            ),
            Expanded(child: _generalPage(includeNotifications: false)),
          ],
        ),
      SettingsPage.appearance => AppearanceScreen(
          embedded: true,
          onBack: back,
        ),
      SettingsPage.models => InferenceProfilesScreen(
          client: widget.client,
          embedded: true,
          onBack: back,
        ),
      SettingsPage.routing => RoutingScreen(
          client: widget.client,
          embedded: true,
          onBack: back,
        ),
      SettingsPage.voice => VoiceScreen(
          client: widget.client,
          embedded: true,
          onBack: back,
        ),
      SettingsPage.webSearch => WebSearchScreen(
          client: widget.client,
          embedded: true,
          onBack: back,
        ),
      SettingsPage.accounts => AccountsScreen(
          client: widget.client,
          embedded: true,
          onBack: back,
        ),
      SettingsPage.memory => MemoryScreen(
          client: widget.client,
          embedded: true,
          onBack: back,
        ),
      SettingsPage.usage => UsageScreen(
          client: widget.client,
          embedded: true,
          onBack: back,
        ),
      SettingsPage.vault => VaultScreen(
          client: widget.client,
          embedded: true,
          onBack: back,
        ),
      SettingsPage.scheduled => RecurringScreen(
          client: widget.client,
          listOnly: true,
          embedded: true,
          onBack: back,
        ),
      SettingsPage.wakes => WakesScreen(
          client: widget.client,
          embedded: true,
          onBack: back,
        ),
    };
  }

  void _addMachine() {
    if (kMobile && widget.embedded) {
      showModal<Instance>(
        context,
        const AddInstanceScreen(),
      ).then((inst) {
        if (inst != null && mounted) {
          _saveInstances((items) => items
            ..removeWhere((e) => e.url == inst.url || e.token == inst.token)
            ..add(inst));
          widget.onAdd?.call(inst);
        }
      });
      return;
    }
    setState(() {
      _addingMachine = true;
      _addMachineError = null;
      _addMachinePaste.clear();
    });
  }

  Future<void> _submitAddMachine() async {
    final raw = _addMachinePaste.text.trim();
    if (raw.isEmpty || _addMachineBusy) return;
    setState(() {
      _addMachineBusy = true;
      _addMachineError = null;
    });
    try {
      final inst = await _connectMachineFromLink(raw);
      if (!mounted) return;
      setState(() {
        _addMachineBusy = false;
        _addingMachine = false;
        _addMachinePaste.clear();
      });
      await _saveInstances((items) => items
        ..removeWhere((e) => e.url == inst.url || e.token == inst.token)
        ..add(inst));
      widget.onAdd?.call(inst);
    } catch (e) {
      if (mounted) {
        setState(() {
          _addMachineBusy = false;
          _addMachineError = 'Connection failed: $e';
        });
      }
    }
  }

  void _startRename(Instance i) {
    setState(() {
      _renamingUrl = i.url;
      _renameController.text = i.label;
    });
  }

  Future<void> _commitRename(Instance inst) async {
    final newName = _renameController.text.trim();
    setState(() => _renamingUrl = null);
    if (newName.isEmpty) return;
    await _saveInstances((items) => _renameStoredInstance(items, inst, newName));
    widget.onRename?.call(inst, newName);
  }

  void _selectInstance(Instance i) {
    widget.onSelect?.call(i);
  }

  /// One row in the desktop settings rail.
  Widget _settingsNavRow(SettingsPage page, String icon, String label) {
    final selected = _page == page;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? AppColors.tint2 : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () {
            setState(() => _page = page);
            _deskSectionKey.currentState?.resetTransient();
          },
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [
              AppIcon(icon,
                  size: 15, color: selected ? AppColors.accent : AppColors.fg3),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13,
                        color: selected ? AppColors.fg1 : AppColors.fg2)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _navChips() {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      children: [
        for (final (page, icon, label) in _nav)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Material(
              color: _page == page
                  ? (kMobile ? AppColors.surface3 : AppColors.tint2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(R.sm),
              child: InkWell(
                onTap: () {
                  setState(() => _page = page);
                  _deskSectionKey.currentState?.resetTransient();
                },
                borderRadius: BorderRadius.circular(R.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: S.s12, vertical: S.s6),
                  child: Row(children: [
                    AppIcon(icon,
                        size: 14,
                        color: _page == page ? AppColors.fg1 : AppColors.fg3),
                    const SizedBox(width: S.s6),
                    Text(label,
                        style: sans(13,
                            weight: _page == page ? W.label : W.body,
                            color:
                                _page == page ? AppColors.fg1 : AppColors.fg2)),
                  ]),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _desktopContent() {
    return SettingsSectionView(
      key: _deskSectionKey,
      client: widget.client,
      instances: _instances,
      active: widget.active,
      page: _page,
      onRemove: (inst) {
        widget.onRemove(inst);
        if (mounted) {
          setState(() => _instances.removeWhere((e) => e.url == inst.url));
        }
      },
      onRename: widget.onRename,
      onSelect: widget.onSelect,
      onAdd: widget.onAdd,
      onSelectPage: (page) => setState(() => _page = page),
    );
  }

  Widget _machineMenu(Instance i, {bool connect = false}) => Builder(
        builder: (anchor) => IconBtn('more-horizontal',
            size: kMobile ? M.minTarget : 28,
            iconSize: 16,
            tooltip: 'Machine actions',
            onTap: () => _showMachineMenu(
                  context,
                  anchor: anchor,
                  instance: i,
                  connect: connect,
                  onSelect: () => _selectInstance(i),
                  onRename: () => _startRename(i),
                  onRemove: () => _confirmRemove(i),
                )),
      );

  Widget _generalPage({bool includeNotifications = true}) {
    if (_addingMachine) return _addMachinePane();
    return PageBody(children: [
      if (includeNotifications)
        const SectionLabel('Machines'),
      if (_instances.isEmpty)
        EmptyState(
          icon: 'server',
          title: 'No saved machines',
          body: 'Connect to a machine running snippet serve.',
          action: HeaderAction('Add machine', onTap: _addMachine),
        )
      else
        ListGroup(children: [for (final i in _instances) _instanceRow(i)]),
      if (includeNotifications) ...[
        const SizedBox(height: S.s24),
        const SectionLabel('Approvals'),
        ListGroup(children: [ApprovalsRow(client: widget.client)]),
      ],
      if (includeNotifications && kCanNotify) ...[
        const SizedBox(height: S.s24),
        const SectionLabel('Notifications'),
        ListGroup(children: [_notifRow()]),
      ],
    ]);
  }

  Widget _addMachinePane() {
    void back() => setState(() {
          _addingMachine = false;
          _addMachineError = null;
        });
    final canConnect =
        !_addMachineBusy && _addMachinePaste.text.trim().isNotEmpty;
    return PageBody(
      topPadding: 18,
      children: [
        Row(children: [
          IconBtn('chevron-left',
              size: 28, iconSize: 15, tooltip: 'Back', onTap: back),
          const SizedBox(width: 6),
          Text('Connect a machine',
              style: sans(17,
                  weight: FontWeight.w500,
                  spacing: -0.2,
                  color: AppColors.fg1)),
        ]),
        const SizedBox(height: 22),
        SettingsGroup(
          header: 'On the other machine',
          footer: 'It prints a link and a QR code. If snippet is already '
              'running there, snippet serve --status shows them again.',
          children: [
            SettingsRow(
              label: 'snippet serve --enable',
              labelWidget: SelectableText('snippet serve --enable',
                  style: mono(13, color: AppColors.fg1)),
              trailing: IconBtn('copy',
                  size: 26, iconSize: 13, tooltip: 'Copy command', onTap: () {
                Clipboard.setData(const ClipboardData(text: 'snippet serve --enable'));
                toast(context, 'Copied');
              }),
            ),
          ],
        ),
        SettingsGroup(
          header: 'Here',
          children: [
            SettingsRow(
              label: 'Link',
              trailing: SettingsField(
                controller: _addMachinePaste,
                hint: 'https://…?token=…',
                mono: true,
                width: 380,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          if (_addMachineError != null)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 4, right: 12),
                child: Text(_addMachineError!,
                    style: sans(12, height: 1.4, color: AppColors.danger)),
              ),
            ),
          SettingsPill('Cancel', onTap: _addMachineBusy ? null : back),
          const SizedBox(width: 8),
          SettingsPill(_addMachineBusy ? 'Connecting…' : 'Connect',
              onTap: canConnect ? _submitAddMachine : null),
        ]),
      ],
    );
  }

  Widget _instanceRow(Instance i) {
    final isActive = i.url == widget.active?.url;
    final isRenaming = _renamingUrl == i.url;
    final compact = kMobile && widget.embedded;
    final canConnect = !isActive && widget.onSelect != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: compact && canConnect && !isRenaming
            ? () => _selectInstance(i)
            : null,
        child: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 14 : S.s12, S.s8, S.s4, S.s8),
        child: Row(
          children: [
            if (compact)
              V5IconTile('server',
                  color: isActive ? AppColors.ok : AppColors.fg2)
            else
              IconTile('server', tone: isActive ? Tone.ok : Tone.neutral),
            const SizedBox(width: S.s12),
            if (isRenaming) ...[
              Expanded(
                child: InlineEditField(
                  controller: _renameController,
                  hint: 'Machine name',
                  commitOnTapOutside: false,
                  showActions: true,
                  onSubmit: () => _commitRename(i),
                  onCancel: () => setState(() => _renamingUrl = null),
                ),
              ),
            ] else ...[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TS.rowTitle()),
                    const SizedBox(height: S.s2),
                    Text(hostOf(i.url),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TS.codeSmall()),
                  ],
                ),
              ),
              const SizedBox(width: S.s8),
              if (compact) ...[
                if (isActive)
                  AppIcon('check', size: 16, color: AppColors.accent),
                _machineMenu(i, connect: canConnect),
              ] else ...[
                if (isActive)
                  const Tag('Active', tone: Tone.ok, dot: true)
                else if (canConnect)
                  TextAction('Connect', onTap: () => _selectInstance(i)),
                const SizedBox(width: S.s4),
                IconBtn('edit',
                    size: 30,
                    iconSize: 16,
                    tooltip: 'Rename machine',
                    onTap: () => _startRename(i)),
                IconBtn('trash',
                    size: 30,
                    iconSize: 16,
                    tooltip: 'Remove machine',
                    onTap: () => _confirmRemove(i)),
              ],
            ],
          ],
        ),
      ),
      ),
    );
  }

  Widget _notifRow() {
    if (kMobile) {
      return _V5SettingsRow(
        label: 'Notifications',
        subtitle: 'When a chat needs you or finishes',
        leading: _settingsIconTile('bell'),
        onTap: _notifBusy ? null : () => _toggleNotif(!_notif),
        trailing: _notifBusy
            ? const DelayedSpinner(size: 18)
            : AppSwitch(on: _notif, onChanged: _toggleNotif),
      );
    }
    return Padding(
      padding: kMobile
          ? const EdgeInsets.fromLTRB(16, 14, 16, 14)
          : const EdgeInsets.fromLTRB(S.s12, S.s12, S.s12, S.s12),
      child: Row(children: [
        if (!kMobile) ...[
          const IconTile('bell'),
          const SizedBox(width: S.s12),
        ] else ...[
          AppIcon('bell', size: 19, color: AppColors.fg3),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(kMobile ? 'Notifications' : 'Session notifications',
                  style: TS.rowTitle()),
              const SizedBox(height: S.s2),
              Text(
                  kMobile
                      ? 'When a chat needs you or finishes'
                      : 'When a session finishes or needs your input',
                  style: TS.meta()),
            ],
          ),
        ),
        const SizedBox(width: S.s8),
        if (_notifBusy)
          const DelayedSpinner(size: 18)
        else
          AppSwitch(on: _notif, onChanged: _toggleNotif),
      ]),
    );
  }
}

bool _instancesMatch(List<Instance> a, List<Instance> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].url != b[i].url || a[i].label != b[i].label) return false;
  }
  return true;
}

Future<List<Instance>> _updateStoredInstances(
    void Function(List<Instance> items) change) async {
  final items = await InstanceStore().load();
  change(items);
  await InstanceStore().save(items);
  return items;
}

Future<Instance> _connectMachineFromLink(String raw) async {
  final parsed = parseConnection(raw);
  if (parsed == null) {
    throw 'That is not a valid link. Run "snippet serve --enable" on the other machine, then "snippet serve --status", and paste the link it prints.';
  }
  final (url, token) = parsed;
  final cfg = await DaemonClient(url, token).getConfig();
  final name = cfg.hostname.isNotEmpty ? cfg.hostname : hostOf(url);
  return Instance(name: name, url: url, token: token);
}

void _renameStoredInstance(
    List<Instance> items, Instance inst, String newName) {
  final idx = items.indexWhere((e) => e.url == inst.url);
  if (idx >= 0) {
    items[idx] = Instance(name: newName, url: inst.url, token: inst.token);
  }
}

Future<bool> _confirmRemoveInstance(BuildContext context, Instance inst) =>
    confirmAction(
      context,
      title: 'Remove instance?',
      body:
          '${inst.label}\n\nRemoves the saved connection from this app. The machine and its sessions are untouched.',
      confirmLabel: 'Remove',
    );

Future<void> _showMachineMenu(
  BuildContext context, {
  required BuildContext anchor,
  required Instance instance,
  required bool connect,
  required VoidCallback onSelect,
  required VoidCallback onRename,
  required VoidCallback onRemove,
}) async {
  final picked = await showAppMenu<String>(context,
      anchor: anchor,
      below: true,
      alignEnd: true,
      minWidth: 160,
      items: [
        if (connect) appMenuItem(value: 'connect', label: 'Connect'),
        appMenuItem(value: 'rename', label: 'Rename'),
        appMenuItem(value: 'remove', label: 'Remove', danger: true),
      ]);
  if (picked == 'connect') onSelect();
  if (picked == 'rename') onRename();
  if (picked == 'remove') onRemove();
}

Future<bool?> _showApprovalsMenu(
  BuildContext context,
  BuildContext anchor,
  bool current,
) =>
    showAppMenu<bool>(
      context,
      anchor: anchor,
      minWidth: 260,
      maxWidth: 320,
      items: [
        appMenuRow(
          value: false,
          icon: 'check-circle',
          label: 'Yolo',
          description: 'Run shell and file edits without asking',
          selected: !current,
        ),
        appMenuRow(
          value: true,
          icon: 'shield',
          label: 'Ask',
          description: 'Pause for approval on each change',
          selected: current,
        ),
      ],
    );

/// Shared desktop settings section content used by both [SettingsPanel]
/// and `DesktopSettingsPage`.
class SettingsSectionView extends StatefulWidget {
  const SettingsSectionView({
    super.key,
    required this.client,
    required this.instances,
    required this.active,
    required this.page,
    required this.onRemove,
    this.onRename,
    this.onSelect,
    this.onAdd,
    this.onSelectPage,
    this.onBack,
    this.v5Desktop = false,
  });

  final DaemonClient client;
  final List<Instance> instances;
  final Instance? active;
  final SettingsPage page;
  final void Function(Instance) onRemove;
  final void Function(Instance, String)? onRename;
  final void Function(Instance)? onSelect;
  final void Function(Instance)? onAdd;
  final ValueChanged<SettingsPage>? onSelectPage;
  final VoidCallback? onBack;
  final bool v5Desktop;

  @override
  State<SettingsSectionView> createState() => SettingsSectionViewState();
}

class SettingsSectionViewState extends State<SettingsSectionView> {
  late final List<Instance> _instances = [...widget.instances];
  final GlobalKey<VaultScreenState> _vaultKey = GlobalKey<VaultScreenState>();
  final GlobalKey<InferenceProfilesScreenState> _modelsKey =
      GlobalKey<InferenceProfilesScreenState>();
  final GlobalKey<RecurringScreenState> _recurringKey =
      GlobalKey<RecurringScreenState>();

  bool _addingMachine = false;
  final TextEditingController _addMachinePaste = TextEditingController();
  bool _addMachineBusy = false;
  String? _addMachineError;

  bool _modelsEditing = false;
  bool _vaultAdding = false;
  bool _recurringAdding = false;

  String? _renamingUrl;
  final TextEditingController _renameController = TextEditingController();

  bool? _manual;
  bool _notif = false;
  bool _notifBusy = false;
  final Map<String, bool> _health = {};
  int? _liveCount;
  int? _warmActiveCount;

  static const _plainPages = {
    SettingsPage.general,
    SettingsPage.appearance,
    SettingsPage.routing,
    SettingsPage.usage,
    SettingsPage.voice,
    SettingsPage.webSearch,
  };

  @override
  void initState() {
    super.initState();
    _addMachinePaste.addListener(() => setState(() {}));
    if (kCanNotify) {
      notificationsEnabled().then((v) {
        if (mounted) setState(() => _notif = v);
      });
    }
    if (widget.page == SettingsPage.general) _loadGeneral();
  }

  @override
  void didUpdateWidget(covariant SettingsSectionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncInstances(widget.instances);
    final pageChanged = widget.page != oldWidget.page;
    if (pageChanged) resetTransient();
    final clientChanged = widget.client != oldWidget.client ||
        widget.active?.url != oldWidget.active?.url;
    if (widget.page == SettingsPage.general && (pageChanged || clientChanged)) {
      _loadGeneral();
    }
  }

  @override
  void dispose() {
    _addMachinePaste.dispose();
    _renameController.dispose();
    super.dispose();
  }

  void resetTransient() {
    if (!_addingMachine &&
        _addMachineError == null &&
        !_modelsEditing &&
        !_vaultAdding &&
        !_recurringAdding &&
        _renamingUrl == null) {
      return;
    }
    setState(() {
      _addingMachine = false;
      _addMachineError = null;
      _modelsEditing = false;
      _vaultAdding = false;
      _recurringAdding = false;
      _renamingUrl = null;
    });
  }

  void triggerCreate(SettingsPage page) {
    switch (page) {
      case SettingsPage.general:
        _addMachine();
      case SettingsPage.models:
        _modelsKey.currentState?.addProfile();
      case SettingsPage.vault:
        _vaultKey.currentState?.add();
      case SettingsPage.scheduled:
        _recurringKey.currentState?.add();
      case SettingsPage.appearance:
      case SettingsPage.usage:
      case SettingsPage.wakes:
      case SettingsPage.memory:
      case SettingsPage.routing:
      case SettingsPage.voice:
      case SettingsPage.webSearch:
      case SettingsPage.accounts:
        break;
    }
  }

  void _syncInstances(List<Instance> items) {
    if (!_instancesMatch(_instances, items)) {
      _instances
        ..clear()
        ..addAll(items);
      if (widget.v5Desktop && widget.page == SettingsPage.general) {
        _pingMachines();
      }
    }
  }

  Future<void> _saveInstances(void Function(List<Instance> items) change) async {
    final items = await _updateStoredInstances(change);
    if (!mounted) return;
    setState(() => _instances
      ..clear()
      ..addAll(items));
  }

  void _loadGeneral() {
    _loadManual();
    if (!widget.v5Desktop) return;
    _pingMachines();
    _loadGeneralStats();
  }

  Future<void> _pingMachines() async {
    for (final i in _instances) {
      final isActive = i.url == widget.active?.url;
      final client =
          isActive ? widget.client : DaemonClient(i.url, i.token);
      client.health().then((ok) {
        if (mounted && _health[i.url] != ok) {
          setState(() => _health[i.url] = ok);
        }
      }).catchError((_) {
        if (mounted && _health[i.url] != false) {
          setState(() => _health[i.url] = false);
        }
      });
    }
  }

  Future<void> _loadGeneralStats() async {
    try {
      final sessions = await widget.client.sessions();
      if (mounted) {
        setState(() => _liveCount = sessions.where((s) => !s.settled).length);
      }
    } catch (_) {}
    try {
      final KeepWarmList warm = await widget.client.keepWarm();
      if (mounted) {
        setState(
            () => _warmActiveCount = warm.entries.where((e) => e.enabled).length);
      }
    } catch (_) {}
  }

  Future<void> _loadManual() async {
    try {
      final c = await widget.client.getConfig();
      if (mounted) setState(() => _manual = c.manualApproval);
    } catch (_) {}
  }

  Future<void> _setManual(bool on) async {
    final before = _manual;
    setState(() => _manual = on);
    try {
      await widget.client.setManualApproval(on);
    } catch (e) {
      if (!mounted) return;
      setState(() => _manual = before);
      toast(context, '$e', danger: true);
    }
  }

  Future<void> _toggleNotif(bool v) async {
    setState(() => _notifBusy = true);
    final err = await setNotificationsEnabled(v);
    if (!mounted) return;
    setState(() {
      _notifBusy = false;
      _notif = err == null ? v : _notif;
    });
    if (err != null) toast(context, err);
  }

  void _addMachine() => setState(() {
        _addingMachine = true;
        _addMachineError = null;
        _addMachinePaste.clear();
      });

  void _closeAddMachine() => setState(() {
        _addingMachine = false;
        _addMachineError = null;
      });

  Future<void> _submitAddMachine() async {
    final raw = _addMachinePaste.text.trim();
    if (raw.isEmpty || _addMachineBusy) return;
    setState(() {
      _addMachineBusy = true;
      _addMachineError = null;
    });
    try {
      final inst = await _connectMachineFromLink(raw);
      if (!mounted) return;
      setState(() {
        _addMachineBusy = false;
        _addingMachine = false;
        _addMachinePaste.clear();
      });
      await _saveInstances((items) => items
        ..removeWhere((e) => e.url == inst.url || e.token == inst.token)
        ..add(inst));
      widget.onAdd?.call(inst);
    } catch (e) {
      if (mounted) {
        setState(() {
          _addMachineBusy = false;
          _addMachineError = 'Connection failed: $e';
        });
      }
    }
  }

  void _startRename(Instance i) => setState(() {
        _renamingUrl = i.url;
        _renameController.text = i.label;
      });

  Future<void> _commitRename(Instance inst) async {
    final newName = _renameController.text.trim();
    setState(() => _renamingUrl = null);
    if (newName.isEmpty) return;
    await _saveInstances((items) => _renameStoredInstance(items, inst, newName));
    widget.onRename?.call(inst, newName);
  }

  Future<void> _confirmRemove(Instance inst) async {
    if (!await _confirmRemoveInstance(context, inst)) return;
    widget.onRemove(inst);
    if (mounted) {
      setState(() => _instances.removeWhere((e) => e.url == inst.url));
    }
  }

  Widget _machineMenu(Instance i, {bool connect = false}) => Builder(
        builder: (anchor) => IconBtn('more-horizontal',
            size: 28,
            iconSize: 16,
            tooltip: 'Machine actions',
            onTap: () => _showMachineMenu(
                  context,
                  anchor: anchor,
                  instance: i,
                  connect: connect,
                  onSelect: () => widget.onSelect?.call(i),
                  onRename: () => _startRename(i),
                  onRemove: () => _confirmRemove(i),
                )),
      );

  String _pageTitle(SettingsPage page) => switch (page) {
        SettingsPage.general => widget.v5Desktop ? 'Machines' : 'General',
        SettingsPage.appearance =>
          widget.v5Desktop ? 'Theme and accent' : 'Appearance',
        SettingsPage.models => 'Profiles',
        SettingsPage.routing => 'Routing',
        SettingsPage.memory => 'Memory',
        SettingsPage.usage => 'Usage',
        SettingsPage.vault => 'Vault',
        SettingsPage.scheduled => 'Scheduled',
        SettingsPage.wakes => 'Wakes',
        SettingsPage.voice => 'Voice',
        SettingsPage.webSearch => 'Web search',
        SettingsPage.accounts => 'Accounts',
      };

  String _pageSubtitle(SettingsPage page) => switch (page) {
        SettingsPage.general => widget.v5Desktop
            ? 'Computers this app can reach. Sessions run on the selected one.'
            : 'Machines this app connects to, and how sessions behave.',
        SettingsPage.appearance =>
          'Theme palette, accent colour, UI typeface and code font saved on this device.',
        SettingsPage.routing =>
          'Which model does each kind of work, and who steps in when it hits a limit.',
        SettingsPage.usage =>
          'Rate limits and token usage across your providers.',
        SettingsPage.voice => 'Voice notes, transcription and speech services.',
        SettingsPage.webSearch => 'Let agents search the web and read pages.',
        _ => '',
      };

  Widget? _pageAction(SettingsPage page) {
    if (widget.v5Desktop && page == SettingsPage.general) return null;
    return switch (page) {
      SettingsPage.general => _addingMachine
          ? null
          : HeaderAction('Add machine', onTap: _addMachine),
      SettingsPage.models => _modelsEditing
          ? null
          : HeaderAction('Add profile',
              onTap: () => _modelsKey.currentState?.addProfile()),
      SettingsPage.scheduled => _recurringAdding
          ? null
          : HeaderAction('New job',
              onTap: () => _recurringKey.currentState?.add()),
      _ => null,
    };
  }

  List<Widget> _addMachineBody() {
    final canConnect =
        !_addMachineBusy && _addMachinePaste.text.trim().isNotEmpty;
    return [
      SettingsGroup(
        header: 'On the other machine',
        footer: 'It prints a link and a QR code. If snippet is already '
            'running there, snippet serve --status shows them again.',
        children: [
          SettingsRow(
            label: 'snippet serve --enable',
            labelWidget: SelectableText('snippet serve --enable',
                style: mono(13, color: AppColors.fg1)),
            trailing: IconBtn('copy',
                size: 28, iconSize: 14, tooltip: 'Copy command', onTap: () {
              Clipboard.setData(
                  const ClipboardData(text: 'snippet serve --enable'));
              toast(context, 'Copied');
            }),
          ),
        ],
      ),
      SettingsGroup(
        header: 'Here',
        footer: _addMachineError,
        children: [
          SettingsRow(
            label: 'Link',
            sub: 'Paste the link it printed.',
            trailing: SettingsField(
              controller: _addMachinePaste,
              hint: 'https://…?token=…',
              mono: true,
              width: 320,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submitAddMachine(),
            ),
          ),
        ],
      ),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Btn('Cancel',
            variant: BtnVariant.secondary,
            onTap: _addMachineBusy ? null : _closeAddMachine),
        const SizedBox(width: S.s8),
        Btn(_addMachineBusy ? 'Connecting…' : 'Connect',
            disabled: !canConnect,
            onTap: canConnect ? _submitAddMachine : null),
      ]),
    ];
  }

  Widget _v5Card(List<Widget> children) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(Container(height: 1, color: AppColors.line));
      }
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.tint1,
        borderRadius: BorderRadius.circular(R.lg),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }

  Widget _v5Row({
    Widget? leading,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? titleColor,
  }) {
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(children: [
        if (leading != null) ...[leading, const SizedBox(width: 12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13,
                      weight: W.label, color: titleColor ?? AppColors.fg1)),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12, color: AppColors.fg4)),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing],
      ]),
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: body),
    );
  }

  Widget _v5MachineRow(Instance i) {
    final isActive = i.url == widget.active?.url;
    final connected = _health[i.url] ?? isActive;
    final iconColor = connected ? AppColors.ok : AppColors.fg4;
    if (_renamingUrl == i.url) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(children: [
          Icon(LucideIcons.laptop, size: 16, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: InlineEditField(
              controller: _renameController,
              hint: 'Machine name',
              commitOnTapOutside: false,
              showActions: true,
              onSubmit: () => _commitRename(i),
              onCancel: () => setState(() => _renamingUrl = null),
            ),
          ),
        ]),
      );
    }
    final live = _liveCount;
    final sub = isActive
        ? (live == null
            ? 'This machine'
            : 'This machine · $live live session${live == 1 ? '' : 's'}')
        : hostOf(i.url);
    return _v5Row(
      leading: Icon(LucideIcons.laptop, size: 16, color: iconColor),
      title: i.label.isEmpty ? hostOf(i.url) : i.label,
      subtitle: sub,
      onTap: !isActive && widget.onSelect != null
          ? () => widget.onSelect?.call(i)
          : null,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(connected ? 'Connected' : 'Offline',
            style: sans(13, color: AppColors.fg4)),
        const SizedBox(width: 6),
        _machineMenu(i, connect: !isActive && widget.onSelect != null),
      ]),
    );
  }

  List<Widget> _v5General() {
    if (_addingMachine) return _addMachineBody();
    final warmCount = _warmActiveCount;
    return [
      _v5Card([
        if (_instances.isEmpty)
          _v5Row(
            leading: Icon(LucideIcons.laptop, size: 16, color: AppColors.fg4),
            title: 'No saved machines',
            subtitle: 'Run snippet serve on one and add its link.',
          )
        else
          for (final i in _instances) _v5MachineRow(i),
        _v5Row(
          leading: AppIcon('plus', size: 16, color: AppColors.fg4),
          title: 'Add machine',
          titleColor: AppColors.fg2,
          onTap: _addMachine,
        ),
      ]),
      const SizedBox(height: S.s16),
      _v5Card([
        Builder(
          builder: (anchor) => _v5Row(
            title: 'Approvals',
            subtitle: 'Ask before running commands',
            onTap: () async {
              final current = _manual ?? false;
              final picked = await _showApprovalsMenu(context, anchor, current);
              if (picked != null && picked != current) {
                await _setManual(picked);
              }
            },
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_manual == null ? '' : (_manual! ? 'Ask' : 'Yolo'),
                  style: sans(13, color: AppColors.fg3)),
              const SizedBox(width: S.s6),
              AppIcon('chevron-down', size: 12, color: AppColors.fg3),
            ]),
          ),
        ),
        if (kCanNotify)
          _v5Row(
            title: 'Notifications',
            subtitle: 'Questions and finished tasks',
            onTap: _notifBusy ? null : () => _toggleNotif(!_notif),
            trailing: _notifBusy
                ? const DelayedSpinner(size: 18)
                : SettingsSwitch(
                    value: _notif,
                    onChanged: _notifBusy ? null : _toggleNotif),
          ),
        _v5Row(
          title: 'Keep sessions warm',
          subtitle: 'Hold the prompt cache while idle',
          onTap: widget.onSelectPage != null
              ? () => widget.onSelectPage!(SettingsPage.wakes)
              : null,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (warmCount != null) ...[
              Text(warmCount == 0 ? 'Off' : '$warmCount active',
                  style: sans(13, color: AppColors.fg3)),
              const SizedBox(width: S.s6),
            ],
            AppIcon('chevron-right', size: 14, color: AppColors.fg3),
          ]),
        ),
      ]),
    ];
  }

  Widget _machineRow(Instance i) {
    final isActive = i.url == widget.active?.url;
    if (_renamingUrl == i.url) {
      return SettingsRow(
        label: i.label,
        leading: _machineDot(isActive),
        labelWidget: InlineEditField(
          controller: _renameController,
          hint: 'Machine name',
          commitOnTapOutside: false,
          showActions: true,
          onSubmit: () => _commitRename(i),
          onCancel: () => setState(() => _renamingUrl = null),
        ),
      );
    }
    return SettingsRow(
      label: i.label.isEmpty ? hostOf(i.url) : i.label,
      sub: hostOf(i.url),
      leading: _machineDot(isActive),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (isActive)
          const Tag('Active', tone: Tone.ok, dot: true)
        else if (widget.onSelect != null)
          Btn('Connect',
              small: true,
              variant: BtnVariant.secondary,
              onTap: () => widget.onSelect?.call(i)),
        const SizedBox(width: S.s8),
        _machineMenu(i),
      ]),
    );
  }

  Widget _machineDot(bool active) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? AppColors.ok : AppColors.fg4,
        ),
      );

  List<Widget> _nativeGeneral() {
    if (widget.v5Desktop) return _v5General();
    return [
      if (_addingMachine)
        ..._addMachineBody()
      else ...[
        SettingsGroup(
          header: 'Machines',
          footer:
              'Snippet talks to the daemon on each machine. Run snippet serve on a new one and paste the link it prints.',
          children: [
            if (_instances.isEmpty)
              const SettingsRow(
                  label: 'No saved machines',
                  sub: 'Run snippet serve on one and add its link.')
            else
              for (final i in _instances) _machineRow(i),
          ],
        ),
        SettingsGroup(
          header: 'Sessions',
          children: [
            SettingsRow(
              label: 'Ask before running commands',
              sub:
                  'Off lets agents run shell commands and edit files without stopping to ask. Applies to every session on this machine.',
              trailing: SettingsSwitch(
                  value: _manual ?? false,
                  onChanged: _manual == null ? null : _setManual),
            ),
            if (kCanNotify)
              SettingsRow(
                label: 'Notifications',
                sub: 'When a session needs you or finishes.',
                trailing: SettingsSwitch(
                    value: _notif, onChanged: _notifBusy ? null : _toggleNotif),
              ),
          ],
        ),
      ],
    ];
  }

  List<Widget> _plainBody(SettingsPage page) => switch (page) {
        SettingsPage.general => _nativeGeneral(),
        SettingsPage.appearance => [
            const AppearanceScreen(embedded: true),
          ],
        SettingsPage.routing => [
            RoutingScreen(client: widget.client, embedded: true)
          ],
        SettingsPage.usage => [
            UsageScreen(client: widget.client, embedded: true)
          ],
        SettingsPage.voice => [
            VoiceScreen(client: widget.client, embedded: true)
          ],
        SettingsPage.webSearch => [
            WebSearchScreen(client: widget.client, embedded: true)
          ],
        _ => const [],
      };

  Widget? _mobilePageAction(SettingsPage page) => switch (page) {
        SettingsPage.general => _addingMachine
            ? null
            : IconBtn('plus',
                size: 40,
                iconSize: 18,
                tooltip: 'Add machine',
                onTap: _addMachine),
        SettingsPage.models => _modelsEditing
            ? null
            : IconBtn('plus',
                size: 40,
                iconSize: 18,
                tooltip: 'Add profile',
                onTap: () => _modelsKey.currentState?.addProfile()),
        SettingsPage.vault => _vaultAdding
            ? null
            : IconBtn('plus',
                size: 40,
                iconSize: 18,
                tooltip: 'Add secret',
                onTap: () => _vaultKey.currentState?.add()),
        SettingsPage.scheduled => _recurringAdding
            ? null
            : IconBtn('plus',
                size: 40,
                iconSize: 18,
                tooltip: 'New job',
                onTap: () => _recurringKey.currentState?.add()),
        _ => null,
      };

  Widget _mobileAddMachineBody() {
    final canConnect =
        !_addMachineBusy && _addMachinePaste.text.trim().isNotEmpty;
    return PageBody(children: [
      const SettingsGroupLabel('On the other machine'),
      ListGroup(children: [
        SettingsRow(
          label: 'snippet serve --enable',
          labelWidget: SelectableText('snippet serve --enable',
              style: mono(13, color: AppColors.fg1)),
          trailing: IconBtn('copy',
              size: 40, iconSize: 15, tooltip: 'Copy command', onTap: () {
            Clipboard.setData(
                const ClipboardData(text: 'snippet serve --enable'));
            toast(context, 'Copied');
          }),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, 0),
        child: Text(
          'It prints a link and a QR code. If snippet is already running '
          'there, snippet serve --status shows them again.',
          style: TS.meta(),
        ),
      ),
      const SettingsGroupLabel('Here'),
      ListGroup(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Link', style: sans(15, color: AppColors.fg1)),
              const SizedBox(height: 6),
              SettingsField(
                controller: _addMachinePaste,
                hint: 'https://…?token=…',
                mono: true,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submitAddMachine(),
              ),
            ],
          ),
        ),
      ]),
      if (_addMachineError != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, 0),
          child: Text(_addMachineError!,
              style: sans(12, height: 1.4, color: AppColors.danger)),
        ),
      const SizedBox(height: S.s16),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Btn('Cancel',
            variant: BtnVariant.secondary,
            onTap: _addMachineBusy ? null : _closeAddMachine),
        const SizedBox(width: S.s8),
        Btn(_addMachineBusy ? 'Connecting…' : 'Connect',
            disabled: !canConnect,
            onTap: canConnect ? _submitAddMachine : null),
      ]),
    ]);
  }

  Widget _mobileGeneralBody() {
    if (_addingMachine) return _mobileAddMachineBody();
    return PageBody(children: [
      const SettingsGroupLabel('Machines'),
      ListGroup(children: [
        if (_instances.isEmpty)
          const SettingsRow(
            label: 'No saved machines',
            sub: 'Run snippet serve on one and add its link.',
          )
        else
          for (final i in _instances) _machineRow(i),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, 0),
        child: Text(
          'Snippet talks to the daemon on each machine. Run snippet serve on '
          'a new one and paste the link it prints.',
          style: TS.meta(),
        ),
      ),
      const SettingsGroupLabel('Sessions'),
      ListGroup(children: [
        SettingsRow(
          label: 'Ask before running commands',
          sub:
              'Off lets agents run shell commands and edit files without stopping to ask. Applies to every session on this machine.',
          trailing: SettingsSwitch(
              value: _manual ?? false,
              onChanged: _manual == null ? null : _setManual),
        ),
        if (kCanNotify)
          SettingsRow(
            label: 'Notifications',
            sub: 'When a session needs you or finishes.',
            trailing: SettingsSwitch(
                value: _notif, onChanged: _notifBusy ? null : _toggleNotif),
          ),
      ]),
    ]);
  }

  Widget _mobileBody(SettingsPage page) => switch (page) {
        SettingsPage.general => _mobileGeneralBody(),
        SettingsPage.appearance => const AppearanceScreen(embedded: true),
        SettingsPage.models => InferenceProfilesScreen(
            key: _modelsKey,
            client: widget.client,
            embedded: true,
            onEditingChanged: (editing) =>
                setState(() => _modelsEditing = editing),
          ),
        SettingsPage.routing =>
          RoutingScreen(client: widget.client, embedded: true),
        SettingsPage.usage =>
          UsageScreen(client: widget.client, embedded: true),
        SettingsPage.voice =>
          VoiceScreen(client: widget.client, embedded: true),
        SettingsPage.webSearch =>
          WebSearchScreen(client: widget.client, embedded: true),
        SettingsPage.accounts =>
          AccountsScreen(client: widget.client, embedded: true),
        SettingsPage.memory =>
          MemoryScreen(client: widget.client, embedded: true),
        SettingsPage.vault => VaultScreen(
            key: _vaultKey,
            client: widget.client,
            embedded: true,
            onAddingChanged: (adding) => setState(() => _vaultAdding = adding),
          ),
        SettingsPage.wakes =>
          WakesScreen(client: widget.client, embedded: true),
        SettingsPage.scheduled => RecurringScreen(
            key: _recurringKey,
            client: widget.client,
            embedded: true,
            onAddingChanged: (adding) =>
                setState(() => _recurringAdding = adding),
          ),
      };

  Widget _pageBody() {
    return switch (widget.page) {
      SettingsPage.models => InferenceProfilesScreen(
          key: _modelsKey,
          client: widget.client,
          embedded: true,
          onEditingChanged: (editing) =>
              setState(() => _modelsEditing = editing),
        ),
      SettingsPage.accounts => AccountsScreen(
          client: widget.client,
          embedded: true,
        ),
      SettingsPage.memory => MemoryScreen(
          client: widget.client,
          embedded: true,
        ),
      SettingsPage.vault => VaultScreen(
          key: _vaultKey,
          client: widget.client,
          embedded: true,
          onAddingChanged: (adding) => setState(() => _vaultAdding = adding),
        ),
      SettingsPage.wakes => WakesScreen(
          client: widget.client,
          embedded: true,
        ),
      SettingsPage.scheduled => RecurringScreen(
          key: _recurringKey,
          client: widget.client,
          embedded: true,
          onAddingChanged: (adding) =>
              setState(() => _recurringAdding = adding),
        ),
      _ => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final page = widget.page;
    if (kMobile) {
      final addingMachine = page == SettingsPage.general && _addingMachine;
      final action = _mobilePageAction(page);
      final title = addingMachine
          ? 'Connect a machine'
          : (page == SettingsPage.general ? 'Machines' : _pageTitle(page));
      return Swap(
        stateKey: page,
        fill: true,
        child: CardGroupScope(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsHeader(
                title: title,
                compact: true,
                onBack: addingMachine ? _closeAddMachine : widget.onBack,
                actions: [if (action != null) action],
              ),
              Expanded(child: _mobileBody(page)),
            ],
          ),
        ),
      );
    }
    final Widget child;
    if (_plainPages.contains(page)) {
      final action = _pageAction(page);
      final addingMachine = page == SettingsPage.general && _addingMachine;
      child = SettingsColumn(children: [
        SettingsHeader(
          title: addingMachine ? 'Connect a machine' : _pageTitle(page),
          subtitle: addingMachine
              ? 'Add another machine running snippet serve.'
              : _pageSubtitle(page),
          back: addingMachine
              ? SettingsBack(widget.v5Desktop ? 'Machines' : 'General',
                  onTap: _closeAddMachine)
              : null,
          actions: [if (action != null) action],
        ),
        const SizedBox(height: S.s16),
        ..._plainBody(page),
      ]);
    } else {
      child = _pageBody();
    }
    return Swap(stateKey: page, fill: true, child: child);
  }
}

/// Action sheet to rename or remove a machine instance.
Future<void> showManageMachineSheet({
  required BuildContext context,
  required Instance instance,
  required void Function(Instance, String) onRename,
  required void Function(Instance) onRemove,
}) async {
  showAppSheet(
    context,
    title: instance.label,
    child: SheetActions([
      SheetAction('edit', 'Rename', () async {
        Navigator.pop(context);
        final name = await promptText(
          context,
          title: 'Rename machine',
          initial: instance.label,
          hint: 'Machine name',
          saveLabel: 'Rename',
        );
        if (name != null && name.isNotEmpty) {
          onRename(instance, name);
        }
      }),
      SheetAction('trash', 'Remove', () async {
        Navigator.pop(context);
        final ok = await confirmAction(
          context,
          title: 'Remove machine?',
          body:
              '${instance.label}\n\nRemoves the saved connection from this app. The machine and its sessions are untouched.',
          confirmLabel: 'Remove',
        );
        if (ok) onRemove(instance);
      }, danger: true),
    ]),
  );
}

class ApprovalsRow extends StatefulWidget {
  const ApprovalsRow({super.key, required this.client});
  final DaemonClient client;

  @override
  State<ApprovalsRow> createState() => _ApprovalsRowState();
}

class _ApprovalsRowState extends State<ApprovalsRow> {
  bool? _manual;

  @override
  void initState() {
    super.initState();
    widget.client.getConfig().then((c) {
      if (mounted) setState(() => _manual = c.manualApproval);
    }).catchError((_) {});
  }

  Future<void> _pick(BuildContext anchor) async {
    final current = _manual ?? false;
    final picked = await _showApprovalsMenu(context, anchor, current);
    if (picked == null || picked == current || !mounted) return;
    setState(() => _manual = picked);
    try {
      await widget.client.setManualApproval(picked);
    } catch (e) {
      if (!mounted) return;
      setState(() => _manual = current);
      toast(context, '$e', danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final manual = _manual;
    if (kMobile) {
      return Builder(
        builder: (anchor) => _V5SettingsRow(
          label: 'Approvals',
          value: manual == null ? null : (manual ? 'Ask' : 'Yolo'),
          leading: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(R.md),
            ),
            child: Center(
              child: AppIcon('shield-check', size: 16, color: AppColors.fg2),
            ),
          ),
          onTap: () => _pick(anchor),
        ),
      );
    }
    return Builder(
      builder: (anchor) => ListRow(
        title: 'Approvals',
        subtitle: kMobile ? null : 'Applies to every session on this machine',
        leading: kMobile
            ? Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.tint2,
                  borderRadius: BorderRadius.circular(R.md),
                ),
                child: Center(
                  child: AppIcon('shield-check',
                      size: 16, color: AppColors.fg2),
                ),
              )
            : AppIcon('shield', size: 19, color: AppColors.fg3),
        onTap: () => _pick(anchor),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(manual == null ? '' : (manual ? 'Ask' : 'Yolo'),
              style: sans(13, color: AppColors.fg3)),
          const SizedBox(width: S.s6),
          AppIcon(kMobile ? 'chevron-right' : 'chevron-down',
              size: 14, color: AppColors.fg3),
        ]),
      ),
    );
  }
}

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key, this.embedded = false, this.onBack});
  final bool embedded;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeManager.instance,
      builder: (context, _) {
        final tm = ThemeManager.instance;
        final base = tm.baseTheme;
        final custom = tm.customAccent;

        final paletteChildren = <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: _ThemeCardCarousel(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('Accent colour',
                        style: sans(kMobile ? 15 : 13,
                            weight: W.label, color: AppColors.fg1)),
                    const SizedBox(width: 8),
                    Text(
                      custom == null
                          ? 'Theme default (${base.label})'
                          : custom.label,
                      style: sans(12, color: AppColors.fg3),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const _AccentSwatchStrip(),
              ],
            ),
          ),
        ];
        const typographyChildren = <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: _FontCardCarousel(mono: false),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: _FontCardCarousel(mono: true),
          ),
        ];

        if (kMobile) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (onBack != null)
                SettingsHeader(
                    title: 'Appearance', compact: true, onBack: onBack!),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, S.s40),
                  children: [
                    _AppearancePreviewCard(),
                    const SettingsGroupLabel('Palette'),
                    ListGroup(children: paletteChildren),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, 0),
                      child: Text(
                        'Theme and accent colour are saved locally on this device.',
                        style: TS.meta(),
                      ),
                    ),
                    const SettingsGroupLabel('Typography'),
                    ListGroup(children: typographyChildren),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, 0),
                      child: Text(
                        'UI typeface applies to headings, chat and controls; code font applies to diffs, terminals and IDs.',
                        style: TS.meta(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AppearancePreviewCard(),
            const SizedBox(height: S.s16),
            const SettingsGroup(
              header: 'Window background',
              footer:
                  'An image replaces the window transparency. Clear it to see the desktop through the window again.',
              children: [_WindowBackgroundRow()],
            ),
            SettingsGroup(
              header: 'Palette',
              footer:
                  'Theme and accent colour are saved locally on this device.',
              children: paletteChildren,
            ),
            SettingsGroup(
              header: 'Typography',
              footer:
                  'UI typeface applies to headings, chat and controls; code font applies to diffs, terminals and IDs.',
              children: typographyChildren,
            ),
          ],
        );
      },
    );
  }
}

class _WindowBackgroundRow extends StatelessWidget {
  const _WindowBackgroundRow();

  Future<void> _choose() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      final p = file?.path;
      if (p != null && p.isNotEmpty) {
        await WindowBackgroundStore.instance.setFromFile(p);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final store = WindowBackgroundStore.instance;
    return ValueListenableBuilder<String?>(
      valueListenable: store.path,
      builder: (context, p, _) {
        final name = p == null ? 'Transparent' : p.split(RegExp(r'[\\/]')).last;
        return SettingsRow(
          label: 'Window background',
          sub: name,
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(R.sm),
            child: SizedBox(
              width: 40,
              height: 28,
              child: p == null
                  ? ColoredBox(color: AppColors.surface2)
                  : Image.file(File(p),
                      fit: BoxFit.cover,
                      cacheWidth: 120,
                      errorBuilder: (_, __, ___) =>
                          ColoredBox(color: AppColors.surface2)),
            ),
          ),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (p != null)
              TextButton(
                  onPressed: store.clear,
                  child: const Text('Use transparency')),
            TextButton(onPressed: _choose, child: const Text('Choose image')),
          ]),
        );
      },
    );
  }
}

class _ThemeCardCarousel extends StatefulWidget {
  const _ThemeCardCarousel();

  @override
  State<_ThemeCardCarousel> createState() => _ThemeCardCarouselState();
}

class _ThemeCardCarouselState extends State<_ThemeCardCarousel> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _step(double delta) {
    if (!_scroll.hasClients) return;
    final target = (_scroll.offset + delta)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(
      target,
      duration: Motion.base,
      curve: Motion.enter,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeManager.instance,
      builder: (context, _) {
        final tm = ThemeManager.instance;
        final currentName = tm.baseTheme.name;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Text('Theme',
                      style: sans(kMobile ? 15 : 13,
                          weight: W.label, color: AppColors.fg1)),
                  const SizedBox(width: 8),
                  Text(
                    '${tm.baseTheme.label} · ${allPresets.length} palettes',
                    style: sans(12, color: AppColors.fg3),
                  ),
                  const Spacer(),
                  if (!kMobile) ...[
                    IconBtn(
                      'chevron-left',
                      size: 24,
                      iconSize: 14,
                      tooltip: 'Scroll left',
                      onTap: () => _step(-340),
                    ),
                    const SizedBox(width: 4),
                    IconBtn(
                      'chevron-right',
                      size: 24,
                      iconSize: 14,
                      tooltip: 'Scroll right',
                      onTap: () => _step(340),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(
              height: 112,
              child: ListView.separated(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                itemCount: allPresets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final preset = allPresets[i];
                  final selected = preset.name == currentName;
                  final dots = [
                    preset.surface1,
                    preset.danger,
                    preset.ok,
                    preset.run,
                    preset.accent,
                    preset.fg2,
                  ];
                  return GestureDetector(
                    onTap: () => tm.setName(preset.name),
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      width: 152,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            height: 82,
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            decoration: BoxDecoration(
                              color: preset.bg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected
                                    ? AppColors.fg1
                                    : preset.border2,
                                width: selected ? 1.8 : 1.0,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Aa',
                                      style: sans(
                                        20,
                                        weight: W.strong,
                                        color: preset.fg1,
                                        height: 1,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: preset.surface3,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '~/',
                                        style: mono(
                                          11,
                                          weight: W.label,
                                          color: preset.fg2,
                                          height: 1,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      width: 14,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: preset.accent,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    for (final c in dots)
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: c,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white
                                                .withValues(alpha: 0.14),
                                            width: 0.75,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            preset.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(
                              12,
                              weight: selected ? W.label : W.body,
                              color: selected ? AppColors.fg1 : AppColors.fg3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FontCardCarousel extends StatefulWidget {
  const _FontCardCarousel({required this.mono});
  final bool mono;

  @override
  State<_FontCardCarousel> createState() => _FontCardCarouselState();
}

class _FontCardCarouselState extends State<_FontCardCarousel> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _step(double delta) {
    if (!_scroll.hasClients) return;
    final target = (_scroll.offset + delta)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(
      target,
      duration: Motion.base,
      curve: Motion.enter,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeManager.instance,
      builder: (context, _) {
        final tm = ThemeManager.instance;
        final fonts = widget.mono ? allMonoFonts : allFonts;
        final active = widget.mono ? tm.currentMonoFont : tm.currentFont;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Text(
                    widget.mono ? 'Code font' : 'UI typeface',
                    style: sans(kMobile ? 15 : 13,
                        weight: W.label, color: AppColors.fg1),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${active.label} · ${active.description}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, color: AppColors.fg3),
                    ),
                  ),
                  if (!kMobile) ...[
                    const SizedBox(width: 8),
                    IconBtn(
                      'chevron-left',
                      size: 24,
                      iconSize: 14,
                      tooltip: 'Scroll left',
                      onTap: () => _step(-320),
                    ),
                    const SizedBox(width: 4),
                    IconBtn(
                      'chevron-right',
                      size: 24,
                      iconSize: 14,
                      tooltip: 'Scroll right',
                      onTap: () => _step(320),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(
              height: 106,
              child: ListView.separated(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                itemCount: fonts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final font = fonts[i];
                  final selected = font.family == active.family;
                  return GestureDetector(
                    onTap: () => widget.mono
                        ? tm.setMonoFontFamily(font.family)
                        : tm.setFontFamily(font.family),
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      width: 148,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            height: 76,
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            decoration: BoxDecoration(
                              color: AppColors.bg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected
                                    ? AppColors.fg1
                                    : AppColors.border2,
                                width: selected ? 1.8 : 1.0,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      widget.mono ? '01 {}' : 'Aa',
                                      style: TextStyle(
                                        fontFamily: font.family,
                                        fontSize: widget.mono ? 16 : 20,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.fg1,
                                        height: 1,
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? AppColors.accent
                                            : AppColors.tint3,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  widget.mono
                                      ? 'fn main() => 42;'
                                      : 'Quick brown fox',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: font.family,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    color: AppColors.fg3,
                                    height: 1.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            font.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: font.family,
                              fontSize: 12,
                              fontWeight:
                                  selected ? FontWeight.w500 : FontWeight.w400,
                              color: selected ? AppColors.fg1 : AppColors.fg3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AccentSwatchStrip extends StatelessWidget {
  const _AccentSwatchStrip();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeManager.instance,
      builder: (context, _) {
        final tm = ThemeManager.instance;
        final custom = tm.customAccent;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            GestureDetector(
              onTap: () => tm.setAccentName(null),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: custom == null ? AppColors.accentBg : AppColors.tint2,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: custom == null
                        ? AppColors.accentLine
                        : AppColors.border,
                  ),
                ),
                child: Text(
                  'Default',
                  style: sans(12,
                      weight: custom == null ? W.label : W.body,
                      color: custom == null ? AppColors.accent : AppColors.fg2),
                ),
              ),
            ),
            for (final a in allAccents)
              GestureDetector(
                onTap: () => tm.setAccentName(a.name),
                behavior: HitTestBehavior.opaque,
                child: Tooltip(
                  message: a.label,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: a.accent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: custom?.name == a.name
                            ? AppColors.fg1
                            : AppColors.border2,
                        width: custom?.name == a.name ? 2.2 : 1.2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: custom?.name == a.name
                        ? Icon(Icons.check, size: 14, color: a.accentFg)
                        : null,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AppearancePreviewCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tm = ThemeManager.instance;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.tint1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${tm.baseTheme.label} · ${tm.currentFont.label}',
                style: sans(13, weight: W.strong, color: AppColors.fg1),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accentBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.accentLine),
              ),
              child: Text(
                tm.currentMonoFont.label,
                style: mono(11, color: AppColors.accent),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            'Round the corner, into the light — live preview of your active theme, accent and typography.',
            style: sans(13, height: 1.4, color: AppColors.fg2),
          ),
          const SizedBox(height: 8),
          Text(
            'git commit -m "Apply ${tm.baseTheme.name} + ${tm.currentFont.family}"',
            style: mono(12, color: AppColors.fg3),
          ),
        ],
      ),
    );
  }
}

/// v5 `.pgi`: a 46px row, 30px tile, 15px label, 15px muted value, chevron.
class _V5SettingsRow extends StatelessWidget {
  const _V5SettingsRow({
    required this.label,
    required this.leading,
    this.value,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final String label;
  final Widget leading;
  final String? value;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final v = value;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 46),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(children: [
            leading,
            const SizedBox(width: S.s12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(15, color: AppColors.fg1)),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13, color: AppColors.fg3)),
                ],
              ),
            ),
            if (v != null && v.isNotEmpty) ...[
              const SizedBox(width: S.s8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(v,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(15, color: AppColors.fg3)),
              ),
            ],
            const SizedBox(width: S.s6),
            trailing ??
                AppIcon('chevron-right', size: 14, color: AppColors.fg3),
          ]),
        ),
      ),
    );
  }
}
