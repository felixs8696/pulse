# Claude Desktop Code integration

Implemented on `feature/claude-desktop-code`. Not included in Pulse 1.2.1 and not yet verified end to end.

Local Code sessions reuse the Claude Code transcript parser and hook states. Desktop metadata under `~/Library/Application Support/Claude/claude-code-sessions` maps `cliSessionId` to Desktop's `sessionId`. Pulse labels these sessions `Claude Desktop · Code` and opens `claude://code/continue?session=<desktop-session-id>`.

The continue link was verified in the installed Desktop app's URL handler, not documented as a stable public API. It must be checked against a real session before release. An unknown or invalid Desktop ID is hidden rather than opening a new conversation or the last-used chat.

Explicit hook host evidence takes precedence over a saved Desktop mapping, so resuming a session in iTerm or Cursor retains its current destination. Hooks recognize Claude Desktop ancestry and discard inherited iTerm pane IDs. Archived Desktop sessions are excluded. The existing rolling-week, pin, and top-level-session rules still apply. Merely focusing an old Desktop session does not refresh its activity in Pulse.

This covers locally indexed Code sessions only. Regular Chat, Cowork, and cloud-only Code sessions are outside this integration.

Validation: fixture tests cover ID mapping, navigation URLs, invalid IDs, archived sessions, stale host mappings, and Desktop hook ancestry. On the development Mac, 16 Desktop metadata records match standard CLI transcripts, but all are older than the rolling week. Desktop remained on its loading screen during verification, so live navigation and completion alerts still need testing.
