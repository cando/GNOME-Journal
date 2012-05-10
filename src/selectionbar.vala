// This file is part of GNOME Activity Journal.
using Clutter;
using Gtk;

private class Journal.Selectionbar: GLib.Object {
    public Clutter.Actor actor { get { return gtk_actor; } }
    public static const float spacing = 60.0f;

    private App app;
    private GtkClutter.Actor gtk_actor;
    private Gtk.Toolbar toolbar;
    private Gtk.ToggleToolButton favorite_btn;
    private Gtk.ToggleToolButton remove_btn;
    
    private bool _visible;

    public Selectionbar (App app) {
        this.app = app;
        
        _visible = false;

        toolbar = new Gtk.Toolbar ();
        toolbar.show_arrow = false;
        toolbar.icon_size = Gtk.IconSize.LARGE_TOOLBAR;

        gtk_actor = new GtkClutter.Actor.with_contents (toolbar);
        gtk_actor.opacity = 0;
        gtk_actor.get_widget ().get_style_context ().add_class ("osd");

        favorite_btn = new Gtk.ToggleToolButton ();
        toolbar.insert (favorite_btn, 0);
        favorite_btn.icon_name = "emblem-favorite-symbolic";

        var separator = new Gtk.SeparatorToolItem();
        toolbar.insert(separator, 1);

        remove_btn = new Gtk.ToggleToolButton ();
        toolbar.insert (remove_btn, 2);
        remove_btn.icon_name = "edit-delete-symbolic";
        toolbar.show_all ();

        actor.reactive = true;
        actor.hide ();

        app.notify["selection-mode"].connect (() => {
            toggle_visible ();
        });

        app.stage.add_actor (actor);
    }

    public void toggle_visible () {
        visible = !visible;
    }

    private bool visible {
        get { return _visible;}
        set {
            _visible = value;
            if (value)
                show ();
            else
                hide ();
        }
    }
    private void show () {
        actor.show ();
        actor.queue_redraw ();
        actor.animate (Clutter.AnimationMode.LINEAR, app.duration,
                       "opacity", 255);
    }

    private void hide () {
        var anim = actor.animate (Clutter.AnimationMode.LINEAR, app.duration,
                                  "opacity", 0);
        anim.completed.connect (() => {
            actor.hide ();
        });
    }
}
