// This file is part of GNOME Activity Journal.
using Gtk;

private class Journal.SingleReminderView: Box {
    private App app;

    private Gd.MainView view;
    private ActivityModel model;
    
    private ScrolledWindow scrolled_window;

    public SingleReminderView (App app) {
        Object (orientation: Orientation.VERTICAL, spacing: 0);

        this.app = app;

        view = new Gd.MainView (Gd.MainViewType.ICON);
        model = new ActivityModel ();
        view.set_model (model.get_model ());

        scrolled_window = new ScrolledWindow (null, null);
        scrolled_window.set_policy (PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
        scrolled_window.add_with_viewport(view);

        var box = new Button.with_label("Test");
        box.sensitive = false;
        box.name = "box-label";
        box.get_child ().get_style_context ().add_class ("day-label");

        this.pack_start (box, false, false, 0);
        this.pack_start (scrolled_window, true, true, 0);
    }
    
//    public void load_events (Gee.ArrayList<Zeitgeist.Event>? events) {
//        //TODO add nice message: "Your activities shows up here"
//        // Hint:Use a Notebook??
//        if(events == null)
//            return;

//        foreach (Zeitgeist.Event e in events) {
//            var activity = new GenericActivity (e);
//            model.add_activity (activity);
//        }
//    }
}

private class Journal.ReminderView: Box{
    private App app;
    private SingleReminderView[] reminder_views;
    
    private int num_days;
    
    public ReminderView (App app) {
        Object (orientation: Orientation.VERTICAL, spacing: 0);

        this.app = app;
        this.reminder_views = new SingleReminderView[num_days];
        this.num_days = 3;

        setup_ui ();
        
        app.backend.events_loaded.connect (() => {
            //load_events ();
        });
    }
    
    private void setup_ui (){
        for (int i = 0; i < num_days; i++) {
            reminder_views[i] = new SingleReminderView (app);
        }

        for (int i = 0; i < num_days; i++)
            this.pack_start (reminder_views[i], true, true, 2);
    }
    
//    public void load_events () {
//        for (int i = 0; i < num_days; i++) {
//            var key = day_views[i].get_day_string ();
//            reminder_views[i].load_events (app.backend.get_events_for_day (key));
//        }
//    }
}

