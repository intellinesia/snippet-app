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
              child: _originTabBody(t,
                  primary: primary, visible: visible ?? primary),
            );

  Widget _originTabBody(_ShellTab t,
      {required bool primary, required bool visible}) {
    if (t.isReadout) {
      final origin = t.readoutOrigin;
      return Container(
        key: ValueKey('body-${t.key}'),
        color: kMobile ? AppColors.bg : Colors.transparent,
        child: _rightTabBody(
          t.readout!,
          origin == null ? null : _macSessionStatuses[origin]?.state,
          origin == null ? null : _macSessionControls[origin],
          deskTrailing: visible && t == _activeTab && t.readout!.isAgent
              ? _agentHeaderTrailing(t)
              : null,
          onDeskInfo: t.readout!.isAgent ? _showAgentInfo : null,
        ),
      );
    }
    if (t.isDraft) {
      return NewSessionDraft(
        key: ValueKey('body-${t.key}-${t.draftFolder}'),
        client: t.client,
        machineLabel: _active?.label ?? '',
        folder: t.draftFolder,
        source: _draftSource(t.draftFolder),
        recentSessions: _sessions,
        onOpenSession: (id) {
          final s = _sessions?.where((s) => s.id == id).firstOrNull;
          _openSession(id, s?.title ?? '', s?.profile);
        },
        onStart: (folder, mode, profile, text) =>
            _startDraft(t, folder, mode, profile, text),
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
      return TaskKanban(key: ValueKey('body-${t.key}'), client: t.client);
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
        onClose: primary ? () => _closeTabByKey(t.key) : null,
      );
    }
    return SessionScreen(
      onTogglePanel: _togglePanel,
      onDeskInfo: t.isMissionControl ? _showAgentInfo : null,
      deskActions: primary
          ? () => Row(
              mainAxisSize: MainAxisSize.min, children: _headerTools(t))
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
              _mobileHome == _MobileHome.chats),
      onTitle: (title) => _onSessionTitle(t.sessionId!, title),
      onMenu: kMobile ? _showMobileChats : null,
      mobileTopBar: kMobile && t.isMissionControl
          ? (openActions) => _mobileMissionBar(onActions: openActions)
          : null,
      onOpenFileTab: (path, name) =>
          _openFileTab(t.client, t.instanceUrl, path, name),
      onOpenToolBatch: null,
      onOpenSession: _openSession,
      onMacStatus: (state, running) =>
          _setMacSessionStatus(t.key, state, running),
      onMacControls: !kMobile
          ? (stop, performAction) =>
              _setMacSessionControls(t.key, stop, performAction)
          : null,
      onGithubReady: !kMobile ? (ok) => _setGithubReady(t.key, ok) : null,
      onShowPullRequests: !kMobile ? _openPrsTab : null,
      onTerminalHost:
          !kMobile ? (host, open) => _setTerminalHost(t.key, host, open) : null,
      onOpenScheduled:
          !kMobile ? () => _toggleRightPanel(_RightPanel.recurring) : null,
    );
  }

  bool _isAuxiliary(_ShellTab t) =>
      t.isTerminal ||
      t.isFile ||
      t.isDiff ||
      (kMobile && t.isBoard) ||
      t.isTask;

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

  void _closeTabAt(_ShellTab t, {bool force = false}) {
    final i = _tabs.indexOf(t);
    if (i >= 0) _closeTab(i, force: force);
  }

  Widget _bodyRow({required bool topInset}) => _splitView(topInset: topInset);

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
          child: Swap(
            stateKey: _effectiveSection,
            fill: true,
            child: _sidebar(topInset: topInset),
          ),
        ),
        sidebarTop: _sidebarTop(),
        mainHeader: _macWindowBar(),
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
        readouts: _rightTabs,
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
        rightPanel: _sessionSidePanel(),
        hideRight: _activeTab != null &&
            (_activeTab!.isDraft ||
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
      );

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
    final side = tab?.readout?.request?.sidePanel;
    if (tab != null && side != null) {
      return _panelHidden
          ? null
          : KeyedSubtree(
              key: ValueKey('side-${tab.key}'),
              child: side(context, () => _closePaneTab(tab)));
    }
    if (tab == null || (tab.sessionId == null && agent == null)) return null;
    if (_panelHidden) return null;
    final tabReadouts = [
      for (final r in _rightTabs)
        if (r.pane == _Pane.right &&
            (r.originTabKey == null || r.originTabKey == tab.key))
          r
    ];
    if (agent != null) {
      final mc = agent.isMissionControl;
      final mcState = mc ? _macSessionStatuses[tab.key]?.state : null;
      return AgentSidePanel(
        key: ValueKey('agent-panel-${tab.key}'),
        contextUsed: mcState?.lastPromptTokens ?? 0,
        contextWindow: mcState?.contextWindow ?? 0,
        onCompact: mc ? () => _dispatchSessionAction('compact') : null,
        onAutonomy: mc ? () => _dispatchSessionAction('autonomy') : null,
        onScheduled:
            mc ? () => _toggleRightPanel(RightPanel.recurring) : null,
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
    if (tab.isMissionControl) {
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
    return SessionSidePanel(
      client: tab.client,
      workspacePath: _macSessionStatuses[tab.key]?.state?.workspace ??
          _activeWorkspaceFolder() ??
          '',
      onOpenFile: (path, name) =>
          _openFileTab(tab.client, tab.instanceUrl, path, name),
      host: _termHosts[tab.key],
      sessionId: tab.sessionId,
      onTogglePanel: _toggleRightPanel,
      onOpenDiff: (f) =>
          _openDiffTab(tab.client, tab.instanceUrl, tab.sessionId!, f),
      readouts: tabReadouts,
      activeReadout: _activeKey[_Pane.right],
      readoutBody: (r) => _rightTabBody(
          r, _macSessionStatuses[tab.key]?.state, _macSessionControls[tab.key]),
      onSelectReadout: (r) => _setState(() => _activeKey[_Pane.right] = r.key),
      onCloseReadout: (r) => _closeRightTab(r.key),
      onClearReadout: () => _setState(() => _activeKey.remove(_Pane.right)),
      onExpandReadout: _openReadoutTab,
    );
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

  Widget _agentHeaderTrailing(_ShellTab t) {
    final tools = buildShellRailTools(
      activeTab: t,
      macSessionStatus: _macSessionStatuses[t.key],
      isRightPanelActive: _rightPanelActive,
      onToggleRightPanel: _toggleRightPanel,
      onSessionAction: _dispatchSessionAction,
      onOpenGoalPopover: _openGoalPopover,
      onAgentAction: _agentAction,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...tools,
        if (_activeTab?.readout?.agent != null) ...[
          if (tools.isNotEmpty) const SizedBox(width: 4),
          Tooltip(
            message: _panelHidden ? 'Show panel' : 'Hide panel',
            child: Material(
              color: _panelHidden ? Colors.transparent : AppColors.surface2,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _togglePanel,
                child: SizedBox.square(
                  dimension: 30,
                  child: Center(
                    child: AppIcon('panel-right',
                        size: 16,
                        color: _panelHidden ? AppColors.fg3 : AppColors.fg1),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _rightTabBody(
    _RightTab t,
    HarnessState? s,
    _MacSessionControls? controls, {
    Widget? deskTrailing,
    VoidCallback? onDeskInfo,
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

  void _openShellSettings([SettingsPage? page]) {
    if (page == null && _settingsOpen) return;
    final c = _client;
    if (c == null) return;
    final inst = _active;
    _settingsOpen = true;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close settings',
      barrierColor: Colors.black.withValues(alpha: 0.38),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, a1, a2) {
        final size = MediaQuery.sizeOf(ctx);
        return Center(
          child: SizedBox(
            width: (size.width - 80).clamp(320.0, 1000.0),
            height: (size.height - 80).clamp(360.0, 700.0),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(R.lg),
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.lg),
                border: Border.all(color: AppColors.border2),
              ),
              child: DesktopSettingsPage(
                client: c,
                instances: _instances,
                active: inst,
                onRemove: _removeInstance,
                onRename: _renameInstance,
                onSelect: _selectInstance,
                onAdd: _onInstanceAdded,
                onBack: () => Navigator.of(ctx).maybePop(),
                initialSection: page,
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, a2, child) {
        final t = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: t,
          child: ScaleTransition(
            scale: Tween(begin: 0.97, end: 1.0).animate(t),
            child: child,
          ),
        );
      },
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
    if (t.isMissionControl) return 'orchestration';
    return _macRepositoryLabel();
  }

  Widget _recentPlaceholder() => ShellRecentPlaceholder(
        sessions: _sessions,
        sessionsLoading: _sessionsLoading,
        onOpenSession: _openSession,
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
    _ensurePinnedMissionControl();
    _connectEventsWatch();
    _syncPage();
  }

  Widget _sidebarTop() {
    return SizedBox(
      height: 44,
      child: Row(children: [
        if (kMacOS) const SizedBox(width: 78) else const SizedBox(width: 14),
        const Spacer(),
        _TbBtn(
            icon: 'sidebar',
            tooltip: kMacOS ? 'Hide sidebar (⌘B)' : 'Hide sidebar (Ctrl+B)',
            onTap: _toggleSidebar),
        const SizedBox(width: 6),
        _TbBtn(icon: 'list', tooltip: 'Tasks', onTap: _openTasksTab),
        const SizedBox(width: 6),
        _TbBtn(icon: 'square-pen', tooltip: 'New session', onTap: _newSessionFlow),
        const SizedBox(width: 10),
      ]),
    );
  }

  Widget _sidebarFooter() {
    final healthy = _active == null ? null : _health[_active!.url];
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(children: [
        Expanded(
          child: HoverSurface(
            key: _topMachineKey,
            radius: 8,
            hoverColor: AppColors.surface2,
            onTap: _instances.isEmpty ? _addInstanceFlow : _openTopMachines,
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: healthy == true ? AppColors.ok : AppColors.fg4,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      _active == null
                          ? 'Add machine'
                          : (_active!.label.isNotEmpty
                              ? _active!.label
                              : _active!.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, color: AppColors.fg2)),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 6),
        if (_client != null) ...[
          ListenableBuilder(
            listenable: AmbientController.instance,
            builder: (_, __) => Builder(
              builder: (ctx) => _ListeningPill(
                on: AmbientController.instance.status.running,
                onTap: () => showAmbientStage(ctx, _client!),
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        if (_client != null) ...[
          Builder(
            builder: (ctx) => _TbBtn(
                icon: 'gauge',
                tooltip: 'Usage',
                onTap: () => showUsagePopover(ctx, _client!)),
          ),
          const SizedBox(width: 2),
        ],
        _TbBtn(
            icon: 'settings',
            tooltip: 'Settings',
            onTap: _openShellSettings),
      ]),
    );
  }

  Widget _macWindowBar() => MacWindowBar(
        sidebarHidden: _sidebarHidden,
        onToggleSidebar: _toggleSidebar,
        canNavigateBack: _canNavigateBack,
        canNavigateForward: _canNavigateForward,
        onNavigateBack: _navigateBack,
        onNavigateForward: _navigateForward,
        tabsRow: _mainTabsRow(),
        onOpenSettings: _openShellSettings,
        machineSwitcher: _topMachineSwitcher(),
        tools: _railTools(),
        reserveWindowControls: kMacOS,
      );

  Widget _topMachineSwitcher() => TopMachineSwitcher(
        active: _active,
        isHealthy: _active == null ? null : _health[_active!.url],
        hasInstances: _instances.isNotEmpty,
        onAdd: _addInstanceFlow,
        onOpenList: _openTopMachines,
        anchorKey: _topMachineKey,
      );

  Future<void> _openTopMachines() async {
    _refreshHealth();
    await showTopMachinesPopover(
      context: context,
      anchorKey: _topMachineKey,
      content: _MachineList(
        instances: _instances,
        active: _active,
        health: _health,
        onSelect: _selectInstance,
        onAdd: _addInstanceFlow,
        onManage: _manageMachine,
        switchOnly: true,
      ),
    );
  }

  void _manageMachine(Instance i) => showManageMachineSheet(
        context: context,
        instance: i,
        onRename: _renameInstance,
        onRemove: _removeInstance,
      );
}

/// The `.tb` button in the `.stop` strip: 28px, fg3 icon, surface2 hover.
class _TbBtn extends StatefulWidget {
  const _TbBtn(
      {required this.icon, required this.tooltip, required this.onTap});
  final String icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_TbBtn> createState() => _TbBtnState();
}

class _TbBtnState extends State<_TbBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _hover ? AppColors.surface2 : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: AppIcon(widget.icon,
                  size: 16, color: _hover ? AppColors.fg1 : AppColors.fg3),
            ),
          ),
        ),
      ),
    );
  }
}

/// The sidebar footer's ambient control: "Listen" when off, the live pill when
/// on; either opens the ambient panel.
class _ListeningPill extends StatelessWidget {
  const _ListeningPill({required this.on, required this.onTap});
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget bar(double h) => Container(
        width: 2,
        height: h,
        decoration: BoxDecoration(
            color: AppColors.ok, borderRadius: BorderRadius.circular(1)));
    return Tooltip(
      message: on ? 'Ambient voice is listening' : 'Ambient listening is off',
      child: HoverSurface(
        radius: 13,
        hoverColor: on
            ? AppColors.ok.withValues(alpha: 0.16)
            : AppColors.fg1.withValues(alpha: 0.08),
        onTap: onTap,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: on ? AppColors.ok.withValues(alpha: 0.10) : null,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (on)
              SizedBox(
                height: 12,
                child: Row(children: [
                  bar(5),
                  const SizedBox(width: 2),
                  bar(11),
                  const SizedBox(width: 2),
                  bar(7),
                  const SizedBox(width: 2),
                  bar(9),
                ]),
              )
            else
              AppIcon('mic', size: 13, color: AppColors.fg3),
            const SizedBox(width: 6),
            Text(on ? 'Listening' : 'Listen',
                style: sans(12, color: on ? AppColors.ok : AppColors.fg3)),
          ]),
        ),
      ),
    );
  }
}
