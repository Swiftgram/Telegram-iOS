"""Host-side tests for the plugin runtime: `python3 -m unittest discover -s Swiftgram/PythonPlugins/tests`."""

import base64
import json
import os
import shutil
import sys
import tempfile
import textwrap
import unittest

STDLIB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "stdlib")
sys.path.insert(0, os.path.abspath(STDLIB))

DATA = tempfile.mkdtemp(prefix="tg-data-")
os.environ["TROLLGRAM_DATA_DIR"] = DATA

import peer_utils  # noqa: E402
import trollgram_bridge  # noqa: E402
import trollgram_host as host  # noqa: E402

UPPER = '''
from base_plugin import BasePlugin, HookResult, HookStrategy
from ui.settings import Header, Switch

__id__ = "upper"
__name__ = "Upper"
__description__ = "shouts"
__author__ = "@me"
__version__ = "2.1"

class UpperPlugin(BasePlugin):
    def on_plugin_load(self):
        self.add_on_send_message_hook()
    def create_settings(self):
        return [Header("x"), Switch("on", "On", default=True)]
    def on_send_message_hook(self, account, params):
        if params.message.startswith("/"):
            return HookResult()
        params.message = params.message.upper()
        return HookResult(strategy=HookStrategy.MODIFY, params=params)
'''

BLOCK = '''
from base_plugin import BasePlugin, HookResult, HookStrategy
__id__ = "blocker"
__name__ = "Blocker"
class P(BasePlugin):
    def on_plugin_load(self):
        self.add_on_send_message_hook(priority=10)
    def on_send_message_hook(self, account, params):
        if "secret" in params.message:
            return HookResult(strategy=HookStrategy.CANCEL)
        return HookResult()
'''


class HostTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="tg-plugins-")
        host._records.clear()
        trollgram_bridge.drain()

    def tearDown(self):
        for record in list(host._records.values()):
            host.unload(record)
        shutil.rmtree(self.dir, ignore_errors=True)

    def write(self, name, source):
        with open(os.path.join(self.dir, name), "w") as handle:
            handle.write(textwrap.dedent(source))

    def sync(self, enabled):
        return {p["id"]: p for p in host.sync(self.dir, enabled)}

    def test_metadata_without_executing(self):
        self.write("evil.py", 'raise SystemExit("must not run")\n__id__ = "evil"\n__name__ = "Evil"\n')
        plugins = self.sync([])
        self.assertEqual(plugins["evil"]["name"], "Evil")
        self.assertFalse(plugins["evil"]["loaded"])

    def test_bad_id_falls_back_to_file_name(self):
        self.write("file_name.py", '__id__ = "1 bad"\n__name__ = "X"\n')
        self.assertIn("file_name", self.sync([]))

    def test_load_and_status(self):
        self.write("upper.py", UPPER)
        plugins = self.sync(["upper"])
        self.assertTrue(plugins["upper"]["loaded"])
        self.assertEqual(plugins["upper"]["author"], "@me")
        self.assertEqual(plugins["upper"]["version"], "2.1")
        self.assertIsNone(plugins["upper"]["error"])

    def test_disable_unloads(self):
        self.write("upper.py", UPPER)
        self.sync(["upper"])
        plugins = self.sync([])
        self.assertFalse(plugins["upper"]["loaded"])
        self.assertEqual(host.dispatch_send_message(0, 1, "hi")["action"], "pass")

    def test_modify_cancel_and_priority(self):
        self.write("upper.py", UPPER)
        self.write("blocker.py", BLOCK)
        self.sync(["upper", "blocker"])
        self.assertEqual(host.dispatch_send_message(0, 1, "hello"), {"action": "modify", "message": "HELLO"})
        self.assertEqual(host.dispatch_send_message(0, 1, "/cmd")["action"], "pass")
        self.assertEqual(host.dispatch_send_message(0, 1, "a secret")["action"], "cancel")

    def test_modify_final_stops_chain(self):
        self.write("a.py", '''
            from base_plugin import *
            __id__ = "first"
            __name__ = "first"
            class A(BasePlugin):
                def on_plugin_load(self): self.add_on_send_message_hook(priority=5)
                def on_send_message_hook(self, account, params):
                    params.message = "final"
                    return HookResult(strategy=HookStrategy.MODIFY_FINAL, params=params)
        ''')
        self.write("upper.py", UPPER)
        self.sync(["first", "upper"])
        self.assertEqual(host.dispatch_send_message(0, 1, "x")["message"], "final")

    def test_broken_hook_does_not_block_sending(self):
        self.write("bad.py", '''
            from base_plugin import *
            __id__ = "bad"
            __name__ = "bad"
            class B(BasePlugin):
                def on_plugin_load(self): self.add_on_send_message_hook()
                def on_send_message_hook(self, account, params): raise ValueError("boom")
        ''')
        self.sync(["bad"])
        self.assertEqual(host.dispatch_send_message(0, 1, "x")["action"], "pass")
        logs = [a for a in trollgram_bridge.drain() if a["kind"] == "log"]
        self.assertTrue(any("boom" in a["text"] for a in logs))

    def test_load_errors_reported(self):
        self.write("syntax.py", "def (:\n")
        self.write("noclass.py", '__id__ = "noclass"\n__name__ = "n"\n')
        self.write("needs.py", '__id__ = "needs"\n__name__ = "n"\n__requirements__ = ["definitely_not_installed_pkg>=1"]\n')
        self.write("crash.py", '''
            from base_plugin import *
            __id__ = "crash"
            __name__ = "crash"
            class C(BasePlugin):
                def on_plugin_load(self): raise RuntimeError("nope")
        ''')
        plugins = self.sync(["syntax", "noclass", "needs", "crash"])
        self.assertIn("cannot read", plugins["syntax"]["error"])
        self.assertIn("no BasePlugin", plugins["noclass"]["error"])
        self.assertIn("definitely_not_installed_pkg", plugins["needs"]["error"])
        self.assertIn("nope", plugins["crash"]["error"])
        for key in ("noclass", "needs", "crash"):
            self.assertFalse(plugins[key]["loaded"])

    def test_changed_file_is_reloaded(self):
        self.write("upper.py", UPPER)
        self.sync(["upper"])
        path = os.path.join(self.dir, "upper.py")
        self.write("upper.py", UPPER.replace("upper()", "lower()"))
        os.utime(path, (os.path.getmtime(path) + 5,) * 2)
        self.sync(["upper"])
        # the edited source lower-cases instead, which proves the new file was loaded
        self.assertEqual(host.dispatch_send_message(0, 1, "HeLLo")["message"], "hello")

    def test_removed_file_forgotten(self):
        self.write("upper.py", UPPER)
        self.sync(["upper"])
        os.remove(os.path.join(self.dir, "upper.py"))
        self.assertEqual(self.sync(["upper"]), {})

    def test_unsupported_hooks_are_reported(self):
        self.write("req.py", '''
            from base_plugin import *
            __id__ = "req"
            __name__ = "req"
            class R(BasePlugin):
                def on_plugin_load(self): self.add_hook("TL_messages_getHistory")
        ''')
        plugins = self.sync(["req"])
        self.assertEqual(plugins["req"]["unsupported"], ["TL_messages_getHistory"])

    def test_settings_roundtrip(self):
        self.write("upper.py", UPPER)
        self.sync(["upper"])
        instance = host._records["upper"].instance
        self.assertEqual(instance.get_setting("k", 7), 7)
        instance.set_setting("k", {"a": [1, 2]})
        self.assertEqual(instance.get_setting("k"), {"a": [1, 2]})
        instance._tg()["settings"] = None
        self.assertEqual(instance.get_setting("k"), {"a": [1, 2]})
        with self.assertRaises(TypeError):
            instance.set_setting("bad", object())

    def test_settings_widgets_serialise(self):
        self.write("upper.py", UPPER)
        self.sync(["upper"])
        widgets = host._records["upper"].instance.create_settings()
        self.assertEqual(widgets[1].to_dict()["key"], "on")
        json.dumps([w.to_dict() for w in widgets])

    def test_call_protocol(self):
        self.write("upper.py", UPPER)
        out = os.path.join(self.dir, "result.json")

        def run(request):
            host.call(base64.b64encode(json.dumps(request).encode()).decode(), out)
            with open(out) as handle:
                return json.load(handle)

        result = run({"op": "sync", "dir": self.dir, "enabled": ["upper"]})
        self.assertTrue(result["ok"], result)
        self.assertTrue(result["plugins"][0]["loaded"])
        peer = peer_utils.make_packed(0, 777)
        result = run({"op": "send_hook", "account": 3, "peer": peer, "message": "héllo \"q\" \\ 😀"})
        self.assertEqual(result["action"], "modify")
        self.assertEqual(result["message"], "HÉLLO \"Q\" \\ 😀")
        bad = run({"op": "nope"})
        self.assertFalse(bad["ok"])

    def test_send_text_action_and_scheduling(self):
        self.write("snd.py", '''
            from base_plugin import *
            import client_utils
            __id__ = "snd"
            __name__ = "snd"
            class S(BasePlugin):
                def on_plugin_load(self):
                    client_utils.send_text(42, "hi")
                    client_utils.run_on_queue(lambda: client_utils.send_text(-100123, "later"), delay_ms=500)
                    try:
                        client_utils.get_messages_controller()
                    except client_utils.UnsupportedOnIOS as error:
                        self.log(str(error))
        ''')
        self.sync(["snd"])
        actions = trollgram_bridge.drain()
        sends = [a for a in actions if a["kind"] == "send_text"]
        self.assertEqual(len(sends), 1)
        self.assertEqual(sends[0]["peer"], peer_utils.make_packed(0, 42))
        token = [a for a in actions if a["kind"] == "schedule"][0]
        self.assertEqual(token["delay_ms"], 500)
        self.assertTrue(any("not supported" in a["text"] for a in actions if a["kind"] == "log"))
        trollgram_bridge.run_scheduled(token["token"])
        later = [a for a in trollgram_bridge.drain() if a["kind"] == "send_text"][0]
        self.assertEqual(peer_utils.to_plugin_id(later["peer"]), -100123)

    def test_reply_to_is_reported_not_silently_dropped(self):
        trollgram_bridge.send_text(5, "x", reply_to=9)
        actions = trollgram_bridge.drain()
        self.assertEqual([a["kind"] for a in actions], ["log", "send_text"])
        self.assertNotIn("reply_to", actions[1])

    def test_toast(self):
        from ui.bulletin import BulletinHelper
        BulletinHelper.show_error("oops")
        self.assertEqual(trollgram_bridge.drain(), [{"kind": "toast", "text": "oops", "style": "error"}])


class PeerTest(unittest.TestCase):
    def test_roundtrip(self):
        for plugin_id in (1, 777000, 6_000_000_000, -5, -4_000_000_000, -1000000000001, -1002345678901, -1009999999999999 + 10**12 * 0):
            if plugin_id == 0:
                continue
            packed = peer_utils.to_packed(plugin_id)
            self.assertEqual(peer_utils.to_plugin_id(packed), plugin_id, plugin_id)
            self.assertTrue(-(1 << 63) <= packed < (1 << 63))

    def test_layout_matches_postbox(self):
        # namespace in bits 32..34, id low 32 bits, id high bits from bit 35 (Postbox/Peer.swift)
        self.assertEqual(peer_utils.make_packed(2, 5), (2 << 32) | 5)
        self.assertEqual(peer_utils.make_packed(0, (1 << 32) + 9), (1 << 35) | 9)
        self.assertEqual(peer_utils.split_packed((1 << 35) | (1 << 32) | 9), (1, (1 << 32) + 9))

    def test_rejects_names(self):
        for value in ("@user", None, True, 0, 1.5):
            with self.assertRaises((TypeError, ValueError)):
                peer_utils.to_packed(value)

    def test_secret_chat_has_no_plugin_id(self):
        self.assertIsNone(peer_utils.to_plugin_id(peer_utils.make_packed(3, 5)))


if __name__ == "__main__":
    unittest.main()
