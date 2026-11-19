import Foundation

/// The JavaScript side of the plugin SDK. It is loaded into every plugin's `JSContext` before the plugin
/// itself. `Swiftgram/JSPlugins/tests/prelude.test.js` extracts this literal and runs it under Node with a
/// mocked `__native`, so keep the `#"""` markers on their own lines.
enum JSPrelude {
    static let source = #"""
(function (g) {
  'use strict';
  var N = g.__native;
  var def = null, nextTimer = 0, timers = {}, nextReq = 0, reqs = {};

  function str(v) {
    if (typeof v === 'string') return v;
    try { var s = JSON.stringify(v); return s === undefined ? String(v) : s; } catch (e) { return String(v); }
  }
  function errText(e) { return (e && e.message) ? e.message : String(e); }
  function logger(level) {
    return function () { N.log(level, Array.prototype.map.call(arguments, str).join(' ')); };
  }
  g.console = { log: logger('info'), info: logger('info'), warn: logger('warning'), error: logger('error') };

  g.setTimeout = function (fn, ms) {
    var rest = Array.prototype.slice.call(arguments, 2);
    var id = ++nextTimer;
    timers[id] = function () { fn.apply(null, rest); };
    N.schedule(id, (ms | 0) < 0 ? 0 : (ms | 0));
    return id;
  };
  g.clearTimeout = function (id) { delete timers[id]; };

  function request(start) {
    return new Promise(function (resolve, reject) {
      var id = ++nextReq;
      reqs[id] = { resolve: resolve, reject: reject };
      start(id);
    });
  }

  g.fetch = function (url, opt) {
    opt = opt || {};
    var body = opt.body;
    if (body !== undefined && body !== null && typeof body !== 'string') body = JSON.stringify(body);
    return request(function (id) {
      N.http(id, JSON.stringify({
        url: String(url),
        method: String(opt.method || 'GET').toUpperCase(),
        headers: opt.headers || {},
        body: body === undefined ? null : body
      }));
    });
  };

  function call(method, params) {
    return request(function (id) { N.api(id, String(method), JSON.stringify(params || {})); });
  }

  function botCall(token, method, params) {
    return g.fetch('https://api.telegram.org/bot' + token + '/' + method, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: params || {}
    }).then(function (r) { return r.json(); }).then(function (j) {
      if (!j.ok) throw new Error(j.description || 'Bot API error');
      return j.result;
    });
  }

  function schemaDefault(key) {
    var list = (def && def.settings) || [];
    for (var i = 0; i < list.length; i++) {
      if (list[i].key === key && list[i]['default'] !== undefined) return list[i]['default'];
    }
    return undefined;
  }

  var TG = {
    version: 1,
    plugin: function (d) { def = d || {}; },
    log: g.console.log,
    toast: function (text, style) { N.toast(str(text), style || 'info'); },
    alert: function (title, text) { N.alert(str(title), str(text)); },
    // Telegram client API (runs as the signed-in account): sendMessage, getPeer.
    api: call,
    sendMessage: function (peer, text, opt) {
      return call('sendMessage', { peer: peer, text: str(text), replyTo: opt && opt.replyTo });
    },
    getPeer: function (peer) { return call('getPeer', { peer: peer }); },
    // Telegram Bot API over HTTPS.
    bot: function (token) {
      return {
        call: function (method, params) { return botCall(token, method, params); },
        sendMessage: function (chat, text, extra) {
          var p = { chat_id: chat, text: str(text) };
          for (var k in (extra || {})) p[k] = extra[k];
          return botCall(token, 'sendMessage', p);
        }
      };
    },
    settings: {
      get: function (key, fallback) {
        var all = {};
        try { all = JSON.parse(N.settingsGet()) || {}; } catch (e) {}
        if (Object.prototype.hasOwnProperty.call(all, key)) return all[key];
        if (fallback !== undefined) return fallback;
        return schemaDefault(key);
      },
      set: function (key, value) { N.settingsSet(String(key), JSON.stringify(value === undefined ? null : value)); }
    }
  };
  g.TrollGram = TG;

  function out(action, text) { return JSON.stringify({ action: action, text: text }); }

  g.__host = {
    info: function () {
      var d = def || {};
      return JSON.stringify({
        ok: !!def,
        commands: Object.keys(d.commands || {}),
        settings: (d.settings || []).map(function (s, i) {
          return {
            index: i, type: String(s.type || ''), key: s.key === undefined ? null : String(s.key),
            title: s.title === undefined ? null : String(s.title),
            text: s.text === undefined ? null : String(s.text),
            placeholder: s.placeholder === undefined ? null : String(s.placeholder),
            'default': s['default'] === undefined ? null : s['default']
          };
        })
      });
    },
    load: function () { try { if (def && def.onLoad) def.onLoad(); } catch (e) { N.log('error', 'onLoad: ' + errText(e)); } },
    unload: function () { try { if (def && def.onUnload) def.onUnload(); } catch (e) { N.log('error', 'onUnload: ' + errText(e)); } },
    // Outgoing message hook: returns {action: pass|cancel|modify, text}.
    send: function (peer, text) {
      var d = def;
      if (!d) return out('pass');
      try {
        var m = /^\.([A-Za-z][\w-]*)(?:\s+([\s\S]*))?$/.exec(text);
        if (m && d.commands && typeof d.commands[m[1]] === 'function') {
          var r = d.commands[m[1]]({ peer: peer, args: m[2] || '', text: text });
          if (r && typeof r.then === 'function') {
            r.then(function (v) { if (typeof v === 'string' && v) TG.sendMessage(peer, v); })
             ['catch'](function (e) { N.log('error', 'command .' + m[1] + ': ' + errText(e)); });
            return out('cancel');
          }
          return (typeof r === 'string' && r.length) ? out('modify', r) : out('cancel');
        }
        if (typeof d.onSend === 'function') {
          var res = d.onSend({ peer: peer, text: text });
          if (res === false || res === null) return out('cancel');
          if (res && typeof res === 'object' && typeof res.text === 'string') res = res.text;
          if (typeof res === 'string' && res !== text) return out('modify', res);
        }
      } catch (e) { N.log('error', 'send hook: ' + errText(e)); }
      return out('pass');
    },
    tap: function (i) {
      var s = ((def && def.settings) || [])[i];
      try { if (s && typeof s.onTap === 'function') s.onTap(); } catch (e) { N.log('error', 'button: ' + errText(e)); }
    },
    settingChanged: function (key, value) {
      try { if (def && typeof def.onSettingChange === 'function') def.onSettingChange(key, value); }
      catch (e) { N.log('error', 'onSettingChange: ' + errText(e)); }
    },
    timer: function (id) {
      var f = timers[id];
      if (!f) return;
      delete timers[id];
      try { f(); } catch (e) { N.log('error', 'timer: ' + errText(e)); }
    },
    httpDone: function (id, json) {
      var r = reqs[id]; delete reqs[id];
      if (!r) return;
      var p = JSON.parse(json);
      if (p.error) { r.reject(new Error(p.error)); return; }
      var body = p.body || '';
      r.resolve({
        ok: p.status >= 200 && p.status < 300, status: p.status, headers: p.headers || {},
        text: function () { return Promise.resolve(body); },
        json: function () { return new Promise(function (ok) { ok(JSON.parse(body)); }); }
      });
    },
    apiDone: function (id, json) {
      var r = reqs[id]; delete reqs[id];
      if (!r) return;
      var p = JSON.parse(json);
      if (p.error) r.reject(new Error(p.error)); else r.resolve(p.result);
    }
  };
})(this);
"""#
}
