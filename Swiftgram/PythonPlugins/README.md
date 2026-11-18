# TrollGram Python plugins (exteraGram `.plugin` files)

exteraGram plugins are Python source saved as `.plugin`. TrollGram runs them as they are on an embedded CPython 3.11,
using an SDK that mirrors exteraGram's module names (`base_plugin`, `client_utils`, `ui.settings`, ...). Plain `.py`
files work the same way. Import a file from **Settings → Plugins → Import**, then switch it on. Plugins stay off until
you enable them, and a plugin with settings gets a **Settings** row on that screen.

What exteraGram plugins can do through Android/Java internals (hooking requests, fragments, media) has no iOS
counterpart. Those calls raise `UnsupportedOnIOS`, and the plugin screen lists the features a plugin asked for that
iOS cannot provide, so nothing fails silently.

## Anatomy

```python
from base_plugin import BasePlugin, HookResult, HookStrategy
from ui.settings import Header, Switch, Input, Selector, Text
from ui.bulletin import BulletinHelper

__id__ = "shout"                 # [a-zA-Z0-9_-]; falls back to the file name when invalid
__name__ = "Shout"
__description__ = "Uppercases outgoing messages"
__author__ = "@you"
__version__ = "1.0"
__requirements__ = []            # pip packages cannot be installed on iOS: a missing one is reported as the load error

class ShoutPlugin(BasePlugin):   # the first BasePlugin subclass in the file
    def on_plugin_load(self):
        self.add_on_send_message_hook()

    def on_plugin_unload(self):
        pass

    def create_settings(self):
        return [
            Header("Shout"),
            Switch("loud", "Loud mode", default=True, subtext="Applies to every chat"),
            Selector("style", "Style", default=0, items=["UPPER", "lower"]),
            Input("suffix", "Suffix", default="!"),
            Text("Say hi", on_click=lambda view: BulletinHelper.show_success("Hi")),
        ]

    def on_send_message_hook(self, account, params):
        if not self.get_setting("loud", True) or params.message.startswith("/"):
            return HookResult()                                   # leave the message alone
        text = params.message.upper() if self.get_setting("style", 0) == 0 else params.message.lower()
        params.message = text + self.get_setting("suffix", "")
        return HookResult(strategy=HookStrategy.MODIFY, params=params)
```

The metadata (`__id__`, `__name__`, ...) is read with `ast` before the plugin is run, so the list can show it for a
plugin that is switched off.

## Supported API

| Area | What works |
| --- | --- |
| Lifecycle | `on_plugin_load`, `on_plugin_unload`, `on_app_event` (not fired yet) |
| Outgoing text | `add_on_send_message_hook(priority=0)` and `on_send_message_hook(account, params)` returning `HookResult(strategy=CANCEL / MODIFY / MODIFY_FINAL / DEFAULT, params=...)`. Higher priority runs first, `MODIFY_FINAL` ends the chain. `params` has `message` and `peer` |
| Settings values | `get_setting(key, default)`, `set_setting(key, value)` (JSON values), `export_settings()`, `import_settings(dict)`; stored per plugin on the device |
| Settings screen | `create_settings()` widgets, below |
| Client | `client_utils.send_text(peer_id, text)`, `send_message(params)` (text only), `run_on_queue(fn, delay_ms=0)`, `get_current_account()` |
| UI | `ui.bulletin.BulletinHelper.show_info / show_error / show_success / show_simple` (shown as toasts) |
| Misc | `android_utils.run_on_ui_thread`, `log`, `copy_to_clipboard`; `self.log(...)` and `self.logger` go to the plugin log |

Peers are numeric ids (users `id`, groups `-id`, channels `-100id`); usernames are not resolved. Modifying a message
drops its formatting. Hooks run on the main thread: keep them short.

### Settings widgets

| Widget | Rendered as |
| --- | --- |
| `Header(text)` | section title |
| `Switch(key, text, default, subtext, on_change)` | switch |
| `Input(key, text, default, subtext, on_change)` | text field |
| `EditText(key, hint, default, on_change)` | text field (`multiline`, `max_length`, `mask` are ignored) |
| `Selector(key, text, default, items, on_change)` | row that opens a list; the value is the chosen index |
| `Text(text, subtext, on_click)` | a button when `on_click` is set, otherwise a note |
| `Divider`, `Custom` | skipped (no native counterpart) |

A change is stored under the widget's `key`, then `on_change(new_value)` runs. A `Text` tap runs `on_click(None)`
(exteraGram passes a view there; there is none on iOS). `icon`, `link_alias`, `on_long_click` and `create_sub_fragment` are ignored.

## Not supported on iOS

These raise `UnsupportedOnIOS` and show up in the plugin log: `client_utils.send_request`, media sending
(`send_photo`, `send_document`, ...), `edit_message`, Java/Android objects such as `get_messages_controller` and
`get_last_fragment`, `hook_utils` method hooks and `ui.alert.AlertDialogBuilder.show`. Registering a hook other than
the send hook, or a menu item, does not fail: it is logged as a warning, listed on the plugin screen and never fires.

## Tests

```bash
python3 -m unittest discover -s Swiftgram/PythonPlugins/tests
```

They run the host without a device. The Swift side needs Xcode and is not covered.
