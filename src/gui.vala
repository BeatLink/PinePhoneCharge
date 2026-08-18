namespace Chargectl {

    private const int REFRESH_SECONDS = 2;

    private string microunits (int? value, string suffix, bool sign = false) {
        if (value == null) {
            return "-";
        }
        int raw = value;
        double scaled = raw / 1000000.0;
        return sign ? "%+.2f %s".printf (scaled, suffix) : "%.2f %s".printf (scaled, suffix);
    }

    private class PackRow : Hdy.ActionRow {
        private string supply;
        private Gtk.LevelBar level;
        private Gtk.Label percentage;

        public PackRow (string title, string supply) {
            Object (title: title);
            this.supply = supply;

            level = new Gtk.LevelBar.for_interval (0, 100);
            level.valign = Gtk.Align.CENTER;
            level.set_size_request (90, -1);

            percentage = new Gtk.Label (null);
            percentage.get_style_context ().add_class ("title-3");
            percentage.get_style_context ().add_class ("numeric");

            // Container add, not add_suffix. libhandy has add_prefix and
            // nothing for the other end -- the row's own container slot is the
            // trailing area, so gtk_container_add puts widgets where
            // AdwActionRow would have put a suffix.
            add (level);
            add (percentage);

            // Shown here, not by the window's show_all: a row with no_show_all set is skipped by that walk, children included.
            level.show ();
            percentage.show ();
        }

        public bool refresh () {
            if (!present (supply)) {
                subtitle = "not attached";
                percentage.set_text ("-");
                level.set_value (0);
                return false;
            }

            int? capacity = read_int (attribute (supply, "capacity"));
            string[] details = {
                microunits (read_int (attribute (supply, "voltage_now")), "V"),
                microunits (read_int (attribute (supply, "current_now")), "A", true),
                read (attribute (supply, "status")) ?? "-",
                selected_behaviour (attribute (supply, "charge_behaviour")) ?? "-",
            };

            subtitle = string.joinv ("  ·  ", details);
            if (capacity == null) {
                percentage.set_text ("-");
                level.set_value (0);
            } else {
                int level_value = capacity;
                percentage.set_text ("%d%%".printf (level_value));
                level.set_value (level_value);
            }
            return true;
        }
    }

    private class Window : Hdy.ApplicationWindow {
        private PackRow phone;
        private PackRow case_pack;
        private Hdy.ActionRow profile_row;
        private Hdy.ActionRow input;
        private Hdy.ActionRow case_input;
        private Gtk.ComboBoxText profile;
        private Gtk.SpinButton low;
        private Gtk.SpinButton high;
        private Hdy.ActionRow low_row;
        private Hdy.ActionRow high_row;
        private Hdy.PreferencesGroup manual;
        private Gtk.ComboBoxText phone_limit;
        private Gtk.SpinButton case_limit;
        private Gtk.Switch inhibit_phone;
        private Gtk.Switch inhibit_case;
        private Gtk.InfoBar info;
        private Gtk.Label info_label;
        private bool loading = false;

        public Window (Gtk.Application application) {
            Object (application: application);
            title = "Charge";
            set_default_size (400, 640);

            phone = new PackRow ("Phone", PHONE);
            case_pack = new PackRow ("Keyboard", CASE);
            case_pack.no_show_all = true;

            var packs = new Hdy.PreferencesGroup ();
            packs.title = "Batteries";
            packs.add (phone);
            packs.add (case_pack);

            profile = new Gtk.ComboBoxText ();
            foreach (string name in profile_names ()) {
                profile.append_text (name);
            }
            profile.valign = Gtk.Align.CENTER;
            profile.changed.connect (on_profile_changed);

            profile_row = new Hdy.ActionRow ();
            profile_row.title = "Profile";
            profile_row.add (profile);

            low = new Gtk.SpinButton.with_range (0, 100, 1);
            low.valign = Gtk.Align.CENTER;
            low.value_changed.connect (on_band_changed);
            low_row = new Hdy.ActionRow ();
            low_row.title = "Resume charging below";
            low_row.add (low);

            high = new Gtk.SpinButton.with_range (0, 100, 1);
            high.valign = Gtk.Align.CENTER;
            high.value_changed.connect (on_band_changed);
            high_row = new Hdy.ActionRow ();
            high_row.title = "Stop charging at";
            high_row.add (high);

            var policy = new Hdy.PreferencesGroup ();
            policy.title = "Policy";
            policy.add (profile_row);
            policy.add (low_row);
            policy.add (high_row);

            // The phone's register holds these three steps and nothing between, so a spin button would offer values it cannot take.
            phone_limit = new Gtk.ComboBoxText ();
            phone_limit.append_text ("0.5 A");
            phone_limit.append_text ("0.9 A");
            phone_limit.append_text ("1.5 A");
            phone_limit.valign = Gtk.Align.CENTER;
            phone_limit.changed.connect (on_manual_changed);
            var phone_limit_row = new Hdy.ActionRow ();
            phone_limit_row.title = "Phone draws";
            phone_limit_row.add (phone_limit);

            case_limit = new Gtk.SpinButton.with_range (0.1, 3.1, 0.1);
            case_limit.digits = 1;
            case_limit.valign = Gtk.Align.CENTER;
            case_limit.value_changed.connect (on_manual_changed);
            var case_limit_row = new Hdy.ActionRow ();
            case_limit_row.title = "Case draws";
            case_limit_row.add (case_limit);

            inhibit_phone = new Gtk.Switch ();
            inhibit_phone.valign = Gtk.Align.CENTER;
            inhibit_phone.notify["active"].connect (on_manual_changed);
            var inhibit_phone_row = new Hdy.ActionRow ();
            inhibit_phone_row.title = "Hold the phone's charger off";
            inhibit_phone_row.add (inhibit_phone);

            inhibit_case = new Gtk.Switch ();
            inhibit_case.valign = Gtk.Align.CENTER;
            inhibit_case.notify["active"].connect (on_manual_changed);
            var inhibit_case_row = new Hdy.ActionRow ();
            inhibit_case_row.title = "Hold the case's charger off";
            inhibit_case_row.add (inhibit_case);

            manual = new Hdy.PreferencesGroup ();
            manual.title = "By hand";
            manual.add (phone_limit_row);
            manual.add (case_limit_row);
            manual.add (inhibit_phone_row);
            manual.add (inhibit_case_row);

            // Always on show, whatever the profile: these are what every profile is ultimately setting.
            input = new Hdy.ActionRow ();
            input.title = "Phone draws";
            case_input = new Hdy.ActionRow ();
            case_input.title = "Case draws";
            var supply = new Hdy.PreferencesGroup ();
            supply.title = "Limits in force";
            supply.add (input);
            supply.add (case_input);

            var page = new Hdy.PreferencesPage ();
            page.add (packs);
            page.add (policy);
            page.add (manual);
            page.add (supply);

            var header = new Hdy.HeaderBar ();
            header.show_close_button = true;
            header.title = "Charge";

            // GTK3 has no ToastOverlay. An InfoBar in the same column is the
            // closest thing that does not need a new dependency, and errors
            // here are rare enough that not having it float is no loss.
            info = new Gtk.InfoBar ();
            info.message_type = Gtk.MessageType.ERROR;
            info.show_close_button = true;
            info.no_show_all = true;
            info_label = new Gtk.Label (null);
            info.get_content_area ().add (info_label);
            info.response.connect ((response) => info.hide ());

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            box.add (header);
            box.add (info);
            box.pack_start (page, true, true, 0);
            add (box);

            refresh ();
            Timeout.add_seconds (REFRESH_SECONDS, refresh);
        }

        private bool refresh () {
            phone.refresh ();
            if (case_pack.refresh ()) {
                case_pack.show (); // Not show_all, which no_show_all makes a no-op on this row.
            } else {
                case_pack.hide ();
            }

            input.subtitle = "%s  ·  case %s".printf (
                microunits (read_int (attribute (PHONE_INPUT, "input_current_limit")), "A"),
                case_attached () ? "attached" : "detached");
            case_input.subtitle = microunits (read_int (attribute (CASE, "constant_charge_current")), "A");

            var values = Settings.load ();
            loading = true;
            string[] names = profile_names ();
            for (int index = 0; index < names.length; index++) {
                if (names[index] == values.profile) {
                    profile.set_active (index);
                }
            }
            profile_row.subtitle = profile_description (values.profile) ?? "";
            low.set_value (values.low);
            high.set_value (values.high);
            case_limit.set_value (values.case_limit / 1000000.0);
            phone_limit.set_active (limit_index (values.limit));
            inhibit_phone.set_active (values.inhibit_phone);
            inhibit_case.set_active (values.inhibit_case);
            show_for (values.profile);
            loading = false;

            return Source.CONTINUE;
        }

        /**
         * Leaves only the controls the active profile actually reads on screen.
         */
        private void show_for (string profile) {
            bool banded = profile_uses_band (profile);
            low_row.visible = banded;
            high_row.visible = banded;

            // Toggled through visible rather than show/hide, so the window's own show_all still reaches the rows inside.
            manual.visible = profile_is_manual (profile);
        }

        private int limit_index (int microamps) {
            if (microamps <= PHONE_LIMIT_LOW) {
                return 0;
            }
            return microamps <= PHONE_LIMIT_MEDIUM ? 1 : 2;
        }

        private void on_manual_changed () {
            var values = Settings.load ();
            int[] steps = { PHONE_LIMIT_LOW, PHONE_LIMIT_MEDIUM, PHONE_LIMIT_HIGH };
            int active = phone_limit.get_active ();
            if (active >= 0) {
                values.limit = steps[active];
            }
            values.case_limit = (int) (case_limit.get_value () * 1000000);
            values.inhibit_phone = inhibit_phone.get_active ();
            values.inhibit_case = inhibit_case.get_active ();
            store (values);
        }

        private void store (Settings values) {
            if (loading) {
                return;
            }
            try {
                values.save ();
            } catch (Error error) {
                report (error.message);
            }
        }

        private void on_profile_changed () {
            int active = profile.get_active ();
            if (active < 0) {
                return;
            }

            string chosen = profile_names ()[active];
            profile_row.subtitle = profile_description (chosen) ?? "";

            show_for (chosen);

            var values = Settings.load ();
            values.profile = chosen;
            store (values);
        }

        private void on_band_changed () {
            int low_value = (int) low.get_value ();
            int high_value = (int) high.get_value ();
            if (low_value >= high_value) {
                return;
            }

            var values = Settings.load ();
            values.low = low_value;
            values.high = high_value;
            store (values);
        }

        private void report (string message) {
            info_label.set_text (message);
            info.show_all ();
        }
    }

    private class Application : Gtk.Application {
        public Application () {
            Object (application_id: APP_ID);
        }

        public override void startup () {
            base.startup ();
            Hdy.init ();
        }

        public override void activate () {
            var window = active_window;
            if (window == null) {
                window = new Window (this);
            }
            window.show_all ();
            window.present ();
        }
    }
}

public static int main (string[] args) {
    return new Chargectl.Application ().run (args);
}
