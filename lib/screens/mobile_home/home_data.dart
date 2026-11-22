import '../../crew_status.dart';
import '../../models.dart';
import '../../notification_text.dart' show approvalOf;
import '../../presence.dart';
import '../session_list_row.dart' show sessionNeedsYou;
import '../shell_nav.dart' show sessionBusy;

enum AskKind { approval, question, handoff }

/// One card in the Needs you pager.
class AskItem {
  const AskItem(this.kind, this.session);

  final AskKind kind;
  final SessionInfo session;

  String get id => session.id;
  String get agentId => session.displayAgentId ?? 'snippet';
}

AskKind askKindOf(SessionInfo s) {
  final type = '${s.attention?['type'] ?? ''}'.toLowerCase();
  if (type == 'approval' && approvalOf(s.attention!) != null) {
    return AskKind.approval;
  }
  if (type == 'handoff' ||
      type == 'in_review' ||
      type == 'review' ||
      (s.attention == null && s.status == 'in_review')) {
    return AskKind.handoff;
  }
  return AskKind.question;
}

/// Every session that needs the user, managed or not: approvals, then
/// questions, then handoffs, newest first within each.
List<AskItem> needsYouItems(Iterable<SessionInfo> sessions) {
  final items = [
    for (final s in sessions)
      if (sessionNeedsYou(s)) AskItem(askKindOf(s), s),
  ];
  items.sort((a, b) {
    final r = a.kind.index.compareTo(b.kind.index);
    return r != 0 ? r : b.session.lastActive.compareTo(a.session.lastActive);
  });
  return items;
}

/// The agent that runs a managed session.
String? managedOwner(SessionInfo s) => s.workerAgentId ?? s.ownerAgentId;

/// Non-settled agent-managed sessions per owning agent, newest first.
Map<String, List<SessionInfo>> managedByAgent(Iterable<SessionInfo> sessions) {
  final out = <String, List<SessionInfo>>{};
  for (final s in sessions) {
    final owner = managedOwner(s);
    if (!s.agentManaged || s.settled || owner == null || owner.isEmpty) continue;
    (out[owner] ??= []).add(s);
  }
  for (final l in out.values) {
    l.sort((a, b) => b.lastActive.compareTo(a.lastActive));
  }
  return out;
}

/// The Sessions list: human-managed, not already shown as an ask, newest
/// first, split into live rows and the settled fold.
({List<SessionInfo> main, List<SessionInfo> settled}) humanSessions(
    Iterable<SessionInfo> sessions) {
  final main = <SessionInfo>[], settled = <SessionInfo>[];
  for (final s in sessions) {
    if (s.agentManaged) continue;
    if (s.settled) {
      settled.add(s);
    } else if (!sessionNeedsYou(s)) {
      main.add(s);
    }
  }
  int byRecent(SessionInfo a, SessionInfo b) =>
      b.lastActive.compareTo(a.lastActive);
  main.sort(byRecent);
  settled.sort((a, b) =>
      (b.settledAt ?? b.lastActive).compareTo(a.settledAt ?? a.lastActive));
  return (main: main, settled: settled);
}

/// Managed sessions of one agent: running ones, then the rest.
({List<SessionInfo> running, List<SessionInfo> idle}) managedSplit(
    List<SessionInfo> sessions) =>
    (
      running: [for (final s in sessions) if (sessionBusy(s)) s],
      idle: [for (final s in sessions) if (!sessionBusy(s)) s],
    );

/// When the agent last did anything: its newest session or direct message.
int agentActivityMs(CrewEntry e) {
  final session = (e.sessions.firstOrNull?.lastActive ?? 0) * 1000;
  final said = e.agent.lastMessage?.at?.millisecondsSinceEpoch ?? 0;
  return session > said ? session : said;
}

/// An agent row: what it is doing, for ordering and the status line.
class AgentRow {
  const AgentRow(this.agent, this.state, this.line);

  final CoordinationAgent agent;
  final CrewState state;
  final String line;
}

({List<AgentRow> working, List<AgentRow> needs, List<AgentRow> asleep})
    agentRows(List<CoordinationAgent> agents, List<SessionInfo> sessions,
        {PresenceStore? presence}) {
  final crew = deriveCrew(
      [for (final a in agents) if (a.id != 'lead') a], sessions,
      presence: presence);
  final working = <AgentRow>[], needs = <AgentRow>[], asleep = <AgentRow>[];
  final at = <String, int>{};
  for (final e in crew) {
    at[e.agent.id] = agentActivityMs(e);
  }
  for (final e in crew) {
    final asks = e.state == CrewState.needsYou ||
        (e.agent.available && e.agent.needsYou > 0);
    if (asks) {
      final line = e.state == CrewState.needsYou
          ? (e.isApproval ? 'Waiting for your approval' : 'Asked you a question')
          : 'Asked you a question';
      needs.add(AgentRow(e.agent, CrewState.needsYou, line));
    } else if (e.state == CrewState.working) {
      working.add(AgentRow(e.agent, CrewState.working, e.line));
    } else {
      asleep.add(AgentRow(e.agent, CrewState.standingBy, e.line));
    }
  }
  // Latest activity first, name as the tiebreak.
  int byRecent(AgentRow a, AgentRow b) {
    final r = at[b.agent.id]!.compareTo(at[a.agent.id]!);
    return r != 0
        ? r
        : a.agent.displayName
            .toLowerCase()
            .compareTo(b.agent.displayName.toLowerCase());
  }

  working.sort(byRecent);
  needs.sort(byRecent);
  asleep.sort(byRecent);
  return (working: working, needs: needs, asleep: asleep);
}

/// Default folds on each open: Asleep agents show, Settled sessions stay
/// collapsed. A tap overrides; a search opens Settled so matches are visible.
bool asleepOpenFor(bool? user) => user ?? true;
bool settledOpenFor(bool? user, {bool searching = false}) =>
    searching || (user ?? false);

/// When a group last had activity (newest event, else creation time).
DateTime? groupActivityAt(GroupSummary g) =>
    DateTime.tryParse(g.lastEventAt ?? '') ?? DateTime.tryParse(g.createdAt);

/// Groups ordered most recent activity first, title ascending as tiebreak.
List<GroupSummary> sortedGroups(Iterable<GroupSummary> groups) {
  final out = groups.toList();
  out.sort((a, b) {
    final at = groupActivityAt(a);
    final bt = groupActivityAt(b);
    if (at != bt) {
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    }
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return out;
}

/// True when a group matches a search query on title, preview or member names/ids.
bool groupMatchesQuery(
  GroupSummary g,
  String query, {
  Map<String, String> agentNames = const {},
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if (g.title.toLowerCase().contains(q)) return true;
  if ((g.preview ?? '').toLowerCase().contains(q)) return true;
  for (final m in g.members) {
    if (m.id.toLowerCase().contains(q)) return true;
    final name = agentNames[m.id];
    if (name != null && name.toLowerCase().contains(q)) return true;
  }
  return false;
}

/// Fallback subtitle when a group has neither live activity nor a preview.
String groupMemberSummary(GroupSummary g, String Function(String id) nameOf) {
  final n = g.members.length;
  return [
    '$n ${n == 1 ? 'member' : 'members'}',
    if (g.lead != null) 'lead ${nameOf(g.lead!)}',
  ].join(' · ');
}
