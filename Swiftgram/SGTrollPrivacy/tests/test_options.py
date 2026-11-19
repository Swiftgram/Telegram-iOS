"""Keeps TrollTweaks' keys, groups and the TelegramCore mirror in step. Swift is not compiled here: this only
checks that every key is shown on the screen and mirrored into TelegramCore, and that the hooks are in place.

Run: python3 -m unittest discover -s Swiftgram/SGTrollPrivacy/tests
"""
import os
import re
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


def source(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as handle:
        return handle.read()


OPTIONS = source("Swiftgram/SGTrollPrivacy/Sources/TrollPrivacyOptions.swift")
BOOTSTRAP = source("Swiftgram/SGTrollPrivacyCore/Sources/TrollPrivacyBootstrap.swift")


class OptionsTests(unittest.TestCase):
    def keys(self):
        return dict(re.findall(r'public static let (\w+) = "(tg_[a-z_]+)"', OPTIONS))

    def test_keys_are_unique(self):
        values = list(self.keys().values())
        self.assertTrue(values)
        self.assertEqual(len(values), len(set(values)))

    def test_every_key_has_a_row_and_a_mirror(self):
        for name in self.keys():
            self.assertEqual(OPTIONS.count("Row(key: Key.%s," % name), 1, "%s needs exactly one row" % name)
            self.assertIn("Key.%s" % name, BOOTSTRAP, "%s is not mirrored into TelegramCore" % name)

    def test_one_group_shows_the_archive(self):
        self.assertEqual(OPTIONS.count("showsArchive: true"), 1)

    def test_ghost_subswitches_depend_on_ghost_mode(self):
        for name in ("ghostHideOnline", "ghostHideRead", "ghostHideTyping", "ghostHideUpload",
                     "ghostHideStories", "ghostHideChannelViews"):
            self.assertRegex(OPTIONS, r"Row\(key: Key\.%s, [^)]*requiresGhostMode: true\)" % name)


class HookTests(unittest.TestCase):
    def test_core_hooks_are_present(self):
        hooks = {
            "submodules/TelegramCore/Sources/TelegramEngine/Messages/DeleteMessages.swift": "captureDeleted(",
            "submodules/TelegramCore/Sources/State/Sync/StateReplay+Messages.swift": "captureEdit(previous:",
            "submodules/TelegramCore/Sources/TelegramEngine/Messages/MarkMessageContentAsConsumedInteractively.swift": "captureSelfDestructing(",
            "submodules/TelegramCore/Sources/TelegramEngine/Messages/Stories.swift": "suppressStoryViews",
            "submodules/TelegramCore/Sources/State/AccountViewTracker.swift": "suppressChannelViews",
        }
        for path, needle in hooks.items():
            self.assertIn(needle, source(path), "%s lost its TrollTweaks hook" % path)

    def test_settings_screen_is_linked(self):
        controller = source("Swiftgram/SGSettingsUI/Sources/SGSettingsController.swift")
        self.assertIn("trollTweaksController(context: context)", controller)
        self.assertIn("public func trollTweaksController", source("Swiftgram/SGSettingsUI/Sources/TrollTweaksController.swift"))


if __name__ == "__main__":
    unittest.main()
