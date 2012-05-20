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

private class Journal.ScrollableViewport : Clutter.Actor {

    public float scroll_to_y {
        get; set;
    }
    public float scroll_to_x {
        get; set;
    }
    public ScrollMode scroll_mode {
        get; set;
    }

    public ScrollableViewport () {
        Object ();
        this.reactive = true;
        scroll_to_y = 0.0f;
        scroll_to_x = 0.0f;
    }
    
    private inline void push_clip () {
        Clutter.ActorBox allocation;
        float width, height;
        float x, y;
        
        allocation = get_allocation_box ();
        allocation.get_size (out width, out height);
        
        if (scroll_mode == ScrollMode.X) {
            x = scroll_to_x;
            y = 0.0f;
        }
        else {
            y = scroll_to_y;
            x = 0.0f;
        }
        
        Cogl.clip_push_rectangle (x, y, x + width, y + height);
    }
    
    public override void paint () {
        push_clip ();
        base.paint ();
        Cogl.clip_pop ();
    }

    public override void pick (Clutter.Color pick_color) {
        Clutter.Actor child;
        
        push_clip ();
        base.pick (pick_color);
        /* FIXME - this has to go away when we remove the vfunc check inside
         * the ClutterActor::pick default implementation
         */
        for (child = this.get_first_child (); child != null;
             child = child.get_next_sibling ()) {
                child.paint ();
        }
        Cogl.clip_pop ();
    }

    public override void apply_transform (ref Cogl.Matrix matrix) {
        base.apply_transform (ref matrix);
        float x_factor, y_factor;
        
        if (scroll_mode == ScrollMode.X) {
            x_factor = -scroll_to_x;
            y_factor = 0.0f;
        }
        else {
            y_factor = -scroll_to_y;
            x_factor = 0.0f;
        }
        matrix.translate (x_factor, y_factor, 0.0f);
    }

    private void set_scroll_to_internal (float x, float y) {
        if (x == scroll_to_x && y == scroll_to_y)
            return;
            
        scroll_to_y = y;
        scroll_to_x = x;
        queue_redraw ();
    }

    public void scroll_to_point (float x, float y) {
        //TODO ANIMATION STUFFS here?
        set_scroll_to_internal (x, y);
    }

}


private class Journal.ClutterVTL : Box {
    public ScrollableViewport viewport;
    public Clutter.Actor container;
    
    private ActivityModel model;
    private App app;
    private Clutter.Stage stage;
    private VTimeline timeline;
    private Scrollbar scrollbar;
    private TimelineNavigator vnav;
    
    private OSDLabel osd_label;
    private LoadingActor loading;
    
    private Gee.HashMap<string, int> y_positions;
    
    //Position and type of last drawn bubble
    private int last_y_position;
    private int last_type;
    //Last position visible (utilized for scrolling).
    private float last_y_visible;
    
    //Date to jump when we have loaded new events
    private DateTime? date_to_jump;
    
    private bool on_loading;

    public ClutterVTL (App app){
        Object (orientation: Orientation.HORIZONTAL, spacing : 0);
        this.model = new ActivityModel ();
        this.app = app;
        var embed = new GtkClutter.Embed ();
        this.stage = embed.get_stage () as Clutter.Stage;
        this.stage.set_color (Utils.gdk_rgba_to_clutter_color (Utils.get_journal_bg_color ()));
        y_positions = new Gee.HashMap<string, int> ();
        
        last_y_position = 50;
        last_type = 0;
        last_y_visible = 0;
        date_to_jump = null;
        on_loading = false;
        
        viewport = new ScrollableViewport ();
        viewport.scroll_mode = ScrollMode.Y;
        viewport.add_constraint (new Clutter.BindConstraint (stage, Clutter.BindCoordinate.WIDTH, 0));
        viewport.add_constraint (new Clutter.BindConstraint (stage, Clutter.BindCoordinate.HEIGHT, 0));

        container = new Clutter.Actor ();
        container.set_reactive (true);
        viewport.add_actor (container);
        container.add_constraint (new Clutter.BindConstraint (stage, Clutter.BindCoordinate.WIDTH, 0));
        
        //Timeline
        timeline = new VTimeline ();
        //timeline.add_constraint (new Clutter.BindConstraint (viewport, Clutter.BindCoordinate.HEIGHT, 0));
        timeline.add_constraint (new Clutter.AlignConstraint (stage, Clutter.AlignAxis.X_AXIS, 0.5f));
        
        container.add_actor (timeline);
        container.scroll_event.connect ( (e) => {
        
        var direction = e.direction;
        var offset = (float)scrollbar.adjustment.step_increment;

        switch (direction)
        {
            case Clutter.ScrollDirection.UP:
                last_y_visible -= offset;
                last_y_visible = last_y_visible.clamp (0.0f, container.get_height () - stage.get_height ());
                if (last_y_visible != 0.0f)
                    scrollbar.move_slider (ScrollType.STEP_UP);
                break;
            case Clutter.ScrollDirection.DOWN:
                last_y_visible += offset;
                last_y_visible = last_y_visible.clamp (0.0f, container.get_height () - stage.get_height ());
                if (last_y_visible != container.get_height () - stage.get_height ())
                    scrollbar.move_slider (ScrollType.STEP_DOWN);
                break;

            /* we're only interested in up and down */
            case Clutter.ScrollDirection.LEFT:
            case Clutter.ScrollDirection.RIGHT:
            break;
       }
       
       viewport.scroll_to_point (0.0f, last_y_visible);
       return false;
       });
       
       stage.add_actor (viewport);
       
       Adjustment adj = new Adjustment (0, 0, 0, 0, 0, stage.height);
       scrollbar = new Scrollbar (Orientation.VERTICAL, adj);
       container.queue_relayout.connect (() => { 
           scrollbar.adjustment.upper = container.height;
           uint num_child = container.get_children ().length ();
           scrollbar.adjustment.step_increment = container.height / (num_child*10);
           scrollbar.adjustment.page_increment = container.height/ 10;
       });
       scrollbar.change_value.connect ((st, v) => { 
            this.on_scrollbar_scroll (); 
            return false;
       });
        
       vnav = new TimelineNavigator (Orientation.VERTICAL);
       vnav.go_to_date.connect ((date) => {this.jump_to_day (date);});

       this.pack_start (vnav, false, false, 0);
       this.pack_start (embed, true, true, 0);
       this.pack_start (scrollbar, false, false, 0);
       
       osd_label = new OSDLabel (stage);
       stage.add_actor (osd_label.actor);
        
       loading = new LoadingActor (this.app, stage);
       loading.start ();
       
       model.activities_loaded.connect ((dates_loaded)=> {
            load_activities (dates_loaded);
            loading.stop ();
       });
    }
    
    public void load_activities (Gee.ArrayList<string> dates_loaded) {
        Side side;
        float offset = 0;
        int last_actor_height = 0;
        foreach (string date in dates_loaded)
        {
          var list = model.activities.get (date);
          foreach (Gee.Map.Entry<string, Gee.List<GenericActivity>> day_entry in list.activities.entries)
          {
            foreach (GenericActivity activity in day_entry.value)
            {
            if (last_type % 2 == 0) 
                side = Side.RIGHT;
            else 
                side = Side.LEFT;
            
            RoundBox r = new RoundBox (side);
            RoundBoxContent rc = new RoundBoxContent (activity, null);
            r.add (rc);
            r.show_all ();
            
            if(y_positions.has_key (date) == false) {
                //Add a visual representation of the change of the day
                //Add a line
                Clutter.Actor day_line = new Clutter.Actor ();
                var color = Utils.get_timeline_bg_color ();
                Clutter.Color bgColor = Utils.gdk_rgba_to_clutter_color (color);
                day_line.background_color = bgColor.shade (1);
                day_line.add_constraint (new Clutter.BindConstraint (stage, Clutter.BindCoordinate.WIDTH, 0));
                day_line.set_height (2);
                day_line.opacity = 150;
                
                //Text's date
                Pango.FontDescription fd = Utils.get_default_font_description ();
                string text = Utils.get_start_of_the_day (activity.time).format (_("%A, %x"));
                Clutter.Text date_text = new Clutter.Text.with_text(null, text);
                date_text.font_description = fd;
                var attr_list = new Pango.AttrList ();
                int text_size = 11;
                var attr_s = new Pango.AttrSize (text_size * Pango.SCALE);
                attr_s.absolute = 1;
                attr_list.insert ((owned) attr_s);
                var desc = new Pango.FontDescription ();
                desc.set_weight (Pango.Weight.BOLD);
                var attr_f = new Pango.AttrFontDesc (desc);
                attr_list.insert ((owned) attr_f);
                date_text.attributes = attr_list;
                date_text.add_constraint (new Clutter.BindConstraint (day_line, Clutter.BindCoordinate.Y, -2));
                date_text.set_x (10);
                date_text.anchor_y = date_text.height;
                if (last_type % 2 == 0) 
                    //Means that the last bubble displayed is on the left
                    last_y_position += last_actor_height + text_size;
                else 
                    last_y_position += 20 + text_size;
                day_line.set_y (last_y_position);
                container.add_actor (day_line);
                container.add_actor (date_text);
                last_y_position += (int)(day_line.height + text_size);
                
                y_positions.set (date, (int)(day_line.y - text_size * 3));
            }

            GtkClutter.Actor actor = new GtkClutter.Actor.with_contents (r);
            /****TODO MOVE THIS WHOLE CODE IN A CLASS WRAPPING THE RoundBoxContent***/
            actor.reactive = true;
            if (last_type % 2 == 0) 
                actor.scale_center_x = actor.width;
                actor.enter_event.connect ((e) => {
                    double scale_x;
                    double scale_y;

                    actor.get_scale (out scale_x, out scale_y);

                    actor.animate (Clutter.AnimationMode.EASE_OUT_QUAD, 200,
                       "scale-x", scale_x * 1.05,
                       "scale-y", scale_y * 1.05);
            
                    return false;
            });
            actor.leave_event.connect ((e) => {
                actor.animate (Clutter.AnimationMode.EASE_OUT_QUAD, 200,
                       "scale-x", 1.0,
                       "scale-y", 1.0);
                return false;
            });
            
            actor.button_release_event.connect ((e) => {
                //TODO Improve here?
                actor.animate (Clutter.AnimationMode.EASE_OUT_QUAD, 200,
                       "scale-x", 1.0,
                       "scale-y", 1.0);
                try {
                    AppInfo.launch_default_for_uri (activity.uri, null);
                } catch (Error e) {
                    warning ("Error in launching: "+ activity.uri);
                }
                return false;
            }); 
            /****************************************************/
            container.add_actor (actor);
            if (last_type % 2 == 0)
                offset = -(5 + actor.get_width());
            else 
                offset = 5 + timeline.get_width ();
            actor.add_constraint (new Clutter.BindConstraint (timeline, Clutter.BindCoordinate.X, offset));  // timeline!
            actor.set_y (last_y_position);
            timeline.add_circle (last_y_position);
            //last_y_position +=  (int)actor.get_height() + 20; // padding TODO FIXME better algorithm here
            last_actor_height = (int)actor.get_height();
            if (last_type % 2 == 1) last_y_position += 20;
            else last_y_position +=  last_actor_height;
            last_type ++;
        }
       }
       }
       timeline.invalidate ();
       
       if (container.height <= stage.height)
            scrollbar.hide ();

       if(date_to_jump != null) {
            jump_to_day (date_to_jump);
            osd_label.hide ();
       }
    }
    
    public void jump_to_day (DateTime date) {
        int y = 0;
        string date_s = date.format("%Y-%m-%d");
        if (y_positions.has_key (date_s) == true) {
            y = this.y_positions.get (date_s);
            viewport.scroll_to_point (0.0f, y);
            scrollbar.adjustment.upper = container.height;
            scrollbar.adjustment.value = y;
            on_loading = false;
        }
        else {
            osd_label.set_message_and_show (_("Loading Activities..."));
            loading.start ();
            date_to_jump = date;
            model.load_activities (date);
            on_loading = true;
        }
    }
    
    public void on_scrollbar_scroll () {
        float y = (float)(scrollbar.adjustment.value);
        y = y.clamp (0.0f, container.get_height () - stage.get_height ());
        last_y_visible = y;
        viewport.scroll_to_point (0.0f, y);
        
        //FIXME
//        if (!on_loading && (y == (container.get_height () - stage.get_height ()))) {
//            //We can't scroll anymmore! Let's load another day!
//            on_loading = true;
//            osd_label.set_message_and_show (_("Loading Activities..."));
//            TimeVal tv;
//            DateTime new_date = app.backend.last_loaded_date.add_days (-1);
//            warning("aa"+new_date.to_string ());
//            date_to_jump = new_date;
//            new_date.to_timeval (out tv);
//            Date start_date = {};
//            start_date.set_time_val (tv);
//            app.backend.last_loaded_date.to_timeval (out tv);
//            Date end_date = {};
//            end_date.set_time_val (tv);
//            app.backend.load_events_for_date_range (start_date, end_date);
//        }
        
        //We are moving so we should highligth the right TimelineNavigator's label
        string final_key = "";
        int final_pos = 0;
        foreach (Gee.Map.Entry<string, int> entry in y_positions.entries) {
            if (entry.value <= (int)((y) + stage.height / 2) && entry.value > final_pos) {
                final_key = entry.key;
                final_pos = entry.value;
            }
        }
        vnav.highlight_date (final_key);
    }
}

private class Journal.ClutterHTL : Object {
    public Clutter.Actor viewport;
    
    private ActivityModel model;
    private App app;
    private Clutter.Stage stage;
    private Clutter.Actor timeline;
    private HTimeline timeline_gtk;
    
    private Gee.HashMap<string, int> x_positions;

    public ClutterHTL (App app, Clutter.Stage stage){
        this.model = new ActivityModel ();
        this.app = app;
        this.stage = stage;
        x_positions = new Gee.HashMap<string, int> ();


        model.activities_loaded.connect ((dates_loaded)=> {
            load_activities ();
        });

        viewport = new Clutter.Actor ();
        //viewport.set_clip_to_allocation (true);
        viewport.set_reactive (true);
        viewport.add_constraint (new Clutter.BindConstraint (stage, Clutter.BindCoordinate.HEIGHT, 0));
        
        //Timeline
        timeline_gtk = new HTimeline ();
        timeline = new GtkClutter.Actor.with_contents (timeline_gtk);
        timeline.width = 8000;
        //timeline.add_constraint (new Clutter.BindConstraint (viewport, Clutter.BindCoordinate.WIDTH, 0));
        timeline.add_constraint (new Clutter.AlignConstraint (stage, Clutter.AlignAxis.Y_AXIS, 0.5f));

        viewport.add_actor (timeline); 
        viewport.scroll_event.connect ( (e) => {
            
        var x = viewport.get_x ();
        var direction = e.direction;

        switch (direction)
        {
            case Clutter.ScrollDirection.RIGHT:
                x -= (float)(viewport.width * 0.1);
                break;
            case Clutter.ScrollDirection.LEFT:
                x += (float)(viewport.width * 0.1);
                break;

            /* we're only interested in right and left */
            case Clutter.ScrollDirection.UP:
            case Clutter.ScrollDirection.DOWN:
            break;
       }
       x = x.clamp (stage.get_width () - viewport.get_width (), 0.0f);
       /* animate the change to the scrollable's y coordinate */
       viewport.animate ( Clutter.AnimationMode.EASE_OUT_CUBIC,
                         150,
                         "x", x);
       return true;
       });
    }
    
    public void load_activities () {
        Gee.ArrayList<Zeitgeist.Event> all_activities= app.backend.all_activities;
        int i = 50;
        int type = 0;
        Side side;
        float offset = 0;
        GtkClutter.Actor actor = null;
        foreach (Zeitgeist.Event e in all_activities)
        {
            GenericActivity activity = ActivityFactory.get_activity_for_event (e);
            if (type % 2 == 0) 
                side = Side.BOTTOM;
            else 
                side = Side.TOP;
                
            RoundBox r = new RoundBox (side);
            RoundBoxContent rc = new RoundBoxContent (activity, 300);
            r.add (rc);
            r.show_all ();
            
            string date = Utils.get_start_of_the_day_string (activity.time);
            if(x_positions.has_key (date) == false)
                x_positions.set (date, i);

            actor = new GtkClutter.Actor.with_contents (r);
            viewport.add_actor (actor);
            if (type % 2 == 0)
                offset = -(5 + actor.get_height());
            else 
                offset = 5 + timeline.get_height ();
            actor.add_constraint (new Clutter.BindConstraint (timeline, Clutter.BindCoordinate.Y, offset));  // timeline!
            actor.set_x (i);
            timeline_gtk.add_circle (i);
            //i +=  (int)actor.get_height() + 20; // padding TODO FIXME better algorithm here
            if (type % 2 == 1) i += 20;
            else i +=  (int)actor.get_width();
            type ++;
        }
    }
    
    public void jump_to_day (DateTime date) {
        int x = 0;
        string date_s = date.format("%Y-%m-%d");
        if (x_positions.has_key (date_s) == true) 
            x = this.x_positions.get (date_s);
        else 
            //jump to TODAY (x == 0)
            warning ("Impossible to jump to this data...jumping to today");

         viewport.animate (Clutter.AnimationMode.EASE_OUT_CUBIC,
                          350,
                          "x", (float)(-x));
    }
}

//private class Journal.GtkVTL : Layout {
//    private ActivityModel model;
//    private App app;
//    private Gee.ArrayList<int> point_circle;
//    
//    private int total_height;
//    
//    //Timeline stuffs
//    private const int len_arrow = 20; // hardcoded
//    private const int arrow_origin = 30;
//    private const int timeline_width = 2;
//    private const int radius = 6;


//    public GtkVTL (App app){
//        this.model = new ActivityModel ();
//        this.app = app;
//        this.point_circle = new Gee.ArrayList<int> ();

//        this.get_style_context ().add_class ("timeline-gtk");
//        this.hexpand = true;
//        this.total_height = 0;
//        
//        this.realize.connect (() => {
//            this.setup_ui ();
//        });
//        
//       this.app.window.configure_event.connect (() => {
//            this.adjust_ui ();
//            return false;
//        });
//        
//        this.app.window.window_state_event.connect (() => {
//            this.adjust_ui ();
//            return false;
//        });
//        
//        app.backend.events_loaded.connect (() => {
//            load_events ();
//        });
//    }
//    
//    private void add_circle (int y) {
//        this.point_circle.add (y + arrow_origin - len_arrow / 2 + radius * 2 - 2); //?? why?
//    }
//    
//    public override bool draw (Cairo.Context ctx) {
//        var bg = this.get_style_context ().get_color (0);
//        Clutter.Color backgroundColor = Utils.gdk_rgba_to_clutter_color (bg);
//        var color = this.get_style_context ().get_border_color (0);
//        Clutter.Color circleColor = Utils.gdk_rgba_to_clutter_color (color);

//        Allocation allocation;
//        get_allocation (out allocation);
//        var width = allocation.width;
//        var height = allocation.height;
//        var cr = ctx;

//        ctx.save ();
//        //Draw the timeline
//        Clutter.cairo_set_source_color (cr, backgroundColor);
//        ctx.translate (width / 2 - timeline_width / 2, 0);
//        ctx.rectangle (0, 0, timeline_width, height);
//        ctx.fill ();
//        
//        //Draw circles
//        foreach (int y in point_circle) {
//            // Paint the border cirle to start with.
//            Clutter.cairo_set_source_color(cr, backgroundColor);
//            ctx.arc (timeline_width / 2, y, radius, 0, 2*Math.PI);
//            ctx.stroke ();
//            // Paint the colored cirle
//            Clutter.cairo_set_source_color(cr, circleColor);
//            ctx.arc (timeline_width / 2, y, radius - 1, 0, 2*Math.PI);
//            ctx.fill ();
//        }

//        ctx.restore ();
//        foreach (Widget child in this.get_children ())
//            this.propagate_draw(child, ctx);

//        return false;
//        }

//    public void load_events () {
//        Gee.ArrayList<Zeitgeist.Event> all_activities= app.backend.all_activities;
//        foreach (Zeitgeist.Event e in all_activities)
//        {
//            GenericActivity activity = new GenericActivity (e);
//            model.add_activity (activity);
//        }
//    }
//    
//    private void setup_ui () {
//        int i = 50;
//        int type = 0;
//        Side side;
//        float offset = 0;
//        foreach (GenericActivity activity in model.activities)
//        {
//            if (type % 2 == 0) 
//                side = Side.RIGHT;
//            else 
//                side = Side.LEFT;
//                
//            RoundBox r = new RoundBox (side);
//            RoundBoxContent rc = new RoundBoxContent (activity, null);
//            r.add (rc);
//            
//            int r_height, r_width, width;
//            r.get_preferred_width (null, out r_width);
//            r.get_preferred_height_for_width (r_width, null, out r_height);
//            width = get_allocated_width ();
//            
//            if (type % 2 == 0)
//                offset = (int)width / 2 + timeline_width / 2 - radius - 5 - r_width;
//            else 
//                offset = (int)width / 2 + timeline_width / 2 + radius + 5;

//            this.add_circle (i);
//            this.put(r, (int) offset, i);
//            //i +=  (int)actor.get_height() + 20; // padding TODO FIXME better algorithm here
//            if (type % 2 == 1) i += 20;
//            else {
//                i += r_height;
//                total_height += r_height ;
//            }
//            type ++;
//        }
//        this.show_all ();
//        
//        adjust_ui ();
//    }
//    
//    private void adjust_ui (){
//        int width = get_allocated_width ();
//        int i = 50;
//        int offset = 0;
//        foreach (Widget child in this.get_children ()) {
//            int r_width = child.get_allocated_width ();
//            int r_height = child.get_allocated_height ();
//            Side side = ((RoundBox)child).arrow_side;
//            if (side == Side.RIGHT) 
//                offset = (int)width / 2 + timeline_width / 2 - radius - 5 - r_width;
//            else
//                offset = (int)width / 2 + timeline_width / 2 + radius + 5; 
//            this.move (child, offset, i);
//            
//            if (side == Side.RIGHT) 
//                i+= r_height;
//            else
//                i+= 20; 
//            
//            total_height += r_height;
//        }
//    }
//    
//   public override void get_preferred_height (out int minimum_height, out int natural_height) {
//       minimum_height = natural_height = this.total_height;
//   }
//}

private class Journal.VTimeline : Clutter.CairoTexture {

    private Gee.ArrayList<int> point_circle;
    private const int len_arrow = 20; // hardcoded
    private const int arrow_origin = 30;
    private const int timeline_width = 2;
    private const int radius = 6;
    
    public VTimeline () {
        this.point_circle = new Gee.ArrayList<int> ();
        this.auto_resize = true;
        invalidate ();
    }
    
    public void add_circle (int y) {
        this.point_circle.add (y + arrow_origin + len_arrow /2 );
    }
    
    public override bool draw (Cairo.Context ctx) {
        var bg =  Utils.get_timeline_bg_color ();
        Clutter.Color backgroundColor = Utils.gdk_rgba_to_clutter_color (bg);
        var color = Utils.get_timeline_circle_color ();
        Clutter.Color circleColor = Utils.gdk_rgba_to_clutter_color (color);

        var cr = ctx;
        this.clear ();
        uint height, width;
        get_surface_size (out width, out height);
        //Draw the timeline
        Clutter.cairo_set_source_color(cr, backgroundColor);
        ctx.rectangle (radius, 0, timeline_width , height);
        ctx.fill ();
        
        //Draw circles
        foreach (int y in point_circle) {
            // Paint the border cirle to start with.
            Clutter.cairo_set_source_color(cr, backgroundColor);
            ctx.arc (radius + timeline_width / 2 , y, radius, 0, 2*Math.PI);
            ctx.stroke ();
            // Paint the colored cirle to start with.
            Clutter.cairo_set_source_color(cr, circleColor);
            ctx.arc (radius + timeline_width / 2, y, radius - 1, 0, 2*Math.PI);
            ctx.fill ();
        }

        return true;
        }
        
  
   public override void get_preferred_width (float for_height,out float min_width, out float nat_width) {
       nat_width = min_width = 2 * radius + timeline_width;
   }
   
   public override void get_preferred_height (float for_width,out float min_height, out float nat_height) {
       nat_height = min_height = 8000;
   }

}

private class Journal.HTimeline : DrawingArea {

    private Gee.ArrayList<int> point_circle;
    private const int len_arrow = 20; // hardcoded
    private const int arrow_origin = 30;
    private const int timeline_height = 2;
    private const int radius = 6;
    
    public HTimeline () {
        this.point_circle = new Gee.ArrayList<int> ();
    }
    
    public void add_circle (int x) {
        this.point_circle.add (x + arrow_origin + len_arrow / 2); //?? why?
    }
    
    public override bool draw(Cairo.Context ctx) {
        var bg = Utils.get_timeline_bg_color ();
        Clutter.Color backgroundColor = Utils.gdk_rgba_to_clutter_color (bg);
        var color = Utils.get_timeline_circle_color ();
        Clutter.Color circleColor = Utils.gdk_rgba_to_clutter_color (color);

        Allocation allocation;
        get_allocation (out allocation);
        var width = allocation.width;
        var cr = ctx;
        ctx.set_source_rgba (1.0, 1.0, 1.0, 0.0);
        // Paint the entire window transparent to start with.
        ctx.set_operator (Cairo.Operator.SOURCE);
        ctx.paint ();
        //Draw the timeline
        Clutter.cairo_set_source_color(cr, backgroundColor);
        ctx.rectangle (0, radius, width, timeline_height);
        ctx.fill ();

        //Draw circles
        foreach (int x in point_circle) {
            // Paint the border cirle to start with.
            Clutter.cairo_set_source_color(cr, backgroundColor);
            ctx.arc (x, radius + timeline_height / 2, radius, 0, 2*Math.PI);
            ctx.stroke ();
            // Paint the colored cirle to start with.
            Clutter.cairo_set_source_color(cr, circleColor);
            ctx.arc (x, radius + timeline_height / 2, radius - 1, 0, 2*Math.PI);
            ctx.fill ();
        }

        return false;
    }
    
    public override Gtk.SizeRequestMode get_request_mode () {
       return SizeRequestMode.WIDTH_FOR_HEIGHT;
   }

   public override void get_preferred_height (out int min_height, out int nat_height) {
       nat_height = min_height = 2 * radius + timeline_height;
   }

}

private class Journal.RoundBox : Button {
    private Side _arrowSide;
    private int _arrowOrigin = 30; 
    private bool highlight;
    
    public static int BORDER_WIDTH = 10;
    
    
    public Side arrow_side {
        get { return _arrowSide; }
    }

    public RoundBox (Side side) {
       this._arrowSide = side;
       this.border_width = BORDER_WIDTH;
       this.highlight = false;
       this.get_style_context ().add_class ("roundbox");

       add_events (Gdk.EventMask.ENTER_NOTIFY_MASK|
                   Gdk.EventMask.LEAVE_NOTIFY_MASK);
                   
    }

    public override bool draw (Cairo.Context ctx) {
        //Code ported from GNOME shell's box pointer
        var borderWidth = 2;
        var baseL = 20; //lunghezza base freccia
        var rise = 10;  //altezza base freccia
        var borderRadius = 10;

        var halfBorder = borderWidth / 2;
        var halfBase = Math.floor(baseL/2);
        
        Clutter.Color borderColor;
        if (!highlight) {
            var bc = this.get_style_context ().get_border_color (0);
            borderColor = Utils.gdk_rgba_to_clutter_color (bc);
        }
        else {
            borderColor = {150, 220, 0, 255};
        }
        var bg = this.get_style_context ().get_background_color (0);
        Clutter.Color backgroundColor = Utils.gdk_rgba_to_clutter_color(bg);

        Allocation allocation;
        get_allocation (out allocation);
        var width = allocation.width;
        var height = allocation.height;
        var boxWidth = width;
        var boxHeight = height;

        if (this._arrowSide == Side.TOP || this._arrowSide == Side.BOTTOM) {
            boxHeight -= rise;
        } else {
            boxWidth -= rise;
        }
        var cr = ctx;
        cr.save ();
        cr.set_source_rgba (0.0, 0.0, 0.0, 0.0);
        cr.set_operator (Cairo.Operator.SOURCE);
        cr.paint ();
        cr.restore ();
        Clutter.cairo_set_source_color(cr, borderColor);

        // Translate so that box goes from 0,0 to boxWidth,boxHeight,
        // with the arrow poking out of that
        if (this._arrowSide == Side.TOP) {
            cr.translate(0, rise);
        } else if (this._arrowSide == Side.LEFT) {
            cr.translate(rise, 0);
        }

        var x1 = halfBorder;
        var y1 = halfBorder;
        var x2 = boxWidth - halfBorder;
        var y2 = boxHeight - halfBorder;

        cr.move_to(x1 + borderRadius, y1);
        if (this._arrowSide == Side.TOP) {
            if (this._arrowOrigin < (x1 + (borderRadius + halfBase))) {
                cr.line_to(this._arrowOrigin, y1 - rise);
                cr.line_to(Math.fmax(x1 + borderRadius, this._arrowOrigin) + halfBase, y1);
            } else if (this._arrowOrigin > (x2 - (borderRadius + halfBase))) {
                cr.line_to(Math.fmin(x2 - borderRadius, this._arrowOrigin) - halfBase, y1);
                cr.line_to(this._arrowOrigin, y1 - rise);
            } else {
                cr.line_to(this._arrowOrigin - halfBase, y1);
                cr.line_to(this._arrowOrigin, y1 - rise);
                cr.line_to(this._arrowOrigin + halfBase, y1);
            }
        }

        cr.line_to(x2 - borderRadius, y1);

        // top-right corner
        cr.arc(x2 - borderRadius, y1 + borderRadius, borderRadius,
               3*Math.PI/2, Math.PI*2);

        if (this._arrowSide == Side.RIGHT) {
            if (this._arrowOrigin < (y1 + (borderRadius + halfBase))) {
                cr.line_to(x2 + rise, this._arrowOrigin);
                cr.line_to(x2, Math.fmax(y1 + borderRadius, this._arrowOrigin) + halfBase);
            } else if (this._arrowOrigin > (y2 - (borderRadius + halfBase))) {
                cr.line_to(x2, Math.fmin(y2 - borderRadius, this._arrowOrigin) - halfBase);
                cr.line_to(x2 + rise, this._arrowOrigin);
            } else {
                cr.line_to(x2, this._arrowOrigin - halfBase);
                cr.line_to(x2 + rise, this._arrowOrigin);
                cr.line_to(x2, this._arrowOrigin + halfBase);
            }
        }

        cr.line_to(x2, y2 - borderRadius);

        // bottom-right corner
        cr.arc(x2 - borderRadius, y2 - borderRadius, borderRadius,
               0, Math.PI/2);

        if (this._arrowSide == Side.BOTTOM) {
            if (this._arrowOrigin < (x1 + (borderRadius + halfBase))) {
                cr.line_to(Math.fmax(x1 + borderRadius, this._arrowOrigin) + halfBase, y2);
                cr.line_to(this._arrowOrigin, y2 + rise);
            } else if (this._arrowOrigin > (x2 - (borderRadius + halfBase))) {
                cr.line_to(this._arrowOrigin, y2 + rise);
                cr.line_to(Math.fmin(x2 - borderRadius, this._arrowOrigin) - halfBase, y2);
            } else {
                cr.line_to(this._arrowOrigin + halfBase, y2);
                cr.line_to(this._arrowOrigin, y2 + rise);
                cr.line_to(this._arrowOrigin - halfBase, y2);
            }
        }

        cr.line_to(x1 + borderRadius, y2);

        // bottom-left corner
        cr.arc(x1 + borderRadius, y2 - borderRadius, borderRadius,
               Math.PI/2, Math.PI);

        if (this._arrowSide == Side.LEFT) {
            if (this._arrowOrigin < (y1 + (borderRadius + halfBase))) {
                cr.line_to(x1, Math.fmax(y1 + borderRadius, this._arrowOrigin) + halfBase);
                cr.line_to(x1 - rise, this._arrowOrigin);
            } else if (this._arrowOrigin > (y2 - (borderRadius + halfBase))) {
                cr.line_to(x1 - rise, this._arrowOrigin);
                cr.line_to(x1, Math.fmin(y2 - borderRadius, this._arrowOrigin) - halfBase);
            } else {
                cr.line_to(x1, this._arrowOrigin + halfBase);
                cr.line_to(x1 - rise, this._arrowOrigin);
                cr.line_to(x1, this._arrowOrigin - halfBase);
            }
        }

        cr.line_to(x1, y1 + borderRadius);

        // top-left corner
        cr.arc(x1 + borderRadius, y1 + borderRadius, borderRadius,
               Math.PI, 3*Math.PI/2);

        Clutter.cairo_set_source_color(cr, backgroundColor);
        cr.fill_preserve();
        Clutter.cairo_set_source_color(cr, borderColor);
        cr.set_line_width(borderWidth);
        cr.stroke();

        this.propagate_draw (this.get_child (), cr);

        return false;
    }
    
    public override bool enter_notify_event (Gdk.EventCrossing  event) {
        highlight = true;
        queue_draw ();
        return true;
    }
    
    public override bool leave_notify_event (Gdk.EventCrossing  event) {
        highlight = false;
        queue_draw ();
        return true;
    }

   public override Gtk.SizeRequestMode get_request_mode () {
       return SizeRequestMode.HEIGHT_FOR_WIDTH;
   }
  
   public override void get_preferred_width (out int min_width, out int nat_width) {
       get_child ().get_preferred_width(out min_width, out nat_width);
       min_width += BORDER_WIDTH * 2 ;
       nat_width += BORDER_WIDTH * 2 ;
   }

   public override void get_preferred_height_for_width (int  width,
                                                       out int min_height,
                                                       out int nat_height) {
       get_child ().get_preferred_height_for_width (width, out min_height, out nat_height);
       min_height += BORDER_WIDTH * 2 ;
       nat_height += BORDER_WIDTH * 2;
   }
}

private class Journal.RoundBoxContent : DrawingArea {

    private GenericActivity activity;
    private Gdk.Pixbuf thumb;
    
    private int width;
    private const int DEFAULT_WIDTH = 400;
    private const int xy_padding = 5;
    
    private bool is_thumb;
    
    private Pango.Layout title_layout;
    private Pango.Layout time_layout;

    public RoundBoxContent (GenericActivity activity, int? width) {
        this.activity = activity;
        this.thumb = activity.type_icon;
        this.is_thumb = false;
        this.width = DEFAULT_WIDTH;
        
        if (width != null)
            this.width = width;

        // Enable the events you wish to get notified about.
        add_events (Gdk.EventMask.BUTTON_RELEASE_MASK);
        
        activity.thumb_loaded.connect (() => {
                  if (activity.thumb_icon != null) {
                    thumb = activity.thumb_icon;
                    is_thumb = true;
                    //resize and redraw but now let's use the thumb
                    queue_resize (); 
                   }
        });
    }

    /* Widget is asked to draw itself */
    public override bool draw (Cairo.Context cr) { 
        int width = get_allocated_width ();
        int height = get_allocated_height ();

        // Draw pixbuf
        var x_pix = 0;
        var y_pix = 0;
        var pad = 0;
        if (is_thumb == true) {
            x_pix = RoundBox.BORDER_WIDTH;
            pad = xy_padding + x_pix;
            y_pix = RoundBox.BORDER_WIDTH;
        }
        cr.set_operator (Cairo.Operator.OVER);
        if (thumb != null)  {
            y_pix = (height - thumb.height) / 2;
            Gdk.cairo_set_source_pixbuf(cr, thumb, x_pix, y_pix);
            cr.rectangle (x_pix, y_pix, thumb.width, thumb.height);
            cr.fill();
        }
        
        //Draw title
        Pango.Rectangle rect;
        title_layout.get_extents (null, out rect);
        this.get_style_context ().render_layout (cr,
               x_pix + thumb.width + pad,
               (height - rect.height/ Pango.SCALE) / 2,
               title_layout);
        
        //Draw timestamp
        title_layout.get_extents (null, out rect);
        this.get_style_context ().render_layout (cr,
               x_pix + thumb.width + pad , //width - rect.width / Pango.SCALE do not work..why?
               height - rect.height / Pango.SCALE ,
               time_layout);

        return false;
    }
    
    private void create_title_layout (int width) {
        Pango.Rectangle rect;
        int f_width, text_width;
        var layout = this.create_pango_layout ("");
        layout.set_text(activity.title , -1);

        var attr_list = new Pango.AttrList ();

        var attr_s = new Pango.AttrSize (12 * Pango.SCALE);
		attr_s.absolute = 1;
		attr_s.start_index = 0;
		attr_s.end_index = attr_s.start_index + activity.title.length;
		attr_list.insert ((owned) attr_s);

		var desc = new Pango.FontDescription ();
		desc.set_weight (Pango.Weight.BOLD);
		var attr_f = new Pango.AttrFontDesc (desc);
		attr_list.insert ((owned) attr_f);
		
		layout.set_ellipsize (Pango.EllipsizeMode.END);
        //layout.set_wrap (Pango.WrapMode.WORD_CHAR);
		
		layout.set_attributes (attr_list);
        layout.get_extents (null, out rect);
        
        var pad = xy_padding;
        if (is_thumb == true)
            pad += RoundBox.BORDER_WIDTH;
        text_width = rect.width;
        var p_width = (width - pad - thumb.width) * Pango.SCALE;
        f_width = int.min (p_width, text_width);
        layout.set_width (f_width);
        
        this.title_layout = layout;
   }
   
   private void create_time_layout (int width) {
        var layout = this.create_pango_layout ("");
        DateTime date = new DateTime.from_unix_utc (activity.time / 1000).to_local ();
        string date_s = date.format ("%Y-%m-%d %H:%M");
        layout.set_text (date_s, -1);

        var attr_list = new Pango.AttrList ();

        var attr_s = new Pango.AttrSize (8 * Pango.SCALE);
		attr_s.absolute = 1;
		attr_s.start_index = 0;
		attr_s.end_index = attr_s.start_index + date_s.length;
		attr_list.insert ((owned) attr_s);

		var desc = new Pango.FontDescription ();
		desc.set_style (Pango.Style.ITALIC);
		var attr_f = new Pango.AttrFontDesc (desc);
		attr_list.insert ((owned) attr_f);
		
		//layout.set_ellipsize (Pango.EllipsizeMode.END);
        layout.set_wrap (Pango.WrapMode.WORD_CHAR);
        layout.set_attributes (attr_list);

        this.time_layout = layout;
   }
   
    public override bool button_release_event (Gdk.EventButton event) {
        //TODO Improve here?
        try {
            AppInfo.launch_default_for_uri (this.activity.uri, null);
        } catch (Error e) {
            warning ("Error in launching: "+ this.activity.uri);
        }
        return false;
    }
    
   public override Gtk.SizeRequestMode get_request_mode () {
       return SizeRequestMode.HEIGHT_FOR_WIDTH;
   }
  
   public override void get_preferred_width (out int minimum_width, out int natural_width) {
      minimum_width = natural_width = this.width;
   }

   public override void get_preferred_height_for_width (int  width,
                                                       out int minimum_height,
                                                       out int natural_height) {
       var x_pix = 0;
       if (is_thumb == true)
           x_pix = RoundBox.BORDER_WIDTH * 2;
           
       create_title_layout (width - x_pix);
       create_time_layout (width - x_pix);
       Pango.Rectangle r, r2;
       time_layout.get_extents (null, out r);
       title_layout.get_extents (null, out r2);

       minimum_height = natural_height = int.max (thumb.height, 
                                     (int)(r.height + r2.height) / Pango.SCALE);
   }
}
