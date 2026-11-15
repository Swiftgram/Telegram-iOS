"""exteraGram SDK: `android_utils` for iOS.

Plugins written for Android import this for a few helpers. The ones with an iOS meaning
are mapped; the rest raise `UnsupportedOnIOS`.
"""

import trollgram_bridge


def run_on_ui_thread(fn, delay=0):
    return trollgram_bridge.schedule(fn, delay)


def log(text):
    return trollgram_bridge.log(text)


class OnClickListener:
    def __init__(self, fn):
        self._fn = fn

    def onClick(self, *args):
        return self._fn(*args)


class OnLongClickListener(OnClickListener):
    pass


def copy_to_clipboard(text):
    trollgram_bridge.unsupported("android_utils.copy_to_clipboard")


def get_application_context():
    trollgram_bridge.unsupported("android_utils.get_application_context")
