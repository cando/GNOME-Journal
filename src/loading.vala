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
using Cairo;

private class Journal.LoadingActor: GLib.Object {
    private Clutter.Stage stage;
    private GtkClutter.Actor gtk_actor_label;
    private Label label;

    public LoadingActor (Clutter.Stage stage) {
        this.stage = stage;

        var event_box = new EventBox ();
        label = new Label(_("Loading..."));
        event_box.add (label);
        gtk_actor_label = new GtkClutter.Actor.with_contents (event_box);
        event_box.get_style_context ().add_class ("loading");
        
        gtk_actor_label.add_constraint (new Clutter.BindConstraint (stage, Clutter.BindCoordinate.SIZE, 0));
        stage.add_actor (gtk_actor_label);

        event_box.show_all();
    }
    
    public void start () {
        gtk_actor_label.opacity = 255;
        gtk_actor_label.show ();
    }
    
    public void stop () {
        var animation = gtk_actor_label.animate (
                       Clutter.AnimationMode.LINEAR,
                       500,
                       "opacity", 0);
        animation.completed.connect (() => {
            gtk_actor_label.hide ();
        });
    }
}

public class Journal.OSDLabel: Object{
    public GtkClutter.Actor actor;
    
    private Clutter.Stage stage;
    private Button button;

    public OSDLabel (Clutter.Stage stage) {
        this.stage = stage;
        
        button = new Button ();
        button.sensitive = false;

        actor = new GtkClutter.Actor.with_contents (button);
        actor.get_widget ().get_style_context ().add_class ("osd");
        
        actor.add_constraint (new Clutter.AlignConstraint (stage, Clutter.AlignAxis.X_AXIS, 0.5f));
        actor.add_constraint (new Clutter.AlignConstraint (stage, Clutter.AlignAxis.Y_AXIS, 0.8f));
        button.show();
        
        actor.hide ();
    }
    
    public void set_message_and_show (string message) {
        button.label = message;
        actor.show ();
        actor.animate (Clutter.AnimationMode.EASE_OUT_CUBIC,
                          500,
                          "opacity", 255);
    }
    
    public void hide () {
        var animation = actor.animate (Clutter.AnimationMode.EASE_OUT_CUBIC,
                          500,
                          "opacity", 0);
        animation.completed.connect (()=> {actor.hide ();});
    }
}
