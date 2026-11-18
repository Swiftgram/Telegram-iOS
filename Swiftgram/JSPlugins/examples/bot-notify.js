// ==TrollGramPlugin==
// @name Bot Notify
// @version 1.0
// @author TrollGram
// @description Forwards the text of ".notify <text>" to a chat through the Telegram Bot API.
// ==/TrollGramPlugin==

TrollGram.plugin({
  commands: {
    // Returning a promise cancels the original message; a string it resolves to is sent as a reply.
    notify: function (ctx) {
      var token = TrollGram.settings.get('token');
      var chat = TrollGram.settings.get('chat');
      if (!token || !chat) { TrollGram.alert('Bot Notify', 'Set a bot token and chat id in the plugin settings.'); return; }
      return TrollGram.bot(token).sendMessage(chat, ctx.args).then(function () {
        TrollGram.toast('Sent', 'success');
      }, function (e) { TrollGram.toast(e.message, 'error'); });
    }
  },
  settings: [
    { type: 'text', text: 'Create a bot with @BotFather, paste its token and the target chat id.' },
    { type: 'input', key: 'token', title: 'Bot token', placeholder: '123456:ABC...', 'default': '' },
    { type: 'input', key: 'chat', title: 'Chat id', placeholder: '-1001234567890', 'default': '' }
  ]
});
