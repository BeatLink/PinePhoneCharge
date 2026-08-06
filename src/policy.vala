namespace Chargectl {

    public const string[,] PROFILES = {
        { "maintain", "hold the phone in the band, charging it before the case" },
        { "full", "charge the phone to 100%, still before the case" },
        { "case-first", "hold the phone in the band, but let the case fill first" },
        { "balance", "let the case carry the load, moving charge only when the phone runs low" },
        { "passive", "manage nothing, leave both chargers on auto" },
    };

    public const int BALANCE_FLOOR = 30;
    public const int BALANCE_SKEW = 5;
    public const int BALANCE_DEADBAND = 50000;
    public const int BALANCE_STEP = 100000;
    public const int BALANCE_MINIMUM = 200000;

    public string? profile_description (string name) {
        for (int row = 0; row < PROFILES.length[0]; row++) {
            if (PROFILES[row, 0] == name) {
                return PROFILES[row, 1];
            }
        }
        return null;
    }

    public string[] profile_names () {
        string[] names = {};
        for (int row = 0; row < PROFILES.length[0]; row++) {
            names += PROFILES[row, 0];
        }
        return names;
    }

    /**
     * The charge_behaviour wanted for the phone and for the case.
     *
     * A null means leave whatever is already selected, which is what keeps the
     * hold band from flapping between its two edges.
     */
    public void wanted_behaviours (string profile, int capacity, int low, int high,
                                   out string? phone, out string? case_pack) {
        if (profile == "passive" || profile == "balance") {
            phone = "auto";
            case_pack = "auto";
            return;
        }

        if (profile == "full") {
            phone = "auto";
            case_pack = capacity < 100 ? "inhibit-charge" : "auto";
            return;
        }

        if (capacity >= high) {
            phone = "inhibit-charge";
        } else if (capacity < low) {
            phone = "auto";
        } else {
            phone = null;
        }

        if (profile == "case-first") {
            case_pack = "auto";
            return;
        }

        case_pack = capacity < high ? "inhibit-charge" : "auto";
    }

    /**
     * Track the input limit so each pack carries its share of the load.
     *
     * Moving charge from the case into the phone costs the boost conversion
     * twice over, so it is only worth doing when the phone is the one running
     * out. Otherwise the limit is nudged until the phone neither charges nor
     * drains and the case carries the system.
     */
    public int balanced_limit (int limit, int phone_capacity, int? case_capacity,
                               int? phone_current, int ceiling) {
        if (phone_capacity < BALANCE_FLOOR) {
            return ceiling;
        }
        if (case_capacity != null) {
            int other = case_capacity;
            if (phone_capacity + BALANCE_SKEW < other) {
                return ceiling;
            }
        }
        if (phone_current == null) {
            return limit;
        }

        int current = phone_current;
        if (current > BALANCE_DEADBAND) {
            return int.max (BALANCE_MINIMUM, limit - BALANCE_STEP);
        }
        if (current < -BALANCE_DEADBAND) {
            return int.min (ceiling, limit + BALANCE_STEP);
        }
        return limit;
    }
}
