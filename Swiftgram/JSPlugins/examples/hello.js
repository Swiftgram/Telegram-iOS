// ==TrollGramPlugin==
// @name Hello
// @version 1.0
// @author TrollGram
// @description Commands .ping and .me, an optional signature and a settings screen.
// ==/TrollGramPlugin==

TrollGram.plugin({
  // Outgoing ".ping" is replaced by the returned text; returning nothing swallows the message.
  commands: {
    ping: function () { return 'pong'; },
    me: function (ctx) {
      TrollGram.getPeer('me').then(function (p) {
        TrollGram.toast(p.title + (p.username ? ' (@' + p.username + ')' : ''), 'success');
      });
    }
  },
  // Runs for every outgoing text message: return a string to rewrite it, false to cancel it.
  onSend: function (msg) {
    var tail = TrollGram.settings.get('signature');
    if (TrollGram.settings.get('enabled') && tail && msg.text.charAt(0) !== '.') {
      return msg.text + '\n' + tail;
    }
  },
  settings: [
    { type: 'header', title: 'Signature' },
    { type: 'switch', key: 'enabled', title: 'Add signature', 'default': false },
    { type: 'input', key: 'signature', title: 'Text', placeholder: '— sent with TrollGram', 'default': '' },
    { type: 'button', title: 'Say hello', onTap: function () { TrollGram.toast('Hello from a plugin', 'success'); } }
  ]
});
