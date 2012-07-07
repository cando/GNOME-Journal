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
 
using Gtk;
using Cairo;

enum Side {
 TOP,
 LEFT,
 RIGHT,
 BOTTOM
}

enum ScrollMode {
    X,
    Y
}

private class Journal.VTL : Box {
    
    private ActivityModel model;
    private App app;
    private Scrollbar scrollbar;
    private TimelineNavigator vnav;
    
    public ScrolledWindow viewport;
    public VBox container;
    private BubbleContainer bubble_c;
    
    private Gee.Map<string, Clutter.Actor> y_positions;
    private Gee.List<string> dates_added;

    //Date to jump when we have loaded new events
    private DateTime? date_to_jump;
    
    private bool on_loading;

    public VTL (App app, ActivityModel model){
        Object (orientation: Orientation.HORIZONTAL, spacing : 0);
        this.model = model;
        this.app = app;
        
        y_positions = new Gee.HashMap <string, Clutter.Actor> ();
        dates_added = new Gee.ArrayList <string> ();
        
        viewport = new ScrolledWindow (null, null);
        viewport.set_policy (PolicyType.NEVER, PolicyType.AUTOMATIC);
        scrollbar = (Scrollbar)viewport.get_vscrollbar ();
        
        container = new VBox (false, 0);
        viewport.add_with_viewport (container);
        
        bubble_c = new BubbleContainer ();
        container.pack_start (bubble_c, true, true, 0);
        
        vnav = new TimelineNavigator (Orientation.VERTICAL);
        vnav.go_to_date.connect ((date) => {this.jump_to_day (date);});

        this.pack_start (new Gtk.Label(""), false, false, 32);
        this.pack_start (viewport, true, true, 0);
        this.pack_start (vnav, false, false, 10);
       
        model.activities_loaded.connect ((dates_loaded)=> {
             load_activities (dates_loaded);
             on_loading = false;
        });
    }
    
    private void load_activities (Gee.ArrayList<string> dates_loaded) {
        foreach (string date in dates_loaded) {
            if (dates_added.contains (date) || date.has_prefix ("*"))
              continue;
            
            dates_added.add (date);
            string text = Utils.datetime_from_string (date).format (_("%A, %x"));
            var d = new Button.with_label (text);
            bubble_c.append_date (d);

            var activity_list = model.activities.get (date);
            foreach (GenericActivity activity in activity_list.composite_activities) 
                 bubble_c.append_bubble (activity);

            bubble_c.show_all ();
        }
    }
    
    private void jump_to_day (DateTime date) {
        float y = 0;
        string date_s = date.format("%Y-%m-%d");
        if (y_positions.has_key (date_s) == true) {
            y = this.y_positions.get (date_s).get_y ();
            if (y == 0 && date.compare (Utils.get_start_of_today ()) != 0)
                //FIXME WTF? why y is 0 for a newly added actor;
                Idle.add (()=>{
                    jump_to_day (date);
                    return false;
                });
            //viewport.scroll_to_point (0.0f, y);
            date_to_jump = null;
        }
        else {
            if (date == date_to_jump) {
                //Break the infinite loop that happens when the user ask for an
                //event period too far and not present in the db.
                date_s = dates_added.get (dates_added.size - 1);
                if (y_positions.has_key (date_s) == true) {
                    y = this.y_positions.get (date_s).get_y ();
                    //viewport.scroll_to_point (0.0f, y);
                    date_to_jump = null;
                }
                return;
            }
            model.load_activities (date);
            date_to_jump = date;
        }
    }
    
    private void on_scrollbar_scroll () {
        float y = (float)(scrollbar.adjustment.value);
        //viewport.scroll_to_point (0.0f, y);
        var limit = (int)scrollbar.adjustment.upper - scrollbar.adjustment.page_size - 500;
        if (!on_loading && y >= limit) {
            //We can't scroll anymmore! Let's load another day!
            //loading.start ();
            model.load_other_days (3);
            on_loading = true;
        }
        
        //We are moving so we should highligth the right TimelineNavigator's label
         //TODO
//        string final_key = "";
//        float final_pos = 0;
//        foreach (Gee.Map.Entry<string, Clutter.Actor> entry in y_positions.entries) {
//            float current_value = entry.value.get_y ();
//            if (current_value <= ((y) + stage.height / 2) && current_value > final_pos) {
//                final_key = entry.key;
//                final_pos = current_value;
//            }
//        }
//        vnav.highlight_date (final_key);
    }
}

private class Journal.BubbleContainer : EventBox {
    private Box right_c;
    private Box left_c;
    private Overlay center_c;
    
    private VBox main_vbox;

    private int turn;
    
    public BubbleContainer () {
        main_vbox = new VBox (false, 0);
        this.add (main_vbox);
        
        turn = 0;
    }
    
    public void append_date (Widget date) {
        date.get_style_context ().add_class ("timeline-date");
        var al = new Alignment (0.5f, 0, 0, 0);
        al.add (date);
        main_vbox.pack_start (al, false, false, 0);
        
        //Let's add the new day boxes!
        center_c = new Overlay ();
        center_c.add (new Timeline ());
        right_c = new Box (Orientation.VERTICAL, 0);
        left_c = new Box (Orientation.VERTICAL, 0);
        
        var main_hbox = new HBox (false, 0);
        
        main_hbox.pack_start (left_c, true, true, 0);
        main_hbox.pack_start (center_c, false, false, 0);
        main_hbox.pack_start (right_c, true, true,  0);
        
        main_vbox.pack_start (main_hbox, false, false, 0);
    }
    
    public void append_bubble (GenericActivity activity) {
        var box = new Box (Orientation.HORIZONTAL, 0);
        
        var spacing = Random.int_range (10, 50);
        if (turn % 2 == 0) {
            var bubble = new ActivityBubble (activity);
            bubble.get_style_context ().add_class ("round-button-right");
            var border = new Arrow (Side.RIGHT);
            bubble.enter.connect (() => {border.hover = true; border.queue_draw ();});
            bubble.leave.connect (() => {border.hover = false; border.queue_draw ();});
            box.pack_start (bubble, true, true, 0);
            box.pack_start (border, false, false, 0);
            this.left_c.pack_start (box, true, true, spacing);
        }
        else {
            var bubble = new ActivityBubble (activity);
            bubble.get_style_context ().add_class ("round-button-left");
            var border = new Arrow (Side.LEFT);
            bubble.enter.connect (() => {border.hover = true; border.queue_draw ();});
            bubble.leave.connect (() => {border.hover = false; border.queue_draw ();});
            box.pack_start (border, false, false, 0);
            box.pack_start (bubble, true, true, 0);
            this.right_c.pack_start (box, true, true, spacing);
        }
        turn++;
    }
} 

private class Journal.Timeline: DrawingArea {
     public override bool draw (Cairo.Context cr) {
         var width = get_allocated_width ();
         var height = get_allocated_height ();
         var color = Utils.get_timeline_bg_color ();
         Gdk.cairo_set_source_rgba (cr, color);
         cr.paint ();
         return false;
     }
     
     public override void get_preferred_width (out int minimum_width, out int natural_width) {
            minimum_width = natural_width = 2;
     }
}

private class Journal.Arrow : DrawingArea {
        private Side arrow_side;
        
        private const int arrow_width = 20;
        private const int spacing = 10;
        private const int radius = 6;
        private const int line_width = 2;
        
        public bool hover {
            get; set;
        }
        
        public Arrow (Side arrow_side) {
            this.arrow_side = arrow_side;
            hover = false;
        }

        public override bool draw (Cairo.Context cr) {
            var width = get_allocated_width ();
            var height = get_allocated_height ();
            
            var arrow_height = 15;
            var border_radius = 5;
            
            var color = Utils.get_roundbox_border_color ();
            if (hover) 
                color = Utils.get_roundbox_border_hover_color ();
            Gdk.cairo_set_source_rgba (cr, color);
            cr.set_line_width (4);
            if (this.arrow_side == Side.RIGHT) {
                //Draw and fill the arrow
                cr.save ();
                cr.move_to (0, height / 2 - arrow_height);
                cr.line_to (arrow_width, height / 2);
                cr.move_to (arrow_width, height / 2);
                cr.line_to (0, height / 2 + arrow_height);
                cr.rel_line_to(0, - arrow_height * 2);
                color = Utils.get_roundbox_border_color ();
                cr.set_source_rgba (1, 1, 1, 0.65);
                cr.fill ();
                cr.restore ();
                
                //Draw the border
                cr.move_to (0, 0);
                cr.line_to (0, height / 2 - arrow_height);
                cr.set_line_width (4);
                cr.stroke ();
                cr.move_to (0, height / 2 - arrow_height);
                cr.set_line_width (2);
                cr.line_to (arrow_width, height /2);
                cr.stroke ();
                cr.move_to (arrow_width, height /2);
                cr.line_to (0, height / 2 + arrow_height);
                cr.stroke ();
                cr.move_to (0, height / 2 + arrow_height);
                cr.line_to (0, height);
                cr.set_line_width (4);
                cr.stroke ();
                
                //Draw the Circle
                var bg =  Utils.get_timeline_bg_color ();
                color = Utils.get_timeline_circle_color ();
                cr.set_line_width (line_width ); 
                // Paint the border cirle to start with.
                Gdk.cairo_set_source_rgba (cr, bg);
                cr.arc (arrow_width + spacing + radius + line_width, 
                        height / 2 - arrow_height / 2 + radius + line_width - 1,
                        radius, 0, 2*Math.PI);
                cr.stroke ();
                // Paint the colored cirle to start with.
                Gdk.cairo_set_source_rgba (cr, color);
                cr.arc (arrow_width + spacing + radius + line_width, 
                        height / 2 - arrow_height / 2 + radius + line_width - 1,
                        radius - 1, 0, 2*Math.PI);
                cr.fill ();
            }
            else {
                //Draw and fill the arrow
                cr.save ();
                cr.move_to (width, height / 2 - arrow_height);
                cr.line_to (radius * 2 + line_width * 2 + spacing, height / 2);
                cr.move_to (radius * 2 + line_width * 2 + spacing, height / 2);
                cr.line_to (width, height / 2 + arrow_height);
                cr.rel_line_to(0, - arrow_height * 2);
                color = Utils.get_roundbox_border_color ();
                cr.set_source_rgba (1, 1, 1, 0.65);
                cr.fill ();
                cr.restore ();
                
                // Draw the border
                cr.move_to (width, 0);
                cr.line_to (width, height / 2 - arrow_height);
                cr.stroke ();
                cr.move_to (width, height / 2 - arrow_height);
                cr.line_to (radius * 2 + line_width * 2 + spacing , height /2);
                cr.set_line_width (2);
                cr.stroke ();   
                cr.move_to (radius * 2 + line_width * 2 + spacing , height /2);
                cr.line_to (width, height / 2 + arrow_height);
                cr.stroke ();
                cr.move_to (width, height / 2 + arrow_height);
                cr.line_to (width, height);
                cr.set_line_width (4);
                cr.stroke ();
                
                //Draw the Circle
                var bg =  Utils.get_timeline_bg_color ();
                color = Utils.get_timeline_circle_color ();
                cr.set_line_width (line_width ); 
                // Paint the border cirle to start with.
                Gdk.cairo_set_source_rgba (cr, bg);
                cr.arc (radius + line_width, 
                        height / 2 - arrow_height / 2 + radius + line_width - 1,
                        radius, 0, 2*Math.PI);
                cr.stroke ();
                // Paint the colored cirle to start with.
                Gdk.cairo_set_source_rgba (cr, color);
                cr.arc (radius + line_width, 
                        height / 2 - arrow_height / 2 + radius + line_width - 1,
                        radius - 1, 0, 2*Math.PI);
                cr.fill ();
            }

            return false;
        }
        
        public override void get_preferred_width (out int minimum_width, out int natural_width) {
            minimum_width = natural_width = arrow_width + spacing
                                            + radius * 2 + line_width * 2;
        }
}

private class Journal.DayActor : Clutter.Actor {

    private Clutter.Text date_text;
    
    public DayActor (string date) {
        var color = Utils.get_timeline_bg_color ();
        Clutter.Color bgColor = Utils.gdk_rgba_to_clutter_color (color);
        this.background_color = bgColor.lighten();
        string text = Utils.datetime_from_string (date).format (_("%A, %x"));
        date_text = new Clutter.Text.with_text (null, text);
        var attr_list = new Pango.AttrList ();
        attr_list.insert (Pango.attr_scale_new (Pango.Scale.MEDIUM));
        attr_list.insert (Pango.attr_weight_new (Pango.Weight.BOLD));
        date_text.attributes = attr_list;

        this.add_child (date_text);
    }
}

private class Journal.CircleTexture: Clutter.CairoTexture {
        private const int radius = 6;
        private const int line_width = 2;

        public CircleTexture () {
            this.auto_resize = true;
            invalidate ();
        }
        
        public override bool draw (Cairo.Context ctx) {
            var bg =  Utils.get_timeline_bg_color ();
            Clutter.Color backgroundColor = Utils.gdk_rgba_to_clutter_color (bg);
            var color = Utils.get_timeline_circle_color ();
            Clutter.Color circleColor = Utils.gdk_rgba_to_clutter_color (color);

            var cr = ctx;
            this.clear ();
            // Paint the border cirle to start with.
            Clutter.cairo_set_source_color(cr, backgroundColor);
            ctx.arc (radius + line_width, radius + line_width, radius, 0, 2*Math.PI);
            ctx.stroke ();
            // Paint the colored cirle to start with.
            Clutter.cairo_set_source_color(cr, circleColor);
            ctx.arc (radius + line_width, radius + line_width, radius - 1, 0, 2*Math.PI);
            ctx.fill ();
            
            return true;
        }

    public override void get_preferred_width (float for_height,out float min_width, out float nat_width) {
        nat_width = min_width = 2 * radius + 2 * line_width;
    }
   
    public override void get_preferred_height (float for_width,out float min_height, out float nat_height) {
        nat_height = min_height = 2 * radius + 2 * line_width;
    }
}

private class Journal.ActivityBubble : Button {
    private const int DEFAULT_WIDTH = 400;
    
    public GenericActivity activity {
        get; private set;
    }
    
    private Image _image;
    
    public ActivityBubble (GenericActivity activity) {
       this.activity = activity;
       
       if (activity is SingleActivity) {
           var act = activity as SingleActivity;
           act.thumb_loaded.connect (() => {
               this._image.set_from_pixbuf (act.thumb_icon);
           });
       }
       
       this.clicked.connect (() => {activity.launch ();});
       
       setup_ui ();
    }
    
    private void setup_ui () {
        var evbox = new EventBox ();
        evbox.set_visible_window (true);
        var title = new Label (activity.title);
        DateTime d = new DateTime.from_unix_utc (this.activity.time_start / 1000).to_local ();
        string date = d.format ("%H:%M");
        var time = new Label (date);
        var vbox = new VBox (false, 5);
        vbox.pack_start (title, true, true, 0);
        vbox.pack_start (time, true, true, 0);
        evbox.add (vbox);
        
        _image = new Image.from_pixbuf (activity.icon);
        
        var container = new VBox (false, 5);
        container.pack_start (evbox,true, true, 0);
        container.pack_start (_image,true, true, 0);
        
        this.add (container);
    }
    
    public override void get_preferred_width (out int minimum_width, out int natural_width) {
            minimum_width = natural_width = DEFAULT_WIDTH;
    }

}

private class Journal.HoleActor : Clutter.Actor {

    private Clutter.Canvas canvas;

    private Clutter.BinLayout box;
    public HoleActor () {
       this.reactive = true;
       box = new Clutter.BinLayout (Clutter.BinAlignment.CENTER, 
                                    Clutter.BinAlignment.CENTER);
       set_layout_manager (box);
       
       this.canvas = new Clutter.Canvas ();
       canvas.draw.connect ((cr, w, h) => { return paint_canvas (cr, w, h); });
       var canvas_box = new Clutter.Actor ();
       canvas_box.set_content (canvas);
       this.allocation_changed.connect ((box, f) => {
            Idle.add (()=>{
                //see this http://www.mail-archive.com/clutter-app-devel-list@clutter-project.org/msg00116.html
                canvas_box.set_size ((int)box.get_width (), (int) box.get_height ());
                canvas.set_size ((int)box.get_width (), (int) box.get_height ());
                return false;
            });
       });
       this.add_child (canvas_box);
    }

    private bool paint_canvas (Cairo.Context ctx, int width, int height) {
        var borderWidth = 3;
        Clutter.Color backgroundColor = {192,192,192, 255};
        Clutter.Color borderColor = {255, 255, 255, 255};

        double boxHeight = height;
        
        var cr = ctx;
        cr.save ();
        cr.set_source_rgba (0.0, 0.0, 0.0, 0.0);
        cr.set_operator (Cairo.Operator.SOURCE);
        cr.paint ();
        cr.restore ();
        
        cr.move_to (0, 0);
        double step = 30;
        double i = step;
        double old_h = boxHeight/6;
        cr.line_to (i, old_h);
        for (i = step * 2; i <= step* 42; i += step) {
            old_h = -old_h;
            cr.rel_line_to (step, old_h);
        }
        
        old_h = boxHeight/6;
        if(old_h > 0)
            cr.rel_line_to (0, boxHeight);
        else
            cr.rel_line_to (0, boxHeight - old_h);

        for (i = 0; i <= step * 42; i += step ) {
            old_h = -old_h;
            cr.rel_line_to (-step, old_h);
        }

        cr.close_path ();
        cr.set_line_join(Cairo.LineJoin.ROUND);
        Clutter.cairo_set_source_color(cr, backgroundColor);
        cr.fill_preserve();
        Clutter.cairo_set_source_color(cr, borderColor);
        cr.set_line_width(borderWidth);
        cr.stroke();

        return true;
    }
}
