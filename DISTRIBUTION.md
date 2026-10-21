# Pulse — install on your Mac

Requires macOS 14 (Sonoma) or newer. Supports Apple Silicon and Intel Macs.

1. Unzip the download and drag **Pulse.app** into **Applications**.
2. Open it. A small floating pill appears; hover it to see your sessions.
3. If macOS blocks opening it because the developer cannot be verified, use **System Settings → Privacy & Security → Open Anyway** after attempting to open it. Only do this for a copy you trust. This personal build is ad-hoc signed; it is not Developer ID signed or Apple-notarized. Managed Macs may prevent it from opening.

The app discovers sessions belonging to the person running it. This download contains no sender session history, pins, read/unread state, credentials, or settings. No account, server, or API key is needed.

## Connect your apps

**Codex Desktop:** install/use Codex normally. Pulse reads its local chat index automatically.

**Cursor:** in Cursor's Extensions panel, open the **…** menu → **Install from VSIX…** and choose the included `pulse-router.vsix`. This enables opening the exact chat or Claude tab. The Claude Code extension must also be installed for Claude tabs.

**Claude Code:** for exact session routing and completion states, install the included hooks. In Terminal, type `python3 `, drag `Claude setup/setup-claude.py` into Terminal, and press Return. Keep `claude-hook.py` beside the installer. Requires Python 3 (Apple's Command Line Tools provide it). The installer backs up your Claude settings and preserves existing hooks. Restart Claude sessions afterward. To remove Pulse's hooks, run the same command with ` --remove` appended.

**iTerm:** allow Pulse's macOS Automation request to control iTerm so it can identify and open your live panes.

## Use

- Hover the pill to expand, drag it to move, or press **Control–Space** to toggle. If another app or macOS already uses that shortcut, it may conflict.
- A pill appears on each connected monitor by default. Turn off **Show pill on every display** in the panel's top-right menu to use a single pill. Hover or click one to open the panel there. Alerts play once, regardless of the number of displays.
- Pin sessions to keep them in **Pinned**. **Working** shows running agents; **Waiting** shows today's unread replies and requests for input. Older activity goes in **Older**.
- Use a row's three-dot menu to pin it or mark a reply read. Find it in Today or Pinned to mark it unread again. The same menu sets its completion tone from 1 (low) to 100 (high), with a preview and reset. Choices are saved only in Pulse.
- A soft two-tap chime plays when a reply is ready; its pitch varies by session. Sound and launch-at-login controls are in the menu bar.

Pulse relies on local data formats in Codex, Cursor, and Claude; future versions of those apps may need compatibility fixes. It tracks top-level locally indexed sessions, not every remote/cloud conversation. No auto-update service is included; replace the app with a newer ZIP to update.
