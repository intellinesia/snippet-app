// Public entry point for Lead. The screen and supporting widgets
// live in this directory; this file re-exports the entry function so existing
// callers (`lib/screens/desktop_shell.dart`) keep working.
library;

export 'lead/lead_state.dart'
    show
        agentOpensLeadSession,
        isDedicatedLeadSession,
        isInboxSession,
        isInboxSessionRow,
        isLeadListRow,
        isLeadTab;
