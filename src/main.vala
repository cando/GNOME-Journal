// This file is part of GNOME Activity Journal
//private static bool version;

//private const OptionEntry[] options = {
//    { "version", 0, 0, OptionArg.NONE, ref version, N_("Display version number"), null },
//    { null }
//};

//private static void parse_args (ref unowned string[] args) {
//    var parameter_string = _("- A simple journal application");
//    var opt_context = new OptionContext (parameter_string);
//    opt_context.set_help_enabled (true);
//    opt_context.set_ignore_unknown_options (true);
//    opt_context.add_main_entries (options, null);
//    opt_context.add_group (Gtk.get_option_group (true));
//    opt_context.add_group (Clutter.get_option_group_without_init ());
//    opt_context.add_group (GtkClutter.get_option_group ());

//    try {
//        opt_context.parse (ref args);
//    } catch (OptionError.BAD_VALUE err) {
//        GLib.stdout.printf (opt_context.get_help (true, null));
//        exit (1);
//    } catch (OptionError error) {
//        warning (error.message);
//    }

//    if (version) {
//        GLib.stdout.printf ("0.1\n");
//        exit (0);
//    }
//}

public int main (string[] args) {
    Intl.bindtextdomain (Config.GETTEXT_PACKAGE, Config.LOCALEDIR);
    Intl.bind_textdomain_codeset (Config.GETTEXT_PACKAGE, "UTF-8");
    Intl.textdomain (Config.GETTEXT_PACKAGE);
    GLib.Environment.set_application_name (_("Activity Journal"));

//    parse_args (ref args);

    GtkClutter.init (ref args);

    Gtk.Window.set_default_icon_name ("Activity Journal");
    var provider = new Gtk.CssProvider ();
    try {
        var sheet = Journal.Utils.get_style ("gtk-style.css");
        provider.load_from_path (sheet);
        var screen = Gdk.Screen.get_default ();
        var display = Gdk.Display.get_default ();
        if(display == null)
            warning ("Nu");
        Gtk.StyleContext.add_provider_for_screen (screen,
                                                  provider,
                                                  Gtk.STYLE_PROVIDER_PRIORITY_USER);
    } catch (GLib.Error error) {
        warning (error.message);
    }

    var utils = new Journal.Utils ();
    var app = new Journal.App ();
    return app.run ();
}

