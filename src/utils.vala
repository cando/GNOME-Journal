// This file is part of GNOME Activity Journal.
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
        settings = new GLib.Settings ("org.gnome.activity-journal");
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

    public static int getIconSize() {
//        int view_type = settings.get_int ("mainview-type");
//        if (view_type == Gd.MainViewType.LIST)
//            return LIST_VIEW_SIZE;
//        else
           return ICON_VIEW_SIZE;
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

}
