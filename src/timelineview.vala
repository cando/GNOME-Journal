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

private class Journal.CustomContainer : Clutter.Actor {
    public CustomContainer () {
        Object ();
        this.reactive = true;
    }
    
    public override void allocate (Clutter.ActorBox box, Clutter.AllocationFlags flags) {
        base.allocate (box, flags);
        float width, height;
        float x, y;
        var child_box = Clutter.ActorBox ();
        foreach (Clutter.Actor child in get_children ()) {
            RoundBox r = child as RoundBox;
            if (r == null) {
                //Timelines and dates
                child.get_preferred_size (null, null, out width, out height);
                x = child.get_x ();
                y = child.get_y ();
                child_box.x1 = x;
                child_box.x2 = x + width;
                child_box.y1 = y;
                child_box.y2 = y + height;
            }
            else {

            r.get_preferred_size (null, null, out width, out height);
            y = r.get_y ();

            if (width > (box.get_width () / 3)) {
                width = box.get_width () / 3;
            }
            if (r.arrow_side == Side.RIGHT) 
                x = box.get_width () / 2  - 10 - width;
            else 
                x = box.get_width () / 2  + 10;

            child_box.x1 = x;
            child_box.x2 = x + width;
            child_box.y1 = y;
            child_box.y2 = y + height;
            }
            
            child.allocate (child_box, flags);
        }
    }
}


private class Journal.ClutterVTL : Box {
    public ScrollableViewport viewport;
    public CustomContainer container;
    
    private ActivityModel model;
    private App app;
    private Clutter.Stage stage;
    private VTimeline timeline;
    private TimelineTexture timeline_texture;
    private Scrollbar scrollbar;
    private TimelineNavigator vnav;
    
    private OSDLabel osd_label;
    private LoadingActor loading;
    
    private Gee.Map<string, int> y_positions;
    
    //Position and type of last drawn bubble
    private int last_y_position;
    private int last_type;
    //Last position visible (utilized for scrolling).
    private float last_y_visible;
    private int last_y_texture;
    
    //Date to jump when we have loaded new events
    private DateTime? date_to_jump;
    
    private bool on_loading;

    public ClutterVTL (App app){
        Object (orientation: Orientation.HORIZONTAL, spacing : 0);
        this.model = new ActivityModel ();
        this.app = app;
        var embed = new GtkClutter.Embed ();
        this.stage = embed.get_stage () as Clutter.Stage;
        this.stage.set_background_color (Utils.gdk_rgba_to_clutter_color (
                                         Utils.get_journal_bg_color ()));
        y_positions = new Gee.HashMap<string, int> ();
        
        last_y_position = 50;
        last_type = 0;
        last_y_visible = 0;
        last_y_texture = 0;
        date_to_jump = null;
        on_loading = false;
        
        viewport = new ScrollableViewport ();
        viewport.scroll_mode = ScrollMode.Y;
        viewport.add_constraint (new Clutter.BindConstraint (stage, Clutter.BindCoordinate.WIDTH, 0));
        viewport.add_constraint (new Clutter.BindConstraint (stage, Clutter.BindCoordinate.HEIGHT, 0));

        container = new CustomContainer ();
        viewport.add_actor (container);
        container.set_reactive (true);
        container.add_constraint (new Clutter.BindConstraint (stage, Clutter.BindCoordinate.WIDTH, 0));
        
        //Timeline
        timeline = new VTimeline ();
        timeline_texture = timeline.get_texture (0);
        timeline_texture.y = 0;
        timeline_texture.add_constraint (new Clutter.AlignConstraint (
                                        stage, Clutter.AlignAxis.X_AXIS, 0.5f));
        container.add_child (timeline_texture);

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
        int last_actor_height = 0;
        //first texture
        var timeline_texture = timeline.get_texture (last_y_texture);
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
                string text = Utils.get_start_of_the_day (activity.time).format (_("%A, %x"));
                Clutter.Text date_text = new Clutter.Text.with_text (null, text);
                var attr_list = new Pango.AttrList ();
                attr_list.insert (Pango.attr_scale_new (Pango.Scale.MEDIUM));
                attr_list.insert (Pango.attr_weight_new (Pango.Weight.BOLD));
                date_text.attributes = attr_list;
                date_text.add_constraint (new Clutter.BindConstraint (day_line, Clutter.BindCoordinate.Y, -2));
                date_text.set_x (10);
                date_text.anchor_y = date_text.height;
                var text_size = 10;
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
            //Add the timeline
            int limit = last_y_texture + timeline.MAXIMUM_TEXTURE_LENGHT;
            if (last_y_position >= limit) {
                int position;
                timeline_texture = timeline.get_next_texture (out position);
                timeline_texture.y = position;
                timeline_texture.add_constraint (new Clutter.AlignConstraint (
                                        stage, Clutter.AlignAxis.X_AXIS, 0.5f));
                container.add_child (timeline_texture);
                last_y_texture = position;
            }
            Clutter.Actor content = activity.actor;
            RoundBox actor = new RoundBox (side, content.width, content.height);
            actor.add_content (content);

            /****TODO MOVE THIS WHOLE CODE IN A CLASS WRAPPING THE RoundBoxContent***/
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
            actor.set_y (last_y_position);
            container.add_child (actor);
            timeline.add_circle (last_y_position);
            //last_y_position +=  (int)actor.get_height() + 20; // padding TODO FIXME better algorithm here
            last_actor_height = (int)actor.get_height();
            if (last_type % 2 == 1) last_y_position += 20;
            else last_y_position +=  last_actor_height;
            last_type ++;
        }
       }
       }
       
       foreach (TimelineTexture tex in timeline.texture_buffer.values) 
            tex.invalidate ();

       if (container.height <= stage.height)
            scrollbar.hide ();

       if(date_to_jump != null) {
            jump_to_day (date_to_jump);
            osd_label.hide ();
       }
       
       //FIXME
       scrollbar.adjustment.upper = last_y_position + last_actor_height;
       uint num_child = container.get_children ().length ();
       scrollbar.adjustment.step_increment = scrollbar.adjustment.upper / (num_child*10);
       scrollbar.adjustment.page_increment = scrollbar.adjustment.upper / 10;
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
            int current_value = entry.value;
            if (current_value <= (int)((y) + stage.height / 2) && current_value > final_pos) {
                final_key = entry.key;
                final_pos = current_value;
            }
        }
        vnav.highlight_date (final_key);
    }
}

private class Journal.TimelineTexture: Clutter.CairoTexture {
        private Gee.List<int> point_circle;
        private const int len_arrow = 20; // hardcoded
        private const int arrow_origin = 30;
        private const int timeline_width = 2;
        private const int radius = 6;
        
        private int exceed = 0;
        public TimelineTexture () {
            this.point_circle = new Gee.ArrayList<int> ();
            this.auto_resize = true;
            invalidate ();
        }
        
        public int add_circle (int y) {
            int real_y = y + arrow_origin;
            this.point_circle.add (real_y);
            if (real_y >= VTimeline.MAXIMUM_TEXTURE_LENGHT) {
                //We enlarge the texture to fit the circle
                exceed = real_y - VTimeline.MAXIMUM_TEXTURE_LENGHT + radius + 2;
                return exceed;
            }

            return 0;
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
        nat_height = min_height = VTimeline.MAXIMUM_TEXTURE_LENGHT + exceed;
    }
}

private class Journal.VTimeline : Object {
    public const int MAXIMUM_TEXTURE_LENGHT = 512;
    
    private Gee.List<int> point_circle;
    //Key: Y position, Value: TimelineTexture
    public Gee.Map<int, TimelineTexture> texture_buffer{
        get; private set;
    }
    
    private int current_key;
    private int next_texture;
    
    public VTimeline () {
        this.point_circle = new Gee.ArrayList<int> ();
        this.texture_buffer = new Gee.HashMap<int, TimelineTexture> ();
        //Add a first texture
        this.texture_buffer.set (0, new TimelineTexture ());
        current_key = 0;
        next_texture = -1;
    }
    
    public void add_circle (int y) {
        var limit = MAXIMUM_TEXTURE_LENGHT + current_key;
        if (y >= limit) {
            this.texture_buffer.set (limit, new TimelineTexture ());
            current_key = limit;
        }
        var texture = texture_buffer.get (current_key);
        int exceed;
        if ((exceed = texture.add_circle (y - current_key)) > 0) {
            var new_texture = new TimelineTexture ();
            next_texture = current_key = limit + exceed; 
            this.texture_buffer.set (current_key, new_texture);
        }
    }
    
    public TimelineTexture get_texture (int key) {
        if (!texture_buffer.has_key (key)) {
            texture_buffer.set (key, new TimelineTexture ());
            current_key = key;
        }
        return texture_buffer.get (key);
    }
    
    public TimelineTexture get_next_texture (out int position) {
        if (next_texture != -1) {
            position = next_texture;
            next_texture = -1;
            return texture_buffer.get (position);
        }
            
        int key = current_key + MAXIMUM_TEXTURE_LENGHT;
        if (!texture_buffer.has_key (key)) {
            texture_buffer.set (key, new TimelineTexture ());
            current_key = key;
        }
        
        position = current_key;
        return texture_buffer.get (key);
    }
}

private class Journal.RoundBox : Clutter.Actor {
    private Side _arrowSide;
    private int _arrowOrigin = 30; 
    private int border_width;
    
    public static int BORDER_WIDTH = 10;
    
    private Clutter.Canvas canvas;
    private Clutter.Actor content_actor;

    public Side arrow_side {
        get { return _arrowSide; }
    }

    private Clutter.BinLayout box;
    public RoundBox (Side side, float width, float height) {
       this._arrowSide = side;
       this.border_width = BORDER_WIDTH;
       this.reactive = true;
       box = new Clutter.BinLayout (Clutter.BinAlignment.CENTER, 
                                    Clutter.BinAlignment.CENTER);
       set_layout_manager (box);
       
       this.canvas = new Clutter.Canvas ();
       canvas.draw.connect ((cr, w, h) => { return paint_canvas (cr, w, h); });
       canvas.set_size ((int)width + BORDER_WIDTH * 2, 
                        (int)height + BORDER_WIDTH * 2);
       var canvas_box = new Clutter.Actor ();
       canvas_box.set_size ((int)width + BORDER_WIDTH * 2,
                            (int)height + BORDER_WIDTH * 2);
       canvas_box.set_content (canvas);
       this.allocation_changed.connect ((box, f) => {
            canvas.set_size ((int)box.get_width (), (int) box.get_height ());
       });
       this.add_child (canvas_box);
    }

    private bool paint_canvas (Cairo.Context ctx, int width, int height) {
        //Code ported from GNOME shell's box pointer
        var borderWidth = 2;
        var baseL = 20; //lunghezza base freccia
        var rise = 10;  //altezza base freccia
        var borderRadius = 5;

        var halfBorder = borderWidth / 2;
        var halfBase = Math.floor(baseL/2);
        
        var bg =  Utils.get_roundbox_bg_color ();
        Clutter.Color backgroundColor = Utils.gdk_rgba_to_clutter_color (bg);
        var color = Utils.get_roundbox_border_color ();
        Clutter.Color borderColor = Utils.gdk_rgba_to_clutter_color (color);

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

        return true;
    }
    
    public void add_content (Clutter.Actor content) {
        this.content_actor = content;
        this.add_child (content);
    }
    public override void get_preferred_width (float for_height,out float min_width, out float nat_width) {
        float min_width_t, nat_width_t;
        nat_width = min_width = 0;
        if (content_actor != null) {
            content_actor.get_preferred_width (-1, out min_width_t, out nat_width_t);
            nat_width = nat_width_t + 2 * BORDER_WIDTH;
            min_width = min_width_t + 2 * BORDER_WIDTH;
        }
    }
}

//private class Journal.RoundBoxContent : DrawingArea {

//    private GenericActivity activity;
//    private Gdk.Pixbuf thumb;
//    
//    private int width;
//    private const int DEFAULT_WIDTH = 400;
//    private const int xy_padding = 5;
//    
//    private bool is_thumb;
//    
//    private Pango.Layout title_layout;
//    private Pango.Layout time_layout;

//    public RoundBoxContent (GenericActivity activity, int? width) {
//        this.activity = activity;
//        this.thumb = activity.type_icon;
//        this.is_thumb = false;
//        this.width = DEFAULT_WIDTH;
//        
//        if (width != null)
//            this.width = width;

//        // Enable the events you wish to get notified about.
//        add_events (Gdk.EventMask.BUTTON_RELEASE_MASK);

//    }

//    /* Widget is asked to draw itself */
//    public override bool draw (Cairo.Context cr) { 
//        int width = get_allocated_width ();
//        int height = get_allocated_height ();

//        // Draw pixbuf
//        var x_pix = 0;
//        var y_pix = 0;
//        var pad = 0;
//        if (is_thumb == true) {
//            x_pix = RoundBox.BORDER_WIDTH;
//            pad = xy_padding + x_pix;
//            y_pix = RoundBox.BORDER_WIDTH;
//        }
//        cr.set_operator (Cairo.Operator.OVER);
//        if (thumb != null)  {
//            y_pix = (height - thumb.height) / 2;
//            Gdk.cairo_set_source_pixbuf(cr, thumb, x_pix, y_pix);
//            cr.rectangle (x_pix, y_pix, thumb.width, thumb.height);
//            cr.fill();
//        }
//        
//        //Draw title
//        Pango.Rectangle rect;
//        title_layout.get_extents (null, out rect);
//        this.get_style_context ().render_layout (cr,
//               x_pix + thumb.width + pad,
//               (height - rect.height/ Pango.SCALE) / 2,
//               title_layout);
//        
//        //Draw timestamp
//        title_layout.get_extents (null, out rect);
//        this.get_style_context ().render_layout (cr,
//               x_pix + thumb.width + pad , //width - rect.width / Pango.SCALE do not work..why?
//               height - rect.height / Pango.SCALE ,
//               time_layout);

//        return false;
//    }
//    
//    private void create_title_layout (int width) {
//        Pango.Rectangle rect;
//        int f_width, text_width;
//        var layout = this.create_pango_layout ("");
//        layout.set_text(activity.title , -1);

//        var attr_list = new Pango.AttrList ();

//        var attr_s = new Pango.AttrSize (12 * Pango.SCALE);
//		attr_s.absolute = 1;
//		attr_s.start_index = 0;
//		attr_s.end_index = attr_s.start_index + activity.title.length;
//		attr_list.insert ((owned) attr_s);

//		var desc = new Pango.FontDescription ();
//		desc.set_weight (Pango.Weight.BOLD);
//		var attr_f = new Pango.AttrFontDesc (desc);
//		attr_list.insert ((owned) attr_f);
//		
//		layout.set_ellipsize (Pango.EllipsizeMode.END);
//        //layout.set_wrap (Pango.WrapMode.WORD_CHAR);
//		
//		layout.set_attributes (attr_list);
//        layout.get_extents (null, out rect);
//        
//        var pad = xy_padding;
//        if (is_thumb == true)
//            pad += RoundBox.BORDER_WIDTH;
//        text_width = rect.width;
//        var p_width = (width - pad - thumb.width) * Pango.SCALE;
//        f_width = int.min (p_width, text_width);
//        layout.set_width (f_width);
//        
//        this.title_layout = layout;
//   }
//   
//   private void create_time_layout (int width) {
//        var layout = this.create_pango_layout ("");
//        DateTime date = new DateTime.from_unix_utc (activity.time / 1000).to_local ();
//        string date_s = date.format ("%Y-%m-%d %H:%M");
//        layout.set_text (date_s, -1);

//        var attr_list = new Pango.AttrList ();

//        var attr_s = new Pango.AttrSize (8 * Pango.SCALE);
//		attr_s.absolute = 1;
//		attr_s.start_index = 0;
//		attr_s.end_index = attr_s.start_index + date_s.length;
//		attr_list.insert ((owned) attr_s);

//		var desc = new Pango.FontDescription ();
//		desc.set_style (Pango.Style.ITALIC);
//		var attr_f = new Pango.AttrFontDesc (desc);
//		attr_list.insert ((owned) attr_f);
//		
//		//layout.set_ellipsize (Pango.EllipsizeMode.END);
//        layout.set_wrap (Pango.WrapMode.WORD_CHAR);
//        layout.set_attributes (attr_list);

//        this.time_layout = layout;
//   }
//   
//    public override bool button_release_event (Gdk.EventButton event) {
//        //TODO Improve here?
//        try {
//            AppInfo.launch_default_for_uri (this.activity.uri, null);
//        } catch (Error e) {
//            warning ("Error in launching: "+ this.activity.uri);
//        }
//        return false;
//    }
//    
//   public override Gtk.SizeRequestMode get_request_mode () {
//       return SizeRequestMode.HEIGHT_FOR_WIDTH;
//   }
//  
//   public override void get_preferred_width (out int minimum_width, out int natural_width) {
//      minimum_width = natural_width = this.width;
//   }

//   public override void get_preferred_height_for_width (int  width,
//                                                       out int minimum_height,
//                                                       out int natural_height) {
//       var x_pix = 0;
//       if (is_thumb == true)
//           x_pix = RoundBox.BORDER_WIDTH * 2;
//           
//       create_title_layout (width - x_pix);
//       create_time_layout (width - x_pix);
//       Pango.Rectangle r, r2;
//       time_layout.get_extents (null, out r);
//       title_layout.get_extents (null, out r2);

//       minimum_height = natural_height = int.max (thumb.height, 
//                                     (int)(r.height + r2.height) / Pango.SCALE);
//   }
//}
