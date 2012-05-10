using Gtk;
using Cairo;

enum Side {
 TOP,
 LEFT,
 RIGHT,
 BOTTOM
}

private class Journal.ClutterRoundBoxView : Box {
    private ActivityModel model;
    private App app;
    private Clutter.Stage stage;
    private Clutter.Actor viewport;
    private Clutter.Actor timeline;
    private Timeline timeline_gtk;


    public ClutterRoundBoxView (App app){
        this.model = new ActivityModel ();
        this.app = app;
        this.stage = app.stage;


        app.backend.events_loaded.connect (() => {
            load_events ();
        });
        
        
        viewport = new Clutter.Actor ();
        viewport.set_clip_to_allocation (true);
        viewport.set_reactive (true);
        viewport.add_constraint (new Clutter.BindConstraint (stage, Clutter.BindCoordinate.WIDTH, 0));
        
        //Timeline
        timeline_gtk = new Timeline ();
        timeline = new GtkClutter.Actor.with_contents (timeline_gtk);
        timeline.add_constraint (new Clutter.BindConstraint (viewport, Clutter.BindCoordinate.HEIGHT, 0));
        timeline.add_constraint (new Clutter.AlignConstraint (stage, Clutter.AlignAxis.X_AXIS, 0.5f));
        
        viewport.add_actor (timeline); 
        stage.add_actor (viewport);
        
        viewport.scroll_event.connect ( (e) => {
            
        var y = viewport.get_y ();
        var direction = e.direction;

        switch (direction)
        {
            case Clutter.ScrollDirection.UP:
                y -= 100;
                break;
            case Clutter.ScrollDirection.DOWN:
                y += 100;
                break;

            /* we're only interested in up and down */
            case Clutter.ScrollDirection.LEFT:
            case Clutter.ScrollDirection.RIGHT:
            break;
       }
       y = y.clamp (stage.get_height () - viewport.get_height (), 0.0f);
       /* animate the change to the scrollable's y coordinate */
       viewport.animate ( Clutter.AnimationMode.EASE_OUT_CUBIC,
                         100,
                         "y", y);
       return true;
       });
    }
    
    public void load_events () {
        Gee.ArrayList<Zeitgeist.Event> all_activities= app.backend.all_activities;
        int i = 50;
        int type = 0;
        Side side;
        float offset = 0;
        foreach (Zeitgeist.Event e in all_activities)
        {
            GenericActivity activity = new GenericActivity (e);
            model.add_activity (activity);
            if (type % 2 == 0) 
                side = Side.RIGHT;
            else 
                side = Side.LEFT;
                
            RoundBox r = new RoundBox (side);
            RoundBoxContent rc = new RoundBoxContent (activity);
            r.add (rc);

            GtkClutter.Actor actor = new GtkClutter.Actor.with_contents (r);
            viewport.add_actor (actor);
            if (type % 2 == 0)
                offset = -(5 + actor.get_width());
            else 
                offset = 5 + timeline.get_width ();
            actor.add_constraint (new Clutter.BindConstraint (timeline, Clutter.BindCoordinate.X, offset));  // timeline!
            actor.set_y (i);
            timeline_gtk.add_circle (i);
            //i +=  (int)actor.get_height() + 20; // padding TODO FIXME better algorithm here
            if (type % 2 == 1) i += 20;
            else i +=  (int)actor.get_height();
            type ++;

            r.show_all ();
        }
    }
}

private class Journal.GtkRoundBoxView : Layout {
    private ActivityModel model;
    private App app;
    private Gee.ArrayList<int> point_circle;
    
    private int total_height;
    
    //Timeline stuffs
    private const int len_arrow = 20; // hardcoded
    private const int arrow_origin = 30;
    private const int timeline_width = 2;
    private const int radius = 6;


    public GtkRoundBoxView (App app){
        this.model = new ActivityModel ();
        this.app = app;
        this.point_circle = new Gee.ArrayList<int> ();

        this.get_style_context ().add_class ("timeline-gtk");
        this.hexpand = true;
        this.total_height = 0;
        
        this.realize.connect (() => {
            this.setup_ui ();
        });
        
       this.app.window.configure_event.connect (() => {
            this.adjust_ui ();
            return false;
        });
        
        this.app.window.window_state_event.connect (() => {
            this.adjust_ui ();
            return false;
        });
        
        app.backend.events_loaded.connect (() => {
            load_events ();
        });
    }
    
    private void add_circle (int y) {
        this.point_circle.add (y + arrow_origin - len_arrow / 2 + radius * 2 - 2); //?? why?
    }
    
    public override bool draw (Cairo.Context ctx) {
        var bg = this.get_style_context ().get_color (0);
        Clutter.Color backgroundColor = Utils.gdk_rgba_to_clutter_color (bg);
        var color = this.get_style_context ().get_border_color (0);
        Clutter.Color circleColor = Utils.gdk_rgba_to_clutter_color (color);

        Allocation allocation;
        get_allocation (out allocation);
        var width = allocation.width;
        var height = allocation.height;
        var cr = ctx;

        ctx.save ();
        //Draw the timeline
        Clutter.cairo_set_source_color (cr, backgroundColor);
        ctx.translate (width / 2 - timeline_width / 2, 0);
        ctx.rectangle (0, 0, timeline_width, height);
        ctx.fill ();
        
        //Draw circles
        foreach (int y in point_circle) {
            // Paint the border cirle to start with.
            Clutter.cairo_set_source_color(cr, backgroundColor);
            ctx.arc (timeline_width / 2, y, radius, 0, 2*Math.PI);
            ctx.stroke ();
            // Paint the colored cirle
            Clutter.cairo_set_source_color(cr, circleColor);
            ctx.arc (timeline_width / 2, y, radius - 1, 0, 2*Math.PI);
            ctx.fill ();
        }

        ctx.restore ();
        foreach (Widget child in this.get_children ())
            this.propagate_draw(child, ctx);

        return false;
        }

    public void load_events () {
        Gee.ArrayList<Zeitgeist.Event> all_activities= app.backend.all_activities;
        foreach (Zeitgeist.Event e in all_activities)
        {
            GenericActivity activity = new GenericActivity (e);
            model.add_activity (activity);
        }
    }
    
    private void setup_ui () {
        int i = 50;
        int type = 0;
        Side side;
        float offset = 0;
        foreach (GenericActivity activity in model.activities)
        {
            if (type % 2 == 0) 
                side = Side.RIGHT;
            else 
                side = Side.LEFT;
                
            RoundBox r = new RoundBox (side);
            RoundBoxContent rc = new RoundBoxContent (activity);
            r.add (rc);
            
            int r_height, r_width, width;
            r.get_preferred_width (null, out r_width);
            r.get_preferred_height_for_width (r_width, null, out r_height);
            width = get_allocated_width ();
            
            if (type % 2 == 0)
                offset = (int)width / 2 + timeline_width / 2 - radius - 5 - r_width;
            else 
                offset = (int)width / 2 + timeline_width / 2 + radius + 5;

            this.add_circle (i);
            this.put(r, (int) offset, i);
            //i +=  (int)actor.get_height() + 20; // padding TODO FIXME better algorithm here
            if (type % 2 == 1) i += 20;
            else {
                i += r_height;
                total_height += r_height ;
            }
            type ++;
        }
        this.show_all ();
        
        adjust_ui ();
    
    }
    
    private void adjust_ui (){
        int width = get_allocated_width ();
        int i = 50;
        int offset = 0;
        foreach (Widget child in this.get_children ()) {
            int r_width = child.get_allocated_width ();
            int r_height = child.get_allocated_height ();
            Side side = ((RoundBox)child).arrow_side;
            if (side == Side.RIGHT) 
                offset = (int)width / 2 + timeline_width / 2 - radius - 5 - r_width;
            else
                offset = (int)width / 2 + timeline_width / 2 + radius + 5; 
            this.move (child, offset, i);
            
            if (side == Side.RIGHT) 
                i+= r_height;
            else
                i+= 20; 
            
            total_height += r_height;

        }
        
    }
  
   public override void get_preferred_height (out int minimum_height, out int natural_height) {
       minimum_height = natural_height = this.total_height;
   }

}

private class Journal.Timeline : DrawingArea {

    private Gee.ArrayList<int> point_circle;
    private const int len_arrow = 20; // hardcoded
    private const int arrow_origin = 30;
    private const int timeline_width = 2;
    private const int radius = 6;
    
    public Timeline () {
        this.point_circle = new Gee.ArrayList<int> ();
        this.get_style_context ().add_class ("timeline-clutter");
    }
    
    public void add_circle (int y) {
        this.point_circle.add (y + arrow_origin - len_arrow / 2 + radius * 2 - 2); //?? why?
    }
    
    public override bool draw(Cairo.Context ctx) {
        var bg = this.get_style_context ().get_background_color (0);
        Clutter.Color backgroundColor = Utils.gdk_rgba_to_clutter_color (bg);
        var color = this.get_style_context ().get_color (0);
        Clutter.Color circleColor = Utils.gdk_rgba_to_clutter_color (color);

        Allocation allocation;
        get_allocation (out allocation);
        var height = allocation.height;
        var cr = ctx;
        ctx.set_source_rgba (1.0, 1.0, 1.0, 0.0);
        // Paint the entire window transparent to start with.
        ctx.set_operator (Cairo.Operator.SOURCE);
        ctx.paint ();
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

        return false;
        }
        
   public override Gtk.SizeRequestMode get_request_mode () {
       return SizeRequestMode.HEIGHT_FOR_WIDTH;
   }
  
   public override void get_preferred_width (out int min_width, out int nat_width) {
       nat_width = min_width = 2 * radius + timeline_width;
   }

}

private class Journal.RoundBox : Frame {
    private Side _arrowSide;
    private int _arrowOrigin = 30; 

    public static int BORDER_WIDTH = 10;
    
    public Side arrow_side {
        get { return _arrowSide; }
    }

    public RoundBox (Side side) {
       this._arrowSide = side;
       this.border_width = BORDER_WIDTH;
       this.get_style_context ().add_class ("roundbox");
    }

    public override bool draw (Cairo.Context ctx) {
        //Code ported from GNOME shell's box pointer
        var borderWidth = 2;
        var baseL = 20; //lunghezza base freccia
        var rise = 10;  //altezza base freccia
        var borderRadius = 10;

        var halfBorder = borderWidth / 2;
        var halfBase = Math.floor(baseL/2);

        var bc = this.get_style_context ().get_border_color (0);
        Clutter.Color borderColor = Utils.gdk_rgba_to_clutter_color (bc);
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
    
    private const int DEFAULT_WIDTH = 400;
    private const int x_padding = 5;
    
    private bool is_thumb;
    
    private Pango.Layout title_layout;
    private Pango.Layout time_layout;

    public RoundBoxContent (GenericActivity activity) {
        this.activity = activity;
        this.thumb = activity.type_icon;
        this.is_thumb = false;

        // Enable the events you wish to get notified about.
        // The 'draw' event is already enabled by the DrawingArea.
        add_events (Gdk.EventMask.BUTTON_PRESS_MASK
                  | Gdk.EventMask.BUTTON_RELEASE_MASK
                  | Gdk.EventMask.POINTER_MOTION_MASK);
        
        activity.thumb_loaded.connect (() => {
                  thumb = activity.thumb_icon;
                  is_thumb = true;
                  //resize and redraw but now let's use the thumb
                  queue_resize (); 
        });
    }

    /* Widget is asked to draw itself */
    public override bool draw (Cairo.Context cr) { 
        int width = get_allocated_width ();
        int height = get_allocated_height ();

        // Draw pixbuf
        var x_pix = 0;
        var pad = 0;
        if (is_thumb == true) {
            x_pix = RoundBox.BORDER_WIDTH;
            pad = x_padding + x_pix;
        }
        var y_pix = (height - thumb.height) / 2;
        cr.set_operator (Cairo.Operator.OVER);
        Gdk.cairo_set_source_pixbuf(cr, thumb, x_pix, y_pix);
        cr.rectangle (x_pix, y_pix, thumb.width, thumb.height);
        cr.fill();
        
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
               width - rect.width / Pango.SCALE ,
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
		
		//layout.set_ellipsize (Pango.EllipsizeMode.END);
        layout.set_wrap (Pango.WrapMode.WORD_CHAR);
		
		layout.set_attributes (attr_list);
        layout.get_extents (null, out rect);
        
        text_width = rect.width;
        var p_width = (width - x_padding - thumb.width) * Pango.SCALE;
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
    
   public override Gtk.SizeRequestMode get_request_mode () {
       return SizeRequestMode.HEIGHT_FOR_WIDTH;
   }
  
   public override void get_preferred_width (out int minimum_width, out int natural_width) {
      minimum_width = natural_width = DEFAULT_WIDTH;
   }

   public override void get_preferred_height_for_width (int  width,
                                                       out int minimum_height,
                                                       out int natural_height) {
       var x_pix = 0;
       if (is_thumb == true)
           x_pix = RoundBox.BORDER_WIDTH;
           
       create_title_layout (width - x_pix);
       create_time_layout (width - x_pix);
       Pango.Rectangle r, r2;
       time_layout.get_extents (null, out r);
       title_layout.get_extents (null, out r2);

       minimum_height = natural_height = int.max (thumb.height, 
                                     (int)(r.height + r2.height) / Pango.SCALE);
   }
}
