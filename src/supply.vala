namespace Chargectl {

    public const string PHONE = "/sys/class/power_supply/axp20x-battery";
    public const string PHONE_INPUT = "/sys/class/power_supply/axp20x-usb";
    public const string CASE = "/sys/class/power_supply/ip5xxx-battery";
    public const string CASE_BOOST = "/sys/class/power_supply/ip5xxx-boost";

    public string attribute (string supply, string name) {
        return supply + "/" + name;
    }

    public bool present (string path) {
        return FileUtils.test (path, FileTest.EXISTS);
    }

    public string? read (string path) {
        string contents;
        try {
            FileUtils.get_contents (path, out contents);
        } catch (FileError error) {
            return null;
        }
        return contents.strip ();
    }

    public int? read_int (string path) {
        string? text = read (path);
        if (text == null) {
            return null;
        }
        int value;
        if (!int.try_parse (text, out value)) {
            return null;
        }
        return value;
    }

    // Written through stdio rather than FileUtils.set_contents, which writes a
    // temporary file beside the target and renames it over the top. sysfs has
    // no room for that: the attribute is the only file that can exist there.
    public bool write_value (string path, string value) {
        FileStream? stream = FileStream.open (path, "w");
        if (stream == null) {
            return false;
        }
        stream.puts (value);
        return stream.flush () == 0;
    }

    public void log (string message) {
        stdout.printf ("chargectl: %s\n", message);
        stdout.flush ();
    }

    public string? selected_behaviour (string path) {
        string? text = read (path);
        if (text == null) {
            return null;
        }
        foreach (string field in text.split (" ")) {
            if (field.has_prefix ("[") && field.has_suffix ("]")) {
                return field.slice (1, field.length - 1);
            }
        }
        return null;
    }

    public void set_behaviour (string path, string? wanted, string subject) {
        if (wanted == null || !present (path)) {
            return;
        }
        string? current = selected_behaviour (path);
        if (current == null || current == wanted) {
            return;
        }
        log (@"$subject charging: $current -> $wanted");
        write_value (path, wanted);
    }

    public bool case_attached () {
        return read (attribute (CASE_BOOST, "online")) == "1";
    }
}
