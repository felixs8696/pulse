const vscode = require('vscode');
const fsSync = require('node:fs');
const fs = require('node:fs/promises');
const path = require('node:path');

function belongsHere(folder) {
  if (!folder) return true;
  if (vscode.workspace.workspaceFile?.fsPath && path.resolve(vscode.workspace.workspaceFile.fsPath) === path.resolve(folder)) return true;
  const folders = (vscode.workspace.workspaceFolders || []).map(w => path.resolve(w.uri.fsPath));
  if (folders.includes(path.resolve(folder))) return true;
  // Untitled multi-folder windows may not expose workspaceFile through the stable API.
  if (path.basename(folder) === 'workspace.json' || folder.endsWith('.code-workspace')) {
    try {
      const saved = JSON.parse(fsSync.readFileSync(folder, 'utf8'));
      const expected = (saved.folders || []).map(f => f.path && path.resolve(path.dirname(folder), f.path)).filter(Boolean);
      return expected.length > 0 && expected.length === folders.length && expected.every(p => folders.includes(p));
    } catch {}
  }
  return false;
}

function validRequest(value) {
  return value && typeof value.id === 'string' && /^[a-zA-Z0-9-]{1,128}$/.test(value.id)
    && typeof value.folder === 'string' && (!value.folder || path.isAbsolute(value.folder))
    && ['composer', 'claude', 'terminal'].includes(value.kind || 'composer')
    && (!value.pids || (Array.isArray(value.pids) && value.pids.every(p => Number.isSafeInteger(p) && p > 0)))
    && typeof value.createdAt === 'number' && Math.abs(Date.now() - value.createdAt) < 60000;
}

function activate(context) {
  const pending = path.join(context.globalStorageUri.fsPath, 'pending-open.json');
  let consuming = false;
  async function consume() {
    if (consuming) return;
    consuming = true;
    try {
      const request = JSON.parse(await fs.readFile(pending, 'utf8'));
      if (!validRequest(request) || !belongsHere(request.folder)) return;
      await fs.unlink(pending);
      await fs.writeFile(path.join(context.globalStorageUri.fsPath, 'last-navigation.json'),
        JSON.stringify({id: request.id, kind: request.kind, folders: (vscode.workspace.workspaceFolders || []).map(w => w.uri.fsPath), state: 'opening', at: Date.now()}), {mode: 0o600});
      // Consume once before invoking navigation, including failed attempts.
      if (request.kind === 'claude') {
        const extension = vscode.extensions.getExtension('anthropic.claude-code');
        if (!extension) throw Error('Claude Code extension is not installed in this Cursor window.');
        await extension.activate();
        // Its installed command reveals an existing session panel before considering a new one.
        // No prompt argument: navigation must never start an agent turn.
        await vscode.commands.executeCommand('claude-vscode.editor.open', request.id,
          undefined, undefined, undefined, undefined, {programmatic: 'honor-preferred-location'});
      } else if (request.kind === 'terminal') {
        let match;
        for (const terminal of vscode.window.terminals) {
          if ((request.pids || []).includes(await terminal.processId)) {match = terminal; break;}
        }
        if (!match) throw Error('The original Cursor terminal pane is no longer available. No new terminal was started.');
        match.show(false);
      } else {
        await vscode.commands.executeCommand('composer.openComposerFromNotification', {composerId: request.id});
      }
      await fs.writeFile(path.join(context.globalStorageUri.fsPath, 'last-navigation.json'),
        JSON.stringify({id: request.id, kind: request.kind, state: 'opened', at: Date.now()}), {mode: 0o600});
    } catch (error) {
      if (error.code !== 'ENOENT') vscode.window.showErrorMessage(`Pulse: ${error.message}`);
    } finally { consuming = false; }
  }
  context.subscriptions.push(vscode.window.registerUriHandler({
    async handleUri(uri) {
      if (uri.path !== '/open') return;
      const params = new URLSearchParams(uri.query);
      const request = {id: params.get('id'), folder: params.get('folder') || '',
        kind: params.get('kind') || 'composer', pids: (params.get('pids') || '').split(',').filter(Boolean).map(Number), createdAt: Date.now()};
      if (!validRequest(request)) return;
      await fs.mkdir(context.globalStorageUri.fsPath, {recursive: true});
      const temporary = pending + '.' + process.pid;
      await fs.writeFile(temporary, JSON.stringify(request), {mode: 0o600});
      await fs.rename(temporary, pending);
      if (belongsHere(request.folder)) { await consume(); return; }
      // Let Cursor route the URI to the existing workspace window when it can.
      let routed = false;
      if (params.get('routed') !== '1') {
        params.set('routed', '1');
        try { routed = await vscode.commands.executeCommand('deeplink.routeToWorkspaceName', path.basename(request.folder).replace(/\.code-workspace$/i, ''), uri.with({query: params.toString()}).toString()); } catch {}
      }
      if (!routed) await vscode.commands.executeCommand('vscode.openFolder', vscode.Uri.file(request.folder), {forceNewWindow: true});
    }
  }));
  // Pending requests also survive opening a previously closed workspace.
  const timer = setInterval(consume, 750);
  context.subscriptions.push({dispose() { clearInterval(timer); }});
  consume();
}
module.exports = {activate, validRequest};
