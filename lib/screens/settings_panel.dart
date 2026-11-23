import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../phosphor_icons.dart';

import 'package:snippet_render/snippet_render.dart';

import '../api.dart';
import '../models.dart';
import '../notifications.dart';
import '../panel.dart';
import '../platform.dart';
import '../settings_form.dart';
import '../inline_flow.dart';
import '../store.dart';
import '../chat_scene.dart';
import '../theme.dart';
import '../widgets.dart';
import 'add_instance.dart';
import 'inference_profiles.dart';
import 'recurring.dart';
import 'routing_screen.dart';
import 'mobile_session_home.dart' show LiveSessionCard, MobileSectionLabel;
import 'session_list_row.dart' show SessionListRow;
import 'shell_nav.dart';
import 'usage.dart';
import 'vault.dart';
import 'voice_screen.dart';
import 'web_search_screen.dart';
import 'accounts_screen.dart';
import '../mochi.dart';
import '../motion.dart';
import '../desktop_look.dart';
import '../window_background.dart';
import 'dart:io' show File;
import '../desktop_pick.dart';
import '../desktop_layout.dart';
import 'memory_screen.dart';
import 'wakes_screen.dart';
import '../tap_detector.dart';

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
          SizedBox(width: S.of(10)),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: kMobile
                      ? TS.rowTitle(AppColors.fg1)
                      : TS.ui(AppColors.fg1)),
              SizedBox(height: S.s2),
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
          padding: EdgeInsets.fromLTRB(S.s12, kMobile ? S.of(14) : S.s8, S.s12,
              kMobile ? S.of(14) : S.s8),
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
            SizedBox(width: S.of(10)),
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
  keepWarm,
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

/// Labelled pill in the phone sub-page header, as in the settings mockup.
Widget _headerAdd(String label, VoidCallback onTap) => Padding(
      padding: EdgeInsets.only(right: S.s12),
      child: Btn(label,
          icon: 'plus',
          small: true,
          variant: BtnVariant.secondary,
          onTap: onTap),
    );

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
  String? _removingUrl;
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
        case SettingsPage.keepWarm:
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
      final week = await client.getUsage(
          since: DateTime.now().subtract(const Duration(days: 7)));
      if (mounted) {
        setState(() => _usageTokens =
            week.providers.fold<int>(0, (n, p) => n + p.totalTokens));
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
                !s.settled && s.status != 'waiting_for_input' && sessionBusy(s))
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

  // Arms the in-place strip; the row renders it until confirmed or cancelled.
  void _confirmRemove(Instance inst) => setState(() => _removingUrl = inst.url);

  Widget _removeStrip(Instance inst) => InlineConfirmStrip(
        title: 'Remove ${inst.label.isEmpty ? hostOf(inst.url) : inst.label}?',
        body:
            'Removes the saved connection from this app. The machine and its sessions are untouched.',
        onCancel: () {
          if (mounted && _removingUrl == inst.url) {
            setState(() => _removingUrl = null);
          }
        },
        onConfirm: () {
          widget.onRemove(inst);
          setState(() {
            _removingUrl = null;
            _instances.removeWhere((e) => e.url == inst.url);
          });
        },
      );

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
        color: AppColors.pageBg,
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
                          padding: EdgeInsets.symmetric(horizontal: S.of(18)),
                          alignment: Alignment.centerLeft,
                          child: Text('Settings',
                              style: sans(15,
                                  weight: W.strong, color: AppColors.fg1)),
                        ),
                        Expanded(
                          child: ListView(
                            padding: EdgeInsets.fromLTRB(S.s8, 0, S.s8, S.s8),
                            children: [
                              for (final (page, icon, label) in _nav) ...[
                                if (_navGroups[page] != null)
                                  Padding(
                                    padding: EdgeInsets.fromLTRB(
                                        S.of(10), S.of(14), S.of(10), S.s4),
                                    child: Text(_navGroups[page]!.toUpperCase(),
                                        style: TS.overline()),
                                  ),
                                _settingsNavRow(page, icon, label),
                              ],
                            ],
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                              S.of(18), S.of(10), S.s16, S.s16),
                          child: Row(children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: AppColors.ok,
                                shape: BoxShape.circle,
                              ),
                            ),
                            SizedBox(width: S.s8),
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
                padding: EdgeInsets.symmetric(horizontal: S.of(14)),
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

  /// One phone settings row: bare icon, title, optional value, chevron.
  Widget _settingsRow(
    String label,
    String icon, {
    String? value,
    SettingsPage? page,
  }) =>
      SettingsRow(
        label: label,
        icon: icon,
        value: value,
        chevron: true,
        onTap: page == null ? null : () => widget.onSection?.call(page),
      );

  /// Phone settings HOME, in design language v7 grouped rows.
  Widget _mobileSettingsHome() {
    final active = widget.active;
    final tm = ThemeManager.instance;
    final name = active?.label.trim() ?? '';
    final live = _liveCount;
    return ListView(
      padding: EdgeInsets.fromLTRB(Grouped.gutter, S.s8, Grouped.gutter, S.s40),
      children: [
        SettingsGroup(children: [
          SettingsRow(
            label: name.isEmpty ? 'No machine yet' : name,
            sub: active == null ? 'Add one to begin' : null,
            subWidget: active == null
                ? null
                : Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: 'Connected',
                          style: Grouped.subStyle(AppColors.ok)),
                      if (live != null) TextSpan(text: ' · $live live'),
                    ]),
                    style: Grouped.subStyle(),
                  ),
            leading: _SettingsTile(null,
                iconData: PhIcons.monitor, ok: active != null),
            chevron: true,
            onTap: () => widget.onSection?.call(SettingsPage.general),
          ),
        ]),
        SettingsGroup(header: 'Models', children: [
          _settingsRow('Inference profiles', 'cpu',
              page: SettingsPage.models, value: _profileCount?.toString()),
          _settingsRow('Routing', 'route', page: SettingsPage.routing),
          _settingsRow('Accounts', 'users', page: SettingsPage.accounts),
          _settingsRow('Usage', 'gauge',
              page: SettingsPage.usage,
              value: _usageTokens == null
                  ? null
                  : '${fmtSi(_usageTokens!)} this week'),
        ]),
        SettingsGroup(
          header: 'Agents',
          footer: 'Approvals apply to every session on this machine.',
          children: [
            ApprovalsRow(client: widget.client),
            _settingsRow('Memory', 'book-marked', page: SettingsPage.memory),
            _settingsRow('Wakes', 'repeat', page: SettingsPage.wakes),
            _settingsRow('Vault', 'lock',
                page: SettingsPage.vault, value: _vaultCount?.toString()),
            _settingsRow('Web search', 'globe', page: SettingsPage.webSearch),
            _settingsRow('Voice', 'mic',
                page: SettingsPage.voice,
                value: _ambientOn == null
                    ? null
                    : _ambientOn!
                        ? 'Listening'
                        : 'Off'),
          ],
        ),
        ListenableBuilder(
          listenable: ThemeManager.instance,
          builder: (context, _) {
            final accent = tm.customAccent;
            return SettingsGroup(
              header: 'This device',
              footer: 'Theme, accent and fonts are saved on this device.',
              children: [
                _settingsRow(
                  'Theme and accent',
                  'sliders',
                  page: SettingsPage.appearance,
                  value: accent == null
                      ? tm.baseTheme.label
                      : '${tm.baseTheme.label} · ${accent.name}',
                ),
                if (kCanNotify) _notifRow(),
              ],
            );
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
                    size: M.minTarget,
                    iconSize: 18,
                    tooltip: 'Add machine',
                    onTap: _addMachine),
              ],
            ),
            Expanded(child: _generalPage(includeNotifications: false)),
          ],
        ),
      SettingsPage.appearance => AppearanceScreen(
          client: widget.client,
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
      SettingsPage.keepWarm => WakesScreen(
          client: widget.client,
          embedded: true,
          keepWarm: true,
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
    await _saveInstances(
        (items) => _renameStoredInstance(items, inst, newName));
    widget.onRename?.call(inst, newName);
  }

  void _selectInstance(Instance i) {
    widget.onSelect?.call(i);
  }

  /// One row in the desktop settings rail.
  Widget _settingsNavRow(SettingsPage page, String icon, String label) {
    final selected = _page == page;
    return Padding(
      padding: EdgeInsets.only(bottom: S.s2),
      child: Material(
        color: selected ? AppColors.tint2 : Colors.transparent,
        borderRadius: BorderRadius.circular(R.of(9)),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.of(9)),
          onTap: () {
            setState(() => _page = page);
            _deskSectionKey.currentState?.resetTransient();
          },
          child: Container(
            height: 34,
            padding: EdgeInsets.symmetric(horizontal: S.of(10)),
            child: Row(children: [
              AppIcon(icon,
                  size: 15, color: selected ? AppColors.accent : AppColors.fg3),
              SizedBox(width: S.of(10)),
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
      padding: EdgeInsets.symmetric(horizontal: S.of(14), vertical: S.s4),
      children: [
        for (final (page, icon, label) in _nav)
          Padding(
            padding: EdgeInsets.only(right: S.s6),
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
                  padding:
                      EdgeInsets.symmetric(horizontal: S.s12, vertical: S.s6),
                  child: Row(children: [
                    AppIcon(icon,
                        size: 14,
                        color: _page == page ? AppColors.fg1 : AppColors.fg3),
                    SizedBox(width: S.s6),
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
      if (kMobile)
        const SettingsGroupLabel('Machines')
      else
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
        SizedBox(height: S.s24),
        const SectionLabel('Approvals'),
        ListGroup(children: [ApprovalsRow(client: widget.client)]),
      ],
      if (includeNotifications && kCanNotify) ...[
        SizedBox(height: S.s24),
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
          SizedBox(width: S.s6),
          Text('Connect a machine',
              style: sans(17,
                  weight: FontWeight.w500,
                  spacing: -0.2,
                  color: AppColors.fg1)),
        ]),
        SizedBox(height: S.of(22)),
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
                Clipboard.setData(
                    const ClipboardData(text: 'snippet serve --enable'));
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
                padding: EdgeInsets.only(left: S.s4, right: S.s12),
                child: Text(_addMachineError!,
                    style: sans(12, height: 1.4, color: AppColors.danger)),
              ),
            ),
          SettingsPill('Cancel', onTap: _addMachineBusy ? null : back),
          SizedBox(width: S.s8),
          SettingsPill(_addMachineBusy ? 'Connecting…' : 'Connect',
              onTap: canConnect ? _submitAddMachine : null),
        ]),
      ],
    );
  }

  Widget _instanceRow(Instance i) =>
      _removingUrl == i.url ? _removeStrip(i) : _instanceRowBase(i);

  Widget _instanceRowBase(Instance i) {
    final isActive = i.url == widget.active?.url;
    final isRenaming = _renamingUrl == i.url;
    final compact = kMobile && widget.embedded;
    final canConnect = !isActive && widget.onSelect != null;
    if (compact && !isRenaming) {
      // The row is the menu: Connect, Rename and Remove all live behind a tap.
      return Builder(
        builder: (anchor) => _V5SettingsRow(
          label: i.label,
          subtitle: hostOf(i.url),
          leading:
              _SettingsTile(null, iconData: PhIcons.monitor, ok: isActive),
          value: isActive ? 'Active' : (canConnect ? 'Connect' : null),
          trailing: const SizedBox.shrink(),
          onTap: () => _showMachineMenu(
            context,
            anchor: anchor,
            instance: i,
            connect: canConnect,
            onSelect: () => _selectInstance(i),
            onRename: () => _startRename(i),
            onRemove: () => _confirmRemove(i),
          ),
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: compact && canConnect && !isRenaming
            ? () => _selectInstance(i)
            : null,
        child: Padding(
          padding:
              EdgeInsets.fromLTRB(compact ? S.of(14) : S.s12, S.s8, S.s4, S.s8),
          child: Row(
            children: [
              if (compact)
                _SettingsTile(null, iconData: PhIcons.monitor, ok: isActive)
              else
                IconTile('server', tone: isActive ? Tone.ok : Tone.neutral),
              SizedBox(width: S.s12),
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
                      SizedBox(height: S.s2),
                      Text(hostOf(i.url),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TS.codeSmall()),
                    ],
                  ),
                ),
                SizedBox(width: S.s8),
                if (compact) ...[
                  _machineMenu(i, connect: canConnect),
                ] else ...[
                  if (isActive)
                    const Tag('Active', tone: Tone.ok, dot: true)
                  else if (canConnect)
                    TextAction('Connect', onTap: () => _selectInstance(i)),
                  SizedBox(width: S.s4),
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
      return SettingsRow(
        label: 'Notifications',
        sub: 'When a chat needs you or finishes',
        icon: 'bell',
        onTap: _notifBusy ? null : () => _toggleNotif(!_notif),
        trailing: _notifBusy
            ? const DelayedSpinner(size: 18)
            : SettingsSwitch(value: _notif, onChanged: _toggleNotif),
      );
    }
    return Padding(
      padding: kMobile
          ? EdgeInsets.fromLTRB(S.s16, S.of(14), S.s16, S.of(14))
          : EdgeInsets.fromLTRB(S.s12, S.s12, S.s12, S.s12),
      child: Row(children: [
        if (!kMobile) ...[
          const IconTile('bell'),
          SizedBox(width: S.s12),
        ] else ...[
          AppIcon('bell', size: 19, color: AppColors.fg3),
          SizedBox(width: S.of(14)),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(kMobile ? 'Notifications' : 'Session notifications',
                  style: TS.rowTitle()),
              SizedBox(height: S.s2),
              Text(
                  kMobile
                      ? 'When a chat needs you or finishes'
                      : 'When a session finishes or needs your input',
                  style: TS.meta()),
            ],
          ),
        ),
        SizedBox(width: S.s8),
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
    this.onClose,
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

  /// Desktop: a close circle at the end of a plain page's header.
  final VoidCallback? onClose;
  final bool v5Desktop;

  /// Pages laid out as one column under a [SettingsHeader].
  static const plainPages = SettingsSectionViewState._plainPages;

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
  String? _openMachineUrl;
  String? _removingUrl;
  bool _connecting = false;

  final TextEditingController _renameController = TextEditingController();

  bool? _manual;
  bool _notif = false;
  bool _notifBusy = false;
  final Map<String, bool> _health = {};
  int? _liveCount;

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
      case SettingsPage.keepWarm:
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

  Future<void> _saveInstances(
      void Function(List<Instance> items) change) async {
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
      final client = isActive ? widget.client : DaemonClient(i.url, i.token);
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

  void _addMachine() {
    if (widget.v5Desktop) {
      setState(() => _connecting = true);
      return;
    }
    setState(() {
      _addingMachine = true;
      _addMachineError = null;
      _addMachinePaste.clear();
    });
  }

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
    await _saveInstances(
        (items) => _renameStoredInstance(items, inst, newName));
    widget.onRename?.call(inst, newName);
  }

  // Arms the in-place strip; the row renders it until confirmed or cancelled.
  void _confirmRemove(Instance inst) => setState(() => _removingUrl = inst.url);

  Widget _removeStrip(Instance inst) => InlineConfirmStrip(
        title: 'Remove ${inst.label.isEmpty ? hostOf(inst.url) : inst.label}?',
        body:
            'Removes the saved connection from this app. The machine and its sessions are untouched.',
        onCancel: () {
          if (mounted && _removingUrl == inst.url) {
            setState(() => _removingUrl = null);
          }
        },
        onConfirm: () {
          widget.onRemove(inst);
          setState(() {
            _removingUrl = null;
            _instances.removeWhere((e) => e.url == inst.url);
          });
        },
      );

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
        SettingsPage.keepWarm => 'Keep warm',
        SettingsPage.voice => 'Voice',
        SettingsPage.webSearch => 'Web search',
        SettingsPage.accounts => 'Accounts',
      };

  String _pageSubtitle(SettingsPage page) => switch (page) {
        SettingsPage.general => widget.v5Desktop
            ? ''
            : 'Machines this app connects to, and how sessions behave.',
        SettingsPage.appearance =>
          'Theme palette, accent colour, UI typeface and code font saved on this device.',
        SettingsPage.routing => 'Which model does each kind of work',
        SettingsPage.usage => 'Tokens and rate limits by provider',
        SettingsPage.voice => '',
        SettingsPage.webSearch => '',
        _ => '',
      };

  Widget? _pageAction(SettingsPage page) {
    if (widget.v5Desktop && page == SettingsPage.general) {
      return _connecting
          ? null
          : HeaderAction('Add machine', onTap: _addMachine);
    }
    return switch (page) {
      SettingsPage.general =>
        _addingMachine ? null : HeaderAction('Add machine', onTap: _addMachine),
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
        SizedBox(width: S.s8),
        Btn(_addMachineBusy ? 'Connecting…' : 'Connect',
            disabled: !canConnect,
            onTap: canConnect ? _submitAddMachine : null),
      ]),
    ];
  }

  List<Widget> _v5MachineRows(Instance i) {
    final removing = _removingUrl == i.url;
    final open = _openMachineUrl == i.url && _renamingUrl != i.url;
    final canConnect = i.url != widget.active?.url && widget.onSelect != null;
    return [
      if (removing) _removeStrip(i) else _v5MachineRow(i),
      if (open && !removing)
        InlineActionsStrip(
          onClose: () => setState(() => _openMachineUrl = null),
          actions: [
            if (canConnect)
              Btn('Connect', small: true, onTap: () {
                setState(() => _openMachineUrl = null);
                widget.onSelect?.call(i);
              }),
            Btn('Rename', small: true, variant: BtnVariant.secondary,
                onTap: () {
              setState(() => _openMachineUrl = null);
              _startRename(i);
            }),
            Btn('Remove',
                small: true,
                variant: BtnVariant.danger,
                onTap: () => setState(() {
                      _openMachineUrl = null;
                      _removingUrl = i.url;
                    })),
          ],
        ),
    ];
  }

  Widget _v5MachineRow(Instance i) {
    final isActive = i.url == widget.active?.url;
    final connected = _health[i.url] ?? isActive;
    if (_renamingUrl == i.url) {
      return SettingsRow(
        label: i.label,
        iconData: PhIcons.monitor,
        iconColor: isActive ? AppColors.ok : null,
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
    final canConnect = !isActive && widget.onSelect != null;
    final live = _liveCount;
    final host = hostOf(i.url);
    return Builder(
      builder: (anchor) => SettingsRow(
        iconData: PhIcons.monitor,
        iconColor: isActive ? AppColors.ok : null,
        label: i.label.isEmpty ? host : i.label,
        sub: isActive && live != null ? '$host · $live live' : host,
        value: isActive
            ? 'Active'
            : !connected
                ? 'Offline'
                : canConnect
                    ? 'Connect'
                    : null,
        chevron: true,
        // The row expands in place: Connect, Rename and Remove.
        onTap: () => setState(
            () => _openMachineUrl = _openMachineUrl == i.url ? null : i.url),
      ),
    );
  }

  Future<void> _connected(Instance inst) async {
    setState(() => _connecting = false);
    await _saveInstances((items) => items
      ..removeWhere((e) => e.url == inst.url || e.token == inst.token)
      ..add(inst));
    widget.onAdd?.call(inst);
  }

  List<Widget> _v5General() {
    final manual = _manual;
    return [
      SettingsGroup(
        header: 'Connected',
        footer:
            'Snippet talks to the daemon on each machine. Run snippet serve on a new one and add its link.',
        children: [
          if (_connecting)
            _ConnectMachinePanel(
              onCancel: () => setState(() => _connecting = false),
              onConnected: _connected,
            ),
          if (_instances.isEmpty && !_connecting)
            const SettingsRow(
              iconData: PhIcons.monitor,
              label: 'No saved machines',
              sub: 'Run snippet serve on one and add its link.',
            )
          else
            for (final i in _instances) ..._v5MachineRows(i),
        ],
      ),
      SettingsGroup(
        header: 'Sessions',
        children: [
          SettingsRow(
            icon: 'shield',
            label: 'Approvals',
            sub: 'Applies to every session on this machine',
            trailing: manual == null
                ? null
                : InlineSegmented<bool>(
                    value: manual,
                    options: const [(true, 'Ask'), (false, 'Yolo')],
                    onChanged: _setManual),
          ),
        ],
      ),
      if (kCanNotify)
        SettingsGroup(
          header: 'Notifications',
          children: [
            SettingsRow(
              icon: 'bell',
              label: 'Notifications',
              sub: 'When a chat needs you or finishes',
              onTap: _notifBusy ? null : () => _toggleNotif(!_notif),
              trailing: _notifBusy
                  ? const DelayedSpinner(size: 18)
                  : SettingsSwitch(
                      value: _notif,
                      onChanged: _notifBusy ? null : _toggleNotif),
            ),
          ],
        ),
    ];
  }

  Widget _machineRow(Instance i) =>
      _removingUrl == i.url ? _removeStrip(i) : _machineRowBase(i);

  Widget _machineRowBase(Instance i) {
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
        SizedBox(width: S.s8),
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
            AppearanceScreen(client: widget.client, embedded: true),
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
        SettingsPage.general =>
          _addingMachine ? null : _headerAdd('Add machine', _addMachine),
        SettingsPage.models => _modelsEditing
            ? null
            : _headerAdd(
                'Add profile', () => _modelsKey.currentState?.addProfile()),
        SettingsPage.vault => _vaultAdding
            ? null
            : _headerAdd('Add secret', () => _vaultKey.currentState?.add()),
        SettingsPage.scheduled => _recurringAdding
            ? null
            : _headerAdd('New job', () => _recurringKey.currentState?.add()),
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
        padding: EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, 0),
        child: Text(
          'It prints a link and a QR code. If snippet is already running '
          'there, snippet serve --status shows them again.',
          style: TS.meta(),
        ),
      ),
      const SettingsGroupLabel('Here'),
      ListGroup(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(S.of(14), S.of(10), S.of(14), S.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Link', style: sans(15, color: AppColors.fg1)),
              SizedBox(height: S.s6),
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
          padding: EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, 0),
          child: Text(_addMachineError!,
              style: sans(12, height: 1.4, color: AppColors.danger)),
        ),
      SizedBox(height: S.s16),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Btn('Cancel',
            variant: BtnVariant.secondary,
            onTap: _addMachineBusy ? null : _closeAddMachine),
        SizedBox(width: S.s8),
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
        padding: EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, 0),
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
        SettingsPage.appearance =>
          AppearanceScreen(client: widget.client, embedded: true),
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
        SettingsPage.keepWarm =>
          WakesScreen(client: widget.client, embedded: true, keepWarm: true),
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
      SettingsPage.keepWarm => WakesScreen(
          client: widget.client,
          embedded: true,
          keepWarm: true,
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
          actions: [
            if (action != null) action,
            // The desktop dialog closes on Esc or a click outside.
            if (widget.onClose != null && !widget.v5Desktop)
              GroupedCircleButton(
                  icon: 'x', tooltip: 'Close', onTap: widget.onClose),
          ],
        ),
        SizedBox(height: S.s16),
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

  Future<void> _apply(bool picked) async {
    final current = _manual ?? false;
    if (picked == current || !mounted) return;
    setState(() => _manual = picked);
    try {
      await widget.client.setManualApproval(picked);
    } catch (e) {
      if (!mounted) return;
      setState(() => _manual = current);
      toast(context, '$e', danger: true);
    }
  }

  Future<void> _pick() async {
    final manual = _manual;
    if (manual == null) return;
    final picked = await showApprovalsSheet(context, manual: manual);
    if (picked != null) await _apply(picked);
  }

  @override
  Widget build(BuildContext context) {
    final manual = _manual;
    final value = manual == null ? null : (manual ? 'Ask' : 'Yolo');
    if (kMobile) {
      return _V5SettingsRow(
        label: 'Approvals',
        leading: _SettingsTile('shield-check'),
        value: value,
        onTap: manual == null ? null : _pick,
      );
    }
    return ListRow(
      title: 'Approvals',
      subtitle: 'Applies to every session on this machine',
      leading: AppIcon('shield', size: 19, color: AppColors.fg3),
      trailing: manual == null
          ? null
          : InlineSegmented<bool>(
              value: manual,
              options: const [(true, 'Ask'), (false, 'Yolo')],
              onChanged: _apply),
    );
  }
}

/// A phone settings row's bare icon; [ok] tints it for the connected machine.
class _SettingsTile extends StatelessWidget {
  const _SettingsTile(this.icon, {this.iconData, this.ok = false});
  final String? icon;
  final IconData? iconData;
  final bool ok;

  @override
  Widget build(BuildContext context) =>
      SettingsIcon(icon, iconData: iconData, color: ok ? AppColors.ok : null);
}

/// The Approvals menu: Ask or Yolo for every session on this machine. A bottom
/// sheet on the phone, a small dialog on desktop. Returns the pick, or null.
Future<bool?> showApprovalsSheet(BuildContext context, {required bool manual}) {
  const sub = 'Applies to every session on this machine';
  Widget option(String label, String detail, bool value) => _V5SettingsRow(
        label: label,
        subtitle: detail,
        onTap: () => Navigator.pop(context, value),
        trailing: value == manual
            ? AppIcon('check', size: 16, color: AppColors.accent)
            : const SizedBox(width: 16),
      );
  final group = CardGroupScope(
    child: ListGroup(children: [
      option('Ask', 'Pause for approval on each change', true),
      option('Yolo', 'Run shell and file edits without asking', false),
    ]),
  );
  return showAppSheet<bool>(context,
      title: 'Approvals', subtitle: sub, child: group);
}

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen(
      {super.key, this.client, this.embedded = false, this.onBack});
  final DaemonClient? client;
  final bool embedded;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeManager.instance,
      builder: (context, _) {
        final tm = ThemeManager.instance;
        final effectiveClient = client;
        final base = tm.baseTheme;
        final custom = tm.customAccent;

        final paletteChildren = <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(S.of(14), S.s12, S.of(14), S.of(14)),
            child: _ThemeCardCarousel(client: effectiveClient),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(S.of(14), S.s12, S.of(14), S.of(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('Accent colour',
                        style: sans(kMobile ? 15 : 13,
                            weight: W.label, color: AppColors.fg1)),
                    SizedBox(width: S.s8),
                    Text(
                      custom == null
                          ? 'Theme default (${base.label})'
                          : custom.label,
                      style: sans(12, color: AppColors.fg3),
                    ),
                  ],
                ),
                SizedBox(height: S.of(10)),
                _AccentSwatchStrip(client: effectiveClient),
              ],
            ),
          ),
        ];
        final typographyChildren = <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(S.of(14), S.s12, S.of(14), S.of(14)),
            child: _FontCardCarousel(mono: false, client: effectiveClient),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(S.of(14), S.s12, S.of(14), S.of(14)),
            child: _FontCardCarousel(mono: true, client: effectiveClient),
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
                  padding: EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, S.s40),
                  children: [
                    _AppearancePreviewCard(),
                    if (shaderSurfaceSupported) ...[
                      const SettingsGroupLabel('Background'),
                      const ListGroup(children: [_ChatSceneRow()]),
                    ],
                    const SettingsGroupLabel('Palette'),
                    ListGroup(children: paletteChildren),
                    Padding(
                      padding: EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, 0),
                      child: Text(
                        'Theme and accent colour are saved locally on this device.',
                        style: TS.meta(),
                      ),
                    ),
                    const SettingsGroupLabel('Typography'),
                    ListGroup(children: typographyChildren),
                    Padding(
                      padding: EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, 0),
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
            SizedBox(height: S.s16),
            const SettingsGroup(
              header: 'Surfaces and wallpaper',
              footer:
                  'Wallpaper sits behind the chat and fades into the theme so text stays readable.',
              children: [
                _TactileRow(),
                _ChromeOpacityRow(),
                _ChatWallpaperPicker()
              ],
            ),
            if (shaderSurfaceSupported)
              const SettingsGroup(
                header: 'Background',
                footer:
                    'An animated scene behind every screen, drawn on the GPU. It pauses in the background and with reduced motion.',
                children: [_ChatSceneRow()],
              ),
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

class _TactileRow extends StatelessWidget {
  const _TactileRow();

  @override
  Widget build(BuildContext context) {
    final look = DesktopLook.instance;
    return ListenableBuilder(
      listenable: look,
      builder: (context, _) => SettingsRow(
        label: 'Tactile surfaces',
        sub: 'Soft highlights on raised controls, inset wells for fields',
        onTap: () => look.setTactile(!look.tactile),
        trailing:
            SettingsSwitch(value: look.tactile, onChanged: look.setTactile),
      ),
    );
  }
}

class _ChromeOpacityRow extends StatelessWidget {
  const _ChromeOpacityRow();

  @override
  Widget build(BuildContext context) {
    final look = DesktopLook.instance;
    return ListenableBuilder(
      listenable: look,
      builder: (context, _) {
        final v = look.chromeOpacity;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsRow(
                label: 'Sidebar opacity',
                sub: v == null
                    ? 'Default. Lower it to let a scene or the desktop show through the sidebar and panes.'
                    : '${(v * 100).round()}%',
                trailing: v == null
                    ? null
                    : TextButton(
                        onPressed: () => look.setChromeOpacity(null),
                        child: const Text('Reset')),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(S.of(14), 0, S.of(14), S.s8),
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    activeTrackColor: AppColors.accent,
                    inactiveTrackColor: AppColors.surface3,
                    thumbColor: AppColors.accent,
                    overlayColor: AppColors.accentBg,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                  ),
                  child: Slider(
                    key: const Key('chrome-opacity'),
                    value: v ?? 0.92,
                    onChanged: (x) => look.setChromeOpacity(x, persist: false),
                    onChangeEnd: look.setChromeOpacity,
                  ),
                ),
              ),
            ]);
      },
    );
  }
}

class _ChatSceneRow extends StatelessWidget {
  const _ChatSceneRow();

  @override
  Widget build(BuildContext context) {
    final scene = ChatScene.instance;
    return ListenableBuilder(
      listenable: scene,
      builder: (context, _) => SettingsRow(
        label: 'Animated background',
        sub: scene.error ?? 'Moves behind every screen',
        trailing: Pills<String>(
          key: const Key('chat-scene'),
          items: [
            (ChatScene.none, 'Off'),
            for (final e in ChatScene.presets.entries) (e.key, e.value),
          ],
          selected: scene.active ? scene.scene : ChatScene.none,
          onSelect: scene.set,
        ),
      ),
    );
  }
}

class _ChatWallpaperPicker extends StatelessWidget {
  const _ChatWallpaperPicker();

  Future<void> _chooseImage() async {
    try {
      final p = await pickLocalImage();
      if (p != null) {
        await DesktopLook.instance.setImageFromFile(p);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final look = DesktopLook.instance;
    return ListenableBuilder(
      listenable: look,
      builder: (context, _) {
        final img = look.hasWallpaper ? look.imagePath : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsRow(
              label: 'Chat wallpaper',
              sub: img == null ? 'None' : img.split(RegExp(r'[\\/]')).last,
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(R.sm),
                child: SizedBox(
                  width: 40,
                  height: 28,
                  child: img == null
                      ? ColoredBox(color: AppColors.surface2)
                      : Image.file(File(img),
                          fit: BoxFit.cover,
                          cacheWidth: 120,
                          errorBuilder: (_, __, ___) =>
                              ColoredBox(color: AppColors.surface2)),
                ),
              ),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (img != null)
                  TextButton(
                      onPressed: look.clearWallpaper,
                      child: const Text('Remove')),
                TextButton(
                    onPressed: _chooseImage,
                    child: Text(img == null ? 'Choose image' : 'Change')),
              ]),
            ),
            if (img != null)
              Padding(
                padding: EdgeInsets.fromLTRB(S.of(14), 0, S.of(14), S.s8),
                child: Row(children: [
                  Text('Strength', style: sans(12, color: AppColors.fg3)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        activeTrackColor: AppColors.accent,
                        inactiveTrackColor: AppColors.surface3,
                        thumbColor: AppColors.accent,
                        overlayColor: AppColors.accentBg,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 14),
                      ),
                      child: Slider(
                        value: look.strength,
                        onChanged: (v) => look.setStrength(v, persist: false),
                        onChangeEnd: look.setStrength,
                      ),
                    ),
                  ),
                ]),
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
      final p = await pickLocalImage();
      if (p != null) {
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

Future<void> _runThemeUpdate(
    BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) toast(context, '$e', danger: true);
  }
}

class _ThemeCardCarousel extends StatefulWidget {
  const _ThemeCardCarousel({this.client});
  final DaemonClient? client;

  @override
  State<_ThemeCardCarousel> createState() => _ThemeCardCarouselState();
}

class _ThemeCardCarouselState extends State<_ThemeCardCarousel> {
  final ScrollController _scroll = ScrollController();
  Map<String, String> _agentNames = const {};

  static final Map<String, int> _builtinOrder = {
    for (var i = 0; i < allPresets.length; i++) allPresets[i].name: i,
  };

  @override
  void initState() {
    super.initState();
    _loadFromDaemon();
  }

  @override
  void didUpdateWidget(covariant _ThemeCardCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.client, widget.client)) {
      _loadFromDaemon();
    }
  }

  void _loadFromDaemon() {
    final c = widget.client;
    if (c == null) return;
    unawaited(c.coordinationAgents().then((all) {
      rememberAgentCharacters([for (final a in all) (a.id, a.character)]);
      if (!mounted) return;
      setState(() {
        _agentNames = {
          for (final a in all)
            a.id: a.displayName.trim().isEmpty ? a.id : a.displayName,
        };
      });
    }, onError: (_) {}));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _step(double delta) {
    if (!_scroll.hasClients) return;
    final target =
        (_scroll.offset + delta).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(
      target,
      duration: Motion.base,
      curve: Motion.enter,
    );
  }

  List<ThemeSummary> _orderedItems(ThemeManager tm) {
    final source = [for (final p in allPresets) ThemeSummary.fromPreset(p)];
    final builtins = <ThemeSummary>[];
    final yours = <ThemeSummary>[];
    final agents = <ThemeSummary>[];
    for (final t in source) {
      if (t.builtin) {
        builtins.add(t);
      } else if (t.isAgent) {
        agents.add(t);
      } else {
        yours.add(t);
      }
    }
    builtins.sort((a, b) {
      final oa = _builtinOrder[a.id] ?? 9999;
      final ob = _builtinOrder[b.id] ?? 9999;
      if (oa != ob) return oa.compareTo(ob);
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    yours.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    agents.sort((a, b) {
      final na = _agentNames[a.agentId] ?? a.agentId;
      final nb = _agentNames[b.agentId] ?? b.agentId;
      final byAgent = na.toLowerCase().compareTo(nb.toLowerCase());
      return byAgent != 0
          ? byAgent
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return [...builtins, ...yours, ...agents];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeManager.instance,
      builder: (context, _) {
        final tm = ThemeManager.instance;
        final items = _orderedItems(tm);
        final currentId = tm.activeId;
        final activeLabel =
            tm.resolved.name.isNotEmpty ? tm.resolved.name : tm.baseTheme.label;
        final showMetaRow = items.any((t) => !t.builtin);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: S.of(10)),
              child: Row(
                children: [
                  Text('Theme',
                      style: sans(kMobile ? 15 : 13,
                          weight: W.label, color: AppColors.fg1)),
                  SizedBox(width: S.s8),
                  Expanded(
                    child: Text(
                      '$activeLabel · ${items.length} palettes',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, color: AppColors.fg3),
                    ),
                  ),
                  if (!kMobile) ...[
                    IconBtn(
                      'chevron-left',
                      size: 24,
                      iconSize: 14,
                      tooltip: 'Scroll left',
                      onTap: () => _step(-340),
                    ),
                    SizedBox(width: S.s4),
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
              height: showMetaRow ? 128 : 112,
              child: ListView.separated(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => SizedBox(width: S.of(10)),
                itemBuilder: (context, i) {
                  final item = items[i];
                  final compiled =
                      allPresets.where((p) => p.name == item.id).firstOrNull;
                  final bg = compiled?.bg ?? item.preview.bg;
                  final surface1 = compiled?.surface1 ?? item.preview.surface1;
                  final fg1 = compiled?.fg1 ?? item.preview.fg1;
                  final fg2 = compiled?.fg2 ?? fg1.withValues(alpha: 0.82);
                  final surface3 =
                      compiled?.surface3 ?? Color.lerp(surface1, fg1, 0.10)!;
                  final border2 =
                      compiled?.border2 ?? fg1.withValues(alpha: 0.16);
                  final accent = compiled?.accent ?? item.preview.accent;
                  final selected = item.id == currentId;
                  final dots = [
                    surface1,
                    compiled?.danger ?? AppColors.danger,
                    compiled?.ok ?? AppColors.ok,
                    compiled?.run ?? AppColors.run,
                    accent,
                    fg2,
                  ];
                  return TapDetector(
                    onTap: () => unawaited(_runThemeUpdate(
                      context,
                      () => tm.applyTheme(item.id),
                    )),
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      width: 152,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            height: 82,
                            padding: EdgeInsets.fromLTRB(
                                S.s12, S.of(10), S.s12, S.of(10)),
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(R.card),
                              border: Border.all(
                                color: selected ? AppColors.fg1 : border2,
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
                                        color: fg1,
                                        height: 1,
                                      ),
                                    ),
                                    SizedBox(width: S.s8),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: S.s6, vertical: S.of(3)),
                                      decoration: BoxDecoration(
                                        color: surface3,
                                        borderRadius:
                                            BorderRadius.circular(R.xs),
                                      ),
                                      child: Text(
                                        '~/',
                                        style: mono(
                                          11,
                                          weight: W.label,
                                          color: fg2,
                                          height: 1,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      width: 14,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: accent,
                                        borderRadius:
                                            BorderRadius.circular(R.xs),
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
                          SizedBox(height: S.s6),
                          Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(
                              12,
                              weight: selected ? W.label : W.body,
                              color: selected ? AppColors.fg1 : AppColors.fg3,
                            ),
                          ),
                          if (item.isAgent) ...[
                            SizedBox(height: S.s2),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AgentMochi(item.agentId, size: 12),
                                SizedBox(width: S.s4),
                                Flexible(
                                  child: Text(
                                    _agentNames[item.agentId] ?? item.agentId,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: sans(11, color: AppColors.fg3),
                                  ),
                                ),
                              ],
                            ),
                          ] else if (item.isUser) ...[
                            SizedBox(height: S.s2),
                            Text(
                              'Yours',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(11, color: AppColors.fg4),
                            ),
                          ],
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
  const _FontCardCarousel({required this.mono, this.client});
  final bool mono;
  final DaemonClient? client;

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
    final target =
        (_scroll.offset + delta).clamp(0.0, _scroll.position.maxScrollExtent);
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
              padding: EdgeInsets.only(bottom: S.of(10)),
              child: Row(
                children: [
                  Text(
                    widget.mono ? 'Code font' : 'UI typeface',
                    style: sans(kMobile ? 15 : 13,
                        weight: W.label, color: AppColors.fg1),
                  ),
                  SizedBox(width: S.s8),
                  Expanded(
                    child: Text(
                      '${active.label} · ${active.description}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, color: AppColors.fg3),
                    ),
                  ),
                  if (!kMobile) ...[
                    SizedBox(width: S.s8),
                    IconBtn(
                      'chevron-left',
                      size: 24,
                      iconSize: 14,
                      tooltip: 'Scroll left',
                      onTap: () => _step(-320),
                    ),
                    SizedBox(width: S.s4),
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
                separatorBuilder: (_, __) => SizedBox(width: S.of(10)),
                itemBuilder: (context, i) {
                  final font = fonts[i];
                  final selected = font.family == active.family;
                  return TapDetector(
                    onTap: () => unawaited(_runThemeUpdate(
                      context,
                      () => widget.mono
                          ? tm.setMonoFontFamily(font.family)
                          : tm.setFontFamily(font.family),
                    )),
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      width: 148,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            height: 76,
                            padding: EdgeInsets.fromLTRB(
                                S.s12, S.of(10), S.s12, S.of(10)),
                            decoration: BoxDecoration(
                              color: AppColors.bg,
                              borderRadius: BorderRadius.circular(R.card),
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
                          SizedBox(height: S.s6),
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
  const _AccentSwatchStrip({this.client});
  final DaemonClient? client;

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
            TapDetector(
              onTap: () => unawaited(_runThemeUpdate(
                context,
                () => tm.setAccentName(null),
              )),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                    EdgeInsets.symmetric(horizontal: S.of(10), vertical: S.s6),
                decoration: BoxDecoration(
                  color: custom == null ? AppColors.accentBg : AppColors.tint2,
                  borderRadius: BorderRadius.circular(R.pill),
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
              TapDetector(
                onTap: () => unawaited(_runThemeUpdate(
                  context,
                  () => tm.setAccentName(a.name),
                )),
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
                        ? Icon(PhIcons.check, size: 14, color: a.accentFg)
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

/// Scaled-down phone home that follows the active theme, accent and fonts.
class _AppearancePreviewCard extends StatelessWidget {
  static const _peek = 236.0;
  static const _h = 360.0;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final live = SessionInfo.fromJson({
      'id': 'preview-live',
      'folder': '/home/you/code/weather-app',
      'title': 'Add hourly forecast view',
      'status': 'running',
      'running': true,
      'running_since': now,
      'branch': 'hourly-forecast',
      'origin_folder': '/home/you/code/weather-app',
      'total_changes': {'files': 64, 'added': 21900, 'removed': 20000},
    });
    final row = SessionInfo.fromJson({
      'id': 'preview-row',
      'folder': '/home/you/code/notes-sync',
      'title': 'Fix offline conflict merge',
      'status': 'idle',
      'last_active': now - 3600,
      'branch': 'main',
      'origin_folder': '/home/you/code/notes-sync',
      'total_changes': {'files': 6, 'added': 412, 'removed': 38},
    });
    // A real-scale crop of the top of home, faded out, over the page's own background.
    return ListenableBuilder(
      listenable: ThemeManager.instance,
      builder: (context, _) => Semantics(
        label: 'Preview of the home screen',
        excludeSemantics: true,
        child: TickerMode(
          enabled: false,
          child: IgnorePointer(
            child: SizedBox(
              height: _peek,
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (r) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.6, 1],
                  colors: [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
                ).createShader(r),
                child: ClipRect(
                  child: LayoutBuilder(
                    builder: (context, c) => OverflowBox(
                      alignment: Alignment.topCenter,
                      minHeight: _h,
                      maxHeight: _h,
                      child: MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(size: Size(c.maxWidth, _h)),
                        child: _home(live, row),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _home(SessionInfo live, SessionInfo row) => Padding(
        padding: EdgeInsets.only(top: S.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 40,
              padding: EdgeInsets.all(S.of(3)),
              decoration: BoxDecoration(
                color: AppColors.tint2,
                borderRadius: BorderRadius.circular(R.pill),
              ),
              child: Row(children: [
                _seg('Sessions', true),
                _seg('Agents', false),
              ]),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(S.s4, S.of(18), S.s4, 0),
              child: Text.rich(TextSpan(children: [
                TextSpan(
                    text: '48.6M',
                    style: sans(kMobile ? 26 : 18,
                        weight: W.strong, color: AppColors.fg1)),
                TextSpan(
                    text: ' tokens today',
                    style: sans(14, color: AppColors.fg3)),
              ])),
            ),
            const MobileSectionLabel('Pinned', top: 14),
            LiveSessionCard(session: live, pinned: true, onTap: null),
            SessionListRow(
                session: row, onTap: null, showProject: true, divider: false),
          ],
        ),
      );

  Widget _seg(String label, bool on) => Expanded(
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AppColors.surface3 : Colors.transparent,
            borderRadius: BorderRadius.circular(R.pill),
          ),
          child: Text(label,
              style: sans(14,
                  weight: on ? W.label : W.body,
                  color: on ? AppColors.fg1 : AppColors.fg3)),
        ),
      );
}

/// A phone settings row; [SettingsRow] with a chevron unless [trailing] is set.
class _V5SettingsRow extends StatelessWidget {
  const _V5SettingsRow({
    required this.label,
    this.leading,
    this.value,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final String label;
  final Widget? leading;
  final String? value;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SettingsRow(
        label: label,
        leading: leading,
        value: value,
        sub: subtitle,
        trailing: trailing,
        onTap: onTap,
        chevron: trailing == null,
      );
}

/// Desktop "Connect a machine" dialog over the Machines page: the command to
/// run on the other computer, then the link it prints. Pops the new [Instance].
/// Connect a machine, expanded inside the Machines card instead of a popover.
class _ConnectMachinePanel extends StatefulWidget {
  const _ConnectMachinePanel(
      {required this.onCancel, required this.onConnected});
  final VoidCallback onCancel;
  final ValueChanged<Instance> onConnected;

  @override
  State<_ConnectMachinePanel> createState() => _ConnectMachinePanelState();
}

class _ConnectMachinePanelState extends State<_ConnectMachinePanel> {
  static const _command = 'snippet serve --enable';
  final TextEditingController _link = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final raw = _link.text.trim();
    if (raw.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final inst = await _connectMachineFromLink(raw);
      if (mounted) widget.onConnected(inst);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Connection failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canConnect = !_busy && _link.text.trim().isNotEmpty;
    Widget label(String text) => Padding(
          padding: EdgeInsets.fromLTRB(0, S.s12, 0, S.s4),
          child: Text(text, style: sans(12, color: AppColors.fg3)),
        );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
      },
      child: Focus(
        autofocus: true,
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            padding: EdgeInsets.all(S.s16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Connect a machine',
                            style: sans(15,
                                weight: W.strong, color: AppColors.fg1)),
                        SizedBox(height: S.s2),
                        Text('Link this app to a computer running snippet',
                            style: sans(12, color: AppColors.fg3)),
                      ],
                    ),
                  ),
                  IconBtn('x',
                      size: 28,
                      iconSize: 15,
                      tooltip: 'Close',
                      onTap: widget.onCancel),
                ]),
                label('Run this on that computer'),
                Container(
                  height: 40,
                  padding: EdgeInsets.fromLTRB(S.s12, 0, S.s6, 0),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(R.md),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: SelectableText(_command,
                          maxLines: 1, style: mono(13, color: AppColors.fg1)),
                    ),
                    Btn('Copy command',
                        small: true, variant: BtnVariant.secondary, onTap: () {
                      Clipboard.setData(const ClipboardData(text: _command));
                      toast(context, 'Copied');
                    }),
                  ]),
                ),
                label('Paste the link it prints'),
                SettingsField(
                  controller: _link,
                  hint: 'https://…?token=…',
                  mono: true,
                  width: 560,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _connect(),
                ),
                if (_error != null) ...[
                  SizedBox(height: S.s8),
                  Text(_error!,
                      style: sans(12, height: 1.4, color: AppColors.danger)),
                ],
                SizedBox(height: S.s16),
                Row(children: [
                  Expanded(
                    child: Text('Connection stays on this device',
                        style: sans(12, color: AppColors.fg3)),
                  ),
                  Btn(_busy ? 'Connecting…' : 'Connect',
                      small: true,
                      disabled: !canConnect,
                      onTap: canConnect ? _connect : null),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
