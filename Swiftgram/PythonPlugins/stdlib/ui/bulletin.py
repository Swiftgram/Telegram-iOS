"""exteraGram SDK: `ui.bulletin.BulletinHelper` -> TrollGram toasts."""

import trollgram_bridge


class BulletinHelper:
    @staticmethod
    def show_info(message, fragment=None):
        trollgram_bridge.show_toast(message, "info")

    @staticmethod
    def show_error(message, fragment=None):
        trollgram_bridge.show_toast(message, "error")

    @staticmethod
    def show_success(message, fragment=None):
        trollgram_bridge.show_toast(message, "success")

    @staticmethod
    def show_simple(text, icon_raw_res_id=None, fragment=None):
        trollgram_bridge.show_toast(text, "info")

    @staticmethod
    def show_with_button(text, icon_raw_res_id=None, button_text=None, on_click=None, fragment=None):
        trollgram_bridge.show_toast(text, "info")


__all__ = ["BulletinHelper"]
