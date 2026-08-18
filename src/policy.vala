namespace Chargectl {

    public const string[,] PROFILES = {
        { "maintain", "hold the phone in the band, charging it before the case" },
        { "full", "charge the phone to 100%, still before the case" },
        { "case-first", "hold the phone in the band, but let the case fill first" },
        { "balance", "let the case carry the load, moving charge only when the phone runs low" },
        { "manual", "hold both limits and both chargers where you set them" },
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
     * What the case draws from the wall for itself.
     *
     * The IP5209 takes arbitrary values here, unlike the phone. Held down to
     * the minimum whenever the phone is the pack that matters, because the two
     * share one supply and the case will otherwise take most of it.
     */
    public const int CASE_LIMIT_MIN = 500000;
    public const int CASE_LIMIT_MAX = 2300000;

    /**
     * Whether a profile holds the phone between two levels.
     *
     * The band is meaningless to the profiles that either charge to full, let
     * the case carry the load, or do as they are told, and showing its controls
     * there invites setting a number that does nothing.
     */
    public bool profile_uses_band (string profile) {
        return profile == "maintain" || profile == "case-first" || profile == "balance";
    }

    /**
     * Whether a profile takes its limits and chargers from the settings alone.
     */
    public bool profile_is_manual (string profile) {
        return profile == "manual";
    }

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
     * Which charger each pack should run, for the profile and level given.
     *
     * The case is never inhibited: an inhibited IP5209 stops drawing from the
     * wall altogether, so with a charger on the case that starves the phone as
     * well as the case. Only the phone's own charger is held off, and only to
     * keep it inside its band.
     *
     * A null means leave whatever is already selected, which is what keeps the
     * hold band from flapping between its two edges.
     */
    public void wanted_behaviours (string profile, int capacity, int low, int high,
                                   out string? phone, out string? case_pack) {
        case_pack = "auto";

        if (profile != "maintain" && profile != "case-first" && profile != "balance") {
            phone = "auto";
            return;
        }

        if (capacity >= high) {
            phone = "inhibit-charge";
        } else if (capacity < low) {
            phone = "auto";
        } else {
            phone = null;
        }
    }

    /**
     * Whether the phone is low enough that the whole supply goes to it.
     *
     * Latched: entered when the phone falls below the band and only left once
     * it is back at the top of it, so a pack sitting on the boundary does not
     * swing the supply back and forth every cycle.
     */
    public bool recovering (bool already, int capacity, int low, int high) {
        return already ? capacity < high : capacity < low;
    }

    /**
     * How much each pack draws, by profile.
     *
     * One supply feeds both, so these are opposites: whichever pack is not
     * being favoured is held at its minimum.
     */
    public void wanted_limits (string profile, bool is_recovering, out int phone_limit, out int case_limit) {
        if (profile == "case-first") {
            phone_limit = PHONE_LIMIT_LOW;
            case_limit = CASE_LIMIT_MAX;
            return;
        }

        if (profile == "balance" && !is_recovering) {
            // The case carries the majority so both packs fall together, which
            // beats moving charge across the boost converter twice over.
            phone_limit = PHONE_LIMIT_MEDIUM;
            case_limit = CASE_LIMIT_MAX;
            return;
        }

        // maintain, full, and balance once the phone has run low.
        phone_limit = PHONE_LIMIT_HIGH;
        case_limit = CASE_LIMIT_MIN;
    }
}
