# Pulse guide

[← Back to Pulse](../README.md) · [Install and connect your apps](../DISTRIBUTION.md)

## The pill and panel

Hover the pill to open the panel. Move away from the pill and panel to collapse it, or press Escape. Clicking the pill does not keep it open by default. Enable **Click pill to keep panel open** in the top-right menu if you prefer clicking once to keep it open and again to collapse it. **Control–Space** shows or hides it.

The pill stays above your windows and across Spaces. Lavender counts show working agents; white counts show sessions waiting for you today. Each working agent has a subtle trace around the pill's border. Working logos in the expanded panel dim together. Both effects respect macOS Reduce Motion.

A pill appears on your laptop screen and external monitors by default. You can turn off **Show pill on every display** in the panel's top-right menu beside the sound button. Hover or click a pill to open the session panel on that display. Counts, pins, read state, and sounds are shared. Extra pills don't play extra alerts. Each display remembers its own pill position, including when you rearrange or reconnect it. With the option off, a single pill stays on the display where you last used it. This setting controls connected displays, while Spaces are macOS virtual desktops.

Drag the pill, the panel's title area, or its empty background to move both surfaces together. Their position persists. The panel opens on whichever side has room, keeping a constant gap from the pill. Use the menu-bar menu to reset its position.

Pulse is a menu-bar app and doesn't appear in the Dock. The menu also includes launch at login, connections, sound, and Quit.

## Finding a conversation

| Tab | What belongs here |
| :--- | :--- |
| **Pinned** | Conversations you've saved, across all dates. |
| **Working** | Agents currently running a turn. Ordered by your most recent message, so tool activity doesn't shuffle the list. |
| **Waiting** | Today's outstanding replies and requests for input. |
| **Today** | Today's activity and agents still running. |
| **Older** | Inactive conversations from previous days. |

Search matches titles, projects, and your latest message. The app filter narrows results, including tab counts. Other than Working, lists sort by actual activity time. Hover a row for its exact date and the evidence behind its status.

The subtext shows your latest user message, excluding tool responses, attachments, and generated context. If readable text isn't available, the row says so. Status badges appear in tabs that mix states; Working and Waiting already describe their contents.

## Returning to a session

Click a row to reopen the original conversation. Pulse uses Codex deep links, a small Cursor router, and captured iTerm pane IDs. It doesn't start a new agent turn.

Claude rows identify their host separately from the agent: **Cursor · Claude**, **Cursor · Terminal**, or **iTerm · Claude**. Unknown or unusable destinations are hidden. Closed iTerm panes leave the list, counts, pins, and sounds rather than offering to create a new terminal. A failed pane inventory check preserves the last known inventory.

The first iTerm check may trigger a macOS Automation prompt. Permission enables live pane detection and selection through Apple Events; screen recording isn't used.

Cursor's router selects the matching workspace and exact chat, Claude tab, or recorded terminal process. If the workspace is closed, it can open a window for it. Multiple windows with the same workspace may each reveal the conversation.

## Read, unread, and Waiting

Opening a chat through Pulse marks its current reply read after the destination opens successfully. Sending a new message also clears the outstanding reply when the scanner detects it. A new agent reply becomes unread again.

Unread rows have bold titles and appear above read rows. Read titles use regular weight and slightly dimmer text. Each group is sorted newest first. Working keeps its order based on your latest message. Waiting keeps today's read replies below unread ones, and its count includes only unread replies.

Use the row menu to mark a reply unread again or mark it read manually. **Mark displayed replies read** applies to the current filtered list. Read state is saved locally and does not change the source app.

## Completion sounds

A soft two-tap chime plays when a tracked reply becomes ready. By default, a stable hash of the session ID selects its pitch from 24 notes. Different sessions can share a note.

Open a row's three-dot menu to set its **Completion tone** from 1 (low) to 100 (high). Releasing the slider previews the tone, and **Preview** plays it again. Choices are saved locally per session across restarts. **Reset** restores that session's automatic tone. Explicit previews play even when completion alerts are muted.

Approval requests and input requests stay silent. Refreshes don't replay a sound; starting the app doesn't chime for an existing backlog. Genuine replies arriving during the initial scan still chime. Simultaneous completions queue their tones.

Mute from the panel's top-right speaker or **Play sound when a reply is ready** in the menu-bar menu. Both controls share a saved setting. Unmuting plays a short confirmation chime.

## Setting up from source

For Codex Desktop, no additional setup is required.

For Cursor, install the local session router:

```sh
python3 scripts/setup-cursor.py
```

It activates on its first link and can install while agents remain running. Claude tabs also require the Claude Code extension. Uninstall **Pulse · Session router** from Cursor's Extensions panel to remove it.

Pulse installs and repairs Claude hooks automatically when Python 3 from Apple’s Command Line Tools is available. For manual setup:

```sh
python3 scripts/setup-claude.py
```

The installer backs up `~/.claude/settings.json`, preserves existing settings and hooks, and merges only Pulse's commands. It is safe to run again. Keep current chats open and continue with your next message or tool action. Current Claude Code versions normally reload hooks automatically. If a chat does not connect, check `/hooks`. To remove Pulse's hooks:

```sh
python3 scripts/setup-claude.py --remove
```

Existing `~/.claude/agent-manager/sessions` reports are detected automatically.

## Tracking and limits

| Agent | Local source | Navigation |
| :--- | :--- | :--- |
| Claude Code | `~/.claude/projects/**/*.jsonl`, optional hooks and status reports | Original Cursor tab or terminal, or live iTerm pane. |
| Codex Desktop | Newest `~/.codex/state_*.sqlite` index and rollout logs | `codex://threads/<id>` |
| Cursor agents | Cursor's local `state.vscdb` and composer metadata | `cursor://local.pulse-router/open` to the matching workspace and composer. |

Only top-level, unarchived, locally indexed conversations with usable destinations appear. This isn't an account-wide cloud monitor. Claude chat, Cowork, and ChatGPT chat aren't integrated. Codex CLI conversations can appear if locally indexed, but navigation returns to Desktop rather than the CLI pane.

Claude hooks provide precise approval states. Codex and Cursor use lifecycle events and stored metadata. If an app doesn't record an approval locally, Pulse can't reliably detect it. Missing evidence becomes **Status unavailable**; a stale turn stops being **Working** after six hours. **Reply ready** means a turn completed, not that the project is finished.

Restored Codex history keeps its original timestamps and stays out of Waiting and completion sounds until a genuine live turn runs. Generated notifications don't replace your query. Connections & setup reports missing or unreadable sources. Source-app format changes may require compatibility fixes.

The scanner checks each app independently every three seconds and discovers new Claude transcript files every fifteen seconds. It loads chats active in the past seven days, plus pinned chats. Sending a new message in an older conversation brings it back. Simply opening a chat may not update its activity timestamp. Child-agent transcripts are skipped. Transcript reads and backward searches are bounded, so startup does not walk entire histories. Slow sources show a message in Connections & setup after twelve seconds, while other apps continue loading. iTerm permission checks run separately from chat discovery. Databases are read-only with WAL visibility. Authentication files aren't read. Conversations aren't uploaded or copied into a second transcript store.

## Builds and diagnostics

Run checks:

```sh
bash scripts/test.sh
```

Create a universal Apple Silicon/Intel ZIP and SHA-256 checksum:

```sh
bash scripts/export.sh
```

Only explicitly listed build artifacts are packaged. Sessions and local preferences are excluded. The app is ad-hoc signed, not notarized; no auto-update service is included. See the [distribution guide](../DISTRIBUTION.md).

Inspect discovery locally without opening the UI:

```sh
swift build --disable-sandbox
.build/debug/Pulse --diagnose
```

The `--diagnose` output includes your session titles and project paths. Keep it local.

For a shareable report of versions, running apps, scan times, and source counts:

```sh
/Applications/Pulse.app/Contents/MacOS/Pulse --diagnose-health 2>/dev/null
```

This report excludes chat text, titles, session IDs, project paths, and raw source errors. It stops waiting after twenty seconds and identifies any source still scanning. It does not request iTerm automation permission.

## Documentation screenshots

```sh
bash scripts/screenshots/render.sh
```

The renderer builds a temporary entry point against Pulse's real SwiftUI views, fills them with fictional sessions, and saves 2× PNGs to `docs/images`. It doesn't start the scanner, install hooks, open sessions, or play sounds. The production app isn't modified.

## Reply banners

Reply banners are on by default. A card appears beside the pill when a reply is ready. You can turn them off with **Show reply banners** in the panel’s top-right menu. **Preview reply banner** lets you try it.

Under **Banner duration**, choose 5, 10, 15, 30, or 60 seconds, or **Until clicked**. The default is **5 seconds**. Timed banners pause while hovered. **Until clicked** keeps the banner visible until you click it, click the pill, or use its close button. Simply hovering over the pill leaves it in place. Clicking a banner opens the conversation. Different chats stack as separate cards, newest chats first. A newer reply from the same chat replaces its card and restarts only that card’s timeout. Dismissing or opening a card removes that chat’s copies on every display, leaving other chats visible. Click the pill to clear the whole stack. Long stacks scroll to keep every chat reachable. Sending another message in that conversation also dismisses its banner on every display, including banners set to Until clicked. This happens when the local scanner detects the message, usually within a few seconds. Switching apps or status changes alone won’t dismiss it. Opening a banner marks its reply read after the chat opens. Dismissing a banner alone does not.

The same banner appears on every connected display and across Spaces. Clicking or dismissing any copy closes them all. Hovering over a card pauses that chat’s timeout across displays. They stay out of the way while the session panel is open or you’re dragging it. They use the same completion events as the chime, so old replies and approval requests don’t trigger them. Muting the chime leaves banners enabled. These are custom app windows, with no macOS notification sound or notification permission required.

## Diagnostic reports

Choose **Export diagnostics** from the top-right menu. Pulse saves a uniquely named text report directly to Downloads and reveals it in Finder. You can share that file for troubleshooting. It includes app and macOS versions, architecture, running-app checks, Claude setup status, scan timings, session counts, and route counts. It excludes conversation text, titles, session IDs, local paths, credentials, and raw logs. Exporting does not upload anything or change connections.

Provider-specific setup and repair controls are under **Connections & setup**. Providers stay in a fixed order while their scans complete.
