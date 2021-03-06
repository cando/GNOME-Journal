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
//        SECONDARY:
//        * Propagate Events
//        * Better bubble's placing algorithm. Please maintain the time ordering.
//        * Disable scrollbar on loading? On-loading message?
using Gtk;
using Cairo;

enum Side {
 TOP,
 LEFT,
 RIGHT,
 BOTTOM
}

enum VTLType {
 NORMAL,
 SEARCH
}

private class Journal.VTL : Box {
    
    private ActivityModel model;
    private App app;
    private VTLType type;
    
    private Scrollbar scrollbar;
    private TimelineNavigator vnav;
    
    public ScrolledWindow viewport;
    public Box container;
    private BubbleContainer bubble_c;

    private Gee.List<string> dates_added;
    private Gee.Map<string, Widget?> dates_widget;
    private Gee.Map<string, uint> search_count_map;

    //Date to jump when we have loaded new events
    private DateTime? date_to_jump;
    
    private bool on_loading;
    private float old_y;

    public VTL (App app, ActivityModel model, VTLType type){
        Object (orientation: Orientation.HORIZONTAL, spacing : 0);
        this.model = model;
        this.app = app;
        this.type = type;

        dates_widget = new Gee.HashMap <string, Widget?> ();
        dates_added = new Gee.ArrayList <string> ();
        
        viewport = new ScrolledWindow (null, null);
        viewport.set_policy (PolicyType.NEVER, PolicyType.AUTOMATIC);
        viewport.set_kinetic_scrolling (true);
        scrollbar = (Scrollbar)viewport.get_vscrollbar ();
        scrollbar.value_changed.connect (() => {on_scrollbar_scroll ();});
        
        container = new Box (Orientation.VERTICAL, 0);
        viewport.add_with_viewport (container);
        
        bubble_c = new BubbleContainer ();
        bubble_c.load_more_results.connect (() => {
            model.load_other_results.begin ();
        });
        container.pack_start (bubble_c, true, true, 0);
        
        vnav = new TimelineNavigator (Orientation.VERTICAL, model);
        vnav.go_to_date.connect ((date, type) => {
            this.jump_to_day (date, type);
        });
        
        this.pack_start (new Label(""), false, false, 10);
        this.pack_start (vnav, false, false, 0);
        this.pack_start (viewport, true, true, 0);
       
       if (type == VTLType.NORMAL) {
           model.activities_loaded.connect ((day_loaded)=> {
                 load_activities (day_loaded);
                 //Check if the last date is effetely loaded--> mean inserted in the
                 //GtkBox container
                 string date = dates_added.get (dates_added.size - 1);
                 check_finished_loading (date);
                 vnav.grab_focus ();
            });
            
            model.end_activities_loaded.connect (() => {
                if (date_to_jump != null)
                    jump_to_day (date_to_jump);
            });
        }
        else {
            //Map used for populating the timebar in the search view.
            search_count_map = new Gee.HashMap<string, uint> ();
                
            model.new_search_query.connect (() => {
                clear_activities ();
                bubble_c.show_searching ();
                search_count_map.clear ();
            });
            
            model.searched_activities_loaded.connect ((days_loaded)=> {
                 if (days_loaded.size == 0) {
                    if (dates_added.size == 0)
                        bubble_c.show_no_results ();
                    else
                        bubble_c.show_no_more_results ();
                    return;
                 }
                 else if (dates_added.size == 0) {
                    clear_activities ();
                 }
                 
                 foreach (string day in days_loaded) {
                     load_activities (day);
                     var list = model.searched_activities.get (day);
                     var num = list.activities.size;
                     if (num > 0)
                        search_count_map.set (day, num);
                     string date = dates_added.get (dates_added.size - 1);
                     check_finished_loading (date);
                 }
                 
                 bubble_c.show_load_more ();
                 
                 //FIXME i'm doing this because Gee seems to not recognize
                 // equality of DateTime keys in its maps (while it does for 
                 //key strings)..or maybe i'm doing something weird.
                 var list = new Gee.ArrayList<DateTime?> ();
                 foreach(string d in search_count_map.keys)
                    list.add (Utils.datetime_from_string (d));
                 vnav.set_events_count (list);
            });
        }
        
        this.key_press_event.connect ((ev) => {
            if (ev.keyval == Gdk.Key.Up || 
               (ev.keyval == Gdk.Key.space && (ev.state & 
                                               Gdk.ModifierType.SHIFT_MASK) != 0))
                this.scrollbar.move_slider (ScrollType.STEP_BACKWARD);
            else if (ev.keyval == Gdk.Key.Down || ev.keyval == Gdk.Key.space) 
                this.scrollbar.move_slider (ScrollType.STEP_FORWARD);
            else if (Utils.is_jump_start_event (ev))
                this.jump_to_day (Utils.get_start_of_today ());
            return false;
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
    
    private void clear_activities () {
        dates_added.clear ();
        dates_widget.clear ();
        bubble_c.clear ();
    }
    
    private void load_activities (string date) {
        if (dates_added.contains (date)) {
            if (type == VTLType.SEARCH)
                //Remove and update the last day in the search
                bubble_c.remove_last_day ();
            else {
                if (Utils.is_today (date))
                    //we are receiving new events from the monitor
                    //Let's delete the last day
                    bubble_c.remove_first_day ();
                else
                    return;
            }
        }
        
        int index;
        get_child_index_for_date (date, out index);
        string text = Utils.datetime_from_string (date).format (_("%A, %B %e"));
        var d = new Button.with_label (text);
        d.set_relief (Gtk.ReliefStyle.NONE);
        d.set_focus_on_click (false);
        bubble_c.append_date_and_reorder (d, index);
        dates_widget.set (date, d);
        dates_added.add (date);
        
        DayActivityModel activity_list;
        if (type == VTLType.NORMAL)
            activity_list = model.activities.get (date);
        else
            activity_list = model.searched_activities.get (date);

        if (activity_list == null || activity_list.activities.size == 0)
            return;
        bubble_c.append_bubbles (activity_list.activities);
        
        bubble_c.show_all ();
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
    
    private void jump_to_day (DateTime date, RangeType? type = null) {
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
            model.load_activities (date, type);
            date_to_jump = date;
            on_loading = true;
        }
    }
    
    private void on_scrollbar_scroll () {
        float y = (float)(scrollbar.adjustment.value);
        var limit = (int)scrollbar.adjustment.upper - 
                         scrollbar.adjustment.page_size;
        
        if (!on_loading && y >= limit) {
            //We can't scroll anymore! Let's load another date range!
            if (type == VTLType.NORMAL)
                model.load_other_days (3);
            else {
                bubble_c.show_searching (false);
                model.load_other_results.begin ();
            }
            on_loading = true;
        }
    }
}

private class Journal.BubbleContainer : EventBox {
    //The left side of the timeline
    private Box right_c;
    //The right side of the timeline
    private Box left_c;
    
    private Fixed fading_timeline;
    
    private Label no_results_label;
    private Label searching_label;
    private Button more_results_button;
    
    private Box main_vbox;
    private int turn;
    private Widget[] last_day;
    
    public signal void load_more_results ();
    
    public BubbleContainer () {
        main_vbox = new Box (Orientation.VERTICAL, 0);
        var al = new Alignment (0.5f, 0, 0, 0);
        al.add (main_vbox);
        this.add (al);
        
        turn = 1;
        last_day = new Widget[2];
        
        create_fading_timeline ();
    }
    
    private void create_fading_timeline () {
        var center_c = new Timeline ();
        center_c.fade_out = true;
        center_c.set_size_request (-1, 200);
        var right_c = new Box (Orientation.VERTICAL, 0);
        var left_c = new Box (Orientation.VERTICAL, 0);

        fading_timeline = new Fixed ();
        // Start of the circle = 430 = 20 (arrow_width + spacing) in Arrow class
        // Start of the circle + radius + line_width/2
        fading_timeline.put (center_c, 430 + 6 + 1, 0);
        fading_timeline.put (left_c, 0, 0);
        fading_timeline.put (right_c, 430, 0);
        
        right_c.margin_right = 20;
        main_vbox.pack_end (fading_timeline, false, false, 0);
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
        
        last_day[0] = date;
        last_day[1] = main_hbox;
//        turn = 1;
    }
    
    public void clear (bool all = false) {
        turn = 1;
        foreach (Widget w in main_vbox.get_children ())
            w.destroy ();
        //Recreate the fading timeline
        if (!all)
            create_fading_timeline ();
    }
    
    public void remove_first_day () {
        var list = main_vbox.get_children ();
        list.first ().data.destroy ();
        list.nth_data (1).destroy ();
    }
    
    public void remove_last_day () {
        last_day[0].destroy ();
        last_day[1].destroy ();
        more_results_button.destroy ();
    }
    
    public void append_bubbles (Gee.List<GenericActivity> activity_list) {
        foreach (GenericActivity activity in activity_list)
            this.append_bubble (activity);
            
        //Move the fading timeline to the end
        main_vbox.reorder_child (fading_timeline, -1);
    }
    
    public void show_no_results () {
        this.clear (true);
        no_results_label = new Label (_("No matches found"));
        no_results_label.get_style_context ().add_class ("search-labels");
        this.main_vbox.pack_start (no_results_label, true, true);
        this.show_all ();
    }
    public void show_no_more_results () {
        this.more_results_button.destroy ();
        no_results_label = new Label (_("No more matches found"));
        no_results_label.get_style_context ().add_class ("search-labels");
        this.main_vbox.pack_end (no_results_label, false, false);
        this.show_all ();
    }
    
    public void show_load_more () {
        more_results_button = new Button.with_label (_("Click to load more results"));
        more_results_button.get_style_context ().add_class ("timeline-date");
        more_results_button.set_relief (Gtk.ReliefStyle.NONE);
        more_results_button.set_focus_on_click (false);
        var al = new Alignment (0.49f, 0, 0, 0);
        al.add (more_results_button);
        more_results_button.clicked.connect (() => {
            more_results_button.set_label ("Searching ...");
            load_more_results ();
        });
        this.main_vbox.pack_end (al, false, false);
        this.show_all ();
    }
    
    public void show_searching (bool first_time=true) {
        if (first_time) {
            this.clear (true);
            searching_label = new Label (_("Searching..."));
            searching_label.get_style_context ().add_class ("search-labels");
            this.main_vbox.pack_start (searching_label, false, false);
        }
        else {
            if (more_results_button == null)
                show_load_more ();
            more_results_button.set_label (_("Searching..."));
        }
        this.show_all ();
    }
    
    private void append_bubble (GenericActivity activity) {
        var box = new Box (Orientation.HORIZONTAL, 0);
        ActivityBubble bubble;
        var spacing = Random.int_range (20, 30);
        if (turn % 2 == 0) {
            bubble = new ActivityBubble (activity, Side.RIGHT);
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
            bubble = new ActivityBubble (activity, Side.LEFT);
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

    public bool fade_out {
        get; set; default = false;
    }
    
    public override bool draw (Cairo.Context cr) {
        var height = get_allocated_height ();
        var color = Utils.get_timeline_bg_color ();
        if (!fade_out) {
            Gdk.cairo_set_source_rgba (cr, color);
        }
        else {
            var p = new Cairo.Pattern.linear (0, 0, height, height);
            p.add_color_stop_rgba (0.0, color.red, color.green, color.blue, color.alpha);
            p.add_color_stop_rgba (0.8, 1.0, 1.0, 1.0, 0.0);
            cr.set_source (p);
        }
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
        private const int line_width = 1;
        
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
            
            var color = Utils.get_roundbox_border_color ();
            if (hover) 
                color = Utils.get_roundbox_border_hover_color ();
            Gdk.cairo_set_source_rgba (cr, color);
            cr.set_line_width (2);
            if (this.arrow_side == Side.RIGHT) {
                //Draw and fill the arrow
                cr.save ();
                cr.move_to (0, height / 2 - arrow_height);
                cr.line_to (arrow_width, height / 2);
                cr.move_to (arrow_width, height / 2);
                cr.line_to (0, height / 2 + arrow_height);
                cr.rel_line_to(0, - arrow_height * 2);
                color = Utils.get_roundbox_border_color ();
                //FIXME make this to be theme independent!
                cr.set_source_rgba (1, 1, 1, 0.65);
                cr.fill ();
                cr.restore ();
                
                //Draw the border
                cr.move_to (0, 7);
                cr.line_to (0, height / 2 - arrow_height);
                cr.set_line_width (2);
                cr.stroke ();
                cr.move_to (0, height / 2 - arrow_height);
                cr.set_line_width (1);
                cr.line_to (arrow_width, height /2);
                cr.stroke ();
                cr.move_to (arrow_width, height /2);
                cr.line_to (0, height / 2 + arrow_height);
                cr.stroke ();
                cr.move_to (0, height / 2 + arrow_height);
                cr.line_to (0, height- 7 );
                cr.set_line_width (2);
                cr.stroke ();
                
                //Draw the Circle
                var bg =  Utils.get_timeline_bg_color ();
                color = Utils.get_timeline_circle_color ();
                cr.set_line_width (line_width ); 
                // Paint the border circle to start with.
                Gdk.cairo_set_source_rgba (cr, bg);
                cr.arc (arrow_width + spacing + radius + line_width + 1, 
                        height / 2 - arrow_height / 2 + radius + line_width - 1,
                        radius, 0, 2*Math.PI);
                cr.stroke ();
                // Paint the colored circle to start with.
                Gdk.cairo_set_source_rgba (cr, color);
                cr.arc (arrow_width + spacing + radius + line_width + 1, 
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
                cr.move_to (width, 7);
                cr.line_to (width, height / 2 - arrow_height);
                cr.stroke ();
                cr.move_to (width, height / 2 - arrow_height);
                cr.line_to (radius * 2 + line_width * 2 + spacing , height /2);
                cr.set_line_width (1);
                cr.stroke ();   
                cr.move_to (radius * 2 + line_width * 2 + spacing , height /2);
                cr.line_to (width, height / 2 + arrow_height);
                cr.stroke ();
                cr.move_to (width, height / 2 + arrow_height);
                cr.line_to (width, height - 7);
                cr.set_line_width (2);
                cr.stroke ();
                
                //Draw the Circle
                var bg =  Utils.get_timeline_bg_color ();
                color = Utils.get_timeline_circle_color ();
                cr.set_line_width (line_width ); 
                // Paint the border circle to start with.
                Gdk.cairo_set_source_rgba (cr, bg);
                cr.arc (radius + line_width + 1, 
                        height / 2 - arrow_height / 2 + radius + line_width - 1,
                        radius, 0, 2*Math.PI);
                cr.stroke ();
                // Paint the colored circle to start with.
                Gdk.cairo_set_source_rgba (cr, color);
                cr.arc (radius + line_width + 1, 
                        height / 2 - arrow_height / 2 + radius + line_width - 1,
                        radius - 1, 0, 2*Math.PI);
                cr.fill ();
            }

            return false;
        }
        
        public override void get_preferred_width (out int minimum_width, out int natural_width) {
            minimum_width = natural_width = arrow_width + spacing
                                            + radius * 2 + line_width * 2 + 1;
        }
}

private class Journal.ActivityBubbleHeader : Box {
    private Label title;
    private Label date;
    
    public ActivityBubbleHeader (GenericActivity activity) {
        Object (orientation:Orientation.HORIZONTAL, spacing: 0);
        var evbox = new EventBox ();
        evbox.set_visible_window (false);
        evbox.add_events (Gdk.EventMask.ENTER_NOTIFY_MASK |
                         Gdk.EventMask.LEAVE_NOTIFY_MASK);
        var title_text = activity.num_activities_title == null ? 
                         activity.title : activity.num_activities_title;
        var inacessible_text = "";
        if (activity is SingleActivity) {
            var act = activity as SingleActivity;
            if (!act.exists)
                inacessible_text = "\t<span color='grey'>%s</span>".printf (_("inaccessible"));
        }
        else {
            var act = activity as CompositeActivity;
            var num_act = act.activities.size;
            if (act.num_inacessible_activities > 0) {
                if (num_act == act.num_inacessible_activities) {
                    var t = _("All inaccessible");
                    inacessible_text = "\t<span color='grey'>%s</span>".printf (t);
                }
                else {
                    var t = act.num_inacessible_activities.to_string () + _(" inaccessible");
                    inacessible_text = "\t<span color='grey'>%s</span>".printf (t);
                }
            }
        }
                
        this.title = new Label (title_text);
        this.title.set_ellipsize (Pango.EllipsizeMode.END);
        this.title.set_alignment (0, 1);
        this.title.set_markup (("<span><b>%s</b></span>").printf(title_text));
                                
        this.date = new Label (null);
        this.date.set_ellipsize (Pango.EllipsizeMode.END);
        this.date.set_alignment (0, 1);
        this.date.set_markup (("<span color='grey'>%s</span>").
                                printf(activity.part_of_the_day));
        
        var inaccessible_label = new Label (inacessible_text);
        inaccessible_label.set_ellipsize (Pango.EllipsizeMode.END);
        inaccessible_label.set_alignment (1, 0);
        inaccessible_label.set_markup (inacessible_text);
        
        var hbox = new Box (Orientation.HORIZONTAL, 10);
        hbox.pack_start (this.title, true, true, 0);
        hbox.pack_end (inaccessible_label, true, true, 0);
        
        var vbox = new Box (Orientation.VERTICAL, 0);
        vbox.pack_start (hbox, false, false, 0);
        vbox.pack_start (this.date, false, false, 0);
        
        evbox.add (vbox);
        evbox.enter_notify_event.connect ((ev)=> {
            this.date.set_markup (("<span color='grey'>%s</span>").
                                printf(activity.date));
            return false;
        });
        
        evbox.leave_notify_event.connect ((ev)=> {
            this.date.set_markup (("<span color='grey'>%s</span>").
                                printf(activity.part_of_the_day));
            return false;
        });
        
        var container = new Box (Orientation.VERTICAL, 0);
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
       this.button_release_event.connect ((ev) => {
            if (activity is SingleActivity) {
                if (ev.button == 1)
                    activity.launch ();
                else if (ev.button == 2)
                    Utils.previewer.show_file (((SingleActivity)activity).uri);
            }
            else
                activity.launch (); 
            return false;
       });
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

       setup_ui ();
    }
    
    private void setup_ui () {
        var header = new ActivityBubbleHeader (activity);
        
        var container = new Box (Orientation.VERTICAL, 0);
        container.set_border_width (24);
        container.pack_start (header, false, false, 2);
        container.pack_start (activity.content, true, true, 9);
        
        var more_button = new Gtk.Button();
        more_button.set_label ("...");
        more_button.set_relief (Gtk.ReliefStyle.NONE);
        more_button.set_focus_on_click (false);
        more_button.clicked.connect (() => {activity.launch ();});
        if (activity.show_more)
            container.pack_start (more_button, false, false, 0);
        
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
