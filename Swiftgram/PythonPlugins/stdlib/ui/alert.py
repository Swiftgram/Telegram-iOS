"""exteraGram SDK: `ui.alert.AlertDialogBuilder`.

Native alert dialogs are not wired up on iOS yet: building one is harmless, showing it
logs the message and raises `UnsupportedOnIOS` so the plugin author sees why nothing popped up.
"""

import trollgram_bridge


class AlertDialogBuilder:
    ALERT_TYPE_MESSAGE = 0
    ALERT_TYPE_LOADING = 3
    ALERT_TYPE_SPINNER = 2

    def __init__(self, context=None, progress_style=0):
        self._title = None
        self._message = None

    def set_title(self, title):
        self._title = title
        return self

    def set_message(self, message):
        self._message = message
        return self

    def set_positive_button(self, text, listener=None):
        return self

    def set_negative_button(self, text, listener=None):
        return self

    def set_neutral_button(self, text, listener=None):
        return self

    def show(self):
        trollgram_bridge.log("alert: %s %s" % (self._title or "", self._message or ""), level="warning")
        trollgram_bridge.unsupported("AlertDialogBuilder.show")

    def dismiss(self):
        pass


__all__ = ["AlertDialogBuilder"]
