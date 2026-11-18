
<div align="center">

# TrollGram

**An unofficial Telegram client for iOS**

Built on Telegram iOS and Swiftgram, with additional privacy controls
and a plugin system (JavaScript on the built-in JavaScriptCore, plus experimental Python).

[Features](#features) · [Installation](#installation) · [Building](#building) · [Contributing](CONTRIBUTING.md)

</div>

---

## About

TrollGram is an iOS Telegram client based on the Telegram iOS codebase.

The project combines selected Swiftgram features, additional privacy
controls and a plugin system: lightweight JavaScript plugins that need no
extra runtime, and experimental exteraGram-style Python plugins.

The goal is to provide useful client-side features while keeping the
project open to modification and community contributions.

## Features

### Privacy controls

- Anti-Delete
- Edit History
- Ghost Mode
- Hide Online Status
- Hide Read Receipts
- Hide Typing Status
- Hide Uploading Status
- View Once Media
- Copy Protected Media
- Remove Sponsored Messages

These features operate on the client side. They do not guarantee
complete anonymity or protection from Telegram's servers.

### JavaScript plugins

JavaScript plugins run on the JavaScriptCore engine that ships with iOS:
no embedded interpreter, no native bridge libraries, nothing extra to
build or download. Each plugin runs in its own isolated context.

- Import `.js` plugins from the Files app (**Settings → Plugins**).
- Plugins are **off until you enable them**.
- A plugin can declare a settings screen (switches, text fields, buttons)
  that the app renders natively.
- Chat commands: a plugin handles outgoing `.command args` messages and
  can answer with text.
- Telegram access: `TrollGram.sendMessage`, `TrollGram.getPeer`, a generic
  `TrollGram.api(method, params)`, the Telegram **Bot API** through
  `TrollGram.bot(token)` and a Promise-based `fetch`.
- Plugin logs and settings are stored on the device.

```js
// ==TrollGramPlugin==
// @name Hello
// @version 1.0
// ==/TrollGramPlugin==
TrollGram.plugin({
  commands: { ping: () => 'pong' },
  onSend: (msg) => msg.text.replace(/\bteh\b/g, 'the'),
  settings: [{ type: 'switch', key: 'loud', title: 'Loud mode', default: false }]
});
```

The full API is in [`Swiftgram/JSPlugins/README.md`](Swiftgram/JSPlugins/README.md);
runnable samples are in `Swiftgram/JSPlugins/examples`. Peers are numeric ids
(users `id`, groups `-id`, channels `-100id`) or `"me"`. Modifying a message
drops its formatting. Run the tests (Node.js 18+, no device needed):

```bash
node --test Swiftgram/JSPlugins/tests/prelude.test.js
```

### Python plugins

TrollGram runs exteraGram-style Python 3.11 plugins on an embedded
interpreter. It implements the parts of the plugin API that make sense on
iOS and reports the rest instead of failing silently.

- Import `.plugin` (exteraGram) or `.py` plugins from the Files app. exteraGram
  plugins are plain Python source, so they run as they are.
- Plugins are **off until you enable them**; they start on the first
  message you send after launching the app.
- Plugin metadata (`__id__`, `__name__`, `__author__`, `__version__`) is
  read without running the plugin.
- The plugin screen shows author, version, running state, errors and
  the features a plugin uses that iOS does not support.
- Plugin settings and logs are stored on the device.

Supported API:

| Area | What works |
| --- | --- |
| Lifecycle | `on_plugin_load`, `on_plugin_unload` |
| Outgoing text messages | `add_on_send_message_hook` with `HookResult(strategy=CANCEL / MODIFY / MODIFY_FINAL)` and priorities |
| Settings | `get_setting`, `set_setting`, `export_settings`, `import_settings`; `ui.settings` widgets (`Header`, `Switch`, `Input`, `EditText`, `Selector`, `Text`) are rendered natively on the plugin's Settings screen |
| Client | `client_utils.send_text`, `send_message` (text only), `run_on_queue`, `ui.bulletin.BulletinHelper` toasts |

Writing plugins: [`Swiftgram/PythonPlugins/README.md`](Swiftgram/PythonPlugins/README.md).

Not supported on iOS (these raise `UnsupportedOnIOS`, which shows up in the
plugin log): hooks on Telegram API requests and updates, Android/Java
objects such as `get_messages_controller` or `get_last_fragment`, media
sending, `hook_utils`, menu items and alert dialogs. Peers are numeric ids
(users `id`, groups `-id`, channels `-100id`); usernames are not resolved.
Modifying a message drops its formatting.

Default directories:

| Purpose | Path |
| --- | --- |
| Plugins | `Documents/Plugins` |
| Plugin data and settings | `Documents/PluginsData` |

Only install plugins from sources you trust. Plugins execute code within
the application environment and may access available data; JavaScript
plugins can also make network requests and send messages as you.

Run the plugin runtime tests (no device needed):

```bash
python3 -m unittest discover -s Swiftgram/PythonPlugins/tests
```

### Compatibility

The project includes selected features and compatibility components
from exteraGram.

Not every feature from other Telegram clients is available in TrollGram.

## Installation

The recommended way to install TrollGram is to use the IPA files
published in [GitHub Releases](../../releases).

Installation requirements depend on the signing method and the
iOS version of your device.

## Building

### Requirements

- macOS
- Xcode
- Python 3
- Git
- Git submodules initialized

### Clone the repository

```bash
git clone --recursive https://github.com/vnikolas2009/TrollGram.git
cd TrollGram
git submodule update --init --recursive
```

### Prepare the build environment

```bash
python3 build-system/setup_python.py
```

### Build

```bash
python3 build-system/Make/Make.py \
  --cacheDir="$HOME/bazel-cache" \
  --bazelUserRoot="$HOME/bazel-trollgram" \
  build \
  --configurationPath=build-system/appstore-configuration.json \
  --codesigningInformationPath=build-system/fake-codesigning \
  --configuration=release_arm64 \
  --buildNumber=1000 \
  --skipDsym \
  --overrideXcodeVersion
```

The build configuration may need to be adjusted for your environment.

## GitHub Actions

The repository includes a workflow for building the application:

`.github/workflows/build-ipa.yml`

Depending on the workflow configuration, signing may require these
GitHub Actions secrets:

- `P12_BASE64`
- `P12_PASSWORD`
- `MOBILEPROVISION_BASE64`

Logging in to the built app requires the fork's own Telegram application,
because a login code is only delivered to the app it was issued for:

- `TG_API_ID`
- `TG_API_HASH`

Register an application at <https://my.telegram.org/apps> (platform
"other"), then add its `api_id` and `api_hash` as the two secrets. Without
them the build keeps the bundled `api_id` 8 -- Telegram's own App Store
application -- and no login code is delivered to this build at all, neither
by SMS nor as an in-app message.

See [docs/SECRETS.md](docs/SECRETS.md) for every secret, where to get it
and how to add it.

Do not publish certificates, provisioning profiles or passwords
in the repository.

## Project structure

| Path | Description |
| --- | --- |
| `Swiftgram/SGTrollPrivacy` | Privacy-related interface and features |
| `Swiftgram/SGTrollPrivacyCore` | Privacy feature implementation |
| `Swiftgram/JSPlugins` | JavaScript plugin host (JavaScriptCore): Swift runtime, SDK prelude, examples, tests |
| `Swiftgram/PythonPlugins` | Python plugin host: Swift runtime, SDK modules (`stdlib/`), tests |
| `Swiftgram/SGTrollPluginsUI` | Plugin management interface |
| `Swiftgram/SGSettingsUI` | Application settings |
| `submodules/TelegramCore` | Telegram Core components |

## Credits

TrollGram builds on the work of several open-source projects:

- [Telegram iOS](https://github.com/TelegramMessenger/Telegram-iOS)
- [Swiftgram](https://github.com/Swiftgram/Telegram-iOS)
- [exteraGram](https://github.com/exteraSquad/exteraGram) (plugin API design)

Thanks to their developers and contributors. See [CONTRIBUTORS.md](CONTRIBUTORS.md).

## Disclaimer

TrollGram is an unofficial third-party project.

It is not affiliated with, endorsed by or sponsored by Telegram
or any of the projects listed above.

Telegram is a trademark of its respective owner.

## License

TrollGram is distributed under the GNU General Public License,
version 2 or, at your option, any later version. See [LICENSE](LICENSE).

Some third-party components may be distributed under different
licenses. See their respective license files.

