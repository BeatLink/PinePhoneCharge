const int CEILING = 1500000;

void assert_behaviours (string profile, int capacity, int low, int high,
                        string? phone_wanted, string? case_wanted) {
    string? phone;
    string? case_pack;
    Chargectl.wanted_behaviours (profile, capacity, low, high, out phone, out case_pack);
    assert (phone == phone_wanted);
    assert (case_pack == case_wanted);
}

void main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/policy/maintain-inhibits-the-phone-at-the-top-of-the-band", () => {
        assert_behaviours ("maintain", 80, 75, 80, "inhibit-charge", "auto");
    });

    Test.add_func ("/policy/maintain-resumes-below-the-band", () => {
        assert_behaviours ("maintain", 74, 75, 80, "auto", "inhibit-charge");
    });

    Test.add_func ("/policy/maintain-leaves-the-phone-alone-inside-the-band", () => {
        assert_behaviours ("maintain", 77, 75, 80, null, "inhibit-charge");
    });

    Test.add_func ("/policy/a-nearly-empty-case-keeps-charging", () => {
        assert (Chargectl.case_floor_guard ("inhibit-charge", 5) == "auto");
    });

    Test.add_func ("/policy/a-full-case-is-still-inhibited", () => {
        assert (Chargectl.case_floor_guard ("inhibit-charge", 97) == "inhibit-charge");
    });

    Test.add_func ("/policy/the-floor-guard-leaves-auto-alone", () => {
        assert (Chargectl.case_floor_guard ("auto", 5) == "auto");
    });

    Test.add_func ("/policy/the-floor-guard-holds-at-the-floor", () => {
        assert (Chargectl.case_floor_guard ("inhibit-charge", Chargectl.CASE_FLOOR) == "inhibit-charge");
    });

    Test.add_func ("/policy/an-unreadable-case-is-left-as-the-profile-asked", () => {
        assert (Chargectl.case_floor_guard ("inhibit-charge", null) == "inhibit-charge");
    });

    Test.add_func ("/policy/a-widened-input-holds-once-the-drain-eases", () => {
        int phone;
        int case_pack;
        // -509mA is what a phone drawing 1A through a 0.5A limit reads once widened; without the margin it drops straight back.
        Chargectl.wanted_limits ("Discharging", 49, -509000, false, true, out phone, out case_pack);
        assert (phone == Chargectl.PHONE_LIMIT_MEDIUM);
    });

    Test.add_func ("/policy/an-idle-phone-still-steps-back-down", () => {
        int phone;
        int case_pack;
        Chargectl.wanted_limits ("Discharging", 49, -50000, false, true, out phone, out case_pack);
        assert (phone == Chargectl.PHONE_LIMIT_LOW);
    });

    Test.add_func ("/policy/only-the-banded-profiles-use-a-band", () => {
        assert (Chargectl.profile_uses_band ("maintain"));
        assert (Chargectl.profile_uses_band ("case-first"));
        assert (!Chargectl.profile_uses_band ("full"));
        assert (!Chargectl.profile_uses_band ("balance"));
        assert (!Chargectl.profile_uses_band ("manual"));
        assert (!Chargectl.profile_uses_band ("passive"));
    });

    Test.add_func ("/policy/only-manual-is-manual", () => {
        assert (Chargectl.profile_is_manual ("manual"));
        assert (!Chargectl.profile_is_manual ("maintain"));
    });

    Test.add_func ("/policy/an-absent-case-gives-the-phone-everything", () => {
        int phone;
        int case_pack;
        Chargectl.wanted_limits (null, 50, null, false, false, out phone, out case_pack);
        assert (phone == Chargectl.PHONE_LIMIT_HIGH);
    });

    Test.add_func ("/policy/a-low-phone-on-case-power-takes-the-widest-input", () => {
        int phone;
        int case_pack;
        Chargectl.wanted_limits ("Discharging", 20, -100000, false, false, out phone, out case_pack);
        assert (phone == Chargectl.PHONE_LIMIT_HIGH);
    });

    Test.add_func ("/policy/an-idle-phone-on-case-power-sips", () => {
        int phone;
        int case_pack;
        Chargectl.wanted_limits ("Discharging", 60, -100000, false, false, out phone, out case_pack);
        assert (phone == Chargectl.PHONE_LIMIT_LOW);
    });

    Test.add_func ("/policy/a-busy-phone-on-case-power-widens", () => {
        int phone;
        int case_pack;
        Chargectl.wanted_limits ("Discharging", 60, -900000, false, false, out phone, out case_pack);
        assert (phone == Chargectl.PHONE_LIMIT_MEDIUM);
    });

    Test.add_func ("/policy/a-busy-phone-charging-starves-the-case", () => {
        int phone;
        int case_pack;
        Chargectl.wanted_limits ("Charging", 40, -900000, true, false, out phone, out case_pack);
        assert (case_pack == Chargectl.CASE_LIMIT_PHONE_FIRST);
    });

    Test.add_func ("/policy/a-quiet-phone-charging-shares-with-the-case", () => {
        int phone;
        int case_pack;
        Chargectl.wanted_limits ("Charging", 40, 200000, true, false, out phone, out case_pack);
        assert (case_pack == Chargectl.CASE_LIMIT_SHARED);
    });

    Test.add_func ("/policy/a-full-case-yields-to-the-phone", () => {
        int phone;
        int case_pack;
        Chargectl.wanted_limits ("Full", 40, 0, true, false, out phone, out case_pack);
        assert (case_pack == Chargectl.CASE_LIMIT_PHONE_FIRST);
        assert (phone == Chargectl.PHONE_LIMIT_HIGH);
    });

    Test.add_func ("/policy/case-first-never-inhibits-the-case", () => {
        assert_behaviours ("case-first", 20, 75, 80, "auto", "auto");
    });

    Test.add_func ("/policy/full-charges-the-phone-past-the-band", () => {
        assert_behaviours ("full", 90, 75, 80, "auto", "inhibit-charge");
    });

    Test.add_func ("/policy/full-releases-the-case-once-the-phone-is-full", () => {
        assert_behaviours ("full", 100, 75, 80, "auto", "auto");
    });

    Test.add_func ("/policy/passive-manages-nothing", () => {
        assert_behaviours ("passive", 10, 75, 80, "auto", "auto");
    });

    Test.add_func ("/policy/balance-pulls-charge-when-the-phone-is-low", () => {
        assert (Chargectl.balanced_limit (200000, 25, 90, 0, CEILING) == CEILING);
    });

    Test.add_func ("/policy/balance-pulls-charge-when-the-phone-trails-the-case", () => {
        assert (Chargectl.balanced_limit (200000, 60, 90, 0, CEILING) == CEILING);
    });

    Test.add_func ("/policy/balance-backs-off-while-the-phone-is-charging", () => {
        assert (Chargectl.balanced_limit (1000000, 70, 68, 200000, CEILING) == 900000);
    });

    Test.add_func ("/policy/balance-opens-up-while-the-phone-is-draining", () => {
        assert (Chargectl.balanced_limit (1000000, 70, 68, -200000, CEILING) == 1100000);
    });

    Test.add_func ("/policy/balance-holds-still-inside-the-deadband", () => {
        assert (Chargectl.balanced_limit (1000000, 70, 68, 10000, CEILING) == 1000000);
    });

    Test.add_func ("/policy/balance-never-exceeds-the-ceiling", () => {
        assert (Chargectl.balanced_limit (CEILING, 70, 68, -200000, CEILING) == CEILING);
    });

    Test.add_func ("/policy/balance-holds-still-without-a-reading", () => {
        assert (Chargectl.balanced_limit (1000000, 70, null, null, CEILING) == 1000000);
    });

    Test.add_func ("/policy/drain-warns-while-the-charger-is-losing", () => {
        assert (Chargectl.draining_under_load ("maintain", true, "auto", -400000));
        assert (Chargectl.draining_under_load ("full", true, "auto", -400000));
        assert (Chargectl.draining_under_load ("balance", true, "auto", -400000));
    });

    Test.add_func ("/policy/drain-stays-quiet-while-the-phone-is-inhibited", () => {
        assert (!Chargectl.draining_under_load ("maintain", true, "inhibit-charge", -400000));
    });

    Test.add_func ("/policy/drain-stays-quiet-off-the-charger", () => {
        assert (!Chargectl.draining_under_load ("maintain", false, "auto", -400000));
    });

    Test.add_func ("/policy/drain-ignores-the-hands-off-profiles", () => {
        assert (!Chargectl.draining_under_load ("passive", true, "auto", -400000));
        assert (!Chargectl.draining_under_load ("case-first", true, "auto", -400000));
    });

    Test.add_func ("/policy/drain-ignores-a-phone-that-is-filling", () => {
        assert (!Chargectl.draining_under_load ("full", true, "auto", 410000));
    });

    Test.add_func ("/policy/drain-ignores-noise-around-zero", () => {
        assert (!Chargectl.draining_under_load ("balance", true, "auto", -10000));
    });

    Test.add_func ("/policy/drain-holds-still-without-a-reading", () => {
        assert (!Chargectl.draining_under_load ("maintain", true, "auto", null));
        assert (!Chargectl.draining_under_load ("maintain", true, null, -400000));
    });

    Test.add_func ("/policy/drain-waits-out-the-window-before-firing", () => {
        var tracker = new Chargectl.DrainTracker ();
        assert (!tracker.update (true, 0));
        assert (!tracker.update (true, 20000000));
        assert (tracker.update (true, 30000000));
    });

    Test.add_func ("/policy/drain-keeps-reporting-once-the-window-has-passed", () => {
        var tracker = new Chargectl.DrainTracker ();
        assert (!tracker.update (true, 0));
        assert (tracker.update (true, 30000000));
        assert (tracker.update (true, 45000000));
    });

    Test.add_func ("/policy/drain-restarts-the-clock-on-one-good-sample", () => {
        var tracker = new Chargectl.DrainTracker ();
        assert (!tracker.update (true, 0));
        assert (!tracker.update (true, 25000000));
        assert (!tracker.update (false, 26000000));
        assert (!tracker.update (true, 27000000));
        assert (!tracker.update (true, 50000000));
        assert (tracker.update (true, 57000000));
    });

    Test.add_func ("/policy/drain-never-fires-on-a-single-sample", () => {
        var tracker = new Chargectl.DrainTracker ();
        assert (!tracker.update (true, 1000000000));
    });

    Test.run ();
}
