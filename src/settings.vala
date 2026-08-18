namespace Chargectl {

    public class Settings : Object {
        public string profile { get; set; default = "maintain"; }
        public int low { get; set; default = 75; }
        public int high { get; set; default = 80; }
        public int limit { get; set; default = 1500000; }
        public int case_limit { get; set; default = 2300000; }
        public bool inhibit_phone { get; set; default = false; }
        public bool inhibit_case { get; set; default = false; }
        public int interval { get; set; default = 30; }

        public static string config_path () {
            string? path = Environment.get_variable ("CHARGECTL_CONFIG");
            return path ?? "/etc/chargectl.json";
        }

        public static string state_path () {
            string? path = Environment.get_variable ("CHARGECTL_STATE");
            return path ?? "/var/lib/chargectl/state.json";
        }

        public static Settings load () {
            var values = new Settings ();
            values.merge (config_path ());
            values.merge (state_path ());
            return values;
        }

        private void merge (string path) {
            var parser = new Json.Parser ();
            try {
                parser.load_from_file (path);
            } catch (Error error) {
                return;
            }

            Json.Node? root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                return;
            }

            var object = root.get_object ();
            if (object.has_member ("profile")) {
                profile = object.get_string_member ("profile");
            }
            if (object.has_member ("low")) {
                low = (int) object.get_int_member ("low");
            }
            if (object.has_member ("high")) {
                high = (int) object.get_int_member ("high");
            }
            if (object.has_member ("limit")) {
                limit = (int) object.get_int_member ("limit");
            }
            if (object.has_member ("case_limit")) {
                case_limit = (int) object.get_int_member ("case_limit");
            }
            if (object.has_member ("inhibit_phone")) {
                inhibit_phone = object.get_boolean_member ("inhibit_phone");
            }
            if (object.has_member ("inhibit_case")) {
                inhibit_case = object.get_boolean_member ("inhibit_case");
            }
            if (object.has_member ("interval")) {
                interval = (int) object.get_int_member ("interval");
            }
        }

        public bool equals (Settings other) {
            return profile == other.profile
                && low == other.low
                && high == other.high
                && limit == other.limit
                && case_limit == other.case_limit
                && inhibit_phone == other.inhibit_phone
                && inhibit_case == other.inhibit_case
                && interval == other.interval;
        }

        // Replaced rather than edited in place, so a member of the group can
        // switch profile without holding the file open for writing.
        public void save () throws Error {
            var builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("profile");
            builder.add_string_value (profile);
            builder.set_member_name ("low");
            builder.add_int_value (low);
            builder.set_member_name ("high");
            builder.add_int_value (high);
            builder.set_member_name ("limit");
            builder.add_int_value (limit);
            builder.set_member_name ("case_limit");
            builder.add_int_value (case_limit);
            builder.set_member_name ("inhibit_phone");
            builder.add_boolean_value (inhibit_phone);
            builder.set_member_name ("inhibit_case");
            builder.add_boolean_value (inhibit_case);
            builder.set_member_name ("interval");
            builder.add_int_value (interval);
            builder.end_object ();

            var generator = new Json.Generator ();
            generator.set_root (builder.get_root ());
            generator.pretty = true;
            generator.indent = 2;

            string state = state_path ();
            DirUtils.create_with_parents (Path.get_dirname (state), 0775);

            string scratch = scratch_path (state);
            FileUtils.set_contents (scratch, generator.to_data (null) + "\n");
            FileUtils.chmod (scratch, 0664);
            if (FileUtils.rename (scratch, state) != 0) {
                throw new FileError.FAILED (@"could not replace $state");
            }
        }

        private static string scratch_path (string state) {
            string name = Path.get_basename (state);
            int dot = name.last_index_of_char ('.');
            if (dot > 0) {
                name = name.substring (0, dot);
            }
            return Path.build_filename (Path.get_dirname (state), name + ".new");
        }
    }
}
