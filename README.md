<p align="center">
  <img src="Sources/Pulse/Resources/Logos/pulse-mark.svg" width="64" height="48" alt="Pulse waveform">
</p>

<h1 align="center">Pulse</h1>

<p align="center"><strong>Keep every agent conversation within reach.</strong></p>

<p align="center">
  A small, persistent Mac companion for Claude Code, Codex, and Cursor.<br>
  See who's working, find the replies waiting for you, and jump back into the right session.
</p>

<p align="center">
  <a href="https://github.com/felixs8696/pulse/releases/latest"><strong>Download for Mac →</strong></a>
  &nbsp; · &nbsp;
  <a href="#get-started">Get started</a>
  &nbsp; · &nbsp;
  <a href="docs/GUIDE.md">User guide</a>
</p>

<p align="center"><sub>macOS 14+ &nbsp; / &nbsp; Apple Silicon + Intel &nbsp; / &nbsp; Runs locally</sub></p>

<p align="center">
  <img src="docs/images/overview.png" width="664" alt="Pulse's floating pill alongside its expanded panel, showing four example Claude Code, Codex, and Cursor sessions. Two agents are working and two replies are waiting.">
</p>

<p align="center"><sub>Actual Pulse UI with fictional sessions. Your conversations stay on your Mac.</sub></p>

## Small pill. All your threads.

Pulse stays above your windows and across Spaces. Hover to take a quick look; click to keep the panel open. When an agent finishes, a soft two-tap chime lets you know.

- **Know what's moving.** Working counts and subtle border traces show active agents.
- **Pick up where you left off.** Each row shows your last message. Click it to reopen the original app and conversation.
- **Keep favorites close.** Pin a thread, search by message or project, and leave older conversations in their own tab.
- **Clear your own inbox.** Mark replies read or unread explicitly. Opening a conversation doesn't dismiss it.

<table>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/images/waiting.png" alt="Waiting tab with two completed example replies and explicit mark-read controls.">
      <strong>Ready when you are.</strong><br>
      Today's outstanding replies live in Waiting. Mark them read when you're done; previous days move to Older.
    </td>
    <td width="50%" valign="top">
      <img src="docs/images/pinned.png" alt="Pinned tab keeping two example conversations close, with their current status visible.">
      <strong>A place for your ongoing threads.</strong><br>
      Pins stay across days. Keep the conversations you return to without mixing them into your working queue.
    </td>
  </tr>
</table>

## Get started

1. **[Download the latest ZIP](https://github.com/felixs8696/pulse/releases/latest)** and unzip it.
2. Drag **Pulse.app** into **Applications** and open it.
3. Hover the pill to see your sessions. Press **⌃ Space** to show or hide the panel.

Pulse lives in the menu bar, so it doesn't add a Dock icon. Drag either the pill or the panel's title area to move them together. The menu-bar menu has launch-at-login and sound controls.

> The app is ad-hoc signed and isn't Apple-notarized yet. If macOS blocks it, use **System Settings → Privacy & Security → Open Anyway** after attempting to open a copy you trust. See the [installation guide](DISTRIBUTION.md).

### Connect your agents

| Agent | Supported app or surface | Setup |
| :--- | :--- | :--- |
| **Claude Code** | iTerm, Cursor's Claude extension, Cursor terminal | Install the included Claude hooks. For Cursor, install the included session router too. |
| **Codex** | Codex Desktop | Discovers locally indexed chats automatically. |
| **Cursor agents** | Cursor | Install the included `pulse-router.vsix`. |

The ZIP includes installers and instructions. The [setup guide](DISTRIBUTION.md#connect-your-apps) walks through each connection.

Only top-level conversations you interact with appear. Child agents and background subtasks stay out of the list and counts. Claude chat, Cowork, and ChatGPT chat aren't integrated. Codex navigation returns to Desktop; there isn't a dedicated Codex CLI destination.

## Local by design

No account, API keys, server, analytics, or telemetry. Pulse reads local session files and databases; it doesn't upload your conversations. Pins, read state, and preferences stay on your Mac. Downloads contain no session history or personal settings.

Pulse relies on each app's local formats and navigation links, which may change. Remote sessions appear only when indexed locally. See [tracking details and limitations](docs/GUIDE.md#tracking-and-limits).

## Build it yourself

Requires macOS 14+ and Apple's Command Line Tools (`xcode-select --install`). No third-party dependency downloads.

```sh
git clone https://github.com/felixs8696/pulse.git
cd pulse
bash scripts/build.sh --run
```

| Task | Command |
| :--- | :--- |
| Run checks | `bash scripts/test.sh` |
| Export a universal Mac app ZIP | `bash scripts/export.sh` |
| Regenerate the sample screenshots | `bash scripts/screenshots/render.sh` |

Build output: `build/Pulse.app`. Shareable download: `build/Pulse-macOS.zip`.
