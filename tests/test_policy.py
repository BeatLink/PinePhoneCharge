from chargectl import balanced_limit, wanted_behaviours

CEILING = 1500000


def test_maintain_inhibits_the_phone_at_the_top_of_the_band():
    assert wanted_behaviours("maintain", 80, 75, 80) == ("inhibit-charge", "auto")


def test_maintain_resumes_below_the_band():
    assert wanted_behaviours("maintain", 74, 75, 80) == ("auto", "inhibit-charge")


def test_maintain_leaves_the_phone_alone_inside_the_band():
    phone, case = wanted_behaviours("maintain", 77, 75, 80)
    assert phone is None
    assert case == "inhibit-charge"


def test_case_first_never_inhibits_the_case():
    assert wanted_behaviours("case-first", 20, 75, 80) == ("auto", "auto")


def test_full_charges_the_phone_past_the_band():
    assert wanted_behaviours("full", 90, 75, 80) == ("auto", "inhibit-charge")


def test_full_releases_the_case_once_the_phone_is_full():
    assert wanted_behaviours("full", 100, 75, 80) == ("auto", "auto")


def test_passive_manages_nothing():
    assert wanted_behaviours("passive", 10, 75, 80) == ("auto", "auto")


def test_balance_pulls_charge_when_the_phone_is_low():
    assert balanced_limit(200000, 25, 90, 0, CEILING) == CEILING


def test_balance_pulls_charge_when_the_phone_trails_the_case():
    assert balanced_limit(200000, 60, 90, 0, CEILING) == CEILING


def test_balance_backs_off_while_the_phone_is_charging():
    assert balanced_limit(1000000, 70, 68, 200000, CEILING) == 900000


def test_balance_opens_up_while_the_phone_is_draining():
    assert balanced_limit(1000000, 70, 68, -200000, CEILING) == 1100000


def test_balance_holds_still_inside_the_deadband():
    assert balanced_limit(1000000, 70, 68, 10000, CEILING) == 1000000


def test_balance_never_exceeds_the_ceiling():
    assert balanced_limit(CEILING, 70, 68, -200000, CEILING) == CEILING
