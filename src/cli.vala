namespace Chargectl {

    private string volts (string supply) {
        int? value = read_int (attribute (supply, "voltage_now"));
        if (value == null) {
            return "    -";
        }
        int raw = value;
        return "%5.2f".printf (raw / 1000000.0);
    }

    private string amps (string supply) {
        int? value = read_int (attribute (supply, "current_now"));
        if (value == null) {
            return "     -";
        }
        int raw = value;
        return "%+6.2f".printf (raw / 1000000.0);
    }

    private string pack_row (string label, string supply) {
        if (!present (supply)) {
            return "%-10s %8s".printf (label, "absent");
        }
        return "%-10s %7s%% %s V %s A  %-12s %s".printf (
            label,
            read (attribute (supply, "capacity")) ?? "-",
            volts (supply),
            amps (supply),
            read (attribute (supply, "status")) ?? "-",
            selected_behaviour (attribute (supply, "charge_behaviour")) ?? "-");
    }

    public void status () {
        var values = Settings.load ();
        int? measured = read_int (attribute (PHONE_INPUT, "input_current_limit"));
        int limit = 0;
        if (measured != null) {
            limit = measured;
        }

        stdout.printf ("profile    %s  (band %d-%d%%)\n",
                       values.profile, values.low, values.high);
        stdout.printf ("           %s\n", profile_description (values.profile) ?? "");
        stdout.printf ("input      %.2f A limit, case %s\n",
                       limit / 1000000.0, case_attached () ? "attached" : "detached");
        stdout.printf ("\n");
        stdout.printf ("%-10s %8s %7s %7s  %-12s %s\n",
                       "pack", "capacity", "voltage", "current", "state", "charger");
        stdout.printf ("%s\n", pack_row ("phone", PHONE));
        stdout.printf ("%s\n", pack_row ("keyboard", CASE));
    }

    public void list_profiles () {
        stdout.printf ("%s\n", Settings.load ().profile);
        for (int row = 0; row < PROFILES.length[0]; row++) {
            stdout.printf ("  %-11s %s\n", PROFILES[row, 0], PROFILES[row, 1]);
        }
    }

    public int set_profile (string name) {
        string? description = profile_description (name);
        if (description == null) {
            stderr.printf ("unknown profile %s, pick one of: %s\n",
                           name, string.joinv (", ", profile_names ()));
            return 1;
        }

        var values = Settings.load ();
        values.profile = name;
        try {
            values.save ();
        } catch (Error error) {
            stderr.printf ("%s\n", error.message);
            return 1;
        }

        stdout.printf ("profile %s: %s\n", name, description);
        return 0;
    }

    public int set_band (int low, int high) {
        if (low < 0 || low >= high || high > 100) {
            stderr.printf ("band must satisfy 0 <= low < high <= 100\n");
            return 1;
        }

        var values = Settings.load ();
        values.low = low;
        values.high = high;
        try {
            values.save ();
        } catch (Error error) {
            stderr.printf ("%s\n", error.message);
            return 1;
        }

        stdout.printf ("band %d-%d%%\n", low, high);
        return 0;
    }

    public int set_limit (string text) {
        double amps = 0;
        if (!double.try_parse (text, out amps) || amps <= 0 || amps > 3) {
            stderr.printf ("limit must be an amperage between 0 and 3\n");
            return 1;
        }

        var values = Settings.load ();
        values.limit = (int) (amps * 1000000);
        try {
            values.save ();
        } catch (Error error) {
            stderr.printf ("%s\n", error.message);
            return 1;
        }

        stdout.printf ("input limit %.2f A\n", amps);
        return 0;
    }

    /**
     * Turns the case's output to the phone on and off.
     *
     * The boost converter is what feeds the phone, so switching it off leaves
     * the case a keyboard that charges from its own port and nothing else.
     */
    public int toggle_output (string? wanted) {
        string path = attribute (CASE_BOOST, "online");
        if (!present (path)) {
            stderr.printf ("no keyboard case attached\n");
            return 1;
        }

        string? state = read (path);
        if (wanted == null) {
            stdout.printf ("case output %s\n", state == "1" ? "on" : "off");
            return 0;
        }

        string value = wanted == "on" ? "1" : "0";
        if (wanted != "on" && wanted != "off") {
            stderr.printf ("usage: chargectl output [on|off]\n");
            return 2;
        }
        if (!write_value (path, value)) {
            stderr.printf ("could not switch the case output, needs root\n");
            return 1;
        }

        stdout.printf ("case output %s\n", wanted);
        return 0;
    }

    public void usage () {
        stdout.printf ("Control how the PinePhone and its keyboard case charge\n");
        stdout.printf ("\n");
        stdout.printf ("  chargectl status          show both packs and the active profile\n");
        stdout.printf ("  chargectl daemon          run the control loop\n");
        stdout.printf ("  chargectl watch           warn when the phone drains on the charger\n");
        stdout.printf ("  chargectl profile [name]  show or set the profile\n");
        stdout.printf ("  chargectl band low high   set the hold band\n");
        stdout.printf ("  chargectl limit [amps]    set the current drawn from the case\n");
        stdout.printf ("  chargectl output [on|off] show or switch the case's output\n");
    }
}

public static int main (string[] args) {
    string command = args.length > 1 ? args[1] : "status";

    switch (command) {
    case "status":
        Chargectl.status ();
        return 0;

    case "daemon":
        Chargectl.daemon ();
        return 0;

    case "watch":
        Chargectl.watch ();
        return 0;

    case "profile":
        if (args.length > 2) {
            return Chargectl.set_profile (args[2]);
        }
        Chargectl.list_profiles ();
        return 0;

    case "band":
        int low = 0;
        int high = 0;
        if (args.length < 4
            || !int.try_parse (args[2], out low)
            || !int.try_parse (args[3], out high)) {
            stderr.printf ("usage: chargectl band <low> <high>\n");
            return 2;
        }
        return Chargectl.set_band (low, high);

    case "limit":
        if (args.length < 3) {
            stdout.printf ("%.2f A\n", Chargectl.Settings.load ().limit / 1000000.0);
            return 0;
        }
        return Chargectl.set_limit (args[2]);

    case "output":
        return Chargectl.toggle_output (args.length > 2 ? args[2] : null);

    case "help":
    case "--help":
    case "-h":
        Chargectl.usage ();
        return 0;

    default:
        stderr.printf ("unknown command %s\n\n", command);
        Chargectl.usage ();
        return 2;
    }
}
