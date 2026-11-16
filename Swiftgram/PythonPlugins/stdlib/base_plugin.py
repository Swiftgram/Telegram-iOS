"""exteraGram plugin SDK: `base_plugin`, backed by TrollGram for iOS.

API shape follows https://plugins.exteragram.app/docs/plugin-class. What works on
iOS: lifecycle (`on_plugin_load` / `on_plugin_unload`), settings persistence, the
outgoing-message hook (`add_on_send_message_hook`). Hooks on Telegram API requests
and updates (`pre_request_hook`, `on_update_hook`, ...) have no iOS counterpart:
registering them is recorded, logged as unsupported and shown in the plugin's status.
"""

import enum
import json
import logging
import os

import trollgram_bridge

SEND_MESSAGE_HOOK = "send_message"


class HookStrategy(enum.Enum):
    DEFAULT = "default"
    CANCEL = "cancel"
    MODIFY = "modify"
    MODIFY_FINAL = "modify_final"


class AppEvent(enum.Enum):
    START = "start"
    STOP = "stop"
    PAUSE = "pause"
    RESUME = "resume"


class HookResult:
    def __init__(self, strategy=HookStrategy.DEFAULT, request=None, response=None, update=None, updates=None, params=None):
        self.strategy = strategy
        self.request = request
        self.response = response
        self.update = update
        self.updates = updates
        self.params = params

    def __repr__(self):
        return "HookResult(strategy=%s)" % (self.strategy,)


class MenuItemData:
    """Accepted so plugins that build menu items still load; menus are not shown on iOS."""

    def __init__(self, *args, **kwargs):
        self.args = args
        self.kwargs = kwargs


class _LoggerHandler(logging.Handler):
    def __init__(self, source):
        super().__init__()
        self._source = source

    def emit(self, record):
        try:
            level = record.levelname.lower()
            trollgram_bridge.log(self.format(record), level=level, source=self._source)
        except Exception:
            pass


def _settings_dir():
    path = os.path.join(trollgram_bridge.plugin_data_dir(), "settings")
    try:
        os.makedirs(path, exist_ok=True)
    except Exception:
        pass
    return path


class BasePlugin:
    """Base class of every plugin."""

    # -- internal state (plugins may override __init__ without calling super) ---
    def _tg(self):
        state = self.__dict__.get("_tg_state")
        if state is None:
            state = {"id": None, "hooks": {}, "settings": None, "unsupported": [], "logger": None}
            self.__dict__["_tg_state"] = state
        return state

    def _bind(self, plugin_id):
        self._tg()["id"] = plugin_id

    @property
    def id(self):
        return self._tg()["id"] or self.__class__.__module__

    @property
    def logger(self):
        state = self._tg()
        if state["logger"] is None:
            logger = logging.getLogger("plugin." + str(self.id))
            logger.setLevel(logging.DEBUG)
            logger.propagate = False
            if not logger.handlers:
                handler = _LoggerHandler(str(self.id))
                handler.setFormatter(logging.Formatter("%(message)s"))
                logger.addHandler(handler)
            state["logger"] = logger
        return state["logger"]

    # -- lifecycle (overridden by plugins) -------------------------------------
    def on_plugin_load(self):
        pass

    def on_plugin_unload(self):
        pass

    def on_app_event(self, event_type):
        pass

    def create_settings(self):
        return []

    # -- hooks -------------------------------------------------------------------
    def add_hook(self, name, match_substring=False, priority=0):
        if name != SEND_MESSAGE_HOOK:
            unsupported = self._tg()["unsupported"]
            if name not in unsupported:
                unsupported.append(name)
                self.logger.warning("hook '%s' is not supported on iOS and will never fire", name)
            return
        self._tg()["hooks"][name] = {"match_substring": bool(match_substring), "priority": int(priority)}

    def add_on_send_message_hook(self, priority=0):
        self.add_hook(SEND_MESSAGE_HOOK, priority=priority)

    def remove_hook(self, name):
        self._tg()["hooks"].pop(name, None)

    def has_hook(self, name):
        return name in self._tg()["hooks"]

    def hook_priority(self, name):
        entry = self._tg()["hooks"].get(name)
        return entry["priority"] if entry else 0

    def clear_hooks(self):
        self._tg()["hooks"].clear()

    @property
    def unsupported_features(self):
        return list(self._tg()["unsupported"])

    def add_menu_item(self, item):
        unsupported = self._tg()["unsupported"]
        if "menu items" not in unsupported:
            unsupported.append("menu items")
            self.logger.warning("menu items are not supported on iOS")

    def remove_menu_item(self, item_id):
        pass

    # default hook callbacks (never called unless registered and supported)
    def on_send_message_hook(self, account, params):
        return HookResult()

    def pre_request_hook(self, request_name, account, request):
        return HookResult()

    def post_request_hook(self, request_name, account, response, error):
        return HookResult()

    def on_update_hook(self, update_name, account, update):
        return HookResult()

    def on_updates_hook(self, container_name, account, updates):
        return HookResult()

    # -- settings ----------------------------------------------------------------
    def _settings_path(self):
        return os.path.join(_settings_dir(), "%s.json" % (self.id,))

    def _load_settings(self):
        state = self._tg()
        if state["settings"] is None:
            try:
                with open(self._settings_path(), "r", encoding="utf-8") as handle:
                    loaded = json.load(handle)
                state["settings"] = loaded if isinstance(loaded, dict) else {}
            except Exception:
                state["settings"] = {}
        return state["settings"]

    def _save_settings(self):
        try:
            tmp = self._settings_path() + ".tmp"
            with open(tmp, "w", encoding="utf-8") as handle:
                json.dump(self._load_settings(), handle, indent=2, ensure_ascii=False)
            os.replace(tmp, self._settings_path())
        except Exception as error:
            self.logger.error("could not save settings: %s", error)

    def get_setting(self, key, default=None):
        return self._load_settings().get(key, default)

    def set_setting(self, key, value, reload_settings=False):
        try:
            json.dumps(value)
        except (TypeError, ValueError):
            raise TypeError("setting values must be JSON serialisable")
        self._load_settings()[key] = value
        self._save_settings()

    def export_settings(self):
        return dict(self._load_settings())

    def import_settings(self, settings, reload_settings=True):
        self._load_settings().update(dict(settings))
        self._save_settings()

    # -- legacy ------------------------------------------------------------------
    def log(self, message):
        self.logger.info(message)
