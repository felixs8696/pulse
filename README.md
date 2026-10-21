# Pulse

A local macOS companion for Claude Code in iTerm or Cursor, Codex Desktop, and Cursor agents. A small vertical floating pill stays above your windows, including across Spaces. Hover for your recent sessions; pin the ones you want to keep nearby. No server, API keys, analytics, or third-party packages.

Download the Mac app from [Releases](https://github.com/felixs8696/pulse/releases), or build it locally below.

## Run

Requires macOS 14+ and Apple’s Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/felixs8696/pulse.git
cd pulse
bash scripts/build.sh --run
```

The runnable app is `build/Pulse.app`. You can keep it there or move it to Applications. It is signed locally for this Mac, not notarized for distribution.

* Hover the pill to expand it; moving away collapses it after a short delay. The pill stays at a fixed position while the separate shelf fades and slides into view. The shelf opens alongside it, switching sides when needed, with a constant 10-point gap between the visible edges. Lavender and white counts show working agents and sessions waiting for you.
* Click the pill to keep the shelf open, including after a hover preview; it stays open when you move away. Click again to release and collapse it. Hover previews resume after you leave and return to the pill. Search focus does not silently toggle the hold. Escape also collapses it. Clicks and drags have separate handling.
* Drag the pill, the expanded panel’s title area, or its empty background to place it anywhere. Search, tabs, session rows, and their controls keep their normal interactions. During a drag the pill and shelf share one native window, so they move together instead of one window chasing the other. Placement and position saving happen when you release. Its position persists; use the menu-bar menu to reset it.
* Each working session has a soft lavender comet traveling around the pill's border, with a stable phase and tempo. When it stops working, its trace eases to rest and fades away. The border stays quiet at idle; macOS Reduce Motion replaces the movement with static ticks.
* In the expanded panel, working sessions' logos dim and brighten together on a shared 2.6-second cycle. Other logos stay still. This effect stops while the panel is collapsed and respects Reduce Motion.
* Activity updates gently move each complete row into its new position over 0.36 seconds, without bounce. Icons, text, and controls travel together. Departing rows first fade out in place for 0.2 seconds, then the list closes the empty space; additions fade in. Reduce Motion makes these changes instant.
* **Control–Space** toggles the shelf without needing Accessibility permissions.
* Use **Pinned**, **Working**, **Waiting**, **Today**, and **Older**, search by title/project, or filter by app. Pinned keeps saved sessions across all dates. Today includes today’s activity plus actively running sessions; Older holds inactive sessions from previous days.
* Pin sessions with the pin beside a row. Working sorts by when you last sent each agent a message, newest first; tool activity and status updates never move a working row. Sessions without a known message timestamp stay at the bottom in a stable order. Other sections sort by actual activity, newest first. Hover a row for the exact date and status evidence.
* The subtext beneath a session title shows your latest user message, excluding tool responses and generated context. Search also matches this message. If the source does not retain readable message text, the row says so.
* Clicking a session opens its app and conversation. Opening a session does not clear it from Waiting. A finished reply stays there for the current local calendar day, unless a new user turn starts or you choose **Mark read**. At midnight it moves to Older without being deleted or marked handled. Use the envelope button or right-click menu to explicitly **Mark read** or **Mark unread**. Read replies leave Waiting and lower the pill count; find them in Today or Pinned to mark unread again. **Mark all read** affects only the displayed list. Read/unread state is saved locally across restarts, applies to that specific reply, and never changes just by opening a session. Marking unread does not play a sound or override the daily expiry.
* A soft two-tap chime plays only when a tracked agent's reply is ready. Its base pitch is deterministically hashed from the session ID into 24 notes (C4–B5), so the same session keeps its pitch across restarts. Right-click a session and choose **Preview session sound** to learn it. Different sessions can share a note. Input and approval requests stay silent. Repeated refreshes stay silent, and starting the app does not replay existing replies; genuinely new replies arriving during the initial scan still chime. Replies arriving together play their session tones in sequence. Use the speaker button in the panel’s top-right corner to mute or unmute. It stays synchronized with **Play sound when a reply is ready** in the menu-bar menu, and the setting survives restarts. Unmuting plays a short confirmation chime.
* The menu-bar menu includes launch at login, setup, reset position, and Quit.

## Cursor setup

Install the tiny local bridge once so local Cursor conversations open in their workspace:

```sh
python3 scripts/setup-cursor.py
```

The navigation extension activates on its first link. It selects the exact Claude tab, Cursor agent chat, or recorded terminal process in the matching workspace (including multi-folder workspaces). Claude tabs are opened through the installed Claude extension’s session-opening command without submitting a prompt. The navigation extension can install while agents remain running and handles Cursor agent chats, Claude tabs, and terminal panes. It contains no network client and never starts a new agent turn. You can uninstall **Pulse · Session router** from Cursor’s Extensions panel.

## Claude Code setup

Existing `~/.claude/agent-manager/sessions` reports are detected automatically. To capture precise approval states and terminal pane IDs for **new sessions**, install Pulse’s own hooks:

```sh
python3 scripts/setup-claude.py
```

The installer backs up `~/.claude/settings.json`, preserves other settings and hooks, and merges only Pulse’s commands. It is safe to run again. Restart Claude Code sessions after installing. To remove these hooks:

```sh
python3 scripts/setup-claude.py --remove
```

Rows show the host separately from the agent: **Cursor · Claude**, **Cursor · Terminal**, or **iTerm · Claude**. Cursor’s saved tab-to-workspace mapping and explicit process host reports take precedence over inherited iTerm environment variables. Claude sessions with an unknown host or missing navigation target are hidden from every tab, pins, counts, and sounds. They can reappear when a later status report identifies a usable destination.

The first time Pulse checks iTerm panes, macOS may ask to let Pulse control iTerm. Allow it for live pane detection and exact pane selection. This uses Apple Events, not screen recording. Sessions whose captured iTerm pane is no longer open are hidden from every tab, pins, counts, and sounds. A failed inventory check preserves the last known inventory. Closed panes never trigger a resume prompt or create a new terminal.

## What is tracked

| Source | Local data | Return to session |
| --- | --- | --- |
| Claude Code | `~/.claude/projects/**/*.jsonl`, optional status reports and hooks | Select the original Cursor workspace and Claude tab, Cursor terminal process, or iTerm window/tab/split; hide closed iTerm panes without offering resume |
| Codex Desktop | Newest `~/.codex/state_*.sqlite` thread index plus its rollout logs | `codex://threads/<id>` |
| Cursor | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, composer headers and metadata | Local `cursor://local.pulse-router/open` URI → matching workspace → exact composer |

All unarchived indexed Codex/Cursor sessions and local Claude transcripts are scanned. Only top-level conversations you interact with are included. Child agents, background subtasks, and internal reviews are excluded from the list, counts, and sounds, even if running, waiting, or previously pinned. Waiting includes outstanding finished replies and requests for input dated today in your Mac’s local time zone. Previous days move to Older at local midnight, without deleting or acknowledging them. Pins do not exempt old replies from expiry; pinned sessions remain accessible in Pinned, and actively running sessions remain in Working regardless of age. Explicit handling applies only to that reply; later completions return to the inbox. Existing automatic click acknowledgments from older builds are ignored. The pill shows today’s total across top-level sessions; the Waiting tab shows the count matching the current search and app filter, with a one-click option to show the full inbox. Pins and acknowledgments are local to Pulse and do not change the source apps.

The scanner polls every three seconds on a background queue and discovers new Claude transcript files every fifteen seconds. Transcript reads are bounded and cached by file size and modification time. Databases are opened strictly read-only and retain WAL visibility. Authentication files are not read, and nothing is sent to a server. Source messages are not copied into a second transcript store.

## Limits

These applications do not share a public universal session API. Pulse uses the installed versions’ local formats and deep links; an app update can require adapting a reader. Connections & setup reports missing/unreadable sources. Remote/cloud sessions only appear if the desktop app has indexed them locally. This is not an account-wide cloud monitor.

Claude approvals are precise with hooks or existing agent-manager reports. Codex and Cursor states are based on lifecycle events and stored metadata. Approvals that the app does not write locally cannot be reliably detected; Pulse uses “Status unavailable” when evidence is missing and stops calling stale turns “Working” after six hours. “Reply ready” means a completed turn, not guaranteed project completion. Restored Codex history uses original turn times and stays out of Waiting and reply sounds until a genuine new turn runs. Generated task notifications do not replace your query. Source-app unread status is not synchronized with Pulse’s local acknowledgments.

Codex deep links target the installed `codex` scheme (on this Mac that is the ChatGPT/Codex app). The Cursor bridge opens the matching workspace window and conversation; if that workspace is closed, it opens a new window. Multiple windows with the same workspace may each reveal the conversation. iTerm exact pane restoration requires a captured live session ID. Accessibility-based window guessing is intentionally avoided.

## Share a build

Run `bash scripts/export.sh` to create `build/Pulse-macOS.zip` and its SHA-256 checksum. The ZIP includes a universal Apple Silicon/Intel app for macOS 14+, the Cursor extension, optional Claude hook installers, and recipient instructions. Only explicitly listed build artifacts are packaged; your sessions and local preferences are excluded. The app is ad-hoc signed, not notarized, so recipients may need macOS's Open Anyway flow. See [DISTRIBUTION.md](DISTRIBUTION.md).

## Validate

```sh
bash scripts/test.sh
```

Inspect current discovery without launching the UI (prints session titles and project paths locally):

```sh
.build/debug/Pulse --diagnose
```

The Swift package separates the native app from the session scanner/parser library. There is no dependency download step.
