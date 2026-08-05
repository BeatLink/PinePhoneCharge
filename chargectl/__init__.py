"""Charge control for the PinePhone and its keyboard case."""

import argparse
import json
import os
import sys
import time
from pathlib import Path

SUPPLY = Path("/sys/class/power_supply")
PHONE = SUPPLY / "axp20x-battery"
PHONE_INPUT = SUPPLY / "axp20x-usb"
CASE = SUPPLY / "ip5xxx-battery"
CASE_BOOST = SUPPLY / "ip5xxx-boost"

STATE = Path(os.environ.get("CHARGECTL_STATE", "/var/lib/chargectl/state.json"))
CONFIG = Path(os.environ.get("CHARGECTL_CONFIG", "/etc/chargectl.json"))

DEFAULTS = {
    "profile": "maintain",
    "low": 75,
    "high": 80,
    "limit": 1500000,
    "interval": 30,
}

PROFILES = {
    "maintain": "hold the phone in the band, charging it before the case",
    "full": "charge the phone to 100%, still before the case",
    "case-first": "hold the phone in the band, but let the case fill first",
    "balance": "let the case carry the load, moving charge only when the phone runs low",
    "passive": "manage nothing, leave both chargers on auto",
}

BALANCE_FLOOR = 30
BALANCE_SKEW = 5
BALANCE_DEADBAND = 50000
BALANCE_STEP = 100000
BALANCE_MINIMUM = 200000


def read(path):
    try:
        return path.read_text().strip()
    except OSError:
        return None


def read_int(path):
    try:
        return int(read(path))
    except (TypeError, ValueError):
        return None


def write(path, value):
    try:
        path.write_text(str(value))
        return True
    except OSError:
        return False


def log(message):
    print("chargectl: " + message, flush=True)


def settings():
    merged = dict(DEFAULTS)
    for source in (CONFIG, STATE):
        try:
            merged.update(json.loads(source.read_text()))
        except (OSError, ValueError):
            pass
    return merged


def save(values):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    scratch = STATE.with_suffix(".new")
    scratch.write_text(json.dumps(values, indent=2) + "\n")
    os.chmod(scratch, 0o664)
    os.replace(scratch, STATE)


def selected_behaviour(path):
    text = read(path)
    if text is None:
        return None
    for field in text.split():
        if field.startswith("[") and field.endswith("]"):
            return field[1:-1]
    return None


def set_behaviour(path, wanted, subject):
    if wanted is None or not path.exists():
        return
    current = selected_behaviour(path)
    if current is None or current == wanted:
        return
    log(subject + " charging: " + current + " -> " + wanted)
    write(path, wanted)


def wanted_behaviours(profile, capacity, low, high):
    """Return the charge_behaviour wanted for (phone, case).

    None means leave whatever is already selected, which is what keeps the
    hold band from flapping between its two edges.
    """
    if profile in ("passive", "balance"):
        return "auto", "auto"

    if profile == "full":
        return "auto", "inhibit-charge" if capacity < 100 else "auto"

    if capacity >= high:
        phone = "inhibit-charge"
    elif capacity < low:
        phone = "auto"
    else:
        phone = None

    if profile == "case-first":
        return phone, "auto"

    return phone, "inhibit-charge" if capacity < high else "auto"


def balanced_limit(limit, phone_capacity, case_capacity, phone_current, ceiling):
    """Track the input limit so each pack carries its share of the load.

    Moving charge from the case into the phone costs the boost conversion
    twice over, so it is only worth doing when the phone is the one running
    out. Otherwise the limit is nudged until the phone neither charges nor
    drains and the case carries the system.
    """
    if phone_capacity < BALANCE_FLOOR:
        return ceiling
    if case_capacity is not None and phone_capacity + BALANCE_SKEW < case_capacity:
        return ceiling
    if phone_current is None:
        return limit
    if phone_current > BALANCE_DEADBAND:
        return max(BALANCE_MINIMUM, limit - BALANCE_STEP)
    if phone_current < -BALANCE_DEADBAND:
        return min(ceiling, limit + BALANCE_STEP)
    return limit


def case_attached():
    return read(CASE_BOOST / "online") == "1"


def apply_limit(wanted):
    limit = PHONE_INPUT / "input_current_limit"
    if read_int(limit) == wanted:
        return
    log("input limit " + str(read_int(limit)) + " -> " + str(wanted))
    write(limit, wanted)


def apply(values, limit):
    capacity = read_int(PHONE / "capacity")
    if capacity is None:
        return limit

    if case_attached():
        if values["profile"] == "balance":
            limit = balanced_limit(limit, capacity, read_int(CASE / "capacity"),
                                   read_int(PHONE / "current_now"), values["limit"])
        else:
            limit = values["limit"]
        apply_limit(limit)

    phone, case = wanted_behaviours(values["profile"], capacity,
                                    values["low"], values["high"])
    where = "phone at " + str(capacity) + "%,"
    set_behaviour(PHONE / "charge_behaviour", phone, where)
    set_behaviour(CASE / "charge_behaviour", case, where + " case")
    return limit


def daemon():
    active = None
    limit = settings()["limit"]
    while True:
        values = settings()
        if values != active:
            log("profile " + values["profile"] + ", band "
                + str(values["low"]) + "-" + str(values["high"]) + "%")
            active = values
            limit = values["limit"]
        limit = apply(values, limit)
        time.sleep(values["interval"])


def amps(path):
    value = read_int(path / "current_now")
    return "     -" if value is None else "%+6.2f" % (value / 1000000.0)


def volts(path):
    value = read_int(path / "voltage_now")
    return "    -" if value is None else "%5.2f" % (value / 1000000.0)


def pack_row(label, path):
    if not path.exists():
        return "%-10s %8s" % (label, "absent")
    return "%-10s %7s%% %s V %s A  %-12s %s" % (
        label,
        read(path / "capacity") or "-",
        volts(path),
        amps(path),
        read(path / "status") or "-",
        selected_behaviour(path / "charge_behaviour") or "-",
    )


def status():
    values = settings()
    limit = read_int(PHONE_INPUT / "input_current_limit") or 0

    print("profile    %s  (band %d-%d%%)"
          % (values["profile"], values["low"], values["high"]))
    print("           %s" % PROFILES.get(values["profile"], ""))
    print("input      %.2f A limit, case %s"
          % (limit / 1000000.0, "attached" if case_attached() else "detached"))
    print()
    print("%-10s %8s %7s %7s  %-12s %s"
          % ("pack", "capacity", "voltage", "current", "state", "charger"))
    print(pack_row("phone", PHONE))
    print(pack_row("keyboard", CASE))


def set_profile(name):
    if name not in PROFILES:
        sys.exit("unknown profile " + name
                 + ", pick one of: " + ", ".join(sorted(PROFILES)))
    values = settings()
    values["profile"] = name
    save(values)
    print("profile " + name + ": " + PROFILES[name])


def set_band(low, high):
    if not 0 <= low < high <= 100:
        sys.exit("band must satisfy 0 <= low < high <= 100")
    values = settings()
    values["low"] = low
    values["high"] = high
    save(values)
    print("band %d-%d%%" % (low, high))


def main():
    parser = argparse.ArgumentParser(
        description="Control how the PinePhone and its keyboard case charge")
    sub = parser.add_subparsers(dest="command")
    sub.add_parser("status", help="show both packs and the active profile")
    sub.add_parser("daemon", help="run the control loop")
    profile = sub.add_parser("profile", help="show or set the profile")
    profile.add_argument("name", nargs="?")
    band = sub.add_parser("band", help="set the hold band")
    band.add_argument("low", type=int)
    band.add_argument("high", type=int)

    args = parser.parse_args()

    if args.command == "daemon":
        daemon()
    elif args.command == "profile":
        if args.name:
            set_profile(args.name)
        else:
            print(settings()["profile"])
            for name in sorted(PROFILES):
                print("  %-11s %s" % (name, PROFILES[name]))
    elif args.command == "band":
        set_band(args.low, args.high)
    else:
        status()
