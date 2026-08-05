# chargectl

Charge control for the PinePhone and its keyboard case.

The phone limits itself to 500mA from the case, which is less than it draws
under load, so the battery falls even while attached and the charger cheerfully
reports "Charging". The case makes it worse when a charger is plugged into it:
its IP5209 fills its own 6000mAh pack first and passes on very little, so a
phone at 20% can sit there getting emptier.

Both are fixable from userspace, and this is what does it.

```
$ chargectl
profile    maintain  (band 75-80%)
           hold the phone in the band, charging it before the case
input      1.50 A limit, case attached

pack       capacity voltage current  state        charger
phone           23%  3.81 V  +0.54 A  Charging     auto
keyboard        97%  3.88 V  -2.28 A  Discharging  inhibit-charge
```

## What it does

**Draws the case's full current.** Raises the phone's input limit from 500mA to
1.5A whenever the case is supplying power. Measured on a PinePhone 1.2 with the
case on its own pack, the phone went from -151mA to +589mA. The limit has to be
re-applied rather than set once, because the driver resets it to 500mA on plug
events.

1.5A is the value [megi's keyboard FAQ][faq] gives. 2A measures no better on
either the case's pack or a wall supply, because the case is the bottleneck.

**Charges the phone before the case.** The IP5209's charger and its boost
converter are separate register fields, so inhibiting the charger leaves the
output to the phone alone. With a charger on the case, the phone went from
-622mA to +246mA and the case pack sat idle. It is handed back once the phone
reaches the top of its band.

**Holds the phone in a band.** Lithium cells age by voltage and heat, so time
spent near full is what wears them. `charge_behaviour` is the driver's own
control for this, not a register poke.

## Profiles

| profile | what it does |
| --- | --- |
| `maintain` | hold the phone in the band, charging it before the case |
| `full` | charge the phone to 100%, still before the case |
| `case-first` | hold the phone in the band, but let the case fill first |
| `balance` | let the case carry the load, moving charge only when the phone runs low |
| `passive` | manage nothing, leave both chargers on auto |

`balance` follows the reasoning in [pinephone-kbpwrd][kbpwrd]: moving charge
from the case into the phone pays the boost conversion twice, so the efficient
thing is to let the case carry the system and only pull charge across when the
phone is the one running out. It tracks the input limit until the phone neither
charges nor drains.

```sh
chargectl                 # status
chargectl profile         # list profiles, show the active one
chargectl profile full    # charge to 100% before a long day out
chargectl band 40 60      # a tighter band for a phone that mostly sits docked
```

Profile and band persist. The state directory is group writable, so switching
profile does not need root; the daemon does, because it writes to sysfs.

## Install

```nix
{
    inputs.pinephone-charge.url = "github:BeatLink/PinePhoneCharge";

    # in your host configuration
    imports = [ inputs.pinephone-charge.nixosModules.default ];
    services.chargectl = {
        enable = true;
        profile = "maintain";
        band = { low = 75; high = 80; };
    };
}
```

Stopping the service restores both chargers to `auto`, so it cannot leave a
pack unable to charge.

## Hardware

Written against a PinePhone 1.2 with the official keyboard case, on megi's
kernel: `axp20x-battery` and `axp20x-usb` for the phone, `ip5xxx-battery` and
`ip5xxx-boost` for the case. It needs `CONFIG_IP5XXX_POWER` for the case to
appear at all.

**Do not plug a charger into the phone's own USB-C port while the case is
attached.** [Pine64's documentation][pine64] warns this may damage the phone or
the keyboard. Charge through the case's port.

[faq]: https://xnux.eu/pinephone-keyboard/faq.html
[kbpwrd]: https://github.com/estokes/pinephone-kbpwrd
[pine64]: https://pine64.org/documentation/Phone_Accessories/Keyboard/
