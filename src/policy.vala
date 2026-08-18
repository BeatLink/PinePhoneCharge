namespace Chargectl {

    public const string[,] PROFILES = {
        { "maintain", "hold the phone in the band, taking the supply from the case" },
        { "full", "charge the phone to 100%, taking the supply from the case" },
        { "case-first", "fill the case first, leaving the phone its minimum" },
        { "balance", "let the case carry the load until the phone runs low, then turn it all to the phone" },
        { "manual", "hold both limits and both chargers where you set them" },
        { "passive", "manage nothing, leave both chargers on auto" },
    };

    public const int DRAIN_THRESHOLD = 50000;
    public const int64 DRAIN_SUSTAIN = 30000000;
    public const string[] DRAIN_PROFILES = { "maintain", "full", "balance" };

    /**
     * What each register actually accepts, probed against the hardware.
     *
     * The phone takes anything up to 4A and clamps above it; the case takes
     * 100000 up to 3100000 and rejects more. ppkbbat-d's 1.5A is its own
     * default rather than a ceiling: the limit is permission to draw, and the
     * supply is what decides the rest. Held at 3A rather than the register's
     * 4A, which is past anything this phone is ever plugged into.
     */
    public const int PHONE_LIMIT_MIN = 500000;
    public const int PHONE_LIMIT_MAX = 3000000;
    public const int CASE_LIMIT_MIN = 100000;
    public const int CASE_LIMIT_MAX = 3100000;

    /**
     * What the phone draws while the case is meant to carry the system.
     *
     * Between the two ends on purpose: the case supplies most of the load and
     * the phone's own pack makes up the rest, so the two fall together.
     */
    public const int PHONE_LIMIT_SHARED = 900000;

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
     * How much each pack draws, by profile and by whether the phone still wants charge.
     *
     * One supply feeds both, so these are opposites: whichever pack is not
     * being favoured is held at its minimum. Once the phone has what it was
     * going to get -- the top of its band, or full -- the supply passes to the
     * case rather than going unused, since holding the phone's charger off does
     * not stop the case being the thing plugged into the wall.
     */
    public void wanted_limits (string profile, bool phone_wants_charge, out int phone_limit, out int case_limit) {
        if (profile == "case-first" || !phone_wants_charge) {
            // balance keeps the phone on its shared draw, so the case still carries the system rather than only filling itself.
            phone_limit = profile == "balance" ? PHONE_LIMIT_SHARED : PHONE_LIMIT_MIN;
            case_limit = CASE_LIMIT_MAX;
            return;
        }

        phone_limit = PHONE_LIMIT_MAX;
        case_limit = CASE_LIMIT_MIN;
    }
}
