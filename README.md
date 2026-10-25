<p align="center">
  <img src="docs/images/pulse-logo.png" width="80" height="80" alt="Pulse mascot">
</p>

<h1 align="center">Pulse</h1>

<p align="center">A Mac app for keeping track of your coding agents.</p>

<p align="center">
  <a href="https://github.com/felixs8696/pulse/releases/latest"><strong>Download for Mac</strong></a>
  &nbsp; · &nbsp;
  <a href="#get-started">Get started</a>
  &nbsp; · &nbsp;
  <a href="docs/GUIDE.md">User guide</a>
</p>

<p align="center"><sub>macOS 14+ &nbsp; / &nbsp; Apple Silicon + Intel &nbsp; / &nbsp; Runs locally</sub></p>

<p align="center">
  <img src="docs/images/overview.png" width="664" alt="Pulse's floating pill alongside its expanded panel, showing four example Claude Code, Codex, and Cursor sessions. Two agents are working and two replies are waiting.">
</p>

<p align="center"><sub>Screenshots use sample conversations.</sub></p>

## How to use it

Click the pill to open your session list. Each row shows your last message. Click a row to return to that session in its original app.

- Click the pill to open the panel. Move away to collapse it. **⌃ Space** also shows or hides it.
- Drag the pill or the panel's title area to move them together.
- Open a row's three-dot menu to pin it, mark a reply read or unread, or change its completion tone.
- Search by message, title, or project.
- Opening a chat marks its current reply read. Unread replies stay above read ones, with each group sorted by recency. You can mark a reply unread again from its menu.
- Mute sounds from the panel or menu bar.
- A pill appears on each connected monitor by default. Turn off **Show pill on every display** in the top-right menu if you prefer a single pill.

## Features

- Claude Code, Codex, and Cursor sessions in one list, with counts for agents working and waiting for you.
- One moving pulse around the pill's border per working agent. Three pulses means three active agents. As agents finish, their pulses fade away.
- A two-tap chime when a reply is ready. Each session keeps its own tone. Set its pitch from 1 (low) to 100 (high), or keep the automatic tone.
- Optional reply banners slide out beside the pill. Choose 5–60 seconds or keep them open until clicked. Different chats stack, and newer replies update their existing card. Banners appear on every display, with dismissal synced per chat. Hover to keep one open, or click to return to the session. Enable **Show reply banners** in the top-right menu.
- A floating pill that stays visible across Spaces, and appears on every connected display by default.

<table>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/images/waiting.png" alt="Waiting tab with two completed example replies and explicit mark-read controls.">
      <strong>Waiting</strong><br>
      Today's replies and requests for input, grouped into unread and read. Previous days' replies move to Older.
    </td>
    <td width="50%" valign="top">
      <img src="docs/images/pinned.png" alt="Pinned tab keeping two example conversations close, with their current status visible.">
      <strong>Pinned</strong><br>
      Pinned conversations stay here across days. You can still see whether they're working or waiting.
    </td>
  </tr>
</table>

## Get started

1. **[Download the latest ZIP](https://github.com/felixs8696/pulse/releases/latest)** and unzip it.
2. Drag **Pulse.app** into **Applications** and open it.
3. Click the pill to see your sessions. Press **⌃ Space** to show or hide the panel.

Sound and reply banners are on by default. Banners close after five seconds by default. You can choose a longer duration or keep them open until clicked. The pill appears on every display, and the panel starts on Pinned. You can change these settings in the app.

Pulse is a menu-bar app, so it won't show up in the Dock. You can turn on launch at login from its menu.

> The app is ad-hoc signed and hasn't been notarized by Apple yet. If macOS blocks it, try opening the app, then go to **System Settings → Privacy & Security → Open Anyway**. Only do this for a copy you trust. More details are in the [installation guide](DISTRIBUTION.md).

### What works with Pulse

These are the setups tested in everyday use so far. The agent is listed first, followed by the app it runs in.

| Agent | Tested in | Setup |
| :--- | :--- | :--- |
| Claude Code | CLI in iTerm | Pulse installs its hooks automatically. Requires Python 3 from Apple's Command Line Tools and permission to control iTerm. |
| Claude Code | Claude Code extension in Cursor | Automatic Claude hooks, plus the included `pulse-router.vsix` to reopen the right tab. |
| Codex | Codex Desktop | Local chats are discovered automatically. No extension or hook setup needed. |

Other integrations are implemented, but haven't been verified end to end in everyday use:

| Agent | Where | Current limits |
| :--- | :--- | :--- |
| Claude Code | Claude Desktop’s Code tab | Local sessions are discovered automatically. Verified discovery and reply previews on a live chat. Exact-chat navigation and completion chimes still need end-to-end verification. |
| Cursor agents | Cursor's own agent chats | Reads local chat data. Install `pulse-router.vsix` to reopen the right chat. |
| Claude Code | CLI in Cursor's integrated terminal | Uses Claude hooks and `pulse-router.vsix` to return to the recorded terminal. |
| Codex | CLI | Chats may appear if they're in the local Codex index. Clicking opens Codex Desktop, not the original terminal pane. |

Claude CLI sessions have a small terminal badge on their logo. Claude in Cursor keeps the Cursor logo with a Claude badge, and Desktop Code uses the Claude logo.

Codex Desktop is the only fully tested setup that needs no additional connection setup. Claude hooks install automatically when the required Python is available. Cursor navigation needs the bundled extension. See the [connection setup guide](DISTRIBUTION.md#connect-your-apps).

Ordinary ChatGPT chats, Claude chat, Cowork, and the Codex extension in Cursor aren't supported integrations. Cloud-only chats won't appear unless a supported app stores them locally.

Pulse tracks conversations active in the past seven days, plus anything you pin. Sending a message in an older chat brings it back. Child agents and background tasks are excluded.

## Privacy and limitations

Pulse reads session files and databases on your Mac and saves pins, read state, and preferences locally. It doesn't upload conversations or collect analytics. You don't need an account or API key, and exported ZIPs don't include your session history or settings.

Updates to Claude Code, Codex, or Cursor can change their file formats or links and break tracking or navigation. Remote sessions only appear if the app has stored them locally. See the [user guide](docs/GUIDE.md#tracking-and-limits) for tracking details and known limits.

## Build it yourself

You'll need macOS 14+ and Apple's Command Line Tools (`xcode-select --install`). The build has no third-party dependencies to download.

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
