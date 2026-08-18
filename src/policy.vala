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
     * The values the AXP's input limit actually takes.
     *
     * The register holds a small set of steps rather than an arbitrary
     * microamp figure, so anything between them rounds down on the way in.
     * Taken from ppkbbat-d, which established them against the driver.
     */
    public const int PHONE_LIMIT_LOW = 500000;
    public const int PHONE_LIMIT_MEDIUM = 900000;
    public const int PHONE_LIMIT_HIGH = 1500000;

    /**
     * What the case may draw for itself, by who needs the supply more.
     *
     * The IP5209 takes arbitrary values here, unlike the phone. These are
     * ppkbbat-d's, whose ladder these mirror: 0.5A while the phone is the one
     * that needs charge, 0.8A once it is close to full, and the pack's own
     * 2.3A default when nothing is competing for the supply.
     */
    public const int CASE_LIMIT_PHONE_FIRST = 500000;
    public const int CASE_LIMIT_SHARED = 800000;
    public const int CASE_LIMIT_PARALLEL = 1500000;
    public const int CASE_LIMIT_DEFAULT = 2300000;

    /**
     * The draw at which the phone counts as busy rather than idle.
     *
     * ppkbbat-d's threshold: below this the case can carry the system on its
     * lowest setting, above it the phone needs a wider input to keep up.
     */
    public const int HIGH_DEMAND = 600000;

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
     * The pair of limits for what both packs are currently doing.
     *
     * Follows ppkbbat-d's ladder rather than inventing one: the phone's input
     * is opened up whenever it is the pack that needs charge or the load is
     * high, and the case's intake is what gives way. A null case status means
     * it is absent or not reporting, where the phone gets everything.
     */
    public void wanted_limits (string? case_status, int phone_capacity, int? phone_current,
                               bool phone_charging, out int phone_limit, out int case_limit) {
        case_limit = CASE_LIMIT_DEFAULT;

        if (case_status == null) {
            phone_limit = PHONE_LIMIT_HIGH;
            return;
        }

        bool busy = phone_current != null && phone_current < -HIGH_DEMAND;

        if (case_status == "Discharging") {
            case_limit = CASE_LIMIT_PARALLEL;
            if (phone_capacity <= BALANCE_FLOOR - 5) {
                phone_limit = PHONE_LIMIT_HIGH;
            } else if (busy) {
                phone_limit = PHONE_LIMIT_MEDIUM;
            } else {
                phone_limit = PHONE_LIMIT_LOW;
            }
            return;
        }

        phone_limit = PHONE_LIMIT_HIGH;

        if (case_status == "Full") {
            case_limit = CASE_LIMIT_PHONE_FIRST;
            return;
        }

        if (phone_charging) {
            case_limit = busy ? CASE_LIMIT_PHONE_FIRST : CASE_LIMIT_SHARED;
            return;
        }

        case_limit = CASE_LIMIT_PARALLEL;
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
