using Gtk;
using Cairo;

private class Journal.LoadingActor: GLib.Object {
    private App app;
    private GtkClutter.Actor gtk_actor_box;
    private GtkClutter.Actor gtk_actor_throbber;
    private Box box;
    private Spinner throbber;

    public LoadingActor (App app) {
        this.app = app;
        
        box = new Box(Orientation.VERTICAL, 0);
        throbber = new Spinner ();
        throbber.set_size_request((int)app.stage.height/3, (int)app.stage.height/3);
        
        gtk_actor_box = new GtkClutter.Actor.with_contents (box);
        gtk_actor_box.opacity = 235;
        gtk_actor_throbber = new GtkClutter.Actor.with_contents (throbber);
        gtk_actor_throbber.get_widget ().get_style_context ().add_class ("throbber");
        
        gtk_actor_throbber.add_constraint (new Clutter.AlignConstraint (app.stage, Clutter.AlignAxis.X_AXIS, 0.5f));
        gtk_actor_throbber.add_constraint (new Clutter.AlignConstraint (app.stage, Clutter.AlignAxis.Y_AXIS, 0.5f));
        gtk_actor_box.add_constraint (new Clutter.BindConstraint (app.stage, Clutter.BindCoordinate.SIZE, 0));
        app.stage.add_actor (gtk_actor_box);
        app.stage.add_actor (gtk_actor_throbber);
        
        app.backend.events_loaded.connect ( () => {
            stop ();
        });

        box.show_all ();
        throbber.show_all ();
    }
    
    public void start () {
        throbber.start ();
        gtk_actor_box.show ();
        gtk_actor_throbber.show ();
    }
    
    public void stop () {
        throbber.stop ();
        gtk_actor_box.hide ();
        gtk_actor_throbber.hide ();
    }
}
