// Runs the JS prelude (extracted from Sources/JSPrelude.swift) under Node with a mocked __native.
// Usage: node --test Swiftgram/JSPlugins/tests/prelude.test.js
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const swift = fs.readFileSync(path.join(__dirname, '../Sources/JSPrelude.swift'), 'utf8');
const prelude = /#"""\n([\s\S]*?)\n"""#/.exec(swift)[1];

function boot(pluginSource) {
  const calls = { log: [], toast: [], alert: [], schedule: [], http: [], api: [] };
  let stored = {};
  const native = {
    log: (l, t) => calls.log.push([l, t]),
    toast: (t, s) => calls.toast.push([t, s]),
    alert: (t, x) => calls.alert.push([t, x]),
    schedule: (id, ms) => calls.schedule.push([id, ms]),
    http: (id, json) => calls.http.push([id, JSON.parse(json)]),
    api: (id, method, json) => calls.api.push([id, method, JSON.parse(json)]),
    settingsGet: () => JSON.stringify(stored),
    settingsSet: (k, v) => { stored[k] = JSON.parse(v); }
  };
  const sandbox = { __native: native };
  vm.createContext(sandbox);
  vm.runInContext(prelude, sandbox);
  vm.runInContext(pluginSource, sandbox);
  const host = sandbox.__host;
  return { host, calls, sandbox, stored: () => stored };
}

const send = (h, text) => JSON.parse(h.send(42, text));

test('info lists commands and settings schema', () => {
  const { host } = boot(`TrollGram.plugin({ commands: { ping() {} }, settings: [
    { type: 'switch', key: 'on', title: 'On', default: true }, { type: 'button', title: 'Go', onTap() {} } ] })`);
  const info = JSON.parse(host.info());
  assert.strictEqual(info.ok, true);
  assert.deepStrictEqual(info.commands, ['ping']);
  assert.strictEqual(info.settings.length, 2);
  assert.strictEqual(info.settings[0].default, true);
  assert.strictEqual(info.settings[1].index, 1);
});

test('a script that never registers is reported', () => {
  const { host } = boot('var x = 1;');
  assert.strictEqual(JSON.parse(host.info()).ok, false);
});

test('commands replace, swallow or defer the message', async () => {
  const { host, calls } = boot(`TrollGram.plugin({ commands: {
    ping() { return 'pong'; }, quiet() {}, later() { return Promise.resolve('done'); },
    args(c) { return '[' + c.args + ']'; } } })`);
  assert.deepStrictEqual(send(host, '.ping'), { action: 'modify', text: 'pong' });
  assert.deepStrictEqual(send(host, '.quiet'), { action: 'cancel' });
  assert.deepStrictEqual(send(host, '.args a b\nc'), { action: 'modify', text: '[a b\nc]' });
  assert.deepStrictEqual(send(host, '.later'), { action: 'cancel' });
  await Promise.resolve(); await Promise.resolve(); await Promise.resolve();
  assert.deepStrictEqual(calls.api.map(c => [c[1], c[2].peer, c[2].text]), [['sendMessage', 42, 'done']]);
  assert.deepStrictEqual(send(host, '.unknown'), { action: 'pass' });
  assert.deepStrictEqual(send(host, 'hello .ping'), { action: 'pass' });
});

test('onSend can rewrite, cancel or pass', () => {
  const { host } = boot(`TrollGram.plugin({ onSend(m) {
    if (m.text === 'drop') return false; if (m.text === 'up') return { text: 'UP' };
    if (m.text === 'same') return 'same'; if (m.text === 'x') return m.text + '!'; } })`);
  assert.deepStrictEqual(send(host, 'drop'), { action: 'cancel' });
  assert.deepStrictEqual(send(host, 'up'), { action: 'modify', text: 'UP' });
  assert.deepStrictEqual(send(host, 'same'), { action: 'pass' });
  assert.deepStrictEqual(send(host, 'x'), { action: 'modify', text: 'x!' });
  assert.deepStrictEqual(send(host, 'other'), { action: 'pass' });
});

test('a throwing hook is logged and the message passes', () => {
  const { host, calls } = boot(`TrollGram.plugin({ onSend() { throw new Error('boom'); } })`);
  assert.deepStrictEqual(send(host, 'hi'), { action: 'pass' });
  assert.ok(calls.log.some(l => l[0] === 'error' && l[1].includes('boom')));
});

test('settings fall back to schema defaults and persist', () => {
  const { sandbox, stored } = boot(`TrollGram.plugin({ settings: [{ type: 'input', key: 'k', default: 'd' }] });
    var before = [TrollGram.settings.get('k'), TrollGram.settings.get('k', 'x'), TrollGram.settings.get('none')];
    TrollGram.settings.set('k', 5);
    var after = TrollGram.settings.get('k');`);
  assert.deepStrictEqual(Array.from(sandbox.before), ['d', 'x', undefined]);
  assert.strictEqual(sandbox.after, 5);
  assert.deepStrictEqual(stored(), { k: 5 });
});

test('buttons, timers and setting callbacks reach the plugin', () => {
  const { host, calls } = boot(`var hits = [];
    TrollGram.plugin({ onLoad() { setTimeout(function (a) { TrollGram.toast('t' + a, 'info'); }, 50, 7); },
      onSettingChange(k, v) { TrollGram.toast(k + '=' + v, 'info'); },
      settings: [{ type: 'button', title: 'b', onTap() { TrollGram.toast('tap', 'success'); } }] })`);
  host.load();
  assert.deepStrictEqual(calls.schedule, [[1, 50]]);
  host.timer(1); host.tap(0); host.settingChanged('k', true);
  assert.deepStrictEqual(calls.toast.map(t => t[0]), ['t7', 'tap', 'k=true']);
});

test('fetch resolves with a Response-like object and rejects on errors', async () => {
  const { host, calls, sandbox } = boot(`TrollGram.plugin({}); var out = [];
    fetch('https://example.com/x', { method: 'post', body: { a: 1 } }).then(r => r.json()).then(j => out.push(j.v));
    fetch('https://bad').catch(e => out.push(e.message));`);
  assert.strictEqual(calls.http[0][1].method, 'POST');
  assert.strictEqual(calls.http[0][1].body, '{"a":1}');
  host.httpDone(calls.http[0][0], JSON.stringify({ status: 200, body: '{"v":3}' }));
  host.httpDone(calls.http[1][0], JSON.stringify({ error: 'offline' }));
  await new Promise(r => setImmediate(r));
  assert.deepStrictEqual(Array.from(sandbox.out).sort(), [3, 'offline'].sort());
});

test('bot API helper posts JSON and unwraps the result', async () => {
  const { host, calls, sandbox } = boot(`TrollGram.plugin({}); var res;
    TrollGram.bot('T:OK').sendMessage(-100, 'hi', { silent: true }).then(v => { res = v; }, e => { res = e.message; });`);
  const [id, req] = calls.http[0];
  assert.strictEqual(req.url, 'https://api.telegram.org/botT:OK/sendMessage');
  assert.deepStrictEqual(JSON.parse(req.body), { chat_id: -100, text: 'hi', silent: true });
  host.httpDone(id, JSON.stringify({ status: 200, body: '{"ok":true,"result":{"message_id":9}}' }));
  await new Promise(r => setImmediate(r));
  assert.strictEqual(sandbox.res.message_id, 9);
});

test('client API calls round trip through apiDone', async () => {
  const { host, calls, sandbox } = boot(`TrollGram.plugin({}); var title;
    TrollGram.getPeer('me').then(p => { title = p.title; });`);
  assert.deepStrictEqual(calls.api[0].slice(1), ['getPeer', { peer: 'me' }]);
  host.apiDone(calls.api[0][0], JSON.stringify({ result: { title: 'Me' } }));
  await new Promise(r => setImmediate(r));
  assert.strictEqual(sandbox.title, 'Me');
});
