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
 
using Gtk;
using Gst;

private class Journal.ImageContent : EventBox {

    private Image image;
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
        }
    }
    
    public signal void clicked ();

    private ImageContent (bool highlight_items=false) {
        GLib.Object ();
        this.name = "image-box";
        this.add_events (Gdk.EventMask.ENTER_NOTIFY_MASK |
                         Gdk.EventMask.LEAVE_NOTIFY_MASK |
                         Gdk.EventMask.BUTTON_RELEASE_MASK);
        
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
        image = new Image.from_pixbuf (pixbuf);
        image.draw.connect (on_draw);
        
        this.add (image);
        image.queue_draw ();
     }
     
     public void set_from_pixbuf (Gdk.Pixbuf pixbuf) {
        this.pixbuf = pixbuf;
        image.queue_draw ();
     }
     
     private bool on_draw (Cairo.Context cr) {
         Gtk.Allocation alloc;
         image.get_allocation (out alloc);
         int width = alloc.width;
         int height = alloc.height;
         
//         var p = new Cairo.Pattern.linear (0, 0, width, height);
//         p.add_color_stop_rgba (0, 0, 0, 0, 0.4);
//         p.add_color_stop_rgba (0.7, 0.4, 0, 0, 0.0);
//         cr.set_source (p);
//         cr.set_operator (Cairo.Operator.SOURCE);
//         cr.rectangle (0, 0, width, height);
//         cr.fill ();
       
         var radius = 5.0f;
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
            Gdk.cairo_set_source_rgba (cr, color);
            cr.stroke_preserve ();
         }
         cr.clip();
         cr.translate (border_width, border_width);
         Gdk.cairo_set_source_pixbuf (cr, pixbuf, 0, 0);
         cr.paint ();
         return true;
     }
     
     public override  bool enter_notify_event (Gdk.EventCrossing event) {
        warning ("qui");
        enter = true;
        image.queue_draw ();
        return false;
    }
    
    public override  bool leave_notify_event (Gdk.EventCrossing event) {
        enter = false;
        image.queue_draw ();
        return false;
    }
    
    public override  bool button_release_event (Gdk.EventButton event) {
        warning ("sii");
        clicked ();
        return true;
    }
}
private class Journal.VideoWidget : EventBox {

    private DrawingArea drawing_area;
    private Element src;
    private Element sink;
    private ulong xid;

    public VideoWidget (string uri) {
        GLib.Object ();
        this.add_events (Gdk.EventMask.ENTER_NOTIFY_MASK |
                         Gdk.EventMask.LEAVE_NOTIFY_MASK |
                         Gdk.EventMask.BUTTON_RELEASE_MASK);
        this.drawing_area = new DrawingArea ();
        this.drawing_area.realize.connect(on_realize);
        this.drawing_area.set_size_request (400, 300);

        add (drawing_area);
        
        this.src = ElementFactory.make ("playbin", "player");
        this.src.set_property("uri", uri);
        this.sink = ElementFactory.make ("xvimagesink", "sink");
        this.sink.set_property ("force-aspect-ratio", true);
        
        this.src.set_property("video-sink", sink);
        
        this.enter_notify_event.connect ((e) => {
            on_play ();
            return false;
        });
        this.leave_notify_event.connect ((e) => {
            on_stop ();
            return false;
        });
    }
    
    private void on_realize() {
        this.xid = (ulong)Gdk.X11Window.get_xid (this.drawing_area.get_window());
        on_play ();
    }
    
    private void on_play () {
        var xoverlay = (XOverlay)this.sink;
        xoverlay.set_xwindow_id (this.xid);
        this.src.set_state (State.PLAYING);
    }

    private void on_stop () {
        this.src.set_state (State.READY);
    }
}

private class Journal.CompositeDocumentWidget : Box {
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

private class Journal.CompositeApplicationWidget : Box {
    public CompositeApplicationWidget (ImageContent[] pixbufs) {
        GLib.Object (orientation:Orientation.HORIZONTAL, spacing:10);

        foreach (ImageContent image in pixbufs) {
            if (image == null)
                continue;
            this.pack_start (image, false, false, 0);
        }
    }
}

private class Journal.CompositeImageWidget : Box {
    private Widget image_box;

    public CompositeImageWidget (ImageContent[] pixbufs) {
        GLib.Object (orientation:Orientation.HORIZONTAL, spacing:0);

        int z = 0;
        if (pixbufs.length > 3) {
            int num_row = pixbufs.length / 3 + 1;
            image_box = new Table (num_row, 3, false);
            for (int i = 0; i < num_row; i++)
                for (int j = 0; j < 3 && z < pixbufs.length; j++, z++)
                   ((Table)image_box).attach_defaults (pixbufs[z], j, j+1, i, i+1);
        }
        else{
            image_box = new Box (Orientation.HORIZONTAL, 5);
            for (int i = 0; i < pixbufs.length; i++)
                ((Box)image_box).pack_start (pixbufs[i], true, true, 0);
        }
        
        this.add (image_box);
    }
}

