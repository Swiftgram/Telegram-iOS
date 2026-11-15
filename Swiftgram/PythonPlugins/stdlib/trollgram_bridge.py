"""TrollGram native bridge (pure Python, no C extension).

Plugins never talk to Telegram directly. Every client-facing call a plugin makes
(`send_text`, `show_toast`, ...) is recorded here as an *action*. After each call
into Python the Swift host drains the queue (`trollgram_host` returns it as part of
its result) and performs the actions with the real TelegramCore / UI APIs.

Requests that need an answer (current account, current chat) are served from the
*context* the host passes in with every call.

Nothing here raises: a plugin must not be able to crash the host.
"""

from __future__ import annotations

import os
import time

_actions = []
_context = {}
_MAX_ACTIONS = 200

_DATA_DIR_ENV = "TROLLGRAM_DATA_DIR"


class UnsupportedOnIOS(NotImplementedError):
    """Raised by SDK calls that exist in exteraGram (Android) but have no iOS backend."""


def unsupported(name):
    raise UnsupportedOnIOS("%s is not supported in TrollGram for iOS" % (name,))


# -- host side -------------------------------------------------------------
def set_context(context):
    _context.clear()
    if context:
        _context.update(context)


def get_context(key, default=None):
    return _context.get(key, default)


def push(kind, **fields):
    if len(_actions) >= _MAX_ACTIONS:
        return False
    action = {"kind": kind}
    action.update(fields)
    _actions.append(action)
    return True


def drain():
    items = list(_actions)
    del _actions[:]
    return items


# -- plugin side -----------------------------------------------------------
def plugin_data_dir():
    """Directory plugins may use for their own files (created on demand)."""
    path = os.environ.get(_DATA_DIR_ENV) or os.path.join(os.path.expanduser("~"), "Documents", "PluginsData")
    try:
        os.makedirs(path, exist_ok=True)
    except Exception:
        pass
    return path


def log(text, level="info", source=None):
    push("log", level=level, text=str(text), source=source, at=time.time())
    return True


def show_toast(text, style="info"):
    push("toast", text=str(text), style=style)
    return True


def send_text(peer_id, text, reply_to=None):
    """Queue a plain text message for `peer_id` (Bot-API style id, see `peer_utils`)."""
    from peer_utils import to_packed

    if not isinstance(text, str):
        raise TypeError("text must be a str")
    packed = to_packed(peer_id)
    if reply_to is not None:
        log("send_text: replies are not supported on iOS yet, sending without reply", level="warning")
    push("send_text", peer=packed, text=text)
    return True


_scheduled = {}
_next_token = [0]


def schedule(fn, delay_ms=0):
    """Run `fn` now (delay 0) or ask the host to call back after `delay_ms`."""
    if not callable(fn):
        raise TypeError("task must be callable")
    delay = max(0, int(delay_ms or 0))
    if delay == 0:
        run_task(fn)
        return True
    if len(_scheduled) >= _MAX_ACTIONS:
        return False
    _next_token[0] += 1
    token = _next_token[0]
    _scheduled[token] = fn
    push("schedule", token=token, delay_ms=delay)
    return True


def run_task(fn):
    try:
        fn()
    except Exception as error:  # a plugin task must never take the host down
        log("scheduled task failed: %s: %s" % (type(error).__name__, error), level="error")


def run_scheduled(token):
    fn = _scheduled.pop(int(token), None)
    if fn is not None:
        run_task(fn)


def get_current_account():
    return int(_context.get("account", 0))


def get_current_peer():
    return _context.get("peer")


def ready():
    return True
