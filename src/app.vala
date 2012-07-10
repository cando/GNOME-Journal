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
 * with Gnome Journal; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 *
 * Author: Stefano Candori <scandori@gnome.org>
 *
 */
using Gtk;

public class Journal.App: GLib.Object {
    public Gtk.ApplicationWindow window;
    public bool fullscreen {
        get { return Gdk.WindowState.FULLSCREEN in window.get_window ().get_state (); }
        set {
            if (value)
                window.fullscreen ();
            else
                window.unfullscreen ();
        }
    }
    private bool maximized { get { return Gdk.WindowState.MAXIMIZED in window.get_window ().get_state (); } }
    public Gtk.Notebook notebook;
    public Gtk.Box main_box; 
    public GLib.SimpleAction action_fullscreen;
    public uint duration;

    private Gtk.Application application;
    private ActivityModel model;
    private VTL vtl;
    private Gd.MainToolbar main_toolbar;
    private ActivityInfoPage activity_page;

    public App () {
        application = new Gtk.Application ("org.gnome.journal", 0);
        model = new ActivityModel ();

        var action = new GLib.SimpleAction ("quit", null);
        action.activate.connect (() => { quit (); });
        application.add_action (action);

        action_fullscreen = new GLib.SimpleAction ("display.fullscreen", null);
        action_fullscreen.activate.connect (() => { fullscreen = true; });
        application.add_action (action_fullscreen);

        action = new GLib.SimpleAction ("about", null);
        action.activate.connect (() => {
            string[] authors = {
                "Stefano Candori <scandori@gnome.org>"
            };
            string[] artists = {
                "Stefano Candori <scandori@gnome.org>"
            };

            Gtk.show_about_dialog (window,
                                   "artists", artists,
                                   "authors", authors,
                                   "translator-credits", _("translator-credits"),
                                   "comments", _("A simple GNOME 3 journal application "),
                                   "copyright", "Copyright 2012 Stefano Candori",
                                   "license-type", Gtk.License.LGPL_2_1,
                                   "logo-icon-name", "gnome-journal",
                                   "version", Config.PACKAGE_VERSION,
                                   "website", "https://live.gnome.org/SummerOfCode2012/Projects/Stefano_Candori_GNOME_Journal",
                                   "wrap-license", true);
        });
        application.add_action (action);

        application.startup.connect_after ((app) => {
            var menu = new GLib.Menu ();
            menu.append (_("New"), "app.new");

            var display_section = new GLib.Menu ();
            display_section.append (_("Fullscreen"), "app.display.fullscreen");
            menu.append_section (null, display_section);

            menu.append (_("About Journal"), "app.about");
            menu.append (_("Quit"), "app.quit");

            application.set_app_menu (menu);

            duration = Utils.settings.get_int ("animation-duration");
            setup_ui ();
            });

        application.activate.connect_after ((app) => {
            window.present ();
        });
    }

    public int run () {
        return application.run ();
    }

    private void save_window_geometry () {
        int width, height, x, y;

        if (maximized)
            return;

        window.get_size (out width, out height);
        Utils.settings.set_value ("window-size", new int[] { width, height });

        window.get_position (out x, out y);
        Utils.settings.set_value ("window-position", new int[] { x, y });
    }

    private void setup_ui () {
        window = new Gtk.ApplicationWindow (application);
        window.show_menubar = false;
        window.hide_titlebar_when_maximized = true;
        window.set_default_size (840, 680);

        // restore window geometry/position
        var size = Utils.settings.get_value ("window-size");
        if (size.n_children () == 2) {
            var width = (int) size.get_child_value (0);
            var height = (int) size.get_child_value (1);

            window.set_default_size (width, height);
        }

        if (Utils.settings.get_boolean ("window-maximized"))
            window.maximize ();

        var position = Utils.settings.get_value ("window-position");
        if (position.n_children () == 2) {
            var x = (int) position.get_child_value (0);
            var y = (int) position.get_child_value (1);

            window.move (x, y);
        }

        window.window_state_event.connect (() => {
            if (fullscreen)
                return false;

            Utils.settings.set_boolean ("window-maximized", maximized);
            return false;
        });

        main_box = new Box (Orientation.VERTICAL, 0);
        window.add (main_box);

        //TODO move in another wrapper class
        main_toolbar = new Gd.MainToolbar();
        main_toolbar.icon_size = IconSize.MENU;
        main_toolbar.set_mode (Gd.MainToolbarMode.OVERVIEW);
        main_toolbar.set_labels (_(""), null);
        main_toolbar.go_back_request.connect (() => {
            notebook.prev_page ();
            main_toolbar.set_back_visible (false);
            main_toolbar.set_labels (_(""), null);
        });
        main_toolbar.selection_mode_request.connect ((mode) => {
                if (mode) {
                    this.main_toolbar.set_mode (Gd.MainToolbarMode.SELECTION);
                    main_toolbar.set_labels (null, _("(Click on items to select them)"));
                }
                else {
                    main_toolbar.set_mode (Gd.MainToolbarMode.OVERVIEW);
                    main_toolbar.set_labels (_(""), null);
                }
        });
        notebook = new Gtk.Notebook ();
        notebook.show_border = false;
        notebook.show_tabs = false;
        
        main_box.pack_start (main_toolbar, false, false, 0);
        main_box.pack_start (notebook, true, true, 0);

        window.delete_event.connect (() => { return quit (); });
        window.key_press_event.connect (on_key_pressed);
        
        //VTL
        vtl = new VTL (this, model);
        notebook.append_page (vtl, null);
        
        //ACTIVITY PAGE
        activity_page = new ActivityInfoPage ();
        notebook.append_page (activity_page, null);
        
        model.launch_composite_activity.connect ((activity) => {
            activity_page.set_activity (activity);
            notebook.next_page ();
            main_toolbar.set_back_visible (true);
            main_toolbar.set_labels (activity.title, 
                                     activity.uris.length.to_string ()
                                     + _(" items"));
        });

        window.show_all();
    }

    public bool quit () {
        save_window_geometry ();
        window.destroy ();

        return false;
    }

    private bool on_key_pressed (Widget widget, Gdk.EventKey event) {
        if (event.keyval == Utils.F11_KEY) { 
            fullscreen = !fullscreen;
            return true;
        }
        return false;
    }
}

