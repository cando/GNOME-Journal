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

//        FIXME :
//        IMPORTANT!
//        * Propagate Events
//        * Better bubble's placing algorithm. Please maintain the time ordering.
//        SECONDARY
//        * Highlight timenavigator widget (Rewrite it!)
//        * Disable scrollbar on loading? On-loading message?
//       CHECK TODO file
using Gtk;
using Cairo;

enum Side {
 TOP,
 LEFT,
 RIGHT,
 BOTTOM
}

private class Journal.VTL : Box {
    
    private ActivityModel model;
    private App app;
    private Scrollbar scrollbar;
    private TimelineNavigator vnav;
    private SearchWidget search_bar;
    
    public ScrolledWindow viewport;
    public Box container;
    private BubbleContainer bubble_c;
    
    private Gee.Map<string, Clutter.Actor> y_positions;
    private Gee.List<string> dates_added;
    private Gee.Map<string, Widget?> dates_widget;

    //Date to jump when we have loaded new events
    private DateTime? date_to_jump;
    
    private bool on_loading;
    private float old_y;

    public VTL (App app, ActivityModel model){
        Object (orientation: Orientation.HORIZONTAL, spacing : 0);
        this.model = model;
        this.app = app;
        
        y_positions = new Gee.HashMap <string, Clutter.Actor> ();
        dates_widget = new Gee.HashMap <string, Widget?> ();
        dates_added = new Gee.ArrayList <string> ();
        
        viewport = new ScrolledWindow (null, null);
        viewport.set_policy (PolicyType.NEVER, PolicyType.AUTOMATIC);
        scrollbar = (Scrollbar)viewport.get_vscrollbar ();
        scrollbar.value_changed.connect (() => { on_scrollbar_scroll ();});
        
        container = new Box (Orientation.VERTICAL, 0);
        viewport.add_with_viewport (container);
        
        bubble_c = new BubbleContainer ();
        container.pack_start (bubble_c, true, true, 0);
        
        vnav = new TimelineNavigator (Orientation.VERTICAL);
        vnav.go_to_date.connect ((date) => {this.jump_to_day (date);});

        //this.pack_start (new Gtk.Label(""), false, false, 32);
        this.pack_start (viewport, true, true, 0);
        this.pack_start (vnav, false, false, 10);
       
        model.activities_loaded.connect ((day_loaded)=> {
             load_activities (day_loaded);
             //Check if the last date is effectely loaded--> mean inserted in the
             //GtkBox container
             string date = dates_added.get (dates_added.size - 1);
             check_finished_loading (date);
        });
        
        old_y = -1;
    }
    
    private void check_finished_loading (string date) {
        int y;
        dates_widget.get (date).translate_coordinates (container, 0, 0, null, out y);
        if (y == -1)
            Idle.add (()=>{
                check_finished_loading (date);
                return false;
            });
        else
            on_loading = false;
    }
    
    private bool get_child_index_for_date (string date, out int index) {
        index = -1;
        var datetime = Utils.datetime_from_string (date);
        dates_added.sort ( (a,b) => {
            DateTime first = Utils.datetime_from_string ((string)a);
            DateTime second= Utils.datetime_from_string ((string)b);
            return - first.compare (second);
        });
        
        int i = 0;
        foreach (string d in dates_added) {
            DateTime dt = Utils.datetime_from_string (d);
            if (dt.compare (datetime) <= 0) {
                //i*2 because the first child is the date and the second is the
                //list of activities
                index = i*2;
                return true;
            }
            i++;
        }
        //Else append to the end
        return false;
    }
    
    private void load_activities (string date) {
        if (dates_added.contains (date))
          return;
        
        int index;
        get_child_index_for_date (date, out index);
        string text = Utils.datetime_from_string (date).format (_("%A, %x"));
        var d = new Button.with_label (text);
        bubble_c.append_date_and_reorder (d, index);
        dates_widget.set (date, d);
        dates_added.add (date);

        var activity_list = model.activities.get (date);
        if (activity_list.activities.size == 0)
            return;
        bubble_c.append_bubbles (activity_list.activities);
        
        bubble_c.show_all ();
        
        if (date_to_jump != null)
            jump_to_day (date_to_jump);
    }
    
    private DateTime find_nearest_date (DateTime date) {
        DateTime nearest = date;
        int diff = 0;
        int min_diff = int.MAX;
        foreach (string tmp in dates_added) {
            var tmp_d = Utils.datetime_from_string (tmp);
            diff = (int)(tmp_d.difference (date) / TimeSpan.DAY).abs ();
            if (diff < min_diff) {
                nearest = tmp_d;
                min_diff = diff;
            }
        }
        return nearest;
    }
    
    private void internal_jump_on_scroll (DateTime date, string date_s) {
        //Thanks http://stackoverflow.com/questions/6903170/auto-scroll-a-gtkscrolledwindow
        int y;
        var vadj = scrollbar.adjustment;
        dates_widget.get (date_s).translate_coordinates (container, 0, 0, null, out y);
        if (y == -1)
            Idle.add (()=>{
                jump_to_day (date);
                return false;
            });
        else
            vadj.value = double.min (y, vadj.upper - vadj.page_size);
    }
    
    private void jump_to_day (DateTime date) {
        string date_s = date.format("%Y-%m-%d");
        if (dates_widget.has_key (date_s)) {
            internal_jump_on_scroll (date, date_s);
            date_to_jump = null;
        }
        else {
            if (date == date_to_jump) {
                //Break the infinite loop that happens when the user ask for an
                //event period not present in the db.
                var nearest_date = find_nearest_date (date);
                var nearest_date_s = nearest_date.format("%Y-%m-%d");
                if (dates_widget.has_key (nearest_date_s)) {
                    internal_jump_on_scroll (nearest_date, nearest_date_s);
                    date_to_jump = null;
                }
                return;
            }
            model.load_activities (date);
            date_to_jump = date;
            on_loading = true;
        }
    }
    
    private void on_scrollbar_scroll () {
        float y = (float)(scrollbar.adjustment.value);
        var limit = (int)scrollbar.adjustment.upper - 
                         scrollbar.adjustment.page_size;
        
        if (!on_loading && y >= limit) {
            //We can't scroll anymmore! Let's load another date range!
            model.load_other_days (3);
            on_loading = true;
        }
        
        //We are moving so we should highligth the right TimelineNavigator's label
        //TODO
//        int current_value;
//        if (!dates_widget.has_key (vnav.current_highlighted)) {
//            var widget = dates_widget.get (vnav.current_highlighted);
//            widget.translate_coordinates (container, 
//                                               0, 0, null, 
//                                               out current_value);
//        }
//        else {
//            var date = Utils.datetime_from_string (vnav.current_highlighted);
//            var nearest_date = find_nearest_date (date);
//            var nearest_date_s = nearest_date.format ("%Y-%m-%d");
//            var widget = dates_widget.get (vnav.current_highlighted);
//            widget.translate_coordinates (container, 
//                                               0, 0, null, 
//                                               out current_value);
//        }
//        if (current_value < y && y > old_y)
//                vnav.highlight_next ();
//        else if (current_value > y && y < old_y)
//                vnav.highlight_previous ();
//        
//        old_y = y;
    }
}

private class Journal.BubbleContainer : EventBox {
    //The left side of the timeline
    private Box right_c;
    //The right side of the timeline
    private Box left_c;
    
    private Box main_vbox;

    private int turn;
    
    public BubbleContainer () {
        main_vbox = new Box (Orientation.VERTICAL, 0);
        var al = new Alignment (0.5f, 0, 0, 0);
        al.add (main_vbox);
        this.add (al);
        
        turn = 0;
    }
    
    public void append_date_and_reorder (Widget date, int index) {
        date.get_style_context ().add_class ("timeline-date");
        var al = new Alignment (0.49f, 0, 0, 0);
        al.add (date);
        main_vbox.pack_start (al, false, false, 0);
        
        //Let's add the new day boxes!
        var center_c = new Timeline ();
        right_c = new Box (Orientation.VERTICAL, 0);
        left_c = new Box (Orientation.VERTICAL, 0);

        //FIXME Hack! Are we sure to use a Fixed? It seems to work pretty well
        var main_hbox = new Fixed ();
        // Start of the circle = 430 = 20 (arrow_width + spacing) in Arrow class
        // Start of the circle + radius + line_width/2
        main_hbox.put (center_c, 430 + 6 + 1, 0);
        main_hbox.put (left_c, 0, 0);
        main_hbox.put (right_c, 430, 0);
        
        main_hbox.size_allocate.connect ((alloc) => {
            Idle.add (() => {
                center_c.set_size_request (-1, alloc.height);
                return false;
            });
        });
        
        right_c.margin_right = 20;
        
        main_vbox.pack_start (main_hbox, false, false, 0);
        
        if (index != -1) {
            main_vbox.reorder_child (al, index);
            main_vbox.reorder_child (main_hbox, index + 1);
        }
        
        turn = 0;
    }
    
    public void append_bubbles (Gee.List<GenericActivity> activity_list) {
        foreach (GenericActivity activity in activity_list)
            this.append_bubble (activity);
    }
    
    private void append_bubble (GenericActivity activity) {
        var box = new Box (Orientation.HORIZONTAL, 0);
        
        var spacing = Random.int_range (10, 30);
        if (turn % 2 == 0) {
            var bubble = new ActivityBubble (activity, Side.RIGHT);
            bubble.get_style_context ().add_class ("round-bubble-right");
            var border = new Arrow (Side.RIGHT);
            bubble.enter_notify_event.connect ((ev) => {
                border.hover = true; 
                border.queue_draw ();
                return false;
            });
            bubble.leave_notify_event.connect ((ev) => {
                border.hover = false;
                border.queue_draw ();
                return false;
            });
            box.pack_start (bubble, true, true, 0);
            box.pack_start (border, false, false, 0);
            this.left_c.pack_start (box, false, false, spacing);
        }
        else {
            var bubble = new ActivityBubble (activity, Side.LEFT);
            bubble.get_style_context ().add_class ("round-bubble-left");
            var border = new Arrow (Side.LEFT);
            bubble.enter_notify_event.connect ((ev) => {
                border.hover = true; 
                border.queue_draw ();
                return false;
            });
            bubble.leave_notify_event.connect ((ev) => {
                border.hover = false;
                border.queue_draw ();
                return false;
            });
            box.pack_start (border, false, false, 0);
            box.pack_start (bubble, true, true, 0);
            this.right_c.pack_start (box, false, false, spacing);
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
                //FIXME make this to be theme indipendent!
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

private class Journal.ActivityBubbleHeader : Box {
    private Label title;
    private Image icon;
    public ActivityBubbleHeader (GenericActivity activity) {
        Object (orientation:Orientation.HORIZONTAL, spacing: 0);
        var evbox = new EventBox ();
        evbox.set_visible_window (false);
        evbox.add_events (Gdk.EventMask.ENTER_NOTIFY_MASK |
                         Gdk.EventMask.LEAVE_NOTIFY_MASK);
        this.title = new Label (activity.title);
        this.title.set_alignment (0, 1);
        this.title.set_markup ("<b>%s</b>\n<span size='small'>%s</span>".
                                printf(activity.title, activity.part_of_the_day));
        evbox.add (this.title);
        evbox.enter_notify_event.connect ((ev)=> {
            this.title.set_markup ("<b>%s</b>\n<span size='small'>%s</span>".
                                printf(activity.title, activity.date));
            return false;
        });
        
        evbox.leave_notify_event.connect ((ev)=> {
            this.title.set_markup ("<b>%s</b>\n<span size='small'>%s</span>".
                                printf(activity.title, activity.part_of_the_day));
            return false;
        });
        
        var pixbuf = activity.icon.scale_simple (32, 32, Gdk.InterpType.NEAREST);
        this.icon = new Gtk.Image.from_pixbuf (pixbuf);
        
        this.pack_start (this.icon, false, true, 3);
        var container = new Box (Orientation.VERTICAL, 5);
        if (activity.content != null) {
            container.pack_start (evbox, true, true, 0);
            container.pack_start (new Gtk.Separator (Orientation.HORIZONTAL),
                                                     false, false, 0);
        }
        this.pack_start (container, true, true, 0);
    }
}


private class Journal.ActivityBubble : EventBox {
    private const int DEFAULT_WIDTH = 400;
    
    public GenericActivity activity {
        get; private set;
    }
    
    private Side side;
    private bool hover;
    
    public ActivityBubble (GenericActivity activity, Side side) {
       this.activity = activity;
       this.side = side;
       this.hover = false;
       this.set_visible_window (false);
       this.add_events (Gdk.EventMask.ENTER_NOTIFY_MASK |
                         Gdk.EventMask.LEAVE_NOTIFY_MASK |
                         Gdk.EventMask.BUTTON_RELEASE_MASK);
       this.button_release_event.connect ((ev) => {activity.launch (); return false;});
       this.enter_notify_event.connect ((ev) => {
            hover = true; 
            queue_draw (); 
            return false;
       });
       this.leave_notify_event.connect ((ev) => {
            hover = false; 
            queue_draw (); 
            return false;
       });
       if (activity.content is GenericCompositeWidget) {
           var content = activity.content as GenericCompositeWidget;
           //FIXME Hack: Gtk doesn't propagate enter/leave_notify_event from child 
           //to parent. So we sintetize a custom signal;
           content.enter.connect ((e) => {
               warning ("enter");
               hover = true; 
               queue_draw (); 
           });
           content.leave.connect ((e) => {
            warning ("leave");
               hover = false; 
               queue_draw (); 
           });
       }

       setup_ui ();
    }
    
    private void setup_ui () {
        var header = new ActivityBubbleHeader (activity);
        
        var container = new Box (Orientation.VERTICAL, 5);
        container.pack_start (header, false, false, 2);
        var al = new Alignment (0.5f, 0, 0, 0);
        al.add (activity.content);
        container.pack_start (al, true, true, 9); 
        
        this.add (container);
        this.draw_as_css_box (this);
    }
    
    public void draw_as_css_box (Widget widget) {
        widget.draw.connect ((cr) => {
            var context = widget.get_style_context ();
            Gtk.Allocation allocation;
            widget.get_allocation (out allocation);
            context.render_background (cr,
                                       0, 0,
                                       allocation.width, allocation.height);
            var button = new Gtk.Button();
            context = button.get_style_context ();
            if (side == Side.RIGHT)
                context.add_class("round-bubble-right");
            else
                context.add_class("round-bubble-left");
            if (hover)
                context.add_class ("round-bubble-hover");
            context.render_frame (cr,
                                  0, 0,
                                  allocation.width, allocation.height);
            return false;
         });
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
