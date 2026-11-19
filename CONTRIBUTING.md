
# Contributing to TrollGram

Contributions, bug reports and suggestions are welcome.

Before submitting changes, please take a moment to read these guidelines.

## Before you start

- Check existing issues and pull requests.
- Make sure your change is relevant to the project.
- For large changes, open an issue first to discuss the approach.

## Development setup

Clone the repository with its submodules:

```bash
git clone --recursive https://github.com/vnikolas2009/TrollGram.git
cd TrollGram
git submodule update --init --recursive
```

Prepare the build environment:

```bash
python3 build-system/setup_python.py
```

See the [README](README.md) for build instructions.

## Making changes

A few guidelines help keep the codebase consistent:

- Keep changes focused on one problem or feature.
- Follow the existing code style.
- Avoid unrelated formatting changes.
- Do not include generated files unless necessary.
- Test your changes before opening a pull request.

## Privacy features

Changes to privacy-related functionality should be tested carefully.

When submitting such changes, explain:

- What the feature does.
- Whether it affects message handling or network requests.
- Any known limitations.
- How you tested it.

Do not describe client-side privacy features as providing complete anonymity.

## TrollTweaks

A switch needs four things, and `python3 -m unittest discover -s Swiftgram/SGTrollPrivacy/tests` checks they stay
in step:

1. A key in `TrollPrivacyOptions.Key` and a `Row` in one of its groups (that is the whole screen: no UI code per
   switch). Features ship enabled; list a key in `defaultValues` only to change that.
2. A mirror line in `TrollPrivacyBootstrap.mirror()` and a flag plus accessor in `TrollPrivacyRuntime`, which is the
   only thing TelegramCore reads.
3. The hook at its one choke point in TelegramCore, written as an early `if TrollPrivacyRuntime.<flag>`.
4. A line in the README group.

Do not change what state sync stores (`State/CLAUDE.md`): hooks there may only add side effects such as a log entry,
and the same commit updates `docs/state-sync.md`.

## JavaScript plugins

The JavaScript host lives in `Swiftgram/JSPlugins` and uses the system
JavaScriptCore framework; do not add an embedded engine or native bridge.

- `Sources/JSPrelude.swift` holds the JavaScript SDK (`TrollGram`, `fetch`,
  timers) as a raw string literal. It is the only copy: the tests extract it.
- `Sources/JSPluginManager.swift` discovers plugins, owns one `JSContext` per
  plugin, exposes the natives and stores settings.
- `Sources/JSPluginsRuntime.swift` is the small surface the app uses.
  Account-bound work (sending, peer lookup, alerts) is installed as handlers
  by `submodules/TelegramUI/Sources/TrollPluginsBridge.swift`.
- `tests/prelude.test.js` runs the prelude under Node with a mocked
  `__native`. Run it before opening a pull request:

```bash
node --test Swiftgram/JSPlugins/tests/prelude.test.js
```

Guidelines:

- Plugins must stay disabled until the user enables them.
- Expose new capabilities as a `__native` function plus a documented
  `TrollGram.*` wrapper; plugins must not get raw file or process access.
- Keep plugin-visible peer ids Bot-API style (they must fit a JS number).
- Document API changes in `Swiftgram/JSPlugins/README.md` and the README.
- Note in the pull request whether the Swift part was built, since it needs
  macOS and Xcode.

## Python plugins

The plugin runtime lives in `Swiftgram/PythonPlugins`:

- `stdlib/` is the Python side: the exteraGram-compatible SDK modules
  (`base_plugin`, `client_utils`, `ui`, ...), the host (`trollgram_host`) and
  the bridge (`trollgram_bridge`). It is packed into `python.zip` by
  `build-system/setup_python.py`.
- `Sources/` is the Swift side. All calls into the interpreter go through
  `EmbeddedPython.call` on the main thread: one base64 JSON request in, one
  JSON result out.
- `tests/` has the unit tests for the Python side.

Run the tests before opening a pull request:

```bash
python3 -m unittest discover -s Swiftgram/PythonPlugins/tests
```

Guidelines:

- Follow the exteraGram API names and behavior where iOS can support them.
  exteraGram `.plugin` files are Python source and must keep loading unchanged.
- Document SDK changes in `Swiftgram/PythonPlugins/README.md`.
- A feature that cannot work on iOS must raise `UnsupportedOnIOS`
  (`trollgram_bridge.unsupported(...)`), never silently do nothing.
- Plugin calls that reach Telegram or the UI are queued as actions in
  `trollgram_bridge` and executed by Swift; do not add side effects in Python.
- Plugins must stay disabled until the user enables them.
- Document changes to the plugin API in the README and avoid introducing
  unnecessary permissions or access to user data.
- Note in the pull request whether the Swift part was built, since it needs
  macOS and Xcode.

## Pull requests

When opening a pull request:

1. Describe the problem or feature.
2. Explain what you changed.
3. Include relevant screenshots or logs when useful.
4. Mention the tests you performed.
5. Reference related issues, if any.

Keep pull requests focused and avoid combining unrelated changes.

## Commit messages

Use short and descriptive commit messages.

Examples:

```text
fix: correct plugin loading
feat: add privacy setting
docs: update installation instructions
refactor: simplify plugin manager
```

## Reporting bugs

When reporting a bug, include:

- iOS version.
- Device model.
- TrollGram version or commit.
- Steps to reproduce the issue.
- Expected and actual behavior.
- Relevant logs or screenshots.

Do not include passwords, certificates, tokens or private messages.

## Security issues

Do not publish details of an unpatched security vulnerability
in a public issue.

Contact the project maintainers privately before disclosing it.

## License

By submitting a contribution, you agree that it may be distributed
under the project's applicable license.
