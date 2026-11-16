"""exteraGram SDK: `hook_utils`.

Java/Kotlin method hooking does not exist on iOS. The module imports cleanly so plugins load,
and every hooking entry point raises `UnsupportedOnIOS` when used.
"""

import trollgram_bridge


def _unsupported(name):
    def fn(*args, **kwargs):
        trollgram_bridge.unsupported("hook_utils." + name)
    fn.__name__ = name
    return fn


find_class = _unsupported("find_class")
find_method = _unsupported("find_method")
hook_method = _unsupported("hook_method")
unhook_method = _unsupported("unhook_method")
hook_all_methods = _unsupported("hook_all_methods")
get_method_original = _unsupported("get_method_original")
skip_hook = _unsupported("skip_hook")


class MethodHook:
    def before_hooked_method(self, param):
        pass

    def after_hooked_method(self, param):
        pass


class MethodReplacement(MethodHook):
    def replace_hooked_method(self, param):
        pass
