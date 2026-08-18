void assert_behaviours (string profile, int capacity, int low, int high,
                        string? phone_wanted, string? case_wanted) {
    string? phone;
    string? case_pack;
    Chargectl.wanted_behaviours (profile, capacity, low, high, out phone, out case_pack);
    assert (phone == phone_wanted);
    assert (case_pack == case_wanted);
}

void assert_limits (string profile, bool recovering, int phone_wanted, int case_wanted) {
    int phone;
    int case_pack;
    Chargectl.wanted_limits (profile, recovering, out phone, out case_pack);
    assert (phone == phone_wanted);
    assert (case_pack == case_wanted);
}

void main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/policy/the-case-charger-is-never-inhibited", () => {
        assert_behaviours ("maintain", 40, 75, 80, "auto", "auto");
        assert_behaviours ("full", 40, 75, 80, "auto", "auto");
        assert_behaviours ("case-first", 40, 75, 80, "auto", "auto");
        assert_behaviours ("balance", 40, 75, 80, "auto", "auto");
        assert_behaviours ("passive", 40, 75, 80, "auto", "auto");
    });

    Test.add_func ("/policy/maintain-inhibits-the-phone-at-the-top-of-the-band", () => {
        assert_behaviours ("maintain", 80, 75, 80, "inhibit-charge", "auto");
    });

    Test.add_func ("/policy/maintain-resumes-below-the-band", () => {
        assert_behaviours ("maintain", 74, 75, 80, "auto", "auto");
    });

    Test.add_func ("/policy/maintain-leaves-the-phone-alone-inside-the-band", () => {
        assert_behaviours ("maintain", 77, 75, 80, null, "auto");
    });

    Test.add_func ("/policy/full-never-holds-the-phone-back", () => {
        assert_behaviours ("full", 99, 75, 80, "auto", "auto");
    });

    Test.add_func ("/policy/maintain-and-full-starve-the-case", () => {
        assert_limits ("maintain", false, Chargectl.PHONE_LIMIT_MAX, Chargectl.CASE_LIMIT_MIN);
        assert_limits ("full", false, Chargectl.PHONE_LIMIT_MAX, Chargectl.CASE_LIMIT_MIN);
    });

    Test.add_func ("/policy/case-first-does-the-opposite", () => {
        assert_limits ("case-first", false, Chargectl.PHONE_LIMIT_MIN, Chargectl.CASE_LIMIT_MAX);
    });

    Test.add_func ("/policy/balance-lets-the-case-carry-the-load", () => {
        assert_limits ("balance", false, Chargectl.PHONE_LIMIT_SHARED, Chargectl.CASE_LIMIT_MAX);
    });

    Test.add_func ("/policy/balance-turns-everything-to-a-low-phone", () => {
        assert_limits ("balance", true, Chargectl.PHONE_LIMIT_MAX, Chargectl.CASE_LIMIT_MIN);
    });

    Test.add_func ("/policy/recovery-starts-below-the-band", () => {
        assert (Chargectl.recovering (false, 74, 75, 80));
        assert (!Chargectl.recovering (false, 75, 75, 80));
    });

    Test.add_func ("/policy/recovery-holds-until-the-top-of-the-band", () => {
        assert (Chargectl.recovering (true, 79, 75, 80));
        assert (!Chargectl.recovering (true, 80, 75, 80));
    });

    Test.add_func ("/policy/only-the-banded-profiles-use-a-band", () => {
        assert (Chargectl.profile_uses_band ("maintain"));
        assert (Chargectl.profile_uses_band ("case-first"));
        assert (Chargectl.profile_uses_band ("balance"));
        assert (!Chargectl.profile_uses_band ("full"));
        assert (!Chargectl.profile_uses_band ("manual"));
        assert (!Chargectl.profile_uses_band ("passive"));
    });

    Test.add_func ("/policy/only-manual-is-manual", () => {
        assert (Chargectl.profile_is_manual ("manual"));
        assert (!Chargectl.profile_is_manual ("maintain"));
    });

    Test.add_func ("/policy/a-drain-on-the-charger-is-reported", () => {
        assert (Chargectl.draining_under_load ("maintain", true, "auto", -200000));
    });

    Test.add_func ("/policy/a-held-pack-is-not-a-drain", () => {
        assert (!Chargectl.draining_under_load ("maintain", true, "inhibit-charge", -200000));
    });

    Test.run ();
}
