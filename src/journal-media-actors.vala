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
using Gst;

const int MEDIA_SIZE_NORMAL = 84;
const int MEDIA_SIZE_LARGE = 256;

//TODO Create a general class DocumentActor and then inherits from it

private class Journal.TextActor : Clutter.Text {

    public TextActor () {
        GLib.Object ();
        this.set_ellipsize (Pango.EllipsizeMode.END);
        this.paint.connect (() => {
            this.text_paint_cb ();
        });
    }
    
    public TextActor.with_text (string text){
        this ();
        this.set_text (text);
        float natural_height;
        this.get_preferred_height (-1, null, out natural_height);
        this.set_height (natural_height);
    }
    
    public TextActor.with_markup (string markup){
        this ();
        this.set_markup (markup);
    }
    
    public TextActor.full_markup (string markup, Pango.AttrList attributes){
        this.with_markup (markup);
        this.attributes = attributes;
    }
    
    public TextActor.full_text (string? text, Pango.AttrList attributes){
        if (text == null)
            text = "";
        this.with_text (text);
        this.attributes = attributes;
    }
    
    private void text_paint_cb () {
        Clutter.Text text = (Clutter.Text)this;
        var layout = text.get_layout ();
        var text_color = text.get_color ();
        var real_opacity = this.get_paint_opacity () * text_color.alpha * 255;
        
        Cogl.Color color = {};
        color.init_from_4ub (0xcc, 0xcc, 0xcc, real_opacity);
        color.premultiply ();
        
        Cogl.pango_render_layout (layout, 1, 1, color, 0);
    }
}

private class Journal.ImageContent : Clutter.Actor {
    private Clutter.Canvas canvas;
    private Gdk.Pixbuf pixbuf;
    
    private int border_width = 4;
    
    //Used for highlight the border on mouse over
    private bool enter;
    private bool _highlight_border;
    public bool highlight_items {
        get {
            return _highlight_border;
        } 
        set {
            _highlight_border = value;
            reactive = value;
        }
    }
    
    public signal void clicked ();

    private ImageContent (bool highlight_items=false) {
        GLib.Object ();
        
        this.reactive = highlight_items;
        this.canvas = new Clutter.Canvas ();
        canvas.draw.connect ((cr, w, h) => { return paint_canvas (cr, w, h); });
        this.set_content (canvas);
      
        this.set_content_scaling_filters (Clutter.ScalingFilter.TRILINEAR,
                                          Clutter.ScalingFilter.LINEAR);
                                          
        this.allocation_changed.connect ((box, f) => {
            Idle.add (()=>{
                //see this http://www.mail-archive.com/clutter-app-devel-list@clutter-project.org/msg00116.html
                canvas.set_size ((int)box.get_width (), (int) box.get_height ());
                return false;
            });
       });
       
       enter = false;
       this.highlight_items = highlight_items;
    }
    
    public ImageContent.from_uri (string uri, bool highlight_items=false) {
        try {
            pixbuf =  new Gdk.Pixbuf.from_file (uri);
        } catch (Error e) {
            debug ("Can't load " + uri);
            pixbuf = Utils.load_fallback_icon ();
        }
        if (pixbuf != null)
            this.from_pixbuf (pixbuf, highlight_items);
    }
    
     public ImageContent.from_pixbuf (Gdk.Pixbuf pixbuf, bool highlight_items=false) {
        this (highlight_items);
        this.pixbuf = pixbuf;
        this.set_size (pixbuf.width + border_width * 2, 
                       pixbuf.height + border_width * 2);
        canvas.set_size (pixbuf.width + border_width * 2, 
                         pixbuf.height + border_width * 2);
        canvas.invalidate ();
     }
     
     public void set_pixbuf (Gdk.Pixbuf pixbuf) {
        this.pixbuf = pixbuf;
        this.set_size (pixbuf.width + border_width * 2,
                       pixbuf.height + border_width * 2);
        canvas.set_size (pixbuf.width + border_width * 2,
                         pixbuf.height + border_width * 2);
        canvas.invalidate ();
     }
     
     private bool paint_canvas (Cairo.Context cr, int width, int height) {
         cr.save ();
         cr.set_source_rgba (0.0, 0.0, 0.0, 0.0);
         cr.set_operator (Cairo.Operator.SOURCE);
         cr.paint ();
         cr.restore ();
         
//         var p = new Cairo.Pattern.linear (0, 0, width, height);
//         p.add_color_stop_rgba (0, 0, 0, 0, 0.4);
//         p.add_color_stop_rgba (0.7, 0.4, 0, 0, 0.0);
//         cr.set_source (p);
//         cr.set_operator (Cairo.Operator.SOURCE);
//         cr.rectangle (0, 0, width, height);
//         cr.fill ();
       
         var radius = 10.0f;
         cr.move_to(0, radius);
         cr.curve_to(0, 0, 0, 0, radius, 0);
         cr.line_to(width - radius, 0);
         cr.curve_to(width, 0, width, 0, width, radius);
         cr.line_to(width, height - radius);
         cr.curve_to(width, height, width, height, width - radius, height);
         cr.line_to(radius, height);
         cr.curve_to(0, height, 0, height, 0, height - radius);
         cr.close_path();
          
         if (enter && highlight_items) {
            var color = Utils.get_roundbox_border_color ();
            Clutter.Color borderColor = Utils.gdk_rgba_to_clutter_color (color);
            borderColor = borderColor.darken ();
            Clutter.cairo_set_source_color(cr, borderColor);
            cr.stroke_preserve ();
         }
         cr.clip();
         cr.translate (border_width, border_width);
         Gdk.cairo_set_source_pixbuf (cr, pixbuf, 0, 0);
         cr.paint ();
         return true;
     }
     
     public override  bool enter_event (Clutter.CrossingEvent event) {
        enter = true;
        canvas.invalidate ();
        return false;
    }
    
    public override  bool leave_event (Clutter.CrossingEvent event) {
        enter = false;
        canvas.invalidate ();
        return false;
    }
    
    public override  bool button_release_event (Clutter.ButtonEvent event) {
        clicked ();
        return true;
    }
}

private class Journal.VideoContent : Clutter.Actor {

    private ClutterGst.VideoTexture video;
    private ImageContent preview;
    private bool playing;

    public VideoContent (string uri, Gdk.Pixbuf thumbnail) {
        GLib.Object ();
        this.playing = false;
        this.reactive = true;
        
        video = new ClutterGst.VideoTexture ();
        //FIXME IMPROVE
        video.set_keep_aspect_ratio (true);
        video.set_property("seek-flags", 1);
        video.set_uri (uri);
        
        preview = new ImageContent.from_pixbuf (thumbnail);
        video.set_size (thumbnail.width, thumbnail.height);
        
        this.enter_event.connect ((e) => {
            if (!playing) {
                this.playing = true;
                video.set_playing (playing);
                video.show ();
                preview.hide ();
            }
            return false;
        });
        this.leave_event.connect ((e) => {
            this.playing = false;
            video.set_playing (playing);
            video.set_progress (0);
            return false;
        });
        
        this.add_child (preview);
        this.add_child (video);
        video.hide ();
    }
    
    public void set_thumbnail (Gdk.Pixbuf thumbnail) {
        preview.set_pixbuf (thumbnail);
        video.set_size (thumbnail.width, thumbnail.height);
    }
}

private class Journal.GenericActor : Clutter.Actor {
    private TextActor title;
    private Clutter.Actor actor_content;
    private TextActor time;
    
    public GenericActor (string title_text, string date) {
        GLib.Object ();
        this.reactive = true;

        var attr_list = new Pango.AttrList ();
        attr_list.insert (Pango.attr_scale_new (Pango.Scale.LARGE));
        attr_list.insert (Pango.attr_weight_new (Pango.Weight.SEMIBOLD));

        title = new TextActor.full_text (title_text, attr_list);
        title.margin_bottom = 10;

        attr_list = new Pango.AttrList ();
        attr_list.insert (Pango.attr_scale_new (Pango.Scale.SMALL));
        attr_list.insert (Pango.attr_style_new (Pango.Style.ITALIC));

        time = new TextActor.full_text (date, attr_list);
        time.margin_top = 10;
        var box = new Clutter.BoxLayout ();
        box.vertical = true;
        box.spacing = 5;
        set_layout_manager (box);

        this.margin_left = 10;
        this.margin_right = 10;
    }
    
    public void set_content_actor (Clutter.Actor content) {
        this.actor_content = content;
        this.add_child (title);
        this.add_child (actor_content);
        this.add_child (time);
    }
    
    public override void get_preferred_width (float for_height, out float min_width, out float nat_width) {
       float content_min_width, content_nat_width;
       float title_min_width, title_nat_width;
       actor_content.get_preferred_width (-1, out content_min_width, out content_nat_width);
       title.get_preferred_width (-1, out title_min_width, out title_nat_width);
       min_width = float.max (content_min_width, title_min_width) + 10 * 2 ;
       nat_width = float.max (content_nat_width, title_nat_width) + 10 * 2 ;
    }
    
    public override void get_preferred_height (float for_width, out float min_height, out float nat_height) {
       float content_min_height, content_nat_height;
       float title_min_height, title_nat_height;
       float time_min_height, time_nat_height;
       actor_content.get_preferred_height(-1, out content_min_height, out content_nat_height);
       title.get_preferred_height(-1, out title_min_height, out title_nat_height);
       time.get_preferred_height(-1, out time_min_height, out time_nat_height);
       min_height = content_min_height + title_min_height + time_min_height ;
       nat_height = content_nat_height + title_nat_height + time_nat_height;
   }
}

private class Journal.CompositeDocumentWidget : Box {
    
    private Clutter.BoxLayout box;
    public CompositeDocumentWidget (Gdk.Pixbuf? pixbuf, string[] uris) {
        GLib.Object (orientation:Orientation.HORIZONTAL, spacing:10);

        var vbox = new Box (Orientation.VERTICAL, 5);
        foreach (string uri in uris) {
            var l_uri = new Label (uri);
            l_uri.set_ellipsize (Pango.EllipsizeMode.END);
            l_uri.halign = Align.START;
            vbox.pack_start (l_uri, false, false, 0);
        }
        
        var _image = new Image.from_pixbuf (pixbuf);
        this.pack_start(_image, true, true, 0);
        this.pack_start(vbox, true, true, 0);
    }
}

private class Journal.CompositeApplicationActor : Clutter.Actor {
    
    public TextActor title;
    private TextActor time;
    private Clutter.Actor icon_box;
    
    private Clutter.BoxLayout box;
    public CompositeApplicationActor (string title_s, ImageContent[] pixbufs, string date) {
        GLib.Object ();
        this.reactive = true;
        
        var attr_list = new Pango.AttrList ();
        attr_list.insert (Pango.attr_scale_new (Pango.Scale.LARGE));
        attr_list.insert (Pango.attr_weight_new (Pango.Weight.SEMIBOLD));

        title = new TextActor.full_text (title_s, attr_list);
        title.margin_bottom = 10;

        attr_list = new Pango.AttrList ();
        attr_list.insert (Pango.attr_scale_new (Pango.Scale.SMALL));
        attr_list.insert (Pango.attr_style_new (Pango.Style.ITALIC));

        time = new TextActor.full_text (date, attr_list);
        time.margin_top = 10;
        box = new Clutter.BoxLayout ();
        box.vertical = true;
        set_layout_manager (box);

        icon_box = new Clutter.Actor ();
        var manager = new Clutter.BoxLayout ();
        manager.vertical = false;
        manager.spacing = 2;
        icon_box.set_layout_manager (manager);
        foreach (ImageContent image in pixbufs) {
            icon_box.add_child (image);
        }
        
        this.add_child (title);
        this.add_child (icon_box);
        this.add_child (time);
        
        this.margin_left = this.margin_right = 10;
    }
    
    public override void get_preferred_width (float for_height, out float min_width, out float nat_width) {
       float box_min_width, box_nat_width;
       float title_min_width, title_nat_width;
       icon_box.get_preferred_width (-1, out box_min_width, out box_nat_width);
       title.get_preferred_width (-1, out title_min_width, out title_nat_width);
       min_width = float.max (box_min_width, title_min_width) + 10 * 2 ;
       nat_width = float.max (box_nat_width, title_nat_width) + 10 * 2 ;
    }
   
   public override void get_preferred_height (float for_width, out float min_height, out float nat_height) {
       float box_min_height, box_nat_height;
       float title_min_height, title_nat_height;
       float time_min_height, time_nat_height;
       icon_box.get_preferred_height(-1, out box_min_height, out box_nat_height);
       title.get_preferred_height(-1, out title_min_height, out title_nat_height);
       time.get_preferred_height(-1, out time_min_height, out time_nat_height);
       min_height = box_min_height + title_min_height + time_min_height ;
       nat_height = box_nat_height + title_nat_height + time_nat_height;
   }
}

private class Journal.CompositeImageActor : Clutter.Actor {
    
    public TextActor title;
    private TextActor time;
    private Clutter.Actor image_box;
    
    private Clutter.BoxLayout box;
    public CompositeImageActor (string title_s, ImageContent[] pixbufs, string date) {
        GLib.Object ();
        this.reactive = true;
        
        var attr_list = new Pango.AttrList ();
        attr_list.insert (Pango.attr_scale_new (Pango.Scale.LARGE));
        attr_list.insert (Pango.attr_weight_new (Pango.Weight.SEMIBOLD));

        title = new TextActor.full_text (title_s, attr_list);
        title.margin_bottom = 10;

        attr_list = new Pango.AttrList ();
        attr_list.insert (Pango.attr_scale_new (Pango.Scale.SMALL));
        attr_list.insert (Pango.attr_style_new (Pango.Style.ITALIC));

        time = new TextActor.full_text (date, attr_list);
        time.margin_top = 10;
        box = new Clutter.BoxLayout ();
        box.vertical = true;
        set_layout_manager (box);

        image_box = new Clutter.Actor ();
        var manager = new Clutter.TableLayout ();
        manager.column_spacing = 2;
        manager.row_spacing = 2;
        image_box.set_layout_manager (manager);
        int z = 0;
        if (pixbufs.length > 3) {
            int num_row = pixbufs.length / 3 + 1;
            for (int i = 0; i < num_row; i++)
                for (int j = 0; j < 3 && z < pixbufs.length; j++, z++) {
                    manager.pack (pixbufs[z], j, i);
                    manager.set_fill (pixbufs[z], false, false);
                }
        }
        else{
            for (int i = 0; i < pixbufs.length; i++) {
                manager.pack (pixbufs[i], 0, i);
                manager.set_fill (pixbufs[z], false, false);
            }
        }
        
        this.add_child (title);
        this.add_child (image_box);
        this.add_child (time);
        
        this.margin_left = this.margin_right = 10;
    }
    
    public override void get_preferred_width (float for_height, out float min_width, out float nat_width) {
       float box_min_width, box_nat_width;
       float title_min_width, title_nat_width;
       image_box.get_preferred_width (-1, out box_min_width, out box_nat_width);
       title.get_preferred_width (-1, out title_min_width, out title_nat_width);
       min_width = float.max (box_min_width, title_min_width) + 10 * 2 ;
       nat_width = float.max (box_nat_width, title_nat_width) + 10 * 2 ;
    }
   
   public override void get_preferred_height (float for_width, out float min_height, out float nat_height) {
       float box_min_height, box_nat_height;
       float title_min_height, title_nat_height;
       float time_min_height, time_nat_height;
       image_box.get_preferred_height(-1, out box_min_height, out box_nat_height);
       title.get_preferred_height(-1, out title_min_height, out title_nat_height);
       time.get_preferred_height(-1, out time_min_height, out time_nat_height);
       min_height = box_min_height + title_min_height + time_min_height ;
       nat_height = box_nat_height + title_nat_height + time_nat_height;
   }
}

