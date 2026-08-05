"""Adaptive GTK front end for chargectl."""

import gi

gi.require_version("Adw", "1")
gi.require_version("Gtk", "4.0")

from gi.repository import Adw, GLib, Gtk  # noqa: E402

from . import (CASE, CASE_BOOST, PHONE, PHONE_INPUT, PROFILES, read, read_int,
               save, selected_behaviour, settings)  # noqa: E402

APP_ID = "io.github.beatlink.Chargectl"
REFRESH_SECONDS = 2
ORDER = ["maintain", "full", "case-first", "balance", "passive"]


def microunits(value, suffix, sign=False):
    if value is None:
        return "-"
    pattern = "%+.2f %s" if sign else "%.2f %s"
    return pattern % (value / 1000000.0, suffix)


class PackRow(Adw.ActionRow):
    def __init__(self, title, path):
        super().__init__(title=title)
        self.path = path
        self.level = Gtk.LevelBar(min_value=0, max_value=100, valign=Gtk.Align.CENTER)
        self.level.set_size_request(90, -1)
        self.percentage = Gtk.Label()
        self.percentage.add_css_class("title-3")
        self.percentage.add_css_class("numeric")
        self.add_suffix(self.level)
        self.add_suffix(self.percentage)

    def refresh(self):
        if not self.path.exists():
            self.set_subtitle("not attached")
            self.percentage.set_text("-")
            self.level.set_value(0)
            return False

        capacity = read_int(self.path / "capacity")
        details = [
            microunits(read_int(self.path / "voltage_now"), "V"),
            microunits(read_int(self.path / "current_now"), "A", sign=True),
            read(self.path / "status") or "-",
            selected_behaviour(self.path / "charge_behaviour") or "-",
        ]
        self.set_subtitle("  ·  ".join(details))
        self.percentage.set_text("-" if capacity is None else "%d%%" % capacity)
        self.level.set_value(capacity or 0)
        return True


class Window(Adw.ApplicationWindow):
    def __init__(self, application):
        super().__init__(application=application, title="Charge")
        self.set_default_size(400, 640)
        self.loading = False

        self.phone = PackRow("Phone", PHONE)
        self.case = PackRow("Keyboard", CASE)

        packs = Adw.PreferencesGroup(title="Batteries")
        packs.add(self.phone)
        packs.add(self.case)

        self.profile = Adw.ComboRow(title="Profile",
                                    model=Gtk.StringList.new(ORDER))
        self.profile.connect("notify::selected", self.on_profile_changed)

        self.low = Adw.SpinRow.new_with_range(0, 100, 1)
        self.low.set_title("Resume charging below")
        self.low.connect("notify::value", self.on_band_changed)

        self.high = Adw.SpinRow.new_with_range(0, 100, 1)
        self.high.set_title("Stop charging at")
        self.high.connect("notify::value", self.on_band_changed)

        policy = Adw.PreferencesGroup(title="Policy")
        policy.add(self.profile)
        policy.add(self.low)
        policy.add(self.high)

        self.input = Adw.ActionRow(title="Input limit")
        supply = Adw.PreferencesGroup(title="From the case")
        supply.add(self.input)

        page = Adw.PreferencesPage()
        page.add(packs)
        page.add(policy)
        page.add(supply)

        view = Adw.ToolbarView()
        view.add_top_bar(Adw.HeaderBar())
        view.set_content(page)

        self.toasts = Adw.ToastOverlay()
        self.toasts.set_child(view)
        self.set_content(self.toasts)

        self.refresh()
        GLib.timeout_add_seconds(REFRESH_SECONDS, self.refresh)

    def refresh(self):
        self.phone.refresh()
        self.case.set_visible(self.case.refresh())

        limit = read_int(PHONE_INPUT / "input_current_limit")
        attached = read(CASE_BOOST / "online") == "1"
        self.input.set_subtitle("%s  ·  case %s" % (
            microunits(limit, "A"),
            "attached" if attached else "detached",
        ))

        values = settings()
        self.loading = True
        if values["profile"] in ORDER:
            self.profile.set_selected(ORDER.index(values["profile"]))
        self.profile.set_subtitle(PROFILES.get(values["profile"], ""))
        self.low.set_value(values["low"])
        self.high.set_value(values["high"])
        self.loading = False

        return GLib.SOURCE_CONTINUE

    def store(self, **changes):
        if self.loading:
            return
        values = settings()
        values.update(changes)
        try:
            save(values)
        except OSError as error:
            self.report(str(error))

    def on_profile_changed(self, *_args):
        chosen = ORDER[self.profile.get_selected()]
        self.profile.set_subtitle(PROFILES.get(chosen, ""))
        self.store(profile=chosen)

    def on_band_changed(self, *_args):
        low = int(self.low.get_value())
        high = int(self.high.get_value())
        if low >= high:
            return
        self.store(low=low, high=high)

    def report(self, message):
        self.toasts.add_toast(Adw.Toast(title=message))


class Application(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)

    def do_activate(self):
        window = self.props.active_window or Window(self)
        window.present()


def main():
    return Application().run(None)
