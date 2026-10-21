const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');

async function fixture(folder, workspaceFile) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'pulse-'));
  const calls = [];
  let handler;
  const vscode = {
    workspace: {workspaceFile: workspaceFile ? {fsPath: workspaceFile} : undefined, workspaceFolders: [{uri: {fsPath: folder}}]},
    extensions: {getExtension() {return {async activate() {}};}},
    window: {terminals: [{processId: Promise.resolve(42), show() {calls.push(['terminal.show', 42]);}}], registerUriHandler(value) {handler = value; return {dispose() {}};}, showErrorMessage(message) {throw Error(message);}},
    commands: {async executeCommand(...args) {calls.push(args); return false;}},
    Uri: {file(value) {return {fsPath: value};}}
  };
  const box = {module: {exports: {}}, require(name) {return name === 'vscode' ? vscode : require(name);},
    process, URLSearchParams, Date, setInterval() {return 0;}, clearInterval() {}};
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../cursor-router/extension.js'), 'utf8'), box);
  box.module.exports.activate({globalStorageUri: {fsPath: directory}, subscriptions: []});
  await new Promise(resolve => setTimeout(resolve, 20));
  return {calls, handler, exported: box.module.exports, cleanup() {fs.rmSync(directory, {recursive: true, force: true});}};
}
function uri(id, folder, routed) {
  const params = new URLSearchParams({id, folder});
  if (routed) params.set('routed', '1');
  return {path: '/open', query: params.toString(), toString() {return 'cursor://local.pulse-router/open?' + this.query;}, with({query}) {return {...this, query};}};
}
test('opens the exact conversation in a matching workspace', async () => {
  const f = await fixture('/tmp/a');
  try {
    await f.handler.handleUri(uri('abc-123', '/tmp/a'));
    assert.equal(f.calls[0][0], 'composer.openComposerFromNotification');
    assert.equal(f.calls[0][1].composerId, 'abc-123');
  } finally {f.cleanup();}
});
test('does not open a conversation in the wrong workspace and routing cannot loop', async () => {
  const f = await fixture('/tmp/a');
  try {
    await f.handler.handleUri(uri('abc-123', '/tmp/b', true));
    assert.equal(f.calls.length, 1);
    assert.equal(f.calls[0][0], 'vscode.openFolder');
    assert.equal(f.calls[0][1].fsPath, '/tmp/b');
  } finally {f.cleanup();}
});
test('rejects arbitrary command IDs, relative folders, and stale requests', async () => {
  const f = await fixture('/tmp/a');
  try {
    assert.equal(f.exported.validRequest({id: 'command:delete', folder: '/tmp', createdAt: Date.now()}), false);
    assert.equal(f.exported.validRequest({id: 'abc', folder: '../relative', createdAt: Date.now()}), false);
    assert.equal(f.exported.validRequest({id: 'abc', folder: '/tmp', createdAt: Date.now() - 65000}), false);
  } finally {f.cleanup();}
});

test('reveals the exact Claude tab in its multi-folder workspace without a prompt', async () => {
  const f = await fixture('/tmp/project', '/tmp/Workspaces/one/workspace.json');
  try {
    const request = uri('session-fork-id', '/tmp/Workspaces/one/workspace.json');
    request.query += '&kind=claude';
    await f.handler.handleUri(request);
    assert.equal(f.calls[0][0], 'claude-vscode.editor.open');
    assert.equal(f.calls[0][1], 'session-fork-id');
    assert.equal(f.calls[0][2], undefined);
    assert.equal(f.calls.length, 1);
  } finally {f.cleanup();}
});
test('selects the recorded Cursor terminal instead of creating or typing into one', async () => {
  const f = await fixture('/tmp/project');
  try {
    const request = uri('cli-id', '/tmp/project');
    request.query += '&kind=terminal&pids=99,42,1';
    await f.handler.handleUri(request);
    assert.equal(f.calls[0][0], 'terminal.show');
    assert.equal(f.calls[0][1], 42);
    assert.equal(f.calls.length, 1);
  } finally {f.cleanup();}
});
test('matches an untitled multi-folder window by its saved folder set', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'shelf-workspace-'));
  const file = path.join(root, 'workspace.json');
  fs.writeFileSync(file, JSON.stringify({folders: [{path: '/tmp/project'}]}));
  const f = await fixture('/tmp/project');
  try {
    const request = uri('exact-session', file); request.query += '&kind=claude';
    await f.handler.handleUri(request);
    assert.equal(f.calls[0][0], 'claude-vscode.editor.open');
    assert.equal(f.calls[0][1], 'exact-session');
  } finally {f.cleanup(); fs.rmSync(root, {recursive: true, force: true});}
});
