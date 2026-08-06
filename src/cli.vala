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

    public void usage () {
        stdout.printf ("Control how the PinePhone and its keyboard case charge\n");
        stdout.printf ("\n");
        stdout.printf ("  chargectl status          show both packs and the active profile\n");
        stdout.printf ("  chargectl daemon          run the control loop\n");
        stdout.printf ("  chargectl profile [name]  show or set the profile\n");
        stdout.printf ("  chargectl band low high   set the hold band\n");
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
