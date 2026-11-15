"""exteraGram SDK: `ui.settings` widgets.

Widgets are plain value objects returned from `BasePlugin.create_settings()`. On iOS the
plugin screen shows each plugin's persisted values; the widgets describe keys and defaults.
"""


class _Widget:
    key = None

    def __init__(self, **kwargs):
        for name, value in kwargs.items():
            setattr(self, name, value)

    def to_dict(self):
        data = {"type": type(self).__name__}
        for name, value in self.__dict__.items():
            if callable(value):
                continue
            try:
                import json
                json.dumps(value)
            except (TypeError, ValueError):
                continue
            data[name] = value
        return data


class Header(_Widget):
    def __init__(self, text=""):
        super().__init__(text=text)


class Divider(_Widget):
    def __init__(self, text=None):
        super().__init__(text=text)


class Switch(_Widget):
    def __init__(self, key, text, default=False, subtext=None, icon=None, on_change=None, on_long_click=None, link_alias=None):
        super().__init__(key=key, text=text, default=bool(default), subtext=subtext, icon=icon,
                         on_change=on_change, on_long_click=on_long_click, link_alias=link_alias)


class Selector(_Widget):
    def __init__(self, key, text, default=0, items=None, icon=None, on_change=None, on_long_click=None, link_alias=None):
        super().__init__(key=key, text=text, default=int(default), items=list(items or []), icon=icon,
                         on_change=on_change, on_long_click=on_long_click, link_alias=link_alias)


class Input(_Widget):
    def __init__(self, key, text, default="", subtext=None, icon=None, on_change=None, on_long_click=None, link_alias=None):
        super().__init__(key=key, text=text, default=default, subtext=subtext, icon=icon,
                         on_change=on_change, on_long_click=on_long_click, link_alias=link_alias)


class EditText(_Widget):
    def __init__(self, key, hint, default="", multiline=False, max_length=None, mask=None, on_change=None):
        super().__init__(key=key, hint=hint, default=default, multiline=multiline,
                         max_length=max_length, mask=mask, on_change=on_change)


class Text(_Widget):
    def __init__(self, text, subtext=None, icon=None, accent=False, red=False, on_click=None,
                 on_long_click=None, create_sub_fragment=None, link_alias=None):
        super().__init__(text=text, subtext=subtext, icon=icon, accent=accent, red=red, on_click=on_click,
                         on_long_click=on_long_click, create_sub_fragment=create_sub_fragment, link_alias=link_alias)


class Custom(_Widget):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)


__all__ = ["Header", "Divider", "Switch", "Selector", "Input", "EditText", "Text", "Custom"]
