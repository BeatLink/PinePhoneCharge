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

    Test.run ();
}
