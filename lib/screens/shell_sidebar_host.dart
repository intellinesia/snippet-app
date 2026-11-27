import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../shells.dart' show GlobalShell;
import '../theme.dart';
import 'agents_sidebar_panel.dart';
import 'file_tree_sidebar_panel.dart';
import 'git.dart';
import 'git_diff_sidebar_panel.dart';
import 'lead/lead_state.dart' show isDedicatedLeadSession;
import 'session.dart' show TerminalInfo;
import '../menu_widgets.dart' show lastPathSegment;
import 'phone_tool_bar.dart';
import 'shell_models.dart';
import 'shell_rail.dart' show ShellSection;
import 'sidebar.dart';
import 'tasks/tasks_panel.dart';
import 'terminals_sidebar_panel.dart';

/// Routes between sidebar panels depending on the active [ShellSection] and state.
class ShellSidebarHost extends StatelessWidget {
  const ShellSidebarHost({
    super.key,
    required this.effectiveSection,
    required this.shells,
    required this.focusShellId,
    required this.activeWorkspaceFolder,
    required this.client,
    required this.activeInstance,
    required this.activeTab,
    required this.sidebarGit,
    required this.onCloseGit,
    required this.onNewTerminal,
    required this.onOpenTerminal,
    required this.onCloseTerminal,
    required this.onOpenRightAgent,
    required this.onOpenSession,
    required this.onOpenDiff,
    required this.onOpenFile,
    this.gitTab = 'changes',
    this.onGitTab,
    this.onOpenPullRequest,
    required this.instances,
    required this.selectedSessionId,
    required this.sessions,
    required this.sessionsLoading,
    required this.sessionsError,
    required this.onRefreshSessions,
    required this.onSessionAction,
    required this.onNewSession,
    this.onNewSessionIn,
    required this.onSelectInstance,
    required this.onOpenLead,
    this.onOpenPalette,
    this.onOpenTasks,
    this.onOpenHome,
    this.onOpenPullRequests,
    this.onOpenArtifacts,
    this.onOpenWakes,
    this.desktopFooter,
    required this.onAddInstance,
    required this.onRenameInstance,
    required this.onRemoveInstance,
    required this.onSessionDeleted,
    required this.health,
    required this.onRefreshHealth,
    required this.mobileHome,
    this.mobileTopBar,
    this.onMobileMenu,
    this.onOpenSettings,
    required this.onMobileHome,
    required this.mobileAgent,
    required this.onMobileAgent,
    this.topInset = true,
    this.onAfterPick,
    this.onSection,
  });

  final ShellSection effectiveSection;
  final List<GlobalShell> shells;
  final String? focusShellId;
  final String? activeWorkspaceFolder;
  final DaemonClient? client;
  final Instance? activeInstance;
  final ShellTab? activeTab;
  final bool sidebarGit;
  final VoidCallback onCloseGit;
  final VoidCallback onNewTerminal;
  final ValueChanged<int> onOpenTerminal;
  final ValueChanged<String> onCloseTerminal;
  final ValueChanged<CoordinationAgent> onOpenRightAgent;
  final void Function(String id, String title, String? profile) onOpenSession;
  final ValueChanged<GitFile> onOpenDiff;
  final String gitTab;
  final ValueChanged<String>? onGitTab;
  final ValueChanged<int>? onOpenPullRequest;
  final void Function(String path, String name) onOpenFile;

  // Sidebar props:
  final bool topInset;
  final VoidCallback? onAfterPick;
  final List<Instance> instances;
  final String? selectedSessionId;
  final List<SessionInfo>? sessions;
  final bool sessionsLoading;
  final String? sessionsError;
  final VoidCallback onRefreshSessions;
  final void Function(String action, [String? extra]) onSessionAction;
  final VoidCallback onNewSession;
  final ValueChanged<String>? onNewSessionIn;
  final ValueChanged<Instance> onSelectInstance;
  final VoidCallback onOpenLead;
  final VoidCallback? onOpenPalette;
  final VoidCallback? onOpenTasks;
  final VoidCallback? onOpenHome;
  final VoidCallback? onOpenPullRequests;
  final VoidCallback? onOpenArtifacts;
  final VoidCallback? onOpenWakes;
  final Widget? desktopFooter;
  final VoidCallback onAddInstance;
  final void Function(Instance inst, String name) onRenameInstance;
  final ValueChanged<Instance> onRemoveInstance;
  final ValueChanged<String> onSessionDeleted;
  final Map<String, bool> health;
  final VoidCallback onRefreshHealth;
  final MobileHome mobileHome;
  final Widget? mobileTopBar;
  final VoidCallback? onMobileMenu;
  final VoidCallback? onOpenSettings;
  final ValueChanged<MobileHome> onMobileHome;
  final CoordinationAgent? mobileAgent;
  final ValueChanged<CoordinationAgent?> onMobileAgent;

  /// Phone chip row: switch between Files, Git and Terminals.
  final ValueChanged<ShellSection>? onSection;

  @override
  Widget build(BuildContext context) {
    final panel = _panel(context);
    // Sidebar lays the footer tools into its own icon row; other panels get it below.
    if (!kMobile && desktopFooter != null && panel is! Sidebar) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: panel),
        SizedBox(
          height: 44,
          child: Align(alignment: Alignment.centerRight, child: desktopFooter),
        ),
      ]);
    }
    final tool = kMobile &&
        (effectiveSection == ShellSection.terminal ||
            effectiveSection == ShellSection.git ||
            effectiveSection == ShellSection.files);
    if (!tool) return panel;
    final folder = (activeWorkspaceFolder ?? '').trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PhoneToolHeader(
        section: effectiveSection,
        subtitle: folder.isEmpty ? '' : lastPathSegment(folder, ifEmpty: folder),
        onSection: onSection,
      ),
      Expanded(child: panel),
    ]);
  }

  Widget _panel(BuildContext context) {
    if (effectiveSection == ShellSection.terminal) {
      return TerminalsSidebarPanel(
        workspacePath: activeWorkspaceFolder ?? '',
        terminals: [
          for (final s in shells)
            TerminalInfo(
              id: s.id,
              title: s.title,
              alive: s.alive,
              live: s.live,
            ),
        ],
        focus: shells.indexWhere((s) => s.id == focusShellId),
        onNewTerminal: onNewTerminal,
        onOpenTerminal: (idx) {
          if (idx < 0 || idx >= shells.length) return;
          onOpenTerminal(idx);
        },
        onCloseTerminal: onCloseTerminal,
        showHeader: !kMobile,
      );
    }

    if (effectiveSection == ShellSection.tasks) {
      final c = client;
      return c == null
          ? const SidebarUnavailable(message: 'Add a machine to see its tasks.')
          : TasksPanel(client: c);
    }

    if (effectiveSection == ShellSection.agents) {
      final c = client;
      return c == null
          ? const SidebarUnavailable(
              message: 'Add a machine to see its agents.')
          : AgentsSidebarPanel(
              client: c,
              onOpenAgent: onOpenRightAgent,
              onOpenLead: onOpenLead,
              lead: sessions
                  ?.where((s) => isDedicatedLeadSession(s.id))
                  .firstOrNull,
            );
    }

    if (effectiveSection == ShellSection.git) {
      final c = client;
      return c == null
          ? const SidebarUnavailable(message: 'Add a machine to see Git diff.')
          : GitDiffSidebarPanel(
              client: c,
              workspacePath: activeWorkspaceFolder ?? '',
              sessionId: activeTab?.sessionId,
              onOpenDiff: onOpenDiff,
              tab: gitTab,
              onTab: onGitTab,
              onOpenPullRequest: onOpenPullRequest,
              showHeader: !kMobile,
            );
    }

    if (effectiveSection == ShellSection.files) {
      final c = client;
      return c == null
          ? const SidebarUnavailable(
              message: 'Add a machine to browse its files.')
          : FileTreeSidebarPanel(
              client: c,
              workspacePath: activeWorkspaceFolder ?? '',
              onOpenFile: onOpenFile,
              showHeader: !kMobile,
            );
    }

    final tab = activeTab;
    if (sidebarGit && tab != null && !tab.isFile) {
      final path = tab.filePath;
      final slash = path?.lastIndexOf('/') ?? -1;
      final folder =
          path != null && slash > 0 ? path.substring(0, slash) : null;
      return Container(
        color: Colors.transparent,
        child: GitScreen(
          client: tab.client,
          sessionId: tab.sessionId ?? '',
          folder: folder,
          embedded: true,
          onClose: onCloseGit,
        ),
      );
    }

    return Sidebar(
      topInset: topInset,
      onOpenPalette: onOpenPalette,
      onOpenTasks: onOpenTasks,
      onOpenHome: onOpenHome,
      onOpenPullRequests: onOpenPullRequests,
      onOpenArtifacts: onOpenArtifacts,
      onOpenWakes: onOpenWakes,
      desktopFooter: desktopFooter,
      onOpenAgent: onOpenRightAgent,
      instances: instances,
      active: activeInstance,
      client: client,
      selectedSessionId: kMobile ? null : selectedSessionId,
      sessions: sessions,
      sessionsLoading: sessionsLoading,
      sessionsError: sessionsError,
      onRefreshSessions: onRefreshSessions,
      onSessionAction: onSessionAction,
      onNewSession: () {
        onNewSession();
      },
      onNewSessionIn: onNewSessionIn,
      onSelectInstance: onSelectInstance,
      onOpenLead: () {
        onOpenLead();
        onAfterPick?.call();
      },
      onOpenSession: (id, title, profile) {
        onOpenSession(id, title, profile);
        onAfterPick?.call();
      },
      onAddInstance: onAddInstance,
      onRenameInstance: onRenameInstance,
      onRemoveInstance: onRemoveInstance,
      onSessionDeleted: onSessionDeleted,
      health: health,
      onRefreshHealth: onRefreshHealth,
      mobileHome: mobileHome,
      mobileTopBar: mobileTopBar,
      onMobileMenu: onMobileMenu,
      onOpenSettings: onOpenSettings,
      onMobileHome: onMobileHome,
      agent: mobileAgent,
      onAgent: onMobileAgent,
    );
  }
}

/// Fallback banner when a sidebar section requires an active machine connection.
class SidebarUnavailable extends StatelessWidget {
  const SidebarUnavailable({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      padding: EdgeInsets.fromLTRB(S.s20, S.s24, S.s20, S.s20),
      child: Text(message, style: sans(12, color: AppColors.fg3, height: 1.5)),
    );
  }
}
