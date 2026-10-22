# Pulse — install on your Mac

Requires macOS 14 (Sonoma) or newer. Supports Apple Silicon and Intel Macs.

1. Unzip the download and drag **Pulse.app** into **Applications**.
2. Open it. A small floating pill appears; hover it to see your sessions.
3. If macOS blocks opening it because the developer cannot be verified, use **System Settings → Privacy & Security → Open Anyway** after attempting to open it. Only do this for a copy you trust. This personal build is ad-hoc signed; it is not Developer ID signed or Apple-notarized. Managed Macs may prevent it from opening.

The app discovers sessions belonging to the person running it. This download contains no sender session history, pins, read/unread state, credentials, or settings. No account, server, or API key is needed.

## Connect your apps

**Codex Desktop:** install/use Codex normally. Pulse reads its local chat index automatically.

**Cursor:** in Cursor's Extensions panel, open the **…** menu → **Install from VSIX…** and choose the included `pulse-router.vsix`. This enables opening the exact chat or Claude tab. The Claude Code extension must also be installed for Claude tabs.

**Claude Code:** Pulse automatically connects Claude Code when it detects your local Claude folder. It installs missing hooks, checks them again on launch, and refreshes the installed hook when a new Pulse version ships. Claude settings are backed up and existing hooks are preserved. Keep chats open and continue with your next message or tool action. Current Claude Code versions normally reload the settings automatically. If a chat does not appear, check `/hooks` in that chat. Hooks explicitly disabled in Claude settings are respected, and invalid settings are left unchanged. Open **Connections & setup** to check provider status or retry a failed connection.

The connection needs Python 3 from Apple’s Command Line Tools. If it is missing, Pulse shows a setup message rather than launching the tools installer in the background.

For manual setup, run `python3 "/Applications/Pulse.app/Contents/Resources/setup-claude.py"`. Add ` --remove` to remove Pulse’s hooks.

**iTerm:** allow Pulse's macOS Automation request to control iTerm so it can identify and open your live panes.

## Use

- Hover the pill to expand, drag it to move, or press **Control–Space** to toggle. If another app or macOS already uses that shortcut, it may conflict.
- A pill appears on each connected monitor by default. Turn off **Show pill on every display** in the panel's top-right menu to use a single pill. Hover or click one to open the panel there. Alerts play once, regardless of the number of displays.
- Pin sessions to keep them in **Pinned**. **Working** shows running agents; **Waiting** groups today's unread replies above read replies. Its count includes only unread replies. Older activity goes in **Older**.
- Opening a chat or sending another message marks its current reply read. Use a row's three-dot menu to pin it or change its read state. The same menu sets its completion tone from 1 (low) to 100 (high), with a preview and reset. Choices are saved only in Pulse.
- A soft two-tap chime plays when a reply is ready; its pitch varies by session. Sound and launch-at-login controls are in the menu bar.

Pulse relies on local data formats in Codex, Cursor, and Claude; future versions of those apps may need compatibility fixes. It tracks top-level locally indexed sessions, not every remote/cloud conversation. No auto-update service is included; replace the app with a newer ZIP to update.
