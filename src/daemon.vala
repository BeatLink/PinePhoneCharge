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

    public int apply (Settings values, int limit) {
        int? capacity = read_int (attribute (PHONE, "capacity"));
        if (capacity == null) {
            return limit;
        }
        int level = capacity;

        if (case_attached () && values.profile != "passive") {
            if (values.profile == "balance") {
                limit = balanced_limit (limit, level,
                                        read_int (attribute (CASE, "capacity")),
                                        read_int (attribute (PHONE, "current_now")),
                                        values.limit);
                apply_limit (limit);
            } else {
                int phone_limit;
                int case_limit;
                wanted_limits (read (attribute (CASE, "status")), level,
                               read_int (attribute (PHONE, "current_now")),
                               read (attribute (PHONE, "status")) == "Charging",
                               out phone_limit, out case_limit);
                // The configured limit is a ceiling on the ladder, not a replacement for it.
                limit = int.min (phone_limit, values.limit);
                apply_limit (limit);
                apply_case_limit (case_limit);
            }
        }

        string? phone_behaviour;
        string? case_behaviour;
        wanted_behaviours (values.profile, level, values.low, values.high,
                           out phone_behaviour, out case_behaviour);

        case_behaviour = case_floor_guard (case_behaviour,
                                           read_int (attribute (CASE, "capacity")));

        string where = "phone at %d%%,".printf (level);
        set_behaviour (attribute (PHONE, "charge_behaviour"), phone_behaviour, where);
        set_behaviour (attribute (CASE, "charge_behaviour"), case_behaviour, where + " case");
        return limit;
    }

    public void daemon () {
        Settings? active = null;
        int limit = Settings.load ().limit;

        while (true) {
            var values = Settings.load ();
            if (active == null || !values.equals (active)) {
                log ("profile %s, band %d-%d%%".printf (values.profile, values.low, values.high));
                active = values;
                limit = values.limit;
            }
            limit = apply (values, limit);
            Thread.usleep ((ulong) values.interval * 1000000);
        }
    }
}
