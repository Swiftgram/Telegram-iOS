# TrollGram JavaScript plugins

Plugins are single `.js` files that run on iOS's built-in JavaScriptCore (ES2015+, Promises). Each plugin gets its
own context with no file or process access; the only way out is the `TrollGram` object, `fetch` and `console`.
Import a plugin from **Settings → Plugins → Import**, then switch it on. Samples: [`examples/`](examples).

## Anatomy

```js
// ==TrollGramPlugin==
// @name Hello            (shown in the list; defaults to the file name)
// @version 1.0
// @author You
// @description One line.
// ==/TrollGramPlugin==

TrollGram.plugin({
  onLoad() {},                       // plugin was switched on
  onUnload() {},                     // switched off or replaced
  onSend(msg) {},                    // every outgoing text message: {peer, text}
  commands: { name(ctx) {} },        // outgoing ".name args": ctx = {peer, args, text}
  settings: [ /* rows, see below */ ],
  onSettingChange(key, value) {}
});
```

- `onSend` returns a string (or `{text}`) to rewrite the message, `false`/`null` to cancel it, anything else to
  leave it alone.
- A command replaces the message with the string it returns, or swallows it if it returns nothing. If it returns a
  Promise, the message is swallowed and the string the Promise resolves to is sent when it settles.
- Hooks run synchronously on the main thread: keep them short. Throwing is safe, the error goes to the log and
  the message is sent unchanged.
- Rewriting a message drops its formatting entities. Only plain text messages reach plugins.

## Settings screen

Rows are rendered natively. `default` is used until the user changes a value.

| Row | Fields |
| --- | --- |
| `{type: 'header', title}` | section title |
| `{type: 'text', text}` | explanatory note |
| `{type: 'switch', key, title, default}` | boolean |
| `{type: 'input', key, title, placeholder, default}` | string |
| `{type: 'button', title, onTap}` | runs `onTap` |

Read and write values with `TrollGram.settings.get(key, fallback)` and `TrollGram.settings.set(key, value)`
(any JSON value). They are stored on the device per plugin.

## API

| Call | What it does |
| --- | --- |
| `TrollGram.toast(text, style)` | toast; style is `info`, `success` or `error` |
| `TrollGram.alert(title, text)` | alert dialog |
| `TrollGram.sendMessage(peer, text)` | sends a text message as you; returns a Promise |
| `TrollGram.getPeer(peer)` | Promise of `{id, title, username}` |
| `TrollGram.api(method, params)` | the two calls above by name; unknown methods reject |
| `TrollGram.bot(token).call(method, params)` | Telegram Bot API request; Promise of `result`, rejects with the description |
| `TrollGram.bot(token).sendMessage(chat, text, extra)` | shorthand for `sendMessage` |
| `fetch(url, {method, headers, body})` | HTTP(S); Promise of `{ok, status, headers, text(), json()}`. Object bodies are sent as JSON |
| `setTimeout(fn, ms, ...args)`, `clearTimeout(id)` | timers (no `setInterval`: reschedule yourself) |
| `console.log/info/warn/error` | goes to the plugin log |

`peer` is a Bot-API style id (user `id`, group `-id`, channel `-100id`) or `"me"`. `sendMessage` and `getPeer`
need an account, which is available once any chat has been opened after launch.

Anything else the app can do for a plugin is added as a named method in `TrollPluginsBridge.handleAPI`
(`submodules/TelegramUI/Sources/TrollPluginsBridge.swift`) so the surface stays small and reviewable.

## Safety

A plugin runs with the app's network access and can send messages as you. Plugins are off until enabled; only
install code you trust. A hook stuck in an infinite loop freezes the app: JavaScriptCore has no timeout.

## Tests

```bash
node --test Swiftgram/JSPlugins/tests/prelude.test.js
```

The tests run the real prelude (extracted from `Sources/JSPrelude.swift`) under Node with a mocked `__native`.
The Swift side needs Xcode and is not covered.
