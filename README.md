<p align="center">
  <img src="Sources/Pulse/Resources/Logos/pulse-mark.svg" width="64" height="48" alt="Pulse waveform">
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

## How it works

Pulse shows your Claude Code, Codex, and Cursor sessions in a small floating pill. You can see how many agents are working and how many have replied without switching between apps to check.

Hover over the pill to see the list. Each session shows the last message you sent, so you can tell what it was about. Click a session to open it in its original app, or click the pill to keep the panel open.

You can also:

- Pin conversations you want to come back to.
- Search by message, title, or project.
- Mark replies read or unread yourself. Opening a session doesn't clear it.
- Hear a two-tap chime when a reply is ready, with a pitch based on the session. Mute it from the panel or menu bar.

The pill stays visible across Spaces. Its border animates while agents are working, and you can drag it or the panel's title area to move both together.

<table>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/images/waiting.png" alt="Waiting tab with two completed example replies and explicit mark-read controls.">
      <strong>Waiting</strong><br>
      Replies you haven't marked read yet. This tab only includes today; older replies move to Older.
    </td>
    <td width="50%" valign="top">
      <img src="docs/images/pinned.png" alt="Pinned tab keeping two example conversations close, with their current status visible.">
      <strong>Pinned</strong><br>
      Conversations you've pinned stay here across days, with their current status.
    </td>
  </tr>
</table>

## Get started

1. **[Download the latest ZIP](https://github.com/felixs8696/pulse/releases/latest)** and unzip it.
2. Drag **Pulse.app** into **Applications** and open it.
3. Hover the pill to see your sessions. Press **⌃ Space** to show or hide the panel.

Pulse is a menu-bar app, so it won't show up in the Dock. You can turn on launch at login from its menu.

> The app is ad-hoc signed and hasn't been notarized by Apple yet. If macOS blocks it, try opening the app, then go to **System Settings → Privacy & Security → Open Anyway**. Only do this for a copy you trust. More details are in the [installation guide](DISTRIBUTION.md).

### Supported apps

| Agent | Where you use it | Setup |
| :--- | :--- | :--- |
| **Claude Code** | iTerm, Cursor's Claude extension, Cursor terminal | Install the included Claude hooks. For Cursor, install the included session router too. |
| **Codex** | Codex Desktop | No extra setup for chats stored locally. |
| **Cursor agents** | Cursor | Install the included `pulse-router.vsix`. |

The ZIP includes the installers. Follow the [setup guide](DISTRIBUTION.md#connect-your-apps) for Claude hooks and the Cursor extension.

The list only includes conversations you interact with directly, so background agents don't inflate the counts. Claude chat, Cowork, and ChatGPT chat aren't supported. Codex sessions open in Desktop, not a CLI pane.

## Privacy and limitations

Pulse reads session files and databases already on your Mac. It doesn't upload conversations or collect analytics, and you don't need an account or API key. Pins, read state, and preferences are saved locally. The downloadable ZIP doesn't include any of your session history or settings.

It relies on each app's local files and links, so updates to those apps can break tracking or navigation. Remote sessions only appear if the app has stored them locally. The [user guide](docs/GUIDE.md#tracking-and-limits) has more detail on what Pulse can detect.

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
