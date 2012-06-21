/*
 * Copyright (c) 2012 Stefano Candori <scandori@gnome.org>
 *
 * GNOME Journal is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by the
 * Free Software Foundation; either version 2 of the License, or (at your
 * option) any later version.
 *
 * GNOME Journal is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 * or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with Gnome Documents; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 *
 * Author: Stefano Candori <scandori@gnome.org>
 *
 */
 
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
    GLib.Environment.set_application_name (_("Journal"));

//    parse_args (ref args);

    var res = GtkClutter.init (ref args);
    if (res != Clutter.InitError.SUCCESS) 
        error ("Can't init clutter-gtk");
        
    Gst.init (ref args);

    Gtk.Window.set_default_icon_name ("Journal");
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

    new Journal.Utils ();
    var app = new Journal.App ();
    return app.run ();
}

