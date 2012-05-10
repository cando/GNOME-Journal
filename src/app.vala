// This file is part of GNOME Activity Journal.
using Gtk;

public class Journal.App: GLib.Object {
    public Clutter.Actor actor { get { return stage; } }
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
    public GtkClutter.Embed embed;
    public Clutter.Stage stage;
    public Clutter.Actor box; // the whole app box
    public GLib.SimpleAction action_fullscreen;
    public uint duration;

    private Gtk.Application application;
    private Clutter.BoxLayout box_table;
    private LoadingActor loading_actor;
    private DayView day_view;
    private ClutterRoundBoxView crv;
    private GtkRoundBoxView grv;
    private ReminderView reminder_view;
    private Revealer revealer;
    private Gd.MainToolbar main_toolbar;

    private ZeitgeistBackend _backend;
    
    public ZeitgeistBackend backend {
        get { return _backend; }
    }

    public App () {
        application = new Gtk.Application ("org.gnome.activity-journal", 0);
        
        _backend = new ZeitgeistBackend ();

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
                                   "logo-icon-name", "gnome-activity-journal",
                                   "version", Config.PACKAGE_VERSION,
                                   "website", "http://live.gnome.org/GnomeActivityJournal",
                                   "wrap-license", true);
        });
        application.add_action (action);

        application.startup.connect_after ((app) => {
            var menu = new GLib.Menu ();
            menu.append (_("New"), "app.new");

            var display_section = new GLib.Menu ();
            display_section.append (_("Fullscreen"), "app.display.fullscreen");
            menu.append_section (null, display_section);

            menu.append (_("About Activity Journal"), "app.about");
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
        main_toolbar.selection_mode_request.connect ((mode) => {
                this.day_view.set_selection_mode (mode);
                if (mode) {
                    this.main_toolbar.set_mode (Gd.MainToolbarMode.SELECTION);
                    main_toolbar.set_labels (null, _("(Click on items to select them)"));
                    //revealer.reveal ();
                }
                else {
                    main_toolbar.set_mode (Gd.MainToolbarMode.OVERVIEW);
                    int num_days = 3;
                    string label = _(@"Last $num_days days");
                    main_toolbar.set_labels (_("Timeline"), label);
                    //revealer.unreveal ();
                }
        });
        notebook = new Gtk.Notebook ();
        notebook.show_border = false;
        //notebook.show_tabs = false;
        
        main_box.pack_start (main_toolbar, false, false, 0);
        main_box.pack_start (notebook, true, true, 0);

        //FIXME Make the num of days displayed a preferences??
        int num_days = 3;
        day_view = new DayView (this, num_days);
        
//        revealer = new Revealer ();
//        reminder_view = new ReminderView (this);
//        reminder_view.set_hexpand (false);
//        revealer.add (reminder_view);

        var grid = new Grid ();
        grid.set_orientation (Orientation.HORIZONTAL);
        grid.add (day_view);
        //grid.add (revealer);
        notebook.append_page (grid, null);

        string label = _(@"Last $num_days days");
        main_toolbar.set_labels (_("Timeline"), label);

        embed = new GtkClutter.Embed ();
        notebook.append_page (embed, null);
        stage = embed.get_stage () as Clutter.Stage;
        stage.set_color (Utils.gdk_rgba_to_clutter_color (Utils.get_journal_bg_color ()));

        window.delete_event.connect (() => { return quit (); });
        window.key_press_event.connect (on_key_pressed);

        crv = new ClutterRoundBoxView (this);
        grv = new GtkRoundBoxView (this);
        ScrolledWindow sw = new ScrolledWindow (null, null);
        sw.set_policy (PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
        sw.add_with_viewport (grv);
        notebook.append_page (sw, null);
        
        loading_actor = new LoadingActor(this);
        loading_actor.start ();
        
        
        main_box.show_all ();
        
//        revealer.set_no_show_all (true);
//        revealer.hide ();
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

