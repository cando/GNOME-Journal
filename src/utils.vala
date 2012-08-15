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
using Config;

private class Journal.Utils : Object{
    // FIXME: Remove these when we can use Vala release that provides binding for gdkkeysyms.h
    public const uint F11_KEY = 0xffc8;
    public const int ICON_VIEW_SIZE = 128;
    public const int LIST_VIEW_SIZE = 48;
    
    public static GLib.Settings settings;
    public static Gee.HashMap<string, string> categories_map;
    private static Gnome.DesktopThumbnailFactory factory;
    
    static construct{
        settings = new GLib.Settings ("org.gnome.journal");
        factory = new Gnome.DesktopThumbnailFactory (Gnome.ThumbnailSize.NORMAL);
        categories_map = new Gee.HashMap<string, string> ();
        
        //Initialize categories_map
        categories_map.set (_("All Activities"), "");
        categories_map.set (_("Documents"), Zeitgeist.NFO_DOCUMENT);
        categories_map.set (_("Code"), Zeitgeist.NFO_SOURCE_CODE);
        categories_map.set (_("Pictures"), Zeitgeist.NFO_IMAGE);
        categories_map.set (_("Audio"), Zeitgeist.NFO_AUDIO);
        categories_map.set (_("Video"), Zeitgeist.NFO_VIDEO);
        categories_map.set (_("Web"), Zeitgeist.NFO_WEBSITE);
        categories_map.set (_("Tasks"), Zeitgeist.NCAL_TODO);
        categories_map.set (_("Archives"), Zeitgeist.NFO_ARCHIVE);
        categories_map.set (_("Folders"), Zeitgeist.NFO_FOLDER);
    }

    public static string get_pkgdata (string? file_name = null) {
        return Path.build_filename (Config.PKGDATADIR, file_name);
    }

    public static string get_style (string? file_name = null) {
        return Path.build_filename (get_pkgdata (), "style", file_name);
    }
    
    public static string get_icon (string? file_name = null) {
        return Path.build_filename (get_pkgdata (), "icons", file_name);
    }

    public static Gdk.RGBA get_journal_bg_color () {
        var style = new Gtk.StyleContext ();
        var path = new Gtk.WidgetPath ();
        path.append_type (typeof (Gtk.Window));
        style.set_path (path);
        style.add_class ("theme_bg_color");
        return style.get_background_color (0);
    }
    
    public static Gdk.RGBA get_timeline_bg_color () {
        var style = new Gtk.StyleContext ();
        var path = new Gtk.WidgetPath ();
        path.append_type (typeof (Gtk.Window));
        style.set_path (path);
        style.add_class ("timeline-gtk");
        return style.get_background_color (0);
    }
    
    public static Gdk.RGBA get_timeline_circle_color () {
        var style = new Gtk.StyleContext ();
        var path = new Gtk.WidgetPath ();
        path.append_type (typeof (Gtk.Window));
        style.set_path (path);
        style.add_class ("timeline-gtk");
        return style.get_color (0);
    }
    
    public static Gdk.RGBA get_roundbox_bg_color () {
        var style = new Gtk.StyleContext ();
        var path = new Gtk.WidgetPath ();
        path.append_type (typeof (Gtk.Window));
        style.set_path (path);
        style.add_class ("round-bubble-left");
        return style.get_background_color (0);
    }
    
    public static Gdk.RGBA get_roundbox_border_color () {
        var style = new Gtk.StyleContext ();
        var path = new Gtk.WidgetPath ();
        path.append_type (typeof (Gtk.Window));
        style.set_path (path);
        style.add_class ("round-bubble-left");
        return style.get_border_color (0);
    }
    
    public static Gdk.RGBA get_roundbox_border_hover_color () {
        var style = new Gtk.StyleContext ();
        var path = new Gtk.WidgetPath ();
        path.append_type (typeof (Gtk.Window));
        style.set_path (path);
        style.add_class ("round-bubble-hover");
        return style.get_border_color (0);
    }

    public static int getIconSize() {
//        int view_type = settings.get_int ("mainview-type");
//        if (view_type == Gd.MainViewType.LIST)
//            return LIST_VIEW_SIZE;
//        else
           return ICON_VIEW_SIZE;
    }
    
    public static Gdk.Pixbuf? load_pixbuf_from_name (string name, int size = 48) {
        IconInfo icon_info = 
                Gtk.IconTheme.get_default().lookup_icon (name, size,
                                            IconLookupFlags.FORCE_SVG | 
                                            IconLookupFlags.GENERIC_FALLBACK);
        if (icon_info != null) {
            try {
                return icon_info.load_icon();
            } catch (Error e) {
                warning ("Unable to load pixbuf: " + e.message);
            }
        }
        return null;
    }
    
    public static Gdk.Pixbuf? load_innacessible_item_icon (int size = 48) {
        Gdk.Pixbuf? pixbuf = null;
        try {
            pixbuf = new Gdk.Pixbuf.from_file (Utils.get_icon("no-item.png"));
        } catch (Error e) {
             warning ("Unable to load pixbuf: " + e.message);
        } 
        return pixbuf;
    }
    
    public static Gdk.Pixbuf? load_pixbuf_from_icon (Icon icon, int size = 48) {
        IconInfo icon_info = null;
        if (icon != null)
            icon_info = 
                Gtk.IconTheme.get_default().lookup_by_gicon (icon, size,
                                            IconLookupFlags.FORCE_SVG | 
                                            IconLookupFlags.GENERIC_FALLBACK);
        if (icon_info != null) {
            try {
                return icon_info.load_icon();
            } catch (Error e) {
                warning ("Unable to load pixbuf: " + e.message);
            }
        }
        return null;
    }
    
    public static Gdk.Pixbuf? load_fallback_icon () {
        var _icon = ContentType.get_icon ("text/plain");
        return load_pixbuf_from_icon (_icon, Utils.getIconSize ());
    }

    public async static bool queue_thumbnail_job_for_file_async (File file) {
        SourceFunc callback = queue_thumbnail_job_for_file_async.callback;
        bool result = false;

         IOSchedulerJob.push(() => {
            Gdk.Pixbuf pixbuf = null;
            FileInfo info;
            string uri = file.get_uri ();
            try{
                info = file.query_info (FileAttribute.TIME_MODIFIED +","+ 
                                        FileAttribute.STANDARD_CONTENT_TYPE,
                                        0, null);
            } catch (Error e) {
                warning ("Unable to query info for file at " + uri + ": " + e.message);
                result = false;
                return false;
            }
            
            uint64 mtime = info.get_attribute_uint64 (FileAttribute.TIME_MODIFIED);
            string mime_type = info.get_content_type ();

            if (mime_type != null)
                pixbuf = factory.generate_thumbnail (uri, mime_type);
            else 
                result = false;

            if (pixbuf != null) {
                factory.save_thumbnail (pixbuf, uri, (ulong)mtime);
                result = true;
            }
            else
                result = false;

            Idle.add((owned) callback);
            return false;
        }, Priority.DEFAULT, null);

    yield;
    return result;
    }
    
    public static bool is_search_event (Gdk.EventKey event) {
        var keyval = event.keyval;
        var state = event.state;
        var retval =
        (((keyval == Gdk.Key.f) &&
          ((state & Gdk.ModifierType.CONTROL_MASK) != 0)) ||
         ((keyval == Gdk.Key.s) &&
          ((state & Gdk.ModifierType.CONTROL_MASK) != 0)));
        return retval;
    }
    
    public static bool is_go_back_event (Gdk.EventKey event) {
        var keyval = event.keyval;
        var state = event.state;
        var retval =
        ((keyval == Gdk.Key.BackSpace) ||
         ((keyval == Gdk.Key.Left) &&
          ((state & Gdk.ModifierType.MOD1_MASK) != 0)) ||
         ((keyval == Gdk.Key.Left) &&
          ((state & Gdk.ModifierType.CONTROL_MASK) != 0)));
        return retval;
    }
    
    public static bool is_jump_start_event (Gdk.EventKey event) {
        var keyval = event.keyval;
        var state = event.state;
        var retval =
        ((keyval == Gdk.Key.@1) ||
         ((keyval == Gdk.Key. @1) &&
          ((state & Gdk.ModifierType.MOD1_MASK) != 0)) ||
         ((keyval == Gdk.Key.@1) &&
          ((state & Gdk.ModifierType.CONTROL_MASK) != 0)));
        return retval;
    }
    
    public static bool is_esc_event (Gdk.EventKey event) {
        var keyval = event.keyval;
        var retval = (keyval == Gdk.Key.Escape);
        return retval;
    }
    
    //DATE UTILS
    public static DateTime get_date_for_event (Zeitgeist.Event e) {
        int64 timestamp = e.get_timestamp () / 1000;
        DateTime date = new DateTime.from_unix_local (timestamp);
        return date;
    }
    
    public static DateTime get_start_of_the_day (int64 time) {
        int64 timestamp = Zeitgeist.Timestamp.prev_midnight (time);
        DateTime date = new DateTime.from_unix_local (timestamp / 1000);
        return date;
    }
    
    public static DateTime get_start_of_today () {
        var today = new DateTime.now_local ();
        int day, month, year;
        today.get_ymd (out year, out month, out day);
        today = new DateTime.local (year, month, day, 0, 0, 0);
        return today;
    }
    
    public static DateTime datetime_from_string (string date) {
        string[] tmp = date.split ("-");
        int year = int.parse (tmp[0]);
        int month = int.parse (tmp[1]);
        int day = int.parse (tmp [2]);
        return new DateTime.local(year, month, day, 0, 0, 0);
    }
  
    public static bool is_today (string date) {
        var tmp = Utils.datetime_from_string (date);
        var today = Utils.get_start_of_today ();
        return tmp.compare (today) == 0;
    }
}
