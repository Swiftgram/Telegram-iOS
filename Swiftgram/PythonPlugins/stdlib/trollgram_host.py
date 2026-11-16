"""TrollGram plugin host: discovery, lifecycle and hook dispatch.

The Swift side talks to this module through one function, `call(payload_b64, result_path)`:
the payload is base64 JSON `{"op": ..., ...}` and the JSON result (including the actions
plugins queued, see `trollgram_bridge`) is written to `result_path`. Only
`PyRun_SimpleString` is needed on the native side.

Ops: `sync` (discover + load the enabled set), `send_hook`, `run_scheduled`, `ping`.
"""

import ast
import base64
import importlib.util
import json
import os
import sys
import traceback

import base_plugin
import trollgram_bridge
from base_plugin import BasePlugin, HookStrategy
from peer_utils import to_plugin_id

_META_KEYS = (
    "__id__", "__name__", "__description__", "__author__", "__version__", "__icon__",
    "__app_version__", "__sdk_version__", "__requirements__", "__category__", "__min_version__",
)
_ID_CHARS = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")

_records = {}


class SendMessageParams:
    """What `on_send_message_hook` receives as `params`."""

    def __init__(self, message, peer=None, replyToMsg=None, replyToTopMsg=None):
        self.message = message
        self.peer = peer
        self.replyToMsg = replyToMsg
        self.replyToTopMsg = replyToTopMsg


class Record:
    def __init__(self, plugin_id, path):
        self.id = plugin_id
        self.path = path
        self.mtime = 0.0
        self.meta = {}
        self.error = None
        self.module = None
        self.instance = None
        self.loaded = False
        self.module_name = "trollgram_plugin_" + plugin_id.replace("-", "_")

    def status(self):
        unsupported = []
        if self.instance is not None:
            try:
                unsupported = self.instance.unsupported_features
            except Exception:
                unsupported = []
        return {
            "id": self.id,
            "path": self.path,
            "name": self.meta.get("name") or self.id,
            "description": self.meta.get("description") or "",
            "author": self.meta.get("author") or "",
            "version": self.meta.get("version") or "1.0",
            "loaded": self.loaded,
            "error": self.error,
            "unsupported": unsupported,
        }


def _error_text(error):
    return "%s: %s" % (type(error).__name__, error)


def parse_metadata(source, stem):
    """Read the `__id__`-style metadata with `ast` (plugin code is not executed)."""
    tree = ast.parse(source)
    found = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            name = node.targets[0].id
            if name in _META_KEYS:
                try:
                    found[name] = ast.literal_eval(node.value)
                except Exception:
                    pass
    plugin_id = found.get("__id__")
    if not isinstance(plugin_id, str) or not (2 <= len(plugin_id) <= 32) or not plugin_id[0].isalpha() \
            or not set(plugin_id) <= _ID_CHARS:
        plugin_id = stem
    category = found.get("__category__")
    return {
        "id": plugin_id,
        "name": str(found.get("__name__") or plugin_id),
        "description": str(found.get("__description__") or ""),
        "author": str(found.get("__author__") or ""),
        "version": str(found.get("__version__") or "1.0"),
        "requirements": found.get("__requirements__") if isinstance(found.get("__requirements__"), list) else [],
        "category": category,
    }


def _module_exists(requirement):
    name = str(requirement)
    for separator in ("==", ">=", "<=", "~=", ">", "<", "["):
        name = name.split(separator)[0]
    name = name.strip().replace("-", "_")
    if not name:
        return True
    try:
        return importlib.util.find_spec(name) is not None
    except Exception:
        return False


def discover(directory):
    """Scan `directory`; returns the list of ids seen. New files are parsed, changed ones reloaded."""
    seen = {}
    try:
        entries = sorted(os.listdir(directory))
    except OSError:
        entries = []
    for entry in entries:
        if not entry.endswith(".py"):
            continue
        path = os.path.join(directory, entry)
        stem = entry[:-3]
        try:
            mtime = os.path.getmtime(path)
            with open(path, "r", encoding="utf-8") as handle:
                source = handle.read()
            meta = parse_metadata(source, stem)
            error = None
        except Exception as problem:
            meta = {"id": stem, "name": stem, "description": "", "author": "", "version": "1.0", "requirements": []}
            mtime = 0.0
            error = "cannot read plugin: " + _error_text(problem)
        plugin_id = meta["id"]
        if plugin_id in seen:
            continue
        record = _records.get(plugin_id)
        if record is None or record.path != path:
            if record is not None:
                unload(record)
            record = Record(plugin_id, path)
            _records[plugin_id] = record
        elif record.loaded and record.mtime != mtime:
            unload(record)
        record.mtime = mtime
        record.meta = meta
        record.error = error
        seen[plugin_id] = record
    for plugin_id in list(_records):
        if plugin_id not in seen:
            unload(_records[plugin_id])
            del _records[plugin_id]
    return list(seen)


def load(record):
    if record.loaded:
        return
    if record.error and record.error.startswith("cannot read"):
        return
    record.error = None
    missing = [r for r in record.meta.get("requirements", []) if not _module_exists(r)]
    if missing:
        record.error = "needs Python packages that cannot be installed on iOS: " + ", ".join(map(str, missing))
        return
    try:
        spec = importlib.util.spec_from_file_location(record.module_name, record.path)
        module = importlib.util.module_from_spec(spec)
        sys.modules[record.module_name] = module
        spec.loader.exec_module(module)
        plugin_class = None
        for value in vars(module).values():
            if isinstance(value, type) and issubclass(value, BasePlugin) and value is not BasePlugin \
                    and value.__module__ == module.__name__:
                plugin_class = value
                break
        if plugin_class is None:
            raise RuntimeError("no BasePlugin subclass found")
        instance = plugin_class()
        instance._bind(record.id)
        record.module = module
        record.instance = instance
        instance.on_plugin_load()
        record.loaded = True
    except BaseException as problem:  # SystemExit from a plugin must not stop the host either
        if isinstance(problem, KeyboardInterrupt):
            raise
        record.error = _error_text(problem)
        trollgram_bridge.log("%s failed to load: %s\n%s" % (record.id, record.error, traceback.format_exc(limit=4)),
                             level="error", source=record.id)
        _discard(record)


def _discard(record):
    sys.modules.pop(record.module_name, None)
    if record.instance is not None:
        try:
            record.instance.clear_hooks()
        except Exception:
            pass
    record.module = None
    record.instance = None
    record.loaded = False


def unload(record):
    if record.instance is not None and record.loaded:
        try:
            record.instance.on_plugin_unload()
        except Exception as problem:
            trollgram_bridge.log("%s on_plugin_unload failed: %s" % (record.id, _error_text(problem)),
                                 level="error", source=record.id)
    _discard(record)


def sync(directory, enabled):
    discover(directory)
    wanted = set(enabled)
    for record in _records.values():
        if record.id not in wanted and record.loaded:
            unload(record)
    for record in _records.values():
        if record.id in wanted and not record.loaded:
            load(record)
    return [_records[key].status() for key in sorted(_records)]


def dispatch_send_message(account, peer, message):
    """Run every loaded plugin's send hook. Returns `{"action": pass|cancel|modify, "message": str}`."""
    hooked = [r for r in _records.values()
              if r.loaded and r.instance is not None and r.instance.has_hook(base_plugin.SEND_MESSAGE_HOOK)]
    hooked.sort(key=lambda r: -r.instance.hook_priority(base_plugin.SEND_MESSAGE_HOOK))
    params = SendMessageParams(message, peer)
    modified = False
    for record in hooked:
        try:
            result = record.instance.on_send_message_hook(account, params)
        except Exception as problem:
            trollgram_bridge.log("%s on_send_message_hook failed: %s" % (record.id, _error_text(problem)),
                                 level="error", source=record.id)
            continue
        strategy = getattr(result, "strategy", HookStrategy.DEFAULT)
        if strategy == HookStrategy.CANCEL:
            return {"action": "cancel", "message": message, "by": record.id}
        if strategy in (HookStrategy.MODIFY, HookStrategy.MODIFY_FINAL):
            new_params = getattr(result, "params", None) or params
            new_message = getattr(new_params, "message", None)
            if isinstance(new_message, str):
                params.message = new_message
                modified = True
            if strategy == HookStrategy.MODIFY_FINAL:
                break
    if modified and params.message != message:
        return {"action": "modify", "message": params.message}
    return {"action": "pass", "message": message}


def handle_request(request):
    op = request.get("op")
    trollgram_bridge.set_context({
        "account": request.get("account", 0),
        "peer": to_plugin_id(request["peer"]) if isinstance(request.get("peer"), int) else None,
    })
    if op == "ping":
        return {"ok": True}
    if op == "sync":
        return {"plugins": sync(request["dir"], request.get("enabled", []))}
    if op == "send_hook":
        peer = to_plugin_id(request["peer"]) if isinstance(request.get("peer"), int) else None
        return dispatch_send_message(int(request.get("account", 0)), peer, request["message"])
    if op == "run_scheduled":
        trollgram_bridge.run_scheduled(request["token"])
        return {}
    raise ValueError("unknown op %r" % (op,))


def call(payload_b64, result_path):
    """Entry point used by Swift. Never raises; failures are reported in the result."""
    try:
        request = json.loads(base64.b64decode(payload_b64).decode("utf-8"))
        result = handle_request(request)
        result["ok"] = True
    except BaseException as problem:
        if isinstance(problem, KeyboardInterrupt):
            raise
        result = {"ok": False, "error": _error_text(problem)}
    result["actions"] = trollgram_bridge.drain()
    try:
        tmp = result_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as out:
            json.dump(result, out, ensure_ascii=False)
        os.replace(tmp, result_path)
    except Exception:
        pass
    return result
