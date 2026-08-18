namespace Chargectl {

    public void apply_limit (int wanted) {
        string path = attribute (PHONE_INPUT, "input_current_limit");
        int? current = read_int (path);
        if (current != null && current == wanted) {
            return;
        }

        string shown = "-";
        if (current != null) {
            int value = current;
            shown = value.to_string ();
        }
        log ("input limit %s -> %d".printf (shown, wanted));
        write_value (path, wanted.to_string ());
    }

    public void apply_case_limit (int wanted) {
        string path = attribute (CASE, "constant_charge_current");
        if (!present (path)) {
            return;
        }
        int? current = read_int (path);
        if (current != null && current == wanted) {
            return;
        }
        log ("case charge current -> %d".printf (wanted));
        write_value (path, wanted.to_string ());
    }

    public int apply (Settings values, int limit, ref bool is_recovering) {
        int? capacity = read_int (attribute (PHONE, "capacity"));
        if (capacity == null) {
            return limit;
        }
        int level = capacity;

        if (case_attached ()) {
            if (values.profile == "manual") {
                limit = values.limit;
                apply_limit (limit);
                apply_case_limit (values.case_limit);
            } else if (values.profile == "passive") {
                // Passive runs no policy, but the input limit is the one thing the driver gets wrong by default.
                limit = values.limit;
                apply_limit (limit);
            } else {
                is_recovering = recovering (is_recovering, level, values.low, values.high);

                int phone_limit;
                int case_limit;
                wanted_limits (values.profile, is_recovering, out phone_limit, out case_limit);
                limit = phone_limit;
                apply_limit (phone_limit);
                apply_case_limit (case_limit);
            }
        }

        string? phone_behaviour;
        string? case_behaviour;
        wanted_behaviours (values.profile, level, values.low, values.high,
                           out phone_behaviour, out case_behaviour);

        if (values.profile == "manual") {
            phone_behaviour = values.inhibit_phone ? "inhibit-charge" : "auto";
            case_behaviour = values.inhibit_case ? "inhibit-charge" : "auto";
        }

        string where = "phone at %d%%,".printf (level);
        set_behaviour (attribute (PHONE, "charge_behaviour"), phone_behaviour, where);
        set_behaviour (attribute (CASE, "charge_behaviour"), case_behaviour, where + " case");
        return limit;
    }

    public void daemon () {
        Settings? active = null;
        int limit = Settings.load ().limit;
        bool is_recovering = false;

        while (true) {
            var values = Settings.load ();
            if (active == null || !values.equals (active)) {
                log ("profile %s, band %d-%d%%".printf (values.profile, values.low, values.high));
                active = values;
                limit = values.limit;
            }
            limit = apply (values, limit, ref is_recovering);
            Thread.usleep ((ulong) values.interval * 1000000);
        }
    }
}
