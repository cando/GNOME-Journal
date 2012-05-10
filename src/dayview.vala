// This file is part of GNOME Activity Journal.
using Gtk;

private class Journal.SingleDayView: Box {
    private App app;

    private Gd.MainView view;
    private ActivityModel model;
    
    private ScrolledWindow scrolled_window;
    //TODO Custom widget?
    //TODO Header like Hylke's mockup! CSS?

    public DateTime day {
        get; private set;
    }
    
    public SingleDayView (App app, DateTime day) {
        Object (orientation: Orientation.VERTICAL, spacing: 0);

        this.app = app;
        this.day = day;

        view = new Gd.MainView (Gd.MainViewType.LIST);
        model = new ActivityModel ();

        scrolled_window = new ScrolledWindow (null, null);
        scrolled_window.set_policy (PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
        scrolled_window.add_with_viewport(view);

        var box = new Button.with_label(get_day_title ());
        box.sensitive = false;
        box.get_style_context ().add_class ("dayview");
        box.get_child ().name = "dayview-label";

        this.pack_start (box, false, false, 0);
        this.pack_start (scrolled_window, true, true, 0);
    }
    
    public void load_events (Gee.ArrayList<Zeitgeist.Event>? events) {
        //TODO add nice message: "Your activities shows up here"
        // Hint:Use a Notebook??
        if(events == null)
            return;

        foreach (Zeitgeist.Event e in events) {
            var activity = new GenericActivity (e);
            model.add_activity (activity);
        }
        view.set_model (model.get_model ());
    }

    public string get_day_string () {
        return day.format ("%Y-%m-%d");
    }
    
    public void set_selection_mode (bool mode) {
        this.view.set_selection_mode (mode);
    }
    
    private string get_day_title () {
        //TODO Today and Yesterday strings
        return day.format (_("%A, %x"));
    }
}

private class Journal.DayView: Box{
    private App app;
    private SingleDayView[] day_views;
    
    private int num_days;
    
    public DayView (App app, int num_days) {
        Object (orientation: Orientation.HORIZONTAL, spacing: 0);

        this.app = app;
        this.day_views = new SingleDayView[num_days];
        this.num_days = num_days;

        setup_ui ();
        
        app.backend.events_loaded.connect (() => {
            load_events ();
        });
    }
    
    private void setup_ui (){
        DateTime day = new DateTime.now_local ();
        //Events for Today
        day_views[0] = new SingleDayView (app, day);
        //Events for previous days
        for (int i = 1; i < num_days; i++) {
            day = day.add_days (-1);
            day_views[i] = new SingleDayView (app, day);
        }

        for (int i = 0; i < num_days; i++)
            this.pack_end (day_views[i], true, true, 2);
    }
    
    public void load_events () {
        for (int i = 0; i < num_days; i++) {
            var key = day_views[i].get_day_string ();
            day_views[i].load_events (app.backend.get_events_for_day (key));
        }
    }
    
    public void set_selection_mode (bool mode) {
        for (int i = 0; i < num_days; i++) {
            day_views[i].set_selection_mode (mode);
        }
    }
}


// VERY VERY OLD
//private class Journal.TestActor: GLib.Object {
//    public Clutter.Actor actor { get { return gtk_actor; } }

//    private App app;
//    private GtkClutter.Actor gtk_actor;
//    private TreeView view;

//    public TestActor (App app) {
//        this.app = app;

//        view = new TreeView ();
//        var scroll = new ScrolledWindow(null, null);
//        scroll.set_policy (PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
//        scroll.set_min_content_height (300);
//        scroll.set_min_content_width (300);
//        
//        gtk_actor = new GtkClutter.Actor ();
//        Gtk.Container bin = (Gtk.Container) gtk_actor.get_widget ();
//        bin.add(scroll);
//        scroll.add_with_viewport(view);

//        bin.show_all ();
//        actor.reactive = true;
//    }
//    
//    public void setup_treeview (Gee.ArrayList<Zeitgeist.Event> events) {

//        var listmodel = new ListStore (1, typeof (string));
//        view.set_model (listmodel);

//        view.insert_column_with_attributes (-1, "Uri", new CellRendererText (), "text", 0);

//        TreeIter iter;
//        foreach(Zeitgeist.Event e in events) {
//            listmodel.append (out iter);
//            listmodel.set (iter, 0, e.get_subject (0).get_uri());
//        }

//    }

//    public void move_in () {
//        actor.animate (Clutter.AnimationMode.LINEAR, app.duration * 5,
//                       "x", 100.0);
//    }

//    public void move_out () {
//        var anim = actor.animate (Clutter.AnimationMode.LINEAR, app.duration * 5,
//                                  "x", 10.0);
//    }
//}
