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

private class Journal.ClutterVTL : Box {
    
    private ActivityModel model;
    private App app;
    private Clutter.Stage stage;
    private Scrollbar scrollbar;
    private TimelineNavigator vnav;
    
    public ScrollableViewport viewport;
    public Clutter.Actor container;
    
    private OSDLabel osd_label;
    private LoadingActor loading;
    
    private Gee.Map<string, Clutter.Actor> y_positions;
    private Gee.List<string> dates_added;

    //Date to jump when we have loaded new events
    private DateTime? date_to_jump;
    
    private bool on_loading;

    public ClutterVTL (App app, ActivityModel model){
        Object (orientation: Orientation.HORIZONTAL, spacing : 0);
        this.model = model;
        this.app = app;
        var embed = new GtkClutter.Embed ();
        this.stage = embed.get_stage () as Clutter.Stage;
        this.stage.set_user_resizable (false);
        this.stage.set_background_color (Utils.gdk_rgba_to_clutter_color (
                                         Utils.get_journal_bg_color ()));
        
        y_positions = new Gee.HashMap <string, Clutter.Actor> ();
        dates_added = new Gee.ArrayList <string> ();
        
        viewport = new ScrollableViewport ();
        viewport.scroll_mode = ScrollMode.Y;
        viewport.add_constraint (new Clutter.BindConstraint (stage, Clutter.BindCoordinate.SIZE, 0));

        container = new Clutter.Actor ();
        container.reactive = true;
        container.add_constraint (new Clutter.BindConstraint (stage, Clutter.BindCoordinate.WIDTH, 0));
        
        var layout = new Clutter.BoxLayout ();
        layout.vertical = true;
        container.set_layout_manager (layout);

        container.scroll_event.connect ( (e) => {
         
        if (on_loading)
            return false;
            
        var direction = e.direction;

        switch (direction)
        {
            case Clutter.ScrollDirection.UP:
                if (scrollbar.adjustment.value != 0.0f)
                    scrollbar.move_slider (ScrollType.STEP_UP);
                break;
            case Clutter.ScrollDirection.DOWN:
                var limit = (int)scrollbar.adjustment.upper - scrollbar.adjustment.page_size - 500;
                if (scrollbar.adjustment.value < limit)
                    scrollbar.move_slider (ScrollType.STEP_DOWN);
                else {
                    scrollbar.adjustment.value = limit;
                    on_scrollbar_scroll ();
                }
                break;

            /* we're only interested in up and down */
            case Clutter.ScrollDirection.LEFT:
            case Clutter.ScrollDirection.RIGHT:
            break;
       }
       
       viewport.scroll_to_point (0.0f, (float)scrollbar.adjustment.value);
       return false;
       });
       
       viewport.add_actor (container);
       stage.add_actor (viewport);
       
       Adjustment adj = new Adjustment (0, 0, 0, 0, 0, stage.height);
       scrollbar = new Scrollbar (Orientation.VERTICAL, adj);
       scrollbar.change_value.connect ((st, v) => { 
            this.on_scrollbar_scroll (); 
            return false;
       });
        
       vnav = new TimelineNavigator (Orientation.VERTICAL);
       vnav.go_to_date.connect ((date) => {this.jump_to_day (date);});

       this.pack_start (new Gtk.Label(""), false, false, 32);
       this.pack_start (embed, true, true, 0);
       this.pack_start (vnav, false, false, 10);
       this.pack_start (scrollbar, false, false, 0);
       
       osd_label = new OSDLabel (stage);
       stage.add_actor (osd_label.actor);
        
       loading = new LoadingActor (stage);
       loading.start ();
       
       model.activities_loaded.connect ((dates_loaded)=> {
            load_activities (dates_loaded);
            on_loading = false;
            loading.stop ();
       });
    }
    
    private int get_child_index_for_date (string date) {
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
                return i * 2;
            }
            i++;
        }
        //Else append to the end
        return container.get_n_children ();
    }
    
    private void adjust_scrollbar () {
        if (container.height <= stage.height)
            scrollbar.hide ();
       else 
            scrollbar.show ();

       scrollbar.adjustment.upper = container.height;
       uint num_child = container.get_n_children ();
       scrollbar.adjustment.step_increment = scrollbar.adjustment.upper / 
                                            (num_child * 15);
       scrollbar.adjustment.page_increment = scrollbar.adjustment.upper / 10;
    }
    
    private void load_activities (Gee.ArrayList<string> dates_loaded) {
        foreach (string date in dates_loaded) {
            if (dates_added.contains (date) || date.has_prefix ("*"))
              continue;
            
            var index = get_child_index_for_date (date);
            dates_added.add (date);
            
            var day_actor = new DayActor (date);
            day_actor.add_constraint (new Clutter.AlignConstraint (stage, Clutter.AlignAxis.X_AXIS, 0.5f));
            container.insert_child_at_index (day_actor, index);
            y_positions.set (date, day_actor);

            index ++;

            var activity_list = model.activities.get (date);
            BubbleContainer bubble_c = new BubbleContainer (stage);
            foreach (GenericActivity activity in activity_list.composite_activities) 
                 bubble_c.append_bubble (activity);

            container.get_layout_manager ().child_set_property (container, bubble_c, "x-fill", true);
            container.insert_child_at_index (bubble_c, index);
        }
       
       adjust_scrollbar ();
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
            viewport.scroll_to_point (0.0f, y);
            scrollbar.adjustment.upper = container.height;
            scrollbar.adjustment.value = y;
            date_to_jump = null;
        }
        else {
            //osd_label.set_message_and_show (_("Loading Activities..."));
            loading.start ();
            if (date == date_to_jump) {
                //Break the infinite loop that happens when the user ask for an
                //event period too far and not present in the db.
                date_s = dates_added.get (dates_added.size - 1);
                if (y_positions.has_key (date_s) == true) {
                    y = this.y_positions.get (date_s).get_y ();
                    viewport.scroll_to_point (0.0f, y);
                    scrollbar.adjustment.upper = container.height;
                    scrollbar.adjustment.value = y;
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
        viewport.scroll_to_point (0.0f, y);
        var limit = (int)scrollbar.adjustment.upper - scrollbar.adjustment.page_size - 500;
        if (!on_loading && y >= limit) {
            //We can't scroll anymmore! Let's load another day!
            //loading.start ();
            model.load_other_days (3);
            on_loading = true;
        }
        
        //We are moving so we should highligth the right TimelineNavigator's label
        string final_key = "";
        float final_pos = 0;
        foreach (Gee.Map.Entry<string, Clutter.Actor> entry in y_positions.entries) {
            float current_value = entry.value.get_y ();
            if (current_value <= ((y) + stage.height / 2) && current_value > final_pos) {
                final_key = entry.key;
                final_pos = current_value;
            }
        }
        vnav.highlight_date (final_key);
    }
}

private class Journal.BubbleContainer : Clutter.Actor {
    private Clutter.Actor center_c;
    private Clutter.Actor right_c;
    private Clutter.Actor left_c;
    
    private Clutter.Stage stage;
    private int turn;
    
    public BubbleContainer (Clutter.Stage stage) {
        
        this.stage = stage;
        center_c = new Clutter.Actor ();
        var bg =  Utils.get_timeline_bg_color ();
        Clutter.Color backgroundColor = Utils.gdk_rgba_to_clutter_color (bg);
        center_c.background_color = backgroundColor;
        center_c.set_width (2);
        center_c.depth = -1;
        center_c.add_constraint (new Clutter.AlignConstraint (stage, Clutter.AlignAxis.X_AXIS, 0.5f));
        this.add_child (center_c);
        
        var layout = new Clutter.BoxLayout ();
        layout.vertical = true;
        layout.spacing = 40;
        layout.use_animations = true;
        
        left_c = new Clutter.Actor ();
        left_c.set_layout_manager (layout);
        this.add_child (left_c);
        
        var fake = new Clutter.Actor ();
        fake.set_size (10, 10);
        left_c.add_child (fake);
        
        left_c.add_constraint (new Clutter.BindConstraint (center_c, Clutter.BindCoordinate.Y, 0));
        left_c.add_constraint (new Clutter.BindConstraint (center_c, Clutter.BindCoordinate.HEIGHT, 0));
        left_c.add_constraint (new Clutter.SnapConstraint (center_c, Clutter.SnapEdge.RIGHT, Clutter.SnapEdge.LEFT, -10.0f));
        left_c.add_constraint (new Clutter.SnapConstraint (this, Clutter.SnapEdge.LEFT, Clutter.SnapEdge.LEFT, 10.0f));
        
        layout = new Clutter.BoxLayout ();
        layout.vertical = true;
        layout.spacing = 40;
        layout.use_animations = true;
        
        right_c = new Clutter.Actor ();
        right_c.set_layout_manager (layout);
        this.add_child (right_c);
        
        fake = new Clutter.Actor ();
        fake.set_size (10, 30);
        right_c.add_child (fake);
        
        right_c.add_constraint (new Clutter.BindConstraint (center_c, Clutter.BindCoordinate.Y, 0));
        right_c.add_constraint (new Clutter.BindConstraint (center_c, Clutter.BindCoordinate.HEIGHT, 0));
        right_c.add_constraint (new Clutter.SnapConstraint (center_c, Clutter.SnapEdge.LEFT, Clutter.SnapEdge.RIGHT, 10.0f));
        right_c.add_constraint (new Clutter.SnapConstraint (this, Clutter.SnapEdge.RIGHT, Clutter.SnapEdge.RIGHT, 0.0f));
        
        turn = 0;
    }
    
    public void append_bubble (GenericActivity activity) {
        RoundBox rb;
        if (turn % 2 == 0) {
            rb = new RoundBox (Side.RIGHT, activity);
            ((Clutter.BoxLayout)left_c.get_layout_manager ()).set_fill (rb, true, false);
            rb.x_align = Clutter.ActorAlign.END;
            left_c.add_child (rb);
        }
        else {
            rb = new RoundBox (Side.LEFT, activity);
            ((Clutter.BoxLayout)right_c.get_layout_manager ()).set_fill (rb, true, false);
            rb.x_align = Clutter.ActorAlign.START;
            right_c.add_child (rb);
        }
        center_c.set_height (this.height + 20);
        
        //Add circle
        var circle = new CircleTexture ();
        this.add_child (circle);
        circle.add_constraint (new Clutter.AlignConstraint (stage, Clutter.AlignAxis.X_AXIS, 0.5f));
        circle.add_constraint (new Clutter.BindConstraint (rb, Clutter.BindCoordinate.Y, 22));
        turn++;
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

private class Journal.RoundBox : Clutter.Actor {
    private Side _arrowSide;
    private int _arrowOrigin = 30; 
    private int border_width;
    
    public static int BORDER_WIDTH = 10;
    
    private Clutter.Canvas canvas;
    private Clutter.Actor content_actor;
    
    private GenericActivity activity;

    public Side arrow_side {
        get { return _arrowSide; }
    }
    
    private bool enter;

    private Clutter.BinLayout box;
    public RoundBox (Side side, GenericActivity activity) {
       this._arrowSide = side;
       this.border_width = BORDER_WIDTH;
       this.activity = activity;
       this.reactive = true;

       box = new Clutter.BinLayout (Clutter.BinAlignment.CENTER, 
                                    Clutter.BinAlignment.CENTER);
       set_layout_manager (box);
       
       this.canvas = new Clutter.Canvas ();
       canvas.draw.connect ((cr, w, h) => { return paint_canvas (cr, w, h); });
       var canvas_box = new Clutter.Actor ();
       canvas_box.set_content (canvas);
       this.add_child (canvas_box);
       
       activity.create_actor ();

       this.add_content (activity.actor);
       float c_nat_width, c_nat_height;
       this.get_preferred_height (-1, null, out c_nat_height);
       this.get_preferred_width (-1, null, out c_nat_width);
       canvas_box.set_size ((int)c_nat_width, (int) c_nat_height);
       canvas.set_size ((int)c_nat_width, (int) c_nat_height);
       this.allocation_changed.connect ((box, f) => {
            Idle.add (()=>{
                //see this http://www.mail-archive.com/clutter-app-devel-list@clutter-project.org/msg00116.html
                canvas_box.set_size ((int)box.get_width (), (int) box.get_height ());
                canvas.set_size ((int)box.get_width (), (int) box.get_height ());
                return false;
            });
       });
       
       this.button_release_event.connect ((e) => {
                activity.launch ();
                return false;
       });
       
       enter = false;
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
        if (enter)
            borderColor = borderColor.darken ();

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
    
    public override  bool enter_event (Clutter.CrossingEvent event) {
        enter = true;
        canvas.invalidate ();
        return true;
    }
    
    public override  bool leave_event (Clutter.CrossingEvent event) {
        enter = false;
        canvas.invalidate ();
        return false;
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
            nat_width = nat_width_t + 4 * BORDER_WIDTH;
            min_width = min_width_t + 4 * BORDER_WIDTH;
        }
    }
    
    public override void get_preferred_height (float for_width, out float min_height, out float nat_height) {
       float min_height_t, nat_height_t;
       min_height = nat_height = 0;
        if (content_actor != null) {
            content_actor.get_preferred_height (-1, out min_height_t, out nat_height_t);
            nat_height = min_height_t + 2 * BORDER_WIDTH;
            min_height = min_height_t + 2 * BORDER_WIDTH;
        }
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
