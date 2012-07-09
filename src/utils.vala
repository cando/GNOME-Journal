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
    private static Gnome.DesktopThumbnailFactory factory;
    
    static construct{
        settings = new GLib.Settings ("org.gnome.journal");
        factory = new Gnome.DesktopThumbnailFactory (Gnome.ThumbnailSize.NORMAL);
    }

    public static string get_pkgdata (string? file_name = null) {
        return Path.build_filename (Config.PKGDATADIR, file_name);
    }

    public static string get_style (string? file_name = null) {
        return Path.build_filename (get_pkgdata (), "style", file_name);
    }

    public static Clutter.Color gdk_rgba_to_clutter_color (Gdk.RGBA gdk_rgba) {
        Clutter.Color color = {
            (uint8) (gdk_rgba.red * 255).clamp (0, 255),
            (uint8) (gdk_rgba.green * 255).clamp (0, 255),
            (uint8) (gdk_rgba.blue * 255).clamp (0, 255),
            (uint8) (gdk_rgba.alpha * 255).clamp (0, 255)
        };

        return color;
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
        style.add_class ("timeline-clutter");
        return style.get_background_color (0);
    }
    
    public static Gdk.RGBA get_timeline_circle_color () {
        var style = new Gtk.StyleContext ();
        var path = new Gtk.WidgetPath ();
        path.append_type (typeof (Gtk.Window));
        style.set_path (path);
        style.add_class ("timeline-clutter");
        return style.get_color (0);
    }
    
    public static Gdk.RGBA get_roundbox_bg_color () {
        var style = new Gtk.StyleContext ();
        var path = new Gtk.WidgetPath ();
        path.append_type (typeof (Gtk.Window));
        style.set_path (path);
        style.add_class ("round-button-left");
        return style.get_background_color (0);
    }
    
    public static Gdk.RGBA get_roundbox_border_color () {
        var style = new Gtk.StyleContext ();
        var path = new Gtk.WidgetPath ();
        path.append_type (typeof (Gtk.Window));
        style.set_path (path);
        style.add_class ("round-button-left");
        return style.get_border_color (0);
    }
    
    public static Gdk.RGBA get_roundbox_border_hover_color () {
        var style = new Gtk.StyleContext ();
        var path = new Gtk.WidgetPath ();
        path.append_type (typeof (Gtk.Window));
        style.set_path (path);
        style.add_class ("round-button-left");
        return style.get_border_color (StateFlags.PRELIGHT);
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
    
    //DATE UTILS
    public static DateTime get_date_for_event (Zeitgeist.Event e) {
        int64 timestamp = e.get_timestamp () / 1000;
        //TODO To localtime here? Zeitgeist uses UTC timestamp, right?
        DateTime date = new DateTime.from_unix_utc (timestamp).to_local ();
        return date;
    }
    
    public static DateTime get_start_of_the_day (int64 time) {
        int64 timestamp = time / 1000;
        //TODO To localtime here? Zeitgeist uses UTC timestamp, right?
        DateTime date = new DateTime.from_unix_utc (timestamp).to_local ();
        int day, month, year;
        date.get_ymd (out year, out month, out day);
        var start_of_day = new DateTime.local (year, month, day, 0, 0, 0);
        return start_of_day;
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

}
