using Gtk;
using Gst;

const int MEDIA_SIZE_NORMAL = 84;
const int MEDIA_SIZE_LARGE = 128;

private class Journal.TextActor : Clutter.Text {
    
    public TextActor () {
        GLib.Object ();
        this.set_ellipsize (Pango.EllipsizeMode.END);
        this.set_line_alignment (Pango.Alignment.CENTER);
    }
    
    public TextActor.with_text (string text){
        this ();
        this.set_text (text);
    }
    
    public TextActor.with_markup (string markup){
        this ();
        this.set_markup (markup);
    }
    
    public TextActor.full_markup (string markup, Pango.AttrList attributes){
        this.with_markup (markup);
        this.attributes = attributes;
    }
    
    public TextActor.full_text (string text, Pango.AttrList attributes){
        this.with_text (text);
        this.attributes = attributes;
    }
}

private class Journal.ImageActor : Clutter.Actor {
    private Clutter.Image image;

    public ImageActor () {
        GLib.Object ();
        this.image = new Clutter.Image ();
        this.set_content_scaling_filters (Clutter.ScalingFilter.TRILINEAR,
                                    Clutter.ScalingFilter.LINEAR);
        this.set_content (image);
    }
    
    public ImageActor.from_uri (string uri) {
        try {
            Gdk.Pixbuf pixbuf =  new Gdk.Pixbuf.from_file (uri);
            this.from_pixbuf (pixbuf);
        } catch (Error e) {
            warning("Can't load " + uri);
        }
    }
    
     public ImageActor.from_pixbuf (Gdk.Pixbuf pixbuf) {
        this ();
        try {
            this.image.set_data (
            pixbuf.get_pixels (),
            pixbuf.has_alpha ? Cogl.PixelFormat.RGBA_8888 : Cogl.PixelFormat.RGB_888,
            pixbuf.width,
            pixbuf.height,
            pixbuf.rowstride);
        } catch (Error e) {
            warning("Can't load pixbuf");
        }
        
        this.set_size (pixbuf.width, pixbuf.height);
     }
     
     public void set_pixbuf (Gdk.Pixbuf pixbuf) {
        try {
            this.image.set_data (
            pixbuf.get_pixels (),
            pixbuf.has_alpha ? Cogl.PixelFormat.RGBA_8888 : Cogl.PixelFormat.RGB_888,
            pixbuf.width,
            pixbuf.height,
            pixbuf.rowstride);
        } catch (Error e) {
            warning("Can't load pixbuf");
        }
        this.set_size (pixbuf.width, pixbuf.height);
     }
}

private class Journal.VideoActor : ClutterGst.VideoTexture {
    
    private bool playing;
    public VideoActor (string uri) {
        GLib.Object ();
        this.reactive = true;
        this.playing = false;
        this.set_keep_aspect_ratio (true);
        this.set_height (MEDIA_SIZE_LARGE);
        this.set_width (MEDIA_SIZE_LARGE);
        this.set_filename (uri);
        
        this.button_release_event.connect ((e) => {
            if (!playing) {
                this.playing = true;
                this.set_playing (playing);
            }
            else {
                this.playing = false;
                this.set_playing (playing);
            }
            
            return false;
        });
    }
}

private class Journal.DocumentActor : Clutter.Actor {
    
    private TextActor title;
    private ImageActor image;
    
    private TextActor time;
    
    private Clutter.BinLayout box;
    public DocumentActor (string title_s, Gdk.Pixbuf pixbuf, string date) {
        GLib.Object ();

        var attr_list = new Pango.AttrList ();
        attr_list.insert (Pango.attr_scale_new (Pango.Scale.LARGE));
        attr_list.insert (Pango.attr_weight_new (Pango.Weight.BOLD));

        title = new TextActor.full_text (title_s, attr_list);
        title.margin_bottom = 10;

        attr_list = new Pango.AttrList ();
        attr_list.insert (Pango.attr_scale_new (Pango.Scale.SMALL));
        attr_list.insert (Pango.attr_style_new (Pango.Style.ITALIC));

        time = new TextActor.full_text (date, attr_list);
        time.margin_top = 10;
        image = new ImageActor.from_pixbuf (pixbuf);
        image.margin_top = 10;
        image.margin_bottom = 10;
        box = new Clutter.BinLayout (Clutter.BinAlignment.CENTER, 
                                         Clutter.BinAlignment.CENTER);
        set_layout_manager (box);

        box.add (image, Clutter.BinAlignment.CENTER, Clutter.BinAlignment.CENTER);
        box.add (title, Clutter.BinAlignment.CENTER, Clutter.BinAlignment.START);
        box.add (time, Clutter.BinAlignment.CENTER, Clutter.BinAlignment.END);
        
        this.set_height (image.height + time.height);
        
        this.margin_left = this.margin_right = 10;

    }
    
    public void update_image (Gdk.Pixbuf pixbuf) {
        this.image.set_pixbuf (pixbuf);
    }
}

private class Journal.RoundedBox : Clutter.Actor {

    private float arc;
    private float step;
    private float border_width;
    
    private Cogl.Color bg_color;
    private Cogl.Color border_color;
    
    public RoundedBox (float arc = 5, float step = 0.1f, float border_width = 2) {
        GLib.Object ();
        this.arc = arc;
        this.step = step;
        this.border_width = border_width;
        var bg =  Utils.get_roundbox_bg_color ();
        this.bg_color = Utils.gdk_rgba_to_cogl_color (bg);
        var color = Utils.get_roundbox_border_color ();
        this.border_color = Utils.gdk_rgba_to_cogl_color (color);
    }
    
    public override void paint () {
        var allocation = get_allocation_box ();
        float width, height;
        allocation.get_size (out width, out height);
        
        Cogl.Path.round_rectangle (0, 0, width, height, arc, step);
        Cogl.Path.close ();
        Cogl.clip_push_from_path ();
        
        Cogl.set_source_color (border_color);
        Cogl.Path.round_rectangle (0, 0, width, height, arc, step);
        Cogl.Path.close ();
        Cogl.Path.fill ();
        
        Cogl.set_source_color (bg_color);
        Cogl.Path.round_rectangle (border_width, border_width, 
                                   width - border_width, 
                                   height - border_width,
                                   arc, step);
        Cogl.Path.fill ();
        Cogl.Path.close ();
        
        Cogl.clip_pop ();
    }
    
    public override void pick (Clutter.Color c) {
        if (should_pick_paint () == false)
            return;
            
        Cogl.Path.round_rectangle (0, 0, width, height, arc, step);
        Cogl.Path.close ();
        Cogl.clip_push_from_path ();
        
        Cogl.Color color = Cogl.Color.from_4ub (c.red, c.green, c.blue, c.alpha);
        Cogl.set_source_color(color);
        
        Cogl.Path.round_rectangle (0, 0, width, height, arc, step);
        Cogl.Path.close ();
        Cogl.Path.fill ();
        Cogl.clip_pop ();
    }
    
   public override void get_preferred_width (float for_height, out float min_width, out float nat_width) {
       first_child.get_preferred_width(-1, out min_width, out nat_width);
       min_width += border_width * 2 ;
       nat_width += border_width * 2 ;
   }

   public override void get_preferred_height (float  width,
                                                       out float min_height,
                                                       out float nat_height) {
       first_child.get_preferred_height (-1, out min_height, out nat_height);
       min_height += border_width * 2 ;
       nat_height += border_width * 2;
   }
}
