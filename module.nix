# NixOS module for chargectl.
#
# The daemon needs root to write the power supply attributes, but the profile
# is a decision made while using the phone, so the state directory is group
# writable and chargectl replaces the file rather than editing it in place.
# Members of the group can switch profile without sudo; nothing else in the
# directory is privileged.

self:
{
    config,
    lib,
    pkgs,
    ...
}:
let
    cfg = config.services.chargectl;
in
{
    options.services.chargectl = {
        enable = lib.mkEnableOption "charge control for the PinePhone and its keyboard case";

        package = lib.mkOption {
            type = lib.types.package;
            default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
            defaultText = lib.literalExpression "chargectl.packages.\${system}.default";
            description = "The chargectl package to install and run.";
        };

        profile = lib.mkOption {
            type = lib.types.enum [
                "maintain"
                "full"
                "case-first"
                "balance"
                "passive"
            ];
            default = "maintain";
            description = ''
                Profile applied when there is no saved state yet.

                `chargectl profile <name>` overrides this at runtime and the
                choice persists, so this is the starting point rather than the
                last word.
            '';
        };

        band = {
            low = lib.mkOption {
                type = lib.types.ints.between 0 100;
                default = 75;
                description = "Charging resumes below this percentage.";
            };

            high = lib.mkOption {
                type = lib.types.ints.between 0 100;
                default = 80;
                description = "Charging stops at this percentage.";
            };
        };

        inputCurrentLimit = lib.mkOption {
            type = lib.types.int;
            default = 1500000;
            description = ''
                Microamps to draw from the keyboard case.

                The phone's own default is 500000, which is less than it uses
                under load, so the battery falls even while attached. megi's
                keyboard FAQ gives 1500000 as the value to use and names
                5V/2.4A as the typical maximum the case can supply.
            '';
        };

        interval = lib.mkOption {
            type = lib.types.int;
            default = 30;
            description = "Seconds between control decisions.";
        };

        stateDirectory = lib.mkOption {
            type = lib.types.str;
            default = "/var/lib/chargectl";
            description = "Where the runtime profile and band are kept.";
        };

        group = lib.mkOption {
            type = lib.types.str;
            default = "users";
            description = "Group allowed to change the profile without root.";
        };
    };

    config = lib.mkIf cfg.enable {
        assertions = [
            {
                assertion = cfg.band.low < cfg.band.high;
                message = "services.chargectl.band.low must be below band.high";
            }
        ];

        environment.systemPackages = [ cfg.package ];

        environment.etc."chargectl.json".source = (pkgs.formats.json { }).generate "chargectl.json" {
            inherit (cfg) profile interval;
            low = cfg.band.low;
            high = cfg.band.high;
            limit = cfg.inputCurrentLimit;
        };

        systemd.tmpfiles.rules = [
            "d ${cfg.stateDirectory} 0775 root ${cfg.group} -"
        ];

        systemd.services.chargectl = {
            description = "Charge control for the PinePhone and its keyboard case";
            wantedBy = [ "multi-user.target" ];
            after = [ "multi-user.target" ];

            environment.CHARGECTL_STATE = "${cfg.stateDirectory}/state.json";

            serviceConfig = {
                Type = "simple";
                Restart = "always";
                RestartSec = 10;
                ExecStart = "${cfg.package}/bin/chargectl daemon";
            };

            postStop = ''
                echo auto > /sys/class/power_supply/axp20x-battery/charge_behaviour || true
                if [ -e /sys/class/power_supply/ip5xxx-battery/charge_behaviour ]; then
                    echo auto > /sys/class/power_supply/ip5xxx-battery/charge_behaviour || true
                fi
            '';
        };

        # A user service rather than part of the root daemon: the notification bus lives in the session, and reading the packs needs no privilege.
        systemd.user.services.chargectl-notify = {
            description = "Warn when the phone drains while it is charging";
            wantedBy = [ "graphical-session.target" ];
            partOf = [ "graphical-session.target" ];
            after = [ "graphical-session.target" ];

            environment.CHARGECTL_STATE = "${cfg.stateDirectory}/state.json";

            serviceConfig = {
                Type = "simple";
                Restart = "always";
                RestartSec = 10;
                ExecStart = "${cfg.package}/bin/chargectl watch";
            };
        };
    };
}
