"""GTK3 front end for chargectl.

The same interface as gui.py, built on GTK3 and libhandy rather than GTK4 and
libadwaita, so the two can be compared on a device where the toolkit choice
actually costs something.

It is worth keeping equivalent rather than merely similar. libhandy is what
libadwaita grew out of and phosh itself is built on it, so the widget for widget
mapping is close: HdyPreferencesPage for AdwPreferencesPage, HdyActionRow for
AdwActionRow, and so on. Where a row type exists only in libadwaita -- SpinRow,
ComboRow in the form used here -- the equivalent is an action row carrying a
plain GTK control, which is what those rows are underneath.

The reason to have both: GTK4 renders through GSK, which on hardware without
GLES 3.0 falls back to rasterising a scene graph in software, while GTK3 draws
with cairo directly and has no scene graph at all.
"""

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Handy", "1")

from gi.repository import GLib, Gtk, Handy  # noqa: E402

from . import (CASE, CASE_BOOST, PHONE, PHONE_INPUT, PROFILES, read, read_int,
               save, selected_behaviour, settings)  # noqa: E402

APP_ID = "io.github.beatlink.Chargectl3"
REFRESH_SECONDS = 2
ORDER = ["maintain", "full", "case-first", "balance", "passive"]


def microunits(value, suffix, sign=False):
    if value is None:
        return "-"
    pattern = "%+.2f %s" if sign else "%.2f %s"
    return pattern % (value / 1000000.0, suffix)


class PackRow(Handy.ActionRow):
    def __init__(self, title, path):
        super().__init__(title=title)
        self.path = path

        self.level = Gtk.LevelBar(min_value=0, max_value=100,
                                  valign=Gtk.Align.CENTER)
        self.level.set_size_request(90, -1)

        self.percentage = Gtk.Label()
        self.percentage.get_style_context().add_class("title-3")
        self.percentage.get_style_context().add_class("numeric")

        # Container add, not add_suffix. libhandy 1.8 has add_prefix and
        # nothing for the other end -- the row's own container slot is the
        # trailing area, so gtk_container_add puts widgets where AdwActionRow
        # would have put a suffix. Checked against the GIR rather than assumed.
        self.add(self.level)
        self.add(self.percentage)

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


class Window(Handy.ApplicationWindow):
    def __init__(self, application):
        super().__init__(application=application, title="Charge")
        self.set_default_size(400, 640)
        self.loading = False

        self.phone = PackRow("Phone", PHONE)
        self.case = PackRow("Keyboard", CASE)

        packs = Handy.PreferencesGroup(title="Batteries")
        packs.add(self.phone)
        packs.add(self.case)

        self.profile = Gtk.ComboBoxText()
        for name in ORDER:
            self.profile.append_text(name)
        self.profile.set_valign(Gtk.Align.CENTER)
        self.profile.connect("changed", self.on_profile_changed)

        self.profile_row = Handy.ActionRow(title="Profile")
        self.profile_row.add(self.profile)

        self.low = Gtk.SpinButton.new_with_range(0, 100, 1)
        self.low.set_valign(Gtk.Align.CENTER)
        self.low.connect("value-changed", self.on_band_changed)
        low_row = Handy.ActionRow(title="Resume charging below")
        low_row.add(self.low)

        self.high = Gtk.SpinButton.new_with_range(0, 100, 1)
        self.high.set_valign(Gtk.Align.CENTER)
        self.high.connect("value-changed", self.on_band_changed)
        high_row = Handy.ActionRow(title="Stop charging at")
        high_row.add(self.high)

        policy = Handy.PreferencesGroup(title="Policy")
        policy.add(self.profile_row)
        policy.add(low_row)
        policy.add(high_row)

        self.input = Handy.ActionRow(title="Input limit")
        supply = Handy.PreferencesGroup(title="From the case")
        supply.add(self.input)

        page = Handy.PreferencesPage()
        page.add(packs)
        page.add(policy)
        page.add(supply)

        header = Handy.HeaderBar(show_close_button=True, title="Charge")

        # GTK3 has no ToastOverlay. An InfoBar in the same column is the
        # closest thing that does not need a new dependency, and errors here
        # are rare enough that not having it float is no loss.
        self.info = Gtk.InfoBar(message_type=Gtk.MessageType.ERROR,
                                show_close_button=True, no_show_all=True)
        self.info_label = Gtk.Label()
        self.info.get_content_area().add(self.info_label)
        self.info.connect("response", lambda bar, _r: bar.hide())

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.add(header)
        box.add(self.info)
        box.pack_start(page, True, True, 0)
        self.add(box)

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
            self.profile.set_active(ORDER.index(values["profile"]))
        self.profile_row.set_subtitle(PROFILES.get(values["profile"], ""))
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
        active = self.profile.get_active()
        if active < 0:
            return
        chosen = ORDER[active]
        self.profile_row.set_subtitle(PROFILES.get(chosen, ""))
        self.store(profile=chosen)

    def on_band_changed(self, *_args):
        low = int(self.low.get_value())
        high = int(self.high.get_value())
        if low >= high:
            return
        self.store(low=low, high=high)

    def report(self, message):
        self.info_label.set_text(message)
        self.info_label.show()
        self.info.show()


class Application(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)

    def do_startup(self):
        Gtk.Application.do_startup(self)
        Handy.init()

    def do_activate(self):
        window = self.props.active_window or Window(self)
        window.show_all()
        window.present()


def main():
    return Application().run(None)
