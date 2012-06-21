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

    private ImageContent () {
        GLib.Object ();
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
    }
    
    public ImageContent.from_uri (string uri) {
        try {
            pixbuf =  new Gdk.Pixbuf.from_file (uri);
        } catch (Error e) {
            debug ("Can't load " + uri);
            pixbuf = Utils.load_fallback_icon ();
        }
        if (pixbuf != null)
            this.from_pixbuf (pixbuf);
    }
    
     public ImageContent.from_pixbuf (Gdk.Pixbuf pixbuf) {
        this ();
        this.pixbuf = pixbuf;
        this.set_size (pixbuf.width, pixbuf.height);
        canvas.set_size (pixbuf.width, pixbuf.height);
        canvas.invalidate ();
     }
     
     public void set_pixbuf (Gdk.Pixbuf pixbuf) {
        this.pixbuf = pixbuf;
        this.set_size (pixbuf.width, pixbuf.height);
        canvas.set_size (pixbuf.width, pixbuf.height);
        canvas.invalidate ();
     }
     
     private bool paint_canvas (Cairo.Context cr, int width, int height) {
         cr.save ();
         cr.set_source_rgba (0.0, 0.0, 0.0, 0.0);
         cr.set_operator (Cairo.Operator.SOURCE);
         cr.paint ();
         cr.restore ();
       
         cr.set_line_width (2);
         var radius = 20.0f;
         cr.move_to(0, radius);
         cr.curve_to(0, 0, 0, 0, radius, 0);
         cr.line_to(width - radius, 0);
         cr.curve_to(width, 0, width, 0, width, radius);
         cr.line_to(width, height - radius);
         cr.curve_to(width, height, width, height, width - radius, height);
         cr.line_to(radius, height);
         cr.curve_to(0, height, 0, height, 0, height - radius);
         cr.close_path();
          
         cr.clip();
         Gdk.cairo_set_source_pixbuf (cr, pixbuf, 0, 0);
         cr.paint ();
         return true;
     }
}

private class Journal.VideoContent : Clutter.Actor {

    private ClutterGst.VideoTexture video;
    private bool playing;

    public VideoContent (string uri) {
        GLib.Object ();
        this.playing = false;
        this.reactive = true;
        
        video = new ClutterGst.VideoTexture ();
        //FIXME IMPROVE
        video.set_height (MEDIA_SIZE_NORMAL);
        video.set_width (MEDIA_SIZE_NORMAL * 1.5f);
        video.set_keep_aspect_ratio (true);
        video.set_property("seek-flags", 1);
        video.set_uri (uri);
        
        video.size_change.connect ((b_w, b_h) => {
            //FIXME Improve!
            b_w /= 4;
            b_h /= 4;
            video.save_easing_state();
            video.set_size (b_w, b_h);
            video.restore_easing_state();
        });
        
        this.enter_event.connect ((e) => {
            if (!playing) {
                this.playing = true;
                video.set_playing (playing);
            }
            return false;
        });
        this.leave_event.connect ((e) => {
            this.playing = false;
            video.set_playing (playing);
            video.set_progress (0);
            return false;
        });
        
        this.add_child (video);
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

private class Journal.CompositeDocumentActor : Clutter.Actor {
    
    public TextActor title;
    private ImageContent image;
    private TextActor time;
    
    private Clutter.BoxLayout box;
    public CompositeDocumentActor (string title_s, Gdk.Pixbuf? pixbuf, string[] uris, string date) {
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
        image = new ImageContent.from_pixbuf (pixbuf);
        image.margin_top = 10;
        image.margin_bottom = 10;
        image.margin_right = 5;
        box = new Clutter.BoxLayout ();
        box.vertical = true;
        set_layout_manager (box);

        var t_box = new Clutter.Actor ();
        var manager = new Clutter.BoxLayout ();
        manager.vertical = true;
        t_box.set_layout_manager (manager);
        float max_w = 0;
        foreach (string uri in uris) {
            attr_list = new Pango.AttrList ();
            attr_list.insert (Pango.attr_scale_new (Pango.Scale.MEDIUM));
            //attr_list.insert (Pango.attr_style_new (Pango.Style.ITALIC));
            var uri_text = new TextActor.full_text (uri, attr_list);
            if (uri_text.width > max_w) max_w = uri_text.width;
            t_box.add_child (uri_text);
            manager.set_alignment (uri_text, Clutter.BoxAlignment.START, 
                                           Clutter.BoxAlignment.START);
        }
        
        var tmp_box = new Clutter.Actor ();
        var manager2 = new Clutter.BoxLayout ();
        manager2.vertical = false;
        tmp_box.set_layout_manager (manager2);
        tmp_box.add_child (image);
        manager2.set_alignment(image, Clutter.BoxAlignment.START, 
                                           Clutter.BoxAlignment.START);
        tmp_box.add_child (t_box);
        
        this.add_child (title);
        this.add_child(tmp_box);
        this.add_child (time);
        
        this.margin_left = this.margin_right = 10;
    }
}

private class Journal.CompositeApplicationActor : Clutter.Actor {
    
    public TextActor title;
    private TextActor time;
    private Clutter.Actor icon_box;
    
    private Clutter.BoxLayout box;
    public CompositeApplicationActor (string title_s, string[] uris, string date) {
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
        foreach (string uri in uris) {
            var info = new  DesktopAppInfo (uri);
            if (info == null)
                continue;
            Gdk.Pixbuf pixbuf = Utils.load_pixbuf_from_icon (info.get_icon ());
            var image = new ImageContent.from_pixbuf (pixbuf);
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
        var manager = new Clutter.BoxLayout ();
        manager.vertical = false;
        manager.spacing = 2;
        image_box.set_layout_manager (manager);
        foreach (ImageContent image in pixbufs) {
            image_box.add_child (image);
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

