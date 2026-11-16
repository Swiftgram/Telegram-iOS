"""exteraGram SDK: `client_utils`, backed by TrollGram for iOS.

Working: `send_text`, `send_message` (text only), `run_on_queue`, `get_*` of the current
account. Everything that hands out Android/Java objects (`get_messages_controller`,
`get_last_fragment`, `send_request`, media sending, ...) raises `UnsupportedOnIOS`, which
shows up in the plugin log instead of failing silently.
"""

import trollgram_bridge
from trollgram_bridge import UnsupportedOnIOS  # noqa: F401

PLUGINS_QUEUE = "plugins"
GLOBAL_QUEUE = "global"
STAGE_QUEUE = "stage"
CACHE_CLEAR_QUEUE = "cache_clear"
SEARCH_QUEUE = "search"
PHONE_BOOK_QUEUE = "phone_book"
THEME_QUEUE = "theme"
EXTERNAL_NETWORK_QUEUE = "external_network"


def send_text(peer_id, text, replyToMsg=None, parse_mode=None):
    """Send `text` to `peer_id` (user id, `-group id` or `-100channel id`)."""
    if parse_mode:
        trollgram_bridge.log("send_text: parse_mode is ignored on iOS", level="warning")
    return trollgram_bridge.send_text(peer_id, text, reply_to=replyToMsg if isinstance(replyToMsg, int) else None)


def send_message(params, parse_mode=None):
    """Low-level send from a dict of SendMessageParams fields (text messages only)."""
    if not isinstance(params, dict):
        params = dict(getattr(params, "__dict__", {}))
    for key in ("photo", "document", "video", "audio", "sticker", "location", "poll"):
        if params.get(key):
            trollgram_bridge.unsupported("send_message with %s" % (key,))
    peer = params.get("peer", params.get("peer_id"))
    return send_text(peer, params.get("message", ""), parse_mode=parse_mode)


def run_on_queue(task, queue=PLUGINS_QUEUE, delay_ms=0):
    """Run `task` after `delay_ms`; on iOS every queue is the interpreter's single thread."""
    return trollgram_bridge.schedule(task, delay_ms)


def get_account_instance():
    return trollgram_bridge.get_current_account()


def get_current_account():
    return trollgram_bridge.get_current_account()


def _unsupported(name):
    def fn(*args, **kwargs):
        trollgram_bridge.unsupported("client_utils." + name)
    fn.__name__ = name
    return fn


for _name in (
    "send_request", "send_photo", "send_document", "send_video", "send_audio", "edit_message",
    "get_last_fragment", "get_user_config", "get_connections_manager", "get_messages_controller",
    "get_send_messages_helper", "get_contacts_controller", "get_media_data_controller",
    "get_location_controller", "get_notifications_controller", "get_messages_storage",
    "get_file_loader", "get_secret_chat_helper", "get_download_controller",
    "get_notifications_settings", "get_notification_center", "get_media_controller",
    "get_queue_by_name",
):
    globals()[_name] = _unsupported(_name)


class NotificationCenterDelegate:
    """Subclassable placeholder; notifications are never delivered on iOS."""

    def didReceivedNotification(self, id, account, args):
        pass
