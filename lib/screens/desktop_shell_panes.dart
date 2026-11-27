part of 'desktop_shell.dart';

extension _DesktopShellPanesExt on _DesktopShellState {
  SessionInfo? _draftSource(String? folder) {
    if (folder == null || folder.isEmpty) return null;
    return _sessions
        ?.where((s) => s.projectFolder == folder || s.folder == folder)
        .firstOrNull;
  }

  Widget _tabBody(_ShellTab t, {required bool primary, bool? visible}) =>
      kMobile
          ? _originTabBody(t, primary: primary, visible: visible ?? primary)
          : ShellPanelScope(
              key: ValueKey('body-${t.key}'),
              open: _openShellPanel,
              client: t.client,
              sessionId: t.sessionId,
              // Hosted screens are Scaffolds; let the card colour show through.
              child: Theme(
                data: Theme.of(context)
                    .copyWith(scaffoldBackgroundColor: Colors.transparent),
                child: _originTabBody(t,
                    primary: primary, visible: visible ?? primary),
              ),
            );

  Widget _originTabBody(_ShellTab t,
      {required bool primary, required bool visible}) {
    if (t.isHome) {
      return DesktopHome(
        key: ValueKey('body-${t.key}'),
        client: t.client,
        sessions: _sessions,
        onOpenSession: (s) => _openSession(s.id, s.title, s.profile),
        onOpenAgent: _openRightAgent,
        onRefresh: _loadSessions,
        onOpenAllSessions: SidebarState.showAllSessions,
      );
    }
    if (t.isReadout) {
      final origin = t.readoutOrigin;
      return _withChatHeader(
          t,
          Container(
            key: ValueKey('body-${t.key}'),
            color: kMobile ? AppColors.pageBg : Colors.transparent,
            child: _rightTabBody(
              t.readout!,
              origin == null ? null : _macSessionStatuses[origin]?.state,
              origin == null ? null : _macSessionControls[origin],
              deskTrailing: null,
              onDeskInfo: t.readout!.isAgent ? _showAgentInfo : null,
              // The XO-03 header carries the agent; no pinned head inside.
              onAgentAction: null,
            ),
          ));
    }
    if (t.isDraft) {
      return NewSessionDraft(
        key: ValueKey('body-${t.key}-${t.draftFolder}'),
        client: t.client,
        machineLabel: _active?.label ?? '',
        folder: t.draftFolder,
        source: _draftSource(t.draftFolder),
        recentSessions: _sessions,
        // The tab is a page, not a dialog: the centred hero, no scrim.
        layout: NewSessionLayout.hero,
        onOpenSession: (id) {
          final s = _sessions?.where((s) => s.id == id).firstOrNull;
          _openSession(id, s?.title ?? '', s?.profile);
        },
        onStart: (folder, mode, profile, text) =>
            _startDraft(t, folder, mode, profile, text),
        onStartWithFiles: (folder, mode, profile, text, files) =>
            _startDraft(t, folder, mode, profile, text, files),
      );
    }
    if (t.isPrs) {
      return PullRequestsScreen(
        key: ValueKey('body-${t.key}'),
        client: t.client,
        session: t.prSession!,
        status: t.github!,
        onClose: () => _closePaneTab(t),
      );
    }
    if (t.isTask) {
      return TaskDetailScreen(
        key: ValueKey('body-${t.key}'),
        client: t.client,
        taskId: t.taskId!,
        pane: true,
      );
    }
    if (t.isBoard) {
      return kMobile
          ? TaskKanban(key: ValueKey('body-${t.key}'), client: t.client)
          : TaskBoard(key: ValueKey('body-${t.key}'), client: t.client);
    }
    if (t.isTerminal) {
      if (t.termSessionKey == null) {
        final s = _shells.byId(t.termId!);
        if (s == null) return _emptyPaneHint();
        return SessionTermView(
          key: ValueKey('shell-${t.termId}'),
          alive: s.alive,
          terminal: s.terminal,
          onInput: (bytes) => _shells.write(s.id, bytes),
          onResize: (cols, rows) => _shells.resize(s.id, cols, rows),
          onClose: () => _closePaneTab(t),
          mobileKeys: kMobile,
          showChrome: false,
        );
      }
      final host = _termHosts[t.termSessionKey];
      if (host == null || !host.terms.any((x) => x.id == t.termId)) {
        return _emptyPaneHint();
      }
      return host.buildView(t.termId!, mobileKeys: kMobile);
    }
    if (t.isWorkspace) {
      return WorkspaceTab(
        key: ValueKey('body-${t.key}'),
        client: t.client,
        sessionId: t.workspaceSession!,
        workspacePath: t.workspacePath,
      );
    }
    if (t.isDiff) {
      return GitFileDiffView(
        key: ValueKey('body-${t.key}'),
        client: t.client,
        sessionId: t.sessionId ?? '',
        file: t.diffPath!,
        staged: t.diffStaged,
        untracked: t.diffUntracked,
        embedded: true,
      );
    }
    if (t.isFile) {
      return FileViewer(
        key: ValueKey('body-${t.key}'),
        client: t.client,
        path: t.filePath!,
        name: t.title,
        embedded: true,
        sessionId: t.sessionId,
        relPath: _relToWorkspace(t.filePath!, t.workspacePath),
        onClose: primary ? () => _closeTabByKey(t.key) : null,
      );
    }
    // The header rides inside the session so the docked panel spans full height.
    final info = _sessions?.where((x) => x.id == t.sessionId).firstOrNull;
    // The line under the composer: machine, project and branch.
    return DeskComposerMeta(
        machine: _active?.label ?? '',
        project: lastPathSegment(info?.folder ?? t.workspacePath),
        branch: (info?.branch ?? '').trim(),
        online: _sessionsError == null,
        child: LayoutBuilder(
            builder: (context, box) => SessionScreen(
                  chatHeader: kMobile ? null : _chatHeaderFor(t, box.maxWidth),
                  onTogglePanel: null,
                  onDeskInfo: t.isLead ? _showAgentInfo : null,
                  deskActions: primary
                      ? () => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: _headerTools(t))
                      : null,
                  key: ValueKey('body-${t.key}'),
                  client: t.client,
                  sessionId: t.sessionId!,
                  title: t.title,
                  profile: t.profile,
                  embedded: true,
                  inboundShare: primary ? t.inboundShare : null,
                  onShareConsumed: !primary || t.inboundShare == null
                      ? null
                      : () => _setState(() => t.inboundShare = null),
                  acceptDrops: primary,
                  live: visible,
                  mobileActive: !kMobile ||
                      (_appForeground &&
                          !_mobileChatsOpen &&
                          _mobileHome.isSessionsHome),
                  onTitle: (title) => _onSessionTitle(t.sessionId!, title),
                  onDeleted:
                      primary ? () => _onSessionDeleted(t.sessionId!) : null,
                  onMenu: kMobile ? _showMobileChats : null,
                  mobileTopBar: kMobile && t.isLead
                      ? (openActions) =>
                          _mobileMissionBar(onActions: openActions)
                      : null,
                  onOpenFileTab: (path, name) =>
                      _openFileTab(t.client, t.instanceUrl, path, name),
                  onOpenToolBatch: null,
                  onOpenSession: _openSessionView,
                  onMacStatus: (state, running) =>
                      _setMacSessionStatus(t.key, state, running),
                  onMacControls: !kMobile
                      ? (stop, performAction) =>
                          _setMacSessionControls(t.key, stop, performAction)
                      : null,
                  onGithubReady:
                      !kMobile ? (ok) => _setGithubReady(t.key, ok) : null,
                  onShowPullRequests: !kMobile ? _openPrsTab : null,
                  onTerminalHost: !kMobile
                      ? (host, open) => _setTerminalHost(t.key, host, open)
                      : null,
                  onOpenRightPanel: null,
                  onOpenWorkspace: !kMobile ? _openActiveWorkspace : null,
                  onOpenDiffTab: !kMobile
                      ? (f) =>
                          _openDiffTab(t.client, t.instanceUrl, t.sessionId!, f)
                      : null,
                )));
  }

  /// Desktop chat tabs (Lead, session, agent, group) sit under the XO-03
  /// header bar; everything else is returned untouched.
  Widget _withChatHeader(_ShellTab t, Widget body) {
    if (kMobile) return body;
    return LayoutBuilder(builder: (context, box) {
      final header = _chatHeaderFor(t, box.maxWidth);
      if (header == null) return body;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, Expanded(child: body)],
      );
    });
  }

  /// Whether a left-pane tab draws its own pane row (and so lists the tabs).
  bool _ownsPaneRow(_ShellTab t) {
    if (kMobile) return false;
    final readout = t.readout;
    if ((readout?.agent ?? (t.isLead ? _mcAgent : null)) != null) return true;
    final request = readout?.request;
    if (request != null) {
      return request.id.startsWith('group:') && request.sidePanel != null;
    }
    return t.isSessionChat && readout == null;
  }

  /// The pane's other tabs as pills, for a chat's own pane row.
  List<Widget> _paneTabsFor(_ShellTab t) {
    final left = _tabsIn(_Pane.left);
    if (!left.contains(t)) return const [];
    VoidCallback? dismiss(_ShellTab x) => x.isTerminal
        ? () => _hideTabView(_Pane.left, x)
        : (_canCloseTab(x) ? () => _closePaneTab(x) : null);
    return [
      for (final x in left)
        if (x.key != t.key)
          PanePill(
              key: ValueKey('pane-pill-${x.key}'),
              icon: tabIconKind(x),
              label: x.title.trim().isEmpty ? '(untitled)' : x.title.trim(),
              active: false,
              onTap: () => _activateIn(_Pane.left, x),
              onClose: dismiss(x)),
      for (final r in _rightTabs)
        if (r.pane == _Pane.left)
          PanePill(
              key: ValueKey('pane-pill-${r.key}'),
              icon: r.icon,
              label: r.label,
              active: false,
              onTap: () => _setState(() => _activeKey[_Pane.left] = r.key),
              onClose: () => _closeRightTab(r.key)),
    ];
  }

  Widget? _chatHeaderFor(_ShellTab t, double width) {
    final readout = t.readout;
    final agent = readout?.agent ?? (t.isLead ? _mcAgent : null);
    if (agent != null) {
      final name = agent.displayName.trim().isEmpty
          ? agent.id
          : agent.displayName.trim();
      final sessions = [
        for (final s in _sessions ?? const <SessionInfo>[])
          if (s.displayAgentId == agent.id) s
      ];
      return ChatHeaderBar(
        tabs: _paneTabsFor(t),
        agentIds: [agent.id],
        title: name,
        // State, model and sessions live in the panel's Overview; the row
        // keeps only quiet controls at its right end.
        leading: [
          Builder(
            builder: (ctx) => IconBtn('plus',
                size: 28,
                iconSize: 12,
                tooltip: 'Open a tab',
                onTap: () => _showAgentAddMenu(ctx, agent.id, sessions)),
          ),
        ],
        actions: [
          // Open, the panel's own row carries the hide button.
          if (_panelHidden) _panelButton('sidebar', 'panel'),
        ],
      );
    }
    final request = readout?.request;
    if (request != null) {
      if (!request.id.startsWith('group:') || request.sidePanel == null) {
        return null;
      }
      final ids = request.iconAgentIds ?? const <String>[];
      return ChatHeaderBar(
        tabs: _paneTabsFor(t),
        agentIds: ids,
        title: (request.title ?? '').trim().isEmpty ? 'Group' : request.title!,
        // A group has no workspace and one panel, so no "+" menu.
        // Open, the panel's own row carries the hide button.
        actions: [if (_panelHidden) _panelButton('sidebar', 'panel')],
      );
    }
    if (!t.isSessionChat || readout != null) return null;
    final s = _sessions?.where((x) => x.id == t.sessionId).firstOrNull;
    final mac = _macSessionStatuses[t.key];
    final running = mac?.running ?? s?.running ?? false;
    final needs = mac?.state?.pendingQuestion != null ||
        (s != null && sessionNeedsYou(s));
    final owner = s?.displayAgentId;
    return ChatHeaderBar(
      tabs: _paneTabsFor(t),
      agentIds: [owner ?? 'snippet'],
      title: t.title.trim().isEmpty ? 'Session' : t.title.trim(),
      // Keep the row quiet: state lives in the panel; only a
      // request for the user surfaces here.
      subtitle: needs ? 'Needs you' : '',
      live: running && !needs,
      leading: [
        Builder(
          builder: (ctx) => IconBtn('plus',
              size: 28,
              iconSize: 12,
              tooltip: 'Open a tab',
              onTap: () => _showPaneAddMenu(ctx)),
        ),
      ],
      actions: [_sessionPanelButton(width)],
    );
  }

  /// The agent, Lead or group panel: opened only from the chat header.
  Widget _panelButton(String icon, String what) => IconBtn(icon,
      size: 28,
      iconSize: 12,
      active: !_panelHidden,
      tooltip: _panelHidden ? 'Show $what' : 'Hide $what',
      onTap: _togglePanel);

  /// The session panel: docked when the pane is wide enough, else floating.
  Widget _sessionPanelButton(double width) => ListenableBuilder(
        listenable:
            Listenable.merge([sessionRailCollapsed, sessionRailFloating]),
        builder: (_, __) {
          final docked = width >= kSessionRailMinColumn;
          final on =
              docked ? !sessionRailCollapsed.value : sessionRailFloating.value;
          // Docked open, the panel's own row carries the toggle.
          if (docked && on) return const SizedBox.shrink();
          return IconBtn('sidebar',
              size: 28,
              iconSize: 12,
              active: on,
              tooltip: on ? 'Hide session panel' : 'Show session panel',
              onTap: () {
            if (docked) {
              setSessionRailCollapsed(on);
            } else {
              sessionRailFloating.value = !on;
            }
          });
        },
      );

  bool _isAuxiliary(_ShellTab t) =>
      t.isTerminal ||
      t.isFile ||
      t.isDiff ||
      (kMobile && t.isBoard) ||
      t.isTask ||
      // Desktop: session views opened from + live in the session's inner strip.
      (!kMobile &&
          (t.isReadout || t.isWorkspace || t.isPrs) &&
          t.groupSessionKey != null &&
          t.readout?.request?.purpose != ShellPanelPurpose.conversation);

  List<_ShellTab> get _mainTabs => [
        for (final t in _tabs)
          if (!_isAuxiliary(t)) t,
      ];

  String? _groupRootFor(_Pane p) {
    final stored = _groupRootKey[p];
    if (stored != null && _tabs.any((t) => t.key == stored && t.pane == p)) {
      return stored;
    }
    final active = _activeTab;
    return active != null && active.pane == p ? active.key : null;
  }

  List<_ShellTab> _tabsIn(_Pane p) {
    final root = _groupRootFor(p);
    return [
      for (final t in _tabs)
        if (t.pane == p &&
            !_hiddenTabs.contains(t.key) &&
            paneTabBelongsInGroup(
              rootKey: root,
              tabKey: t.key,
              groupSessionKey: t.groupSessionKey,
              isAuxiliary: _isAuxiliary(t),
            ))
          t,
    ];
  }

  String? _activeGroupKeyFor(_Pane p) =>
      _groupRootFor(p) ?? (_activeTab?.pane == p ? _activeTab?.key : null);

  _Pane get _focusedPane {
    if (_rightCollapsed) return _Pane.left;
    if (_activePane == _Pane.right) {
      final rightHasContent = _tabsIn(_Pane.right).isNotEmpty ||
          _rightTabs.any((r) => r.pane == _Pane.right);
      if (rightHasContent) return _Pane.right;
    }
    return _activeTab?.pane ?? _Pane.left;
  }

  void _activateIn(_Pane p, _ShellTab tab) {
    final i = _tabs.indexOf(tab);
    if (i < 0) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _setState(() {
      _activePane = p;
      _activeKey[p] = tab.key;
      final root =
          _isAuxiliary(tab) ? tab.groupSessionKey ?? _groupRootFor(p) : tab.key;
      if (root != null) _groupRootKey[p] = root;
      if (!_isAuxiliary(tab)) _activeIndex = i;
    });
    _persistTabs();
    _syncPage();
  }

  void _moveTo(_Pane p, _ShellTab tab) {
    final i = _tabs.indexOf(tab);
    if (i < 0) return;
    if (tab.pane == p) return;
    final targetRoot = _groupRootFor(p);
    _setState(() {
      _activePane = p;
      tab.pane = p;
      if (!_isAuxiliary(tab)) _activeIndex = i;
      if (_isAuxiliary(tab)) {
        if (targetRoot != null) {
          tab.groupSessionKey = targetRoot;
          _groupRootKey[p] = targetRoot;
        } else {
          _groupRootKey[p] = tab.groupSessionKey ?? tab.key;
        }
      } else {
        _groupRootKey[p] = tab.key;
        tab.groupSessionKey = null;
      }
      _dockAux(p, tab.key);
    });
    _persistTabs();
  }

  void _dockAux(_Pane p, String key) {
    _activePane = p;
    _activeKey[p] = key;
    if (p == _Pane.right) {
      _rightCollapsed = false;
    }
  }

  void _closePaneTab(_ShellTab t) {
    final pane = t.pane;
    final tabs = _tabsIn(pane);
    final idx = tabs.indexOf(t);
    String? nextKey;
    if (idx >= 0) {
      if (idx + 1 < tabs.length) {
        nextKey = tabs[idx + 1].key;
      } else if (idx - 1 >= 0) {
        nextKey = tabs[idx - 1].key;
      }
    }
    final i = _tabs.indexOf(t);
    if (i >= 0) {
      _closeTab(i);
      if (nextKey != null && mounted) {
        final key = nextKey;
        _setState(() => _activeKey[pane] = key);
      }
    }
  }

  /// A session referenced from a chat opens in the canvas beside it, not as a
  /// new tab. An already open session just comes forward.
  void _openSessionView(String id, String title, String? profile) {
    final tab = _activeTab;
    final c = _client;
    final open = _tabs.any((t) => t.sessionId == id);
    if (kMobile ||
        c == null ||
        tab == null ||
        tab.sessionId == null ||
        tab.isLead ||
        open) {
      _openSession(id, title, profile);
      return;
    }
    _openShellPanel(ShellPanelRequest(
      purpose: ShellPanelPurpose.generic,
      id: 'session:$id',
      client: c,
      sessionId: tab.sessionId,
      title: title.trim().isEmpty ? 'Session' : title,
      builder: (_, close) => SessionScreen(
        client: c,
        sessionId: id,
        title: title,
        embedded: true,
        acceptDrops: false,
        live: true,
        onMenu: close,
      ),
    ));
  }

  void _closeTabAt(_ShellTab t, {bool force = false}) {
    final i = _tabs.indexOf(t);
    if (i >= 0) _closeTab(i, force: force);
  }

  Widget _bodyRow({required bool topInset}) => _splitView(topInset: topInset);

  String? _relToWorkspace(String path, String workspace) {
    final root = workspace.replaceAll(RegExp(r'/+$'), '');
    if (root.isEmpty || !path.startsWith('$root/')) return null;
    return path.substring(root.length + 1);
  }

  Widget _splitView({required bool topInset}) => ShellSplitView(
        key: const ValueKey('shell-split'),
        sidebarHidden: _sidebarHidden,
        sidebarWidth: _sidebarWidth,
        onSidebarResize: _resizeSidebar,
        onSidebarResizeEnd: _saveSidebarWidth,
        onSidebarReset: _resetSidebarWidth,
        sidebar: ShellPanelScope(
          open: _openShellPanel,
          client: _client,
          sessionId: _activeTab?.sessionId,
          child: KeyedSubtree(
              key: _panelScopeKey,
              child: Swap(
                stateKey: _effectiveSection,
                fill: true,
                child: _sidebar(topInset: topInset),
              )),
        ),
        sidebarTop: _sidebarTop(),
        mainHeader: kMobile ? _macWindowBar() : _tabStripBand(),
        tabOwnsStrip: _ownsPaneRow,
        leftStripAfter: _sessionStripAdd(),
        leftStripTrailing: _sessionStripTools(),
        sidebarHeader: _effectiveSection == ShellSection.sessions ||
                _effectiveSection == ShellSection.tasks
            ? null
            : ShellSectionTabs(
                section: _effectiveSection,
                onSelect: (s) => _setState(() => _section = s),
                hidden: _hiddenSections,
              ),
        paneWidth: _paneWidth,
        leftCollapsed: _leftCollapsed,
        rightCollapsed: _rightCollapsed,
        leftTabs: _tabsIn(_Pane.left),
        rightTabs: _tabsIn(_Pane.right),
        // Readouts belong to the screen that opened them; none carry over.
        readouts: [
          for (final r in _rightTabs)
            if (r.originTabKey == _activeTab?.key ||
                (kMobile && r.originTabKey == null))
              r
        ],
        activeKey: _activeKey,
        focusedPane: _focusedPane,
        statusForTab: _statusForTab,
        canCloseTab: (t) => _canCloseTab(t) || t.isTerminal,
        tabBodyBuilder: (t, primary, visible) =>
            _tabBody(t, primary: primary, visible: visible),
        readoutBodyBuilder: (r) {
          final tab = _activeTab;
          final controls = tab == null ? null : _macSessionControls[tab.key];
          final s = tab == null ? null : _macSessionStatuses[tab.key]?.state;
          return _rightTabBody(r, s, controls);
        },
        fallbackBuilder: _paneFallback,
        // The canvas takes the inspector's place while it has content.
        rightPanel: _tabsIn(_Pane.right).isEmpty ? _sessionSidePanel() : null,
        hideRight: _activeTab != null &&
            (_activeTab!.isHome ||
                _activeTab!.isDraft ||
                (_activeTab!.isReadout && !_dockedInfo) ||
                _activeTab!.isPrs ||
                (_activeTab!.isBoard && _tabsIn(_Pane.right).isEmpty)),
        panelHostsReadouts: _activeTab != null &&
            (_activeTab!.sessionId != null || _activeAgent != null),
        onPaneResize: (delta) => _setState(() {
          final max = MediaQuery.sizeOf(context).width * 0.72;
          _paneWidth = (_paneWidth - delta).clamp(kPaneMinWidth, max);
        }),
        onExpandPane: (p) => _setState(() {
          if (p == _Pane.left) {
            _leftCollapsed = false;
          } else {
            _rightCollapsed = false;
          }
        }),
        onMoveTab: _moveTo,
        onMoveReadout: _moveReadout,
        onActivateTab: _activateIn,
        onActivateReadout: (p, r) => _setState(() => _activeKey[p] = r.key),
        onDismissTab: (p, t) {
          if (t.isTerminal) {
            _hideTabView(p, t);
          } else {
            _closePaneTab(t);
          }
        },
        onCloseReadout: (r) => _closeRightTab(r.key),
        hostFor: kMobile ? null : _innerTabHost,
        hostInset: (host, width) => sessionRailCollapsed.value ||
                _inboxSession(host.sessionId) ||
                width < kSessionRailMinColumn
            ? 0
            : sessionRailOuterWidth(width),
      );

  Future<void> _refreshUsage() async {
    if (kMobile) return;
    final c = _client;
    if (c == null) {
      if (_usageItems.isNotEmpty) _setState(() => _usageItems = const []);
      return;
    }
    try {
      final summary = await c.getUsage();
      if (!mounted || !identical(c, _client)) return;
      final byProvider = <String, ShellUsageItem>{};
      for (final provider in summary.providers) {
        final live = provider.rateLimits.where((r) => !r.isExpired).toList();
        if (live.isEmpty) continue;
        live.sort((a, b) => b.usedPercent.compareTo(a.usedPercent));
        final window = live.first;
        final label = usageProviderTitle(provider.provider);
        final item = ShellUsageItem(
          label: label,
          usedPercent: window.usedPercent,
          resetsAt: window.resetsAt <= 0
              ? null
              : DateTime.fromMillisecondsSinceEpoch(window.resetsAt * 1000),
        );
        final prior = byProvider[label];
        if (prior == null || item.usedPercent > prior.usedPercent) {
          byProvider[label] = item;
        }
      }
      _setState(() => _usageItems = byProvider.values.toList());
    } catch (_) {}
  }

  _ShellTab? _innerTabHost(_ShellTab t) {
    if (!_isAuxiliary(t) || t.groupSessionKey == null) return null;
    final root = _tabs.where((x) => x.key == t.groupSessionKey).firstOrNull;
    return root?.sessionId != null && root!.readout == null ? root : null;
  }

  static bool _inboxSession(String? id) => id?.startsWith('inbox-') ?? false;

  void _moveReadout(_Pane p, _RightTab r) {
    if (r.pane == p) return;
    _setState(() {
      final from = r.pane;
      r.pane = p;
      _rightCollapsed = false;
      if (_activeKey[from] == r.key) _activeKey.remove(from);
      _activeKey[p] = r.key;
    });
  }

  Widget? _sessionSidePanel() {
    final tab = _activeTab;
    final agent = _activeAgent;
    final request = tab?.readout?.request;
    final side = request?.sidePanel;
    if (tab != null && side != null) {
      // Restored or sidebar-opened groups skip _openShellPanel; wire the
      // toggle here so the panel row always carries its hide button.
      request!.toggleSide ??= _togglePanel;
      request.showSide ??= _showAgentInfo;
      return _panelHidden
          ? null
          : KeyedSubtree(
              key: ValueKey('side-${tab.key}'),
              // The panel reads its hide toggle from the request scope.
              child: ShellRequestScope(
                  request: request,
                  child: Builder(
                      builder: (c) => side(c, () => _closePaneTab(tab)))));
    }
    if (tab == null || (tab.sessionId == null && agent == null)) return null;
    if (_panelHidden) return null;
    final tabReadouts = [
      for (final r in _rightTabs)
        if (r.pane == _Pane.right &&
            (r.originTabKey == tab.key ||
                (kMobile && r.originTabKey == null)))
          r
    ];
    if (agent != null) {
      final mc = agent.isLead;
      final mcState = mc ? _macSessionStatuses[tab.key]?.state : null;
      return AgentSidePanel(
        key: ValueKey('agent-panel-${tab.key}'),
        contextUsed: mcState?.lastPromptTokens ?? 0,
        contextWindow: mcState?.contextWindow ?? 0,
        onCompact: mc ? () => _dispatchSessionAction('compact') : null,
        onAutonomy: mc ? () => _dispatchSessionAction('autonomy') : null,
        sessionId: mc ? tab.sessionId : null,
        onModel: mc ? () => _dispatchSessionAction('model') : null,
        onOpenSession: (s) => _openSession(s.id, s.title, s.profile),
        onAllSessions: SidebarState.showAllSessions,
        client: tab.client,
        agent: agent,
        onHide: _togglePanel,
        agentId: agent.id,
        agentName: agent.displayName.trim().isEmpty
            ? agent.id
            : agent.displayName.trim(),
        onAction: _agentAction,
        readouts: tabReadouts,
        activeReadout: _activeKey[_Pane.right],
        readoutBody: (r) => _rightTabBody(r, null, null),
        onSelectReadout: (r) =>
            _setState(() => _activeKey[_Pane.right] = r.key),
        onCloseReadout: (r) => _closeRightTab(r.key),
        onClearReadout: () => _setState(() => _activeKey.remove(_Pane.right)),
      );
    }
    if (tab.isLead) {
      return MissionBoardPanel(
        key: ValueKey('board-${tab.instanceUrl}'),
        client: tab.client,
        onOpenSession: (id, title) => _openSession(id, title, null),
        readouts: tabReadouts,
        activeReadout: _activeKey[_Pane.right],
        readoutBody: (r) => _rightTabBody(r,
            _macSessionStatuses[tab.key]?.state, _macSessionControls[tab.key]),
        onSelectReadout: (r) =>
            _setState(() => _activeKey[_Pane.right] = r.key),
        onCloseReadout: (r) => _closeRightTab(r.key),
        onClearReadout: () => _setState(() => _activeKey.remove(_Pane.right)),
        onExpandReadout: _openReadoutTab,
      );
    }
    return null;
  }

  Widget _paneFallback(_Pane p) {
    if (p == _Pane.right) return _emptyPaneHint();
    return _client == null ? _welcome() : _recentPlaceholder();
  }

  void _newGlobalShell() {
    final root = _activeTab;
    if (root == null) return;
    final s = _shells.create();
    _setState(() {
      _tabs.add(_ShellTab.terminal(
        client: root.client,
        instanceUrl: root.instanceUrl,
        termId: s.id,
        termSessionKey: null,
        title: s.title,
        pane: root.pane,
        groupSessionKey: root.key,
      ));
      _groupRootKey[root.pane] = root.key;
      _activeKey[root.pane] = _tabs.last.key;
    });
    _persistTabs();
  }

  void _focusGlobalShell(String id) {
    _shells.focus(id);
    for (final t in _tabs) {
      if (t.isTerminal && t.termSessionKey == null && t.termId == id) {
        final root = _tabs.firstWhere(
          (candidate) => candidate.key == t.groupSessionKey,
          orElse: () => t,
        );
        final i = _tabs.indexOf(root);
        _setState(() {
          if (!_isAuxiliary(root) && i >= 0) _activeIndex = i;
          _hiddenTabs.remove(t.key);
          _groupRootKey[t.pane] = root.key;
          _activeKey[t.pane] = t.key;
        });
        _syncPage();
        return;
      }
    }
  }

  void _closeGlobalShell(String id) {
    _shells.close(id);
    _syncGlobalShellTabs();
  }

  void _syncGlobalShellTabs() {
    if (!mounted) return;
    final live = {for (final s in _shells.shells) s.id: s};
    var changed = false;
    _setState(() {
      final seen = <String>{};
      _tabs.removeWhere((t) {
        if (!t.isTerminal || t.termSessionKey != null) return false;
        final id = t.termId!;
        final duplicate = !seen.add(id);
        final stale = !live.containsKey(id);
        if (!duplicate && !stale) return false;
        _activeKey.removeWhere((_, key) => key == t.key);
        _hiddenTabs.remove(t.key);
        changed = true;
        return true;
      });

      final owner = _activeTab;
      if (owner != null) {
        for (final s in live.values) {
          if (seen.contains(s.id)) continue;
          _tabs.add(_ShellTab.terminal(
            client: owner.client,
            instanceUrl: owner.instanceUrl,
            termId: s.id,
            termSessionKey: null,
            title: s.title,
            pane: owner.pane,
            groupSessionKey: owner.key,
          ));
          seen.add(s.id);
          changed = true;
        }
      }
      for (final t in _tabs) {
        if (t.isTerminal && t.termSessionKey == null) {
          final s = live[t.termId];
          if (s != null && s.title != t.title) {
            t.title = s.title;
            changed = true;
          }
        }
      }
      _normalizeActiveIndex();
    });
    if (changed) _persistTabs();
  }

  void _hideTabView(_Pane p, _ShellTab t) {
    _setState(() {
      _hiddenTabs.add(t.key);
      if (_activeKey[p] == t.key) {
        _activeKey.remove(p);
      }
    });
    _persistTabs();
  }

  Widget _emptyPaneHint() => const EmptyPaneHint();

  _ShellTab? get _chatTab {
    final t = _activeTab;
    return !kMobile && t != null && t.isSessionChat ? t : null;
  }

  Widget? _sessionStripAdd() {
    if (_chatTab == null) return null;
    return Builder(
      builder: (ctx) => StripSquareButton(
          icon: 'plus',
          tooltip: 'Add to this pane',
          onTap: () => _showPaneAddMenu(ctx)),
    );
  }

  /// The panel toggle at the end of the pane row. With the panel docked the
  /// row's right end becomes the panel's own strip, the panel's width wide.
  Widget Function(double)? _sessionStripTools() {
    // The docked panel now has its own pane row with + and the toggle.
    if (_chatTab == null || !kMobile) return null;
    return (width) => ListenableBuilder(
          listenable: Listenable.merge(
              [sessionRailCollapsed, sessionRailFloating, sessionRailFraction]),
          builder: (_, __) {
            final docked = width >= kSessionRailMinColumn;
            final on = docked
                ? !sessionRailCollapsed.value
                : sessionRailFloating.value;
            final toggle = IconBtn('sidebar',
                size: 28,
                iconSize: 12,
                active: on,
                tooltip: on ? 'Hide panel' : 'Show panel', onTap: () {
              if (docked) {
                setSessionRailCollapsed(on);
              } else {
                sessionRailFloating.value = !on;
              }
            });
            // Closed, the panel opens from the chat header (XO-03).
            if (!(docked && on)) return const SizedBox.shrink();
            return Container(
              width: sessionRailOuterWidth(width),
              // Full strip height so the divider meets the panel's below.
              height: double.infinity,
              decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: AppColors.paneSeam, width: AppColors.hairline))),
              padding: EdgeInsets.only(left: S.s6, right: S.s6),
              child: Row(children: [
                Builder(
                  builder: (ctx) => StripSquareButton(
                      icon: 'plus',
                      tooltip: 'More inspector views',
                      onTap: () => _showPanelAddMenu(ctx)),
                ),
                const Spacer(),
                toggle,
              ]),
            );
          },
        );
  }

  /// The session panel's "+": only views that open inside the panel.
  void _showPanelAddMenu(BuildContext ctx) {
    final t = _chatTab;
    if (t == null) return;
    final s = _macSessionStatuses[t.key]?.state;
    final cps = s?.checkpoints.length ?? 0;
    final lanes = s?.lanes.where((l) => l.running).length ?? 0;
    String? count(int n) => n > 0 ? '$n' : null;
    void page(String p) => sessionRailPageRequest.value = p;
    showPaneAddMenu(
      ctx,
      title: t.title,
      views: [
        PaneAddEntry(
            icon: 'folder',
            label: 'Files and changes',
            onTap: () => page('changes')),
        PaneAddEntry(
            icon: 'history',
            label: 'Checkpoints',
            meta: count(cps),
            onTap: () => page('checkpoints')),
        PaneAddEntry(
            icon: 'book-marked', label: 'Memory', onTap: () => page('memory')),
        PaneAddEntry(
            icon: 'git-branch',
            label: 'Lanes',
            meta: lanes > 0 ? '$lanes running' : null,
            onTap: () => page('lanes')),
      ],
    );
  }

  void _showPaneAddMenu(BuildContext ctx) {
    final t = _chatTab;
    if (t == null) return;
    final s = _macSessionStatuses[t.key]?.state;
    final changed =
        fileChanges(sessionChangeSteps(s?.events ?? const [])).length;
    final cps = s?.checkpoints.length ?? 0;
    final lanes = s?.lanes.where((l) => l.running).length ?? 0;
    String? count(int n) => n > 0 ? '$n' : null;
    void act(String a) => _dispatchSessionAction(a);
    // Views open as tabs in the session panel, not as drawers.
    void page(String p) {
      sessionRailPageRequest.value = p;
      if (sessionRailCollapsed.value) setSessionRailCollapsed(false);
    }

    showPaneAddMenu(
      ctx,
      title: t.title,
      views: [
        PaneAddEntry(
            icon: 'list', label: 'Overview', onTap: () => page('overview')),
        PaneAddEntry(
            icon: 'file-diff',
            label: 'Diffs',
            meta: count(changed),
            onTap: () => page('changes')),
        PaneAddEntry(
            icon: 'folder', label: 'Files', onTap: () => page('files')),
        PaneAddEntry(
            icon: 'history',
            label: 'Checkpoints',
            meta: count(cps),
            onTap: () => page('checkpoints')),
        PaneAddEntry(
            icon: 'image',
            label: 'Shared files',
            onTap: () => act('artifacts')),
        PaneAddEntry(
            icon: 'book-marked', label: 'Memory', onTap: () => page('memory')),
      ],
      crew: [
        PaneAddEntry(
            icon: 'git-branch',
            label: 'Lanes',
            meta: lanes > 0 ? '$lanes running' : null,
            onTap: () => page('lanes')),
        PaneAddEntry(
            icon: 'pull-request',
            label: 'Pull requests',
            onTap: () => act('pull_requests')),
      ],
      terminals: [
        PaneAddEntry(
            icon: 'terminal', label: 'Shell', onTap: () => act('shell')),
        PaneAddEntry(
            icon: 'plus', label: 'New terminal', onTap: () => act('shell_new')),
      ],
    );
  }

  /// An agent pane's "+": its views and the agent's sessions. No terminal:
  /// an agent chat has no workspace to run one in.
  void _showAgentAddMenu(
      BuildContext ctx, String? agentId, List<SessionInfo> sessions) {
    final work = agentId != null && agentWorkView.value.contains(agentId);
    final recent = [...sessions]
      ..sort((a, b) => b.lastActive.compareTo(a.lastActive));
    showPaneAddMenu(
      ctx,
      title: 'Open a tab',
      views: [
        if (agentId != null && agentId != 'lead') ...[
          PaneAddEntry(
              icon: 'chat',
              label: 'Chat',
              checked: !work,
              onTap: () => setAgentWorkView(agentId, false)),
          PaneAddEntry(
              icon: 'layers',
              label: 'Desk work',
              checked: work,
              onTap: () => setAgentWorkView(agentId, true)),
        ],
        PaneAddEntry(
            icon: agentId == null ? 'users' : 'info',
            label: agentId == null ? 'Members' : 'Agent info',
            checked: !_panelHidden,
            onTap: _togglePanel),
      ],
      crew: [
        for (final s in recent.take(6))
          PaneAddEntry(
              icon: 'chat-thread',
              label: s.title.trim().isEmpty ? '(untitled)' : s.title.trim(),
              onTap: () => _openSessionView(s.id, s.title, s.profile)),
      ],
    );
  }

  /// Agent tabs: the Chat | Work switch and the panel toggle, in the window bar.
  Widget _agentBarTools(_ShellTab t) {
    final a = t.readout!.agent!;
    final presence = t.client.presence;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      // Only a wait on the user shows here; the stop button and transcript
      // show working.
      ListenableBuilder(
        listenable: presence,
        builder: (_, __) {
          final p = presence.presenceForAgentId(a.id);
          final status = switch (p?.state) {
            'waiting' when PresenceStore.chatWord(p!) == 'waiting on you' =>
              'needs_you',
            _ => null,
          };
          if (status == null) return const SizedBox.shrink();
          return Padding(
            padding: EdgeInsets.only(right: S.s8),
            child: SessionStatusPill(
              status: status,
              startedAt: p!.since > 0
                  ? DateTime.fromMillisecondsSinceEpoch(p.since * 1000)
                  : null,
            ),
          );
        },
      ),
    ]);
  }

  Widget _rightTabBody(
    _RightTab t,
    HarnessState? s,
    _MacSessionControls? controls, {
    Widget? deskTrailing,
    VoidCallback? onDeskInfo,
    ValueChanged<String>? onAgentAction,
  }) =>
      RightTabBody(
        tab: t,
        state: s,
        controls: controls,
        client: _client,
        activeSessionId: _activeTab?.sessionId,
        onClose: () => _closeRightTab(t.key),
        onOpenFile: _openFileFromRightPane,
        deskTrailing: deskTrailing,
        onDeskInfo: onDeskInfo,
        onAgentAction: onAgentAction,
      );

  Widget _mainPane({VoidCallback? onMenu}) => MainPaneView(
        client: _client,
        tabs: _tabs,
        activeIndex: _activeIndex,
        pageController: _pageController,
        onPageChanged: (i) {
          _setState(() => _activeIndex = i);
          _persistTabs();
          _scrollStripToActive();
          _refreshMacGit();
        },
        tabBodyBuilder: (t, primary, visible) =>
            _tabBody(t, primary: primary, visible: visible),
        welcomeView: _welcome(),
        recentPlaceholder: _recentPlaceholder(),
        tabStrip: _tabStrip(onMenu),
        onMenu: onMenu,
      );

  /// Settings is an overlay (spec S0): every entry (gear, shortcut, palette)
  /// lands on the same dialog. Opening again while it is up closes it.
  void _openShellSettings(
      [SettingsPage? page, String? backLabel, String? targetId]) {
    if (_settingsOpen) {
      closeSettingsOverlay();
      return;
    }
    final c = _client;
    if (c == null) return;
    _settingsOpen = true;
    showSettings(
      context,
      client: c,
      instances: _instances,
      active: _active,
      onRemove: _removeInstance,
      onRename: _renameInstance,
      onSelect: _selectInstance,
      onAdd: _onInstanceAdded,
      page: page,
      backLabel: backLabel,
      targetId: targetId,
      onSearchAll: (q) => _openCommandPalette(query: q),
    ).whenComplete(() => _settingsOpen = false);
  }

  Widget _tabStrip(VoidCallback? onMenu) => CardTabStrip(
        controller: _stripController,
        tabs: _tabs,
        activeIndex: _activeIndex,
        onMenu: onMenu,
        subtitleForTab: _tabSubtitle,
        canCloseTab: _canCloseTab,
        onActivateTab: _activateTab,
        onTabMenu: _tabMenu,
        onCloseTab: _closeTab,
        onNewTab: _newSessionFlow,
        isFileActive: _activeTab?.isFile == true,
        onDownloadFile: _downloadActiveFile,
        onEditFile: _editActiveFile,
        chipKeyFor: (key) => _chipKeys.putIfAbsent(key, () => GlobalKey()),
      );

  String _tabSubtitle(_ShellTab t) {
    if (t.isFile) {
      final path = t.filePath ?? '';
      final slash = path.lastIndexOf('/');
      final parent = slash > 0 ? path.substring(0, slash) : '';
      return lastPathSegment(parent, ifEmpty: 'file');
    }
    if (t.isLead) return 'orchestration';
    return _macRepositoryLabel();
  }

  Widget _recentPlaceholder() => ShellRecentPlaceholder(
        sessions: _sessions,
        sessionsLoading: _sessionsLoading,
        onOpenSession: _openSession,
        client: _client,
        machineLabel: _active?.label ?? '',
        onStart: _client == null
            ? null
            : (folder, mode, profile, text) =>
                _startSheet(_client!, folder, mode, profile, text, const []),
        onStartWithFiles: _client == null
            ? null
            : (folder, mode, profile, text, files) =>
                _startSheet(_client!, folder, mode, profile, text, files),
      );

  Widget _welcome() => ShellWelcomeView(
        onAddInstance: _addInstanceFlow,
        onConnected: _onInstanceAdded,
      );

  Future<void> _addInstanceFlow() async {
    final inst = kMobile
        ? await showModal<Instance>(context, const AddInstanceScreen(),
            width: 480, height: 520)
        : await showAddMachineDialog(context);
    if (inst != null) await _onInstanceAdded(inst);
  }

  Future<void> _renameInstance(Instance inst, String name) async {
    final items = (await _store.load())
        .map((e) => e.url == inst.url
            ? Instance(name: name, url: e.url, token: e.token)
            : e)
        .toList();
    await _store.save(items);
    if (!mounted) return;
    _setState(() {
      _instances = items;
      if (_active?.url == inst.url) {
        _active = items.firstWhere((e) => e.url == inst.url);
      }
    });
  }

  Future<void> _onInstanceAdded(Instance inst) async {
    final items = await _store.load()
      ..removeWhere((e) => e.url == inst.url || e.token == inst.token)
      ..add(inst);
    await _store.save(items);
    if (!mounted) return;
    _setState(() => _instances = items);
    _selectInstance(inst);
    _refreshHealth();
  }

  Future<void> _removeInstance(Instance inst) async {
    final items = await _store.load()
      ..removeWhere((e) => e.url == inst.url);
    await _store.save(items);
    if (!mounted) return;
    _setState(() {
      _instances = items;
      for (final tab in _tabs.where((t) => t.instanceUrl == inst.url)) {
        _clearTabState(tab.key);
      }
      _tabs.removeWhere((t) => t.instanceUrl == inst.url);
      if (_activeIndex >= _tabs.length) _activeIndex = _tabs.length - 1;
      if (_active?.url == inst.url) {
        _active = items.isNotEmpty ? items.first : null;
        _client =
            _active != null ? DaemonClient(_active!.url, _active!.token) : null;
        _liveStatus.clear();
      }
    });
    _ensurePinnedLead();
    _connectEventsWatch();
    _syncPage();
  }

  Widget _sidebarTop() {
    if (!kMobile) {
      return ShellTitleRow(
        onToggleSidebar: _toggleSidebar,
        canNavigateBack: _canNavigateBack,
        canNavigateForward: _canNavigateForward,
        onNavigateBack: _navigateBack,
        onNavigateForward: _navigateForward,
        reserveWindowControls: kMacOS,
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        // Centred at 26, level with the traffic lights and the pane bar.
        height: kMobile ? 44 : 52,
        child: Row(children: [
          if (kMacOS) const SizedBox(width: 80) else SizedBox(width: S.of(14)),
          const Spacer(),
          _TbBtn(
              icon: 'sidebar',
              tooltip: kMacOS ? 'Hide sidebar (⌘B)' : 'Hide sidebar (Ctrl+B)',
              onTap: _toggleSidebar),
          // 9 + half the 28 px button's spare 12 = 15, the row content edge.
          const SizedBox(width: 9),
        ]),
      ),
      Padding(
        // Right 9 puts the 16 px icons on the 16 px content edge.
        padding: const EdgeInsets.fromLTRB(16, 0, 9, 6),
        child: SidebarBrand(trailing: [
          _TbBtn(
              icon: 'search',
              tooltip: kMacOS ? 'Search (⌘K)' : 'Search (Ctrl+K)',
              onTap: _openCommandPalette),
          Builder(
            builder: (ctx) => _TbBtn(
                icon: 'edit',
                tooltip: 'New session',
                onTap: () => _showNewMenu(ctx)),
          ),
        ]),
      ),
    ]);
  }

  Widget _sidebarFooter() {
    final needsYou = [
      for (final s in _sessions ?? const <SessionInfo>[])
        if (sessionNeedsYou(s)) s
    ].isNotEmpty;
    return ShellFooterFrame(child: _sidebarFooterRow(needsYou));
  }

  Widget _sidebarFooterRow(bool needsYou) {
    final down = _client != null && _sessionsError != null;
    final need = _mcAttentionCount;
    return Padding(
      padding: const EdgeInsets.only(left: 6, right: 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (need > 0)
          Tooltip(
            message: 'Open needs you',
            child: InkWell(
              key: const ValueKey('footer-needs-you'),
              onTap: _openHomeTab,
              borderRadius: BorderRadius.circular(R.of(6)),
              child: Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: AppColors.run, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                  Text('$need',
                      style: sans(11.5, color: AppColors.fg2, tabular: true)),
                ]),
              ),
            ),
          ),
        // The host only shows when it needs action; settings sits at the left.
        if (down)
          _FooterBtn(
              icon: 'server',
              dot: AppColors.danger,
              tooltip: 'Agent offline, retry',
              onTap: _loadSessions),
      ]),
    );
  }

  /// Desktop centre band: the tab strip, with the title-row cluster over its
  /// left edge while the sidebar is hidden.
  Widget _tabStripBand() => ShellTabStripFrame(
        leading: _sidebarHidden
            ? ShellCollapsedNavCluster(
                onToggleSidebar: _toggleSidebar,
                canNavigateBack: _canNavigateBack,
                canNavigateForward: _canNavigateForward,
                onNavigateBack: _navigateBack,
                onNavigateForward: _navigateForward,
                reserveWindowControls: kMacOS,
              )
            : const SizedBox(width: 8),
        tabs: _mainTabsRow(),
        trailing: _windowBarTools(),
      );

  List<Widget> _windowBarTools() => [
        ListenableBuilder(
            listenable: sessionBarTools,
            builder: (_, __) =>
                sessionBarTools.of(_activeTab?.sessionId) ??
                const SizedBox.shrink()),
        if (_activeTab?.readout?.agent != null) _agentBarTools(_activeTab!),
      ];

  Widget _macWindowBar() => MacWindowBar(
        sidebarHidden: _sidebarHidden,
        onToggleSidebar: _toggleSidebar,
        canNavigateBack: _canNavigateBack,
        canNavigateForward: _canNavigateForward,
        onNavigateBack: _navigateBack,
        onNavigateForward: _navigateForward,
        tabsRow: _mainTabsRow(),
        tools: _windowBarTools(),
        reserveWindowControls: kMacOS,
      );
}

/// Compact 28 px title-row icon button.
class _TbBtn extends StatefulWidget {
  const _TbBtn(
      {required this.icon, required this.tooltip, required this.onTap});
  final String icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  State<_TbBtn> createState() => _TbBtnState();
}

class _TbBtnState extends State<_TbBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: enabled ? (_) => setState(() => _hover = true) : null,
        onExit: enabled ? (_) => setState(() => _hover = false) : null,
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color:
                  _hover && enabled ? AppColors.surface2 : Colors.transparent,
              borderRadius: BorderRadius.circular(R.of(6)),
            ),
            child: Center(
              child: AppIcon(widget.icon,
                  size: 14,
                  color: !enabled
                      ? AppColors.fg3
                      : _hover
                          ? AppColors.fg1
                          : AppColors.fg2),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact footer icon button: 28 x 26 target, 15 px glyph.
class _FooterBtn extends StatefulWidget {
  const _FooterBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.dot,
  });
  final String icon;
  final String tooltip;
  final VoidCallback? onTap;

  /// A small status dot over the glyph's corner.
  final Color? dot;

  @override
  State<_FooterBtn> createState() => _FooterBtnState();
}

class _FooterBtnState extends State<_FooterBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: enabled ? (_) => setState(() => _hover = true) : null,
        onExit: enabled ? (_) => setState(() => _hover = false) : null,
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 28,
            height: 26,
            decoration: BoxDecoration(
              color:
                  _hover && enabled ? AppColors.surface2 : Colors.transparent,
              borderRadius: BorderRadius.circular(R.of(6)),
            ),
            child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(clipBehavior: Clip.none, children: [
                    AppIcon(widget.icon,
                        size: 15,
                        color: !enabled
                            ? AppColors.fg3
                            : _hover
                                ? AppColors.fg1
                                : AppColors.fg3),
                    if (widget.dot != null)
                      Positioned(
                        right: -2,
                        bottom: -1,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                              color: widget.dot, shape: BoxShape.circle),
                        ),
                      ),
                  ]),
                ]),
          ),
        ),
      ),
    );
  }
}
