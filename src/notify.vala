// Desktop notification for a phone that drains while it is plugged in.
//
// This runs in the user's session rather than in the root daemon: the
// notification bus lives there, and reading the packs needs no privilege.

namespace Chargectl {

    public const string APP_ID = "io.github.beatlink.Chargectl";
    public const string DRAIN_ID = "phone-draining";
    public const string DRAIN_TITLE = "Phone Discharging";
    public const string DRAIN_BODY =
        "Current power draw exceeds charging capabilities, close some applications or reduce system load.";
    public const int64 DRAIN_REPEAT = 60000000;

    // Its own cadence, not the daemon's control interval: sampling slower than DRAIN_SUSTAIN would step over the dips the window exists to catch.
    public const int WATCH_POLL = 5;

    public class Notifier : Object {
        private GLib.Application application;
        private int64 raised = 0;
        private bool registered = false;

        public Notifier () {
            // NON_UNIQUE so a running GUI keeps the bus name; notifications reach the shell either way.
            application = new GLib.Application (APP_ID, ApplicationFlags.NON_UNIQUE);
        }

        private bool connect_bus () {
            if (registered) {
                return true;
            }
            try {
                registered = application.register (null);
            } catch (Error error) {
                log (@"notify: $(error.message)");
                return false;
            }
            return registered;
        }

        // Held to one banner a minute, and re-sent under the same id so a repeat replaces it instead of stacking.
        public void raise () {
            int64 now = get_monotonic_time ();
            if (raised != 0 && now - raised < DRAIN_REPEAT) {
                return;
            }
            if (!connect_bus ()) {
                return;
            }

            var notification = new GLib.Notification (DRAIN_TITLE);
            notification.set_body (DRAIN_BODY);
            notification.set_priority (NotificationPriority.HIGH);
            application.send_notification (DRAIN_ID, notification);
            raised = now;
        }

        public void clear () {
            if (raised == 0) {
                return;
            }
            raised = 0;
            if (connect_bus ()) {
                application.withdraw_notification (DRAIN_ID);
            }
        }
    }

    private void inspect (Notifier notifier, DrainTracker tracker) {
        var values = Settings.load ();
        bool online = read (attribute (PHONE_INPUT, "online")) == "1";
        string? behaviour = selected_behaviour (attribute (PHONE, "charge_behaviour"));
        int? current = read_int (attribute (PHONE, "current_now"));

        bool draining = draining_under_load (values.profile, online, behaviour, current);
        if (tracker.update (draining, get_monotonic_time ())) {
            notifier.raise ();
        } else if (!draining) {
            notifier.clear ();
        }
    }

    public void watch () {
        var notifier = new Notifier ();
        var tracker = new DrainTracker ();

        inspect (notifier, tracker);
        Timeout.add_seconds (WATCH_POLL, () => {
            inspect (notifier, tracker);
            return Source.CONTINUE;
        });
        new MainLoop ().run ();
    }
}
