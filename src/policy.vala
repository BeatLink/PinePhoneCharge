namespace Chargectl {

    public const string[,] PROFILES = {
        { "maintain", "hold the phone in the band, charging it before the case" },
        { "full", "charge the phone to 100%, still before the case" },
        { "case-first", "hold the phone in the band, but let the case fill first" },
        { "balance", "let the case carry the load, moving charge only when the phone runs low" },
        { "passive", "manage nothing, leave both chargers on auto" },
    };

    public const int DRAIN_THRESHOLD = 50000;
    public const int64 DRAIN_SUSTAIN = 30000000;
    public const string[] DRAIN_PROFILES = { "maintain", "full", "balance" };

    /**
     * The case pack level below which its charger is left alone.
     *
     * Inhibiting the case's charger hands its output to the phone, which is the
     * point, but the boost converter still runs off that pack. Once it is close
     * to empty there is nothing to convert: the phone stops charging and both
     * packs fall together, which is worse than sharing the supply. Measured on a
     * case at 5%, where inhibiting took the phone from +27mA to -328mA.
     */
    public const int CASE_FLOOR = 20;

    /**
     * What the case may draw for itself once the floor guard has let it charge.
     *
     * The pack has to come back up, but at its own 2.3A it takes most of what
     * the supply offers and the phone is no better off than under inhibit. A
     * small share refills it slowly while leaving the phone the rest.
     */
    public const int CASE_SHARE_CURRENT = 500000;

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
     * Whether the phone is losing charge while something is trying to fill it.
     *
     * Only the profiles that mean to charge the phone qualify, and only while
     * its own charger is on auto: a pack held at the top of the band is
     * inhibited deliberately, so draining there is the policy working rather
     * than the load winning. The threshold is the balance deadband, which keeps
     * a pack sitting near zero from raising anything.
     */
    public bool draining_under_load (string profile, bool charger_online,
                                     string? phone_behaviour, int? phone_current) {
        if (!charger_online || phone_behaviour != "auto" || phone_current == null) {
            return false;
        }

        bool managed = false;
        foreach (string name in DRAIN_PROFILES) {
            if (name == profile) {
                managed = true;
            }
        }
        if (!managed) {
            return false;
        }

        int current = phone_current;
        return current < -DRAIN_THRESHOLD;
    }

    /**
     * Holds a drain back until it has lasted the whole window.
     *
     * A phone under a brief load dips negative and recovers on its own, which
     * is not worth a banner. One sample back in the black restarts the clock,
     * so only a drain that survives every reading across the window is
     * reported. Time is passed in rather than read so the window is testable.
     */
    public class DrainTracker : Object {
        private bool started = false;
        private int64 since = 0;

        public bool update (bool draining, int64 now) {
            if (!draining) {
                started = false;
                return false;
            }
            if (!started) {
                started = true;
                since = now;
                return false;
            }
            return now - since >= DRAIN_SUSTAIN;
        }
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
     * Keeps a nearly empty case pack charging even where the profile would not.
     *
     * Applied over the profile's choice rather than inside it, because the rule
     * is about the hardware rather than the intent: every profile that inhibits
     * the case wants the phone charged, and none of them want it charged from a
     * pack with nothing in it.
     */
    public string? case_floor_guard (string? wanted, int? case_capacity) {
        if (wanted != "inhibit-charge" || case_capacity == null) {
            return wanted;
        }
        int level = case_capacity;
        return level < CASE_FLOOR ? "auto" : wanted;
    }

    /**
     * How much the case may draw for itself, given what the profile asked for.
     *
     * Only the relieved case is throttled: a profile that wanted the case
     * charging normally gets its full rate back, and one whose inhibit still
     * stands does not care what the rate is. Null leaves the attribute alone.
     */
    public int? wanted_case_current (string? profile_wanted, string? applied, int? maximum) {
        if (profile_wanted == "inhibit-charge" && applied == "auto") {
            return CASE_SHARE_CURRENT;
        }
        return maximum;
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
