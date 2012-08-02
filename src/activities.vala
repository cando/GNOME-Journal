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
 
using Gdk;
using Gtk;

private abstract class Journal.GenericActivity : Object {
    
    public Widget content {
        get; protected set;
    }
    
    public int64 time_start {
        get; protected set;
    }
    
    public int64 time_end {
        get; protected set;
    }
    
    public string title {
        get; protected set;
    }
    
    public string num_activities_title {
        get; protected set;
    }
    
    public string date {
        get; protected set;
    }
    
    public string part_of_the_day {
        get; set;
    }
    
    public Pixbuf? icon {
        get; protected set;
    }
    
    /*Used to discrimante bubbles in which the "..." button should be showed*/
    public bool show_more {
        get; protected set;
    }
    
    public abstract void launch ();
    
    public abstract void create_content ();
    
    public abstract Gee.List<uint> get_events_id ();
    
}

private class Journal.SingleActivity : GenericActivity {

    public Zeitgeist.Event event {
        get; construct set;
    }
    
    public string uri {
        get; private set;
    }
    
    public Pixbuf? thumb_icon {
        get; protected set;
    }
    
    public string display_uri {
        get; private set;
    }
    
    public bool selected {
        get; set;
    }
    
    public string mimetype {
        get; private set;
    }
    
    public string interpretation {
        get; private set;
    }
    
    private Zeitgeist.Subject subject;
    private string thumb_path;
    
    public signal void thumb_loaded ();

    public SingleActivity (Zeitgeist.Event event) {
        Object (event: event);
    }
    
    construct {
        this.subject = event.get_subject (0);
        this.uri = subject.get_uri ();
        this.thumb_icon = null;
        this.display_uri = create_display_uri ();
        this.title = subject.get_text () == null ? 
                     this.display_uri : subject.get_text ();
        this.num_activities_title = null;
        this.time_start = this.time_end = event.get_timestamp ();
        this.selected = false;
        this.mimetype = subject.get_mimetype ();
        string intpr = subject.get_interpretation ();
        if (intpr == null) 
            //Better way for handling this?
            intpr = Zeitgeist.NFO_DOCUMENT;
        this.interpretation = intpr;
        var d = new DateTime.from_unix_utc (this.time_start / 1000).to_local ();
        this.date = d.format ("%H:%M");
        this.show_more = false;

        updateActivityIcon ();
        create_content ();
       
    }
    
    private string create_display_uri () {
        string home = Environment.get_home_dir ();
        string origin = this.subject.get_origin ();
        string uri, display_uri;
        if (origin != null) {
            uri = origin.split ("://")[1];
            display_uri = uri.replace (home, "~");
        }
        else {
            uri = this.uri.split ("://")[1];
            display_uri = uri;
        }
        return display_uri;
    }
    
    //The code related to this function is extracted, ported and adapted
    //from GNOME Documents. Thanks!
    //TODO move the file:// code in the DocumentActivity Class
    // Let's make it generic.
    protected virtual async void updateActivityIcon () {
        updateTypeIcon ();
        
        //TODO Icon for WEB Events?
        if (!uri.has_prefix ("file://"))
            return;
        if (this.thumb_path != null) {
            this.get_thumb ();
            return;
        }

        //Let's try to find the thumb
        var file = File.new_for_uri (this.uri);
        if(!file.query_exists ())
            return;

        FileInfo info = null;
        try {
            info = yield file.query_info_async(FileAttribute.THUMBNAIL_PATH,
                                                    0, 0, null);
        } catch (Error e) {
            debug ("Unable to query info for file at " + this.uri + ": " + e.message);
        }
        
        if (info != null) {
            this.thumb_path = info.get_attribute_byte_string (FileAttribute.THUMBNAIL_PATH);
            if (this.thumb_path != null)
                this.get_thumb ();
        }

        // The thumb doesn't exists: Let's try to create it
        bool thumbnailed = yield Utils.queue_thumbnail_job_for_file_async (file);
        if (!thumbnailed)
            return;

        //Otherwise let's retry to find the thumb
        info = null;
        try {
            info = yield file.query_info_async (FileAttribute.THUMBNAIL_PATH,
                                               0, 0, null);
        } catch (Error e) {
            debug ("Unable to query info for file at " + this.uri + ": " + e.message);
            return;
        }

        this.thumb_path = info.get_attribute_byte_string (FileAttribute.THUMBNAIL_PATH);
        if (this.thumb_path != null)
            this.get_thumb ();
    }
    
    private void updateTypeIcon () {
        Icon _icon = null;
        IconInfo icon_info = null;
        if (this.mimetype != null)
            _icon = ContentType.get_icon (this.mimetype);

        if (_icon != null)
            icon_info = 
                Gtk.IconTheme.get_default().lookup_by_gicon (_icon, Utils.getIconSize (),
                                            IconLookupFlags.FORCE_SVG | 
                                            IconLookupFlags.GENERIC_FALLBACK);
        if (icon_info != null) {
            try {
                this.icon = icon_info.load_icon();
                //Let's use this for the moment.
                this.thumb_icon = this.icon;
            } catch (Error e) {
                debug ("Unable to load pixbuf: " + e.message);
            }
        }
        
        //If the icon is still null let's use a default text/plain mime icon.
        if (icon == null) {
            _icon = ContentType.get_icon ("text/plain");

            if (_icon != null)
                icon_info = 
                    Gtk.IconTheme.get_default().lookup_by_gicon (_icon, Utils.getIconSize (),
                                            IconLookupFlags.FORCE_SVG | 
                                            IconLookupFlags.GENERIC_FALLBACK);
            if (icon_info != null) {
                try {
                    this.icon = icon_info.load_icon();
                    //Let's use this for the moment.
                    this.thumb_icon = this.icon;
                } catch (Error e) {
                    debug ("Unable to load pixbuf: " + e.message);
                }
            }
        }
    }

    private async void get_thumb () {
        var file = File.new_for_path (this.thumb_path);
        try {
            FileInputStream stream = yield file.read_async (Priority.LOW, null);
            this.thumb_icon = yield Pixbuf.new_from_stream_at_scale_async (
                                                       stream, 
                                                       Utils.getIconSize(),
                                                       Utils.getIconSize(),
                                                       true, null);
            update_icon ();
            thumb_loaded ();
        } catch (Error e) {
            debug ("Unable to load pixbuf of"+ this.uri+" : " + e.message);
       }
    }
    
    public override void create_content () {
        this.content = new Image.from_pixbuf (this.icon);
    }
    
    public virtual void update_icon () {
        ((Image)content).set_from_pixbuf (this.thumb_icon);
    }
    
    public override void launch (){
        try {
            AppInfo.launch_default_for_uri (uri, null);
        } catch (Error e) {
            warning ("Impossible to launch " + uri);
        }
    }
    
    public override Gee.List<uint> get_events_id () {
        var list = new Gee.ArrayList<uint> ();
        list.add (event.get_id ());
        return list;
    }
}

/**Single Activity**/
private class Journal.DocumentActivity : SingleActivity {
    public DocumentActivity (Zeitgeist.Event event) {
        Object (event:event);
    }
}

private class Journal.DevelopmentActivity : SingleActivity {
    public DevelopmentActivity (Zeitgeist.Event event) {
        Object (event:event);
    }
}

private class Journal.AudioActivity : SingleActivity {
    public AudioActivity (Zeitgeist.Event event) {
        Object (event:event);
    }
}

private class Journal.ImageActivity : SingleActivity {
    public ImageActivity (Zeitgeist.Event event) {
        Object (event:event);
    }
}

private class Journal.VideoActivity : SingleActivity {
    public VideoActivity (Zeitgeist.Event event) {
        Object (event:event);
    }
    
    public override void create_content () {
        content = new VideoWidget (uri);
    }
    
    public override void update_icon () {
       //None
    }
}

private class Journal.ApplicationActivity : SingleActivity {
    public ApplicationActivity (Zeitgeist.Event event) {
        Object (event:event);
    }
    
    protected override async void updateActivityIcon () {
        var info = new  DesktopAppInfo (display_uri);
        if (info == null) {
             this.icon = Utils.load_pixbuf_from_name ("application-x-executable");
             this.thumb_icon = this.icon;
             return;
        }
        Gdk.Pixbuf pixbuf = Utils.load_pixbuf_from_icon (info.get_icon ());
        this.icon = this.thumb_icon = pixbuf;
    }
    
    public override void update_icon () {
        //do nothing
    }
    
    public override void launch (){
        try {
            var command = display_uri.split (".desktop")[0];
            Process.spawn_command_line_async (command);
        } catch (Error e) {
            warning ("Impossible to launch " + display_uri);
        }
    }
}

private class Journal.WebActivity : SingleActivity {
    public WebActivity (Zeitgeist.Event event) {
        Object (event:event);
    }
}

private class Journal.DownloadActivity : SingleActivity {
    public DownloadActivity (Zeitgeist.Event event) {
        Object (event:event);
    }
}

private class Journal.TodoActivity : ApplicationActivity {
    public TodoActivity (Zeitgeist.Event event) {
        Object (event:event);
    }
    
    protected override async void updateActivityIcon () {
        var info = new  DesktopAppInfo (this.
                                        event.get_actor ().split("://")[1]);
        if (info == null) {
             this.icon = Utils.load_pixbuf_from_name ("application-x-executable");
             this.thumb_icon = this.icon;
             return;
        }
        Gdk.Pixbuf pixbuf = Utils.load_pixbuf_from_icon (info.get_icon ());
        this.icon = this.thumb_icon = pixbuf;
    }
    
    public override void launch (){
        try {
            var command = display_uri.split (".desktop")[0];
            Process.spawn_command_line_async (command);
        } catch (Error e) {
            warning ("Impossible to launch " + display_uri);
        }
    }
}

/**Collection of Activity TODO documention here!**/
private class Journal.CompositeActivity : GenericActivity {

    private const int MAXIMUM_ITEMS = 5;

    public Gee.List<SingleActivity> activities {
        get; construct set;
    }
    
    public string[] uris {
        get; private set;
    }
    
    public bool selected {
        get; set;
    }
    
    public signal void launch_activity (CompositeActivity activity);

    public CompositeActivity (Gee.List<SingleActivity> activities) {
        Object (activities: activities);
    }
    
    construct {
            
        this.uris = new string[int.min (MAXIMUM_ITEMS + 1, activities.size)];
        int i = 0;
        foreach (SingleActivity activity in activities) {
            if (i >= MAXIMUM_ITEMS) {
                this.show_more = true;
//                this.uris[i] = _("...");
                break;
            }
            this.uris[i] = activity.title;
            i++;
        }
        this.icon = create_icon ();
        //Subclasses will modify this.
        this.num_activities_title = create_title ();
        //First activity timestamp? FIXME
        int64 min_start_t = activities.get(0).time_start;
        int64 max_end_t = 0;
        foreach (SingleActivity activity in activities) {
            if (activity.time_start < min_start_t)
                min_start_t = activity.time_start;
            else if (activity.time_start > max_end_t )
                max_end_t = activity.time_start;
        }
        this.time_start = min_start_t;
        this.time_end = max_end_t;
        this.date = create_date ();
        this.selected = false;
        
        create_content ();
    }
    
    private string create_date () {
        string s_date, e_date = "";
        DateTime d_start = new DateTime.from_unix_utc (this.time_start / 1000).to_local ();
        s_date = d_start.format (_("from %H:%M "));
        DateTime d_end = new DateTime.from_unix_utc (this.time_end / 1000).to_local ();
        if (d_start.compare (d_end) == 0)
            s_date = d_start.format (_("At %H:%M "));
        else 
            e_date = d_end.format (_("until %H:%M"));
        
        string date = s_date + e_date;
        return date;
    }
    
    public virtual string create_title () {
        this.title = _("Various activities");
        var text = _("Various activities (%d)");
        return text.printf (activities.size);
    }
    
    public virtual Gdk.Pixbuf? create_icon () {
        //Find icon names in http://developer.gnome.org/icon-naming-spec/
        return Utils.load_fallback_icon ();
    }
    
    public override void create_content () {
        content = new CompositeDocumentWidget (this.icon, this.uris);
    }
    
    public override void launch (){
        this.launch_activity (this);
    }
    
    public override Gee.List<uint> get_events_id () {
        var list = new Gee.ArrayList<uint> ();
        foreach (SingleActivity activity in activities) {
            list.add (activity.event.get_id ());
        }
        return list;
    }
}

private class Journal.CompositeDocumentActivity : CompositeActivity {
    public CompositeDocumentActivity (Gee.List<SingleActivity> activities) {
        Object (activities:activities);
    }
    
    public override string create_title () {
        this.title = _("Worked with Documents");
        var text = _("Worked with %d Documents");
        return text.printf (activities.size);
    }
    
    public override Gdk.Pixbuf? create_icon () {
        try {
            return Gtk.IconTheme.get_default().load_icon ("applications-office", Utils.getIconSize (),
                                            IconLookupFlags.FORCE_SVG | 
                                            IconLookupFlags.GENERIC_FALLBACK);
        } catch (Error e) {
            debug ("Unable to load pixbuf: " + e.message);
        }
        
        return null;
    }
}

private class Journal.CompositeAudioActivity : CompositeActivity {
    public CompositeAudioActivity (Gee.List<SingleActivity> activities) {
        Object (activities:activities);
    }
    
    public override string create_title () {
        this.title = _("Listened to Music");
        var text = _("Listened to Music (%d)");
        return text.printf (activities.size);
    }
    
    public override Gdk.Pixbuf? create_icon () {
        try {
        return Gtk.IconTheme.get_default().load_icon ("applications-multimedia", Utils.getIconSize (),
                                            IconLookupFlags.FORCE_SVG | 
                                            IconLookupFlags.GENERIC_FALLBACK);
        } catch (Error e) {
            debug ("Unable to load pixbuf: " + e.message);
        }
        
        return null;
    }
}

private class Journal.CompositeDevelopmentActivity : CompositeActivity {
    public CompositeDevelopmentActivity (Gee.List<SingleActivity> activities) {
        Object (activities:activities);
    }
    
    public override string create_title () {
        this.title = _("Hacked on some Code");
        var text = _("Hacked on some Code (%d)");
        return text.printf (activities.size);
    }
    
    public override Gdk.Pixbuf? create_icon () {
        try {
        return Gtk.IconTheme.get_default().load_icon ("applications-development", Utils.getIconSize (),
                                            IconLookupFlags.FORCE_SVG | 
                                            IconLookupFlags.GENERIC_FALLBACK);
        } catch (Error e) {
            debug ("Unable to load pixbuf: " + e.message);
        }
        
        return null;
    }
}

private class Journal.CompositeImageActivity : CompositeActivity {
    public CompositeImageActivity (Gee.List<SingleActivity> activities) {
        Object (activities:activities);
    }
    
    public override string create_title () {
        this.title = _("Worked with Images");
        var text = _("Worked with %d Images");
        return text.printf (activities.size);
    }
    
    public override Gdk.Pixbuf? create_icon () {
        try {
        return Gtk.IconTheme.get_default().load_icon ("applications-graphics", Utils.getIconSize (),
                                            IconLookupFlags.FORCE_SVG | 
                                            IconLookupFlags.GENERIC_FALLBACK);
        } catch (Error e) {
            debug ("Unable to load pixbuf: " + e.message);
        }
        
        return null;
    }
    
    public override void create_content () {
        int num = int.min (9, activities.size);
        ImageContent[] pixbufs = new ImageContent[num];
        for (int i = 0; i < num; i++){
            var activity = activities.get (i);
            var content = new ImageContent.from_pixbuf (activity.icon);
            content.highlight_items = true;
            content.clicked.connect (() => {activity.launch ();});
            activity.thumb_loaded.connect (() => {
                content.set_from_pixbuf (activity.thumb_icon);
            });
            pixbufs[i] = content;
        }
        content = new CompositeImageWidget (pixbufs);
    }
}

private class Journal.CompositeVideoActivity : CompositeActivity {
    public CompositeVideoActivity (Gee.List<SingleActivity> activities) {
        Object (activities:activities);
    }
    
    public override string create_title () {
        this.title = _("Watched Videos");
        var text = _("Watched %d Videos");
        return text.printf (activities.size);
    }
    
    public override Gdk.Pixbuf? create_icon () {
        try {
        return Gtk.IconTheme.get_default().load_icon ("camera-video", Utils.getIconSize (),
                                            IconLookupFlags.FORCE_SVG | 
                                            IconLookupFlags.GENERIC_FALLBACK);
        } catch (Error e) {
            debug ("Unable to load pixbuf: " + e.message);
        }
        
        return null;
    }
}

private class Journal.CompositeApplicationActivity : CompositeActivity {
    public CompositeApplicationActivity (Gee.List<SingleActivity> activities) {
        Object (activities:activities);
    }
    
    public override string create_title () {
        this.title = _("Used Applications");
        var text = _("Used %d Applications");
        return text.printf (activities.size);
    }
    
    public override Gdk.Pixbuf? create_icon () {
        try {
        return Gtk.IconTheme.get_default().load_icon ("applications-other", Utils.getIconSize (),
                                            IconLookupFlags.FORCE_SVG | 
                                            IconLookupFlags.GENERIC_FALLBACK);
        } catch (Error e) {
            debug ("Unable to load pixbuf: " + e.message);
        }
        
        return null;
    }
    
    public override void create_content () {
        int num = int.min (6, activities.size);
        ImageContent[] pixbufs = new ImageContent[num];
        for (int i = 0; i < num; i++){
            var activity = activities.get (i);
            var content = new ImageContent.from_pixbuf (activity.icon);
            content.highlight_items = true;
            content.clicked.connect ((ev) => {
                activity.launch ();
            });
            pixbufs[i] = content;
        }
        content = new CompositeApplicationWidget (pixbufs);
    }
}

private class Journal.CompositeDownloadActivity : CompositeActivity {
    public CompositeDownloadActivity (Gee.List<SingleActivity> activities) {
        Object (activities:activities);
    }
    
    public override string create_title () {
        this.title = _("Downloads");
        var text = _("Downloads (%d)");
        return text.printf (activities.size);
    }
    
    public override Gdk.Pixbuf? create_icon () {
        try {
        return Gtk.IconTheme.get_default().load_icon ("emblem-downloads", Utils.getIconSize (),
                                            IconLookupFlags.FORCE_SVG | 
                                            IconLookupFlags.GENERIC_FALLBACK);
        } catch (Error e) {
            debug ("Unable to load pixbuf: " + e.message);
        }
        
        return null;
    }
}

private class Journal.CompositeWebActivity : CompositeActivity {
    public CompositeWebActivity (Gee.List<SingleActivity> activities) {
        Object (activities:activities);
    }
    
    public override string create_title () {
        this.title = _("Surfed the Web");
        var text = _("Surfed the Web (%d)");
        return text.printf (activities.size);
    }
    
    public override Gdk.Pixbuf? create_icon () {
        try {
        return Gtk.IconTheme.get_default().load_icon ("applications-internet", Utils.getIconSize (),
                                            IconLookupFlags.FORCE_SVG | 
                                            IconLookupFlags.GENERIC_FALLBACK);
        } catch (Error e) {
            debug ("Unable to load pixbuf: " + e.message);
        }
        
        return null;
    }
}

private class Journal.CompositeTodoActivity : CompositeActivity {
    public CompositeTodoActivity (Gee.List<SingleActivity> activities) {
        Object (activities:activities);
    }
    
    public override string create_title () {
        this.title = _("Worked with Tasks");
        var text = _("Worked with %d Tasks");
        return text.printf (activities.size);
    }
    
    public override Gdk.Pixbuf? create_icon () {
        var info = new  DesktopAppInfo (activities.get (0).
                                        event.get_actor ().split("://")[1]);
        if (info == null) {
             return Utils.load_pixbuf_from_name ("application-x-executable");
        }
        Gdk.Pixbuf pixbuf = Utils.load_pixbuf_from_icon (info.get_icon ());
        return pixbuf;
    }
}

private class Journal.ActivityFactory : Object {
    
    private static Gee.Map<string, Type> interpretation_types;
    private static Gee.Map<string, Type> interpretation_types_comp;
    private static Gee.Map<string, string> interpretation_parents;
    
    private static void init () {
        interpretation_types = new Gee.HashMap<string, Type> ();
        //Fill in all interpretations
        /****DOCUMENTS****/
        interpretation_types.set (Zeitgeist.NFO_DOCUMENT, typeof (DocumentActivity));
        /****PROGRAMMING****/
        interpretation_types.set (Zeitgeist.NFO_SOURCE_CODE, typeof (DevelopmentActivity));
        /****IMAGES****/
        interpretation_types.set (Zeitgeist.NFO_IMAGE, typeof (ImageActivity));
        /****AUDIO****/
        interpretation_types.set (Zeitgeist.NFO_AUDIO, typeof (AudioActivity));
        /****VIDEOS****/
        interpretation_types.set (Zeitgeist.NFO_VIDEO, typeof (VideoActivity));
        /****APPLICATIONS****/
        interpretation_types.set (Zeitgeist.NFO_APPLICATION ,typeof (ApplicationActivity));
        /****WEBSITE*******/
        interpretation_types.set (Zeitgeist.NFO_WEBSITE ,typeof (WebActivity));
        /****TODOs****/
        interpretation_types.set (Zeitgeist.NCAL_TODO ,typeof (TodoActivity));
        
        /**************COMPOSITE ACTIVITIES*********/
        interpretation_types_comp = new Gee.HashMap<string, Type> ();
        //Fill in all interpretations
        /****DOCUMENTS****/
        interpretation_types_comp.set (Zeitgeist.NFO_DOCUMENT, typeof (CompositeDocumentActivity));
        /****PROGRAMMING****/
        interpretation_types_comp.set (Zeitgeist.NFO_SOURCE_CODE, typeof (CompositeDevelopmentActivity));
        /****IMAGES****/
        interpretation_types_comp.set (Zeitgeist.NFO_IMAGE, typeof (CompositeImageActivity));
        /****AUDIO****/
        interpretation_types_comp.set (Zeitgeist.NFO_AUDIO, typeof (CompositeAudioActivity));
        /****VIDEOS****/
        interpretation_types_comp.set (Zeitgeist.NFO_VIDEO, typeof (CompositeVideoActivity));
        /****APPLICATIONS****/
        interpretation_types_comp.set (Zeitgeist.NFO_APPLICATION ,typeof (CompositeApplicationActivity));
        /****WEBSITE*******/
        interpretation_types_comp.set (Zeitgeist.NFO_WEBSITE ,typeof (CompositeWebActivity));
        /****TODOs*******/
        interpretation_types_comp.set (Zeitgeist.NCAL_TODO ,typeof (CompositeTodoActivity));
        
        /**********HIERARCHY OF INTERPRETATIONS*******/
        interpretation_parents = new Gee.HashMap<string, string> ();
        //Fill in all interpretations
        /****DOCUMENTS****/
        interpretation_parents.set (Zeitgeist.NFO_DOCUMENT, Zeitgeist.NFO_DOCUMENT);
        interpretation_parents.set (Zeitgeist.NFO_PAGINATED_TEXT_DOCUMENT, Zeitgeist.NFO_DOCUMENT);
        interpretation_parents.set (Zeitgeist.NFO_PLAIN_TEXT_DOCUMENT, Zeitgeist.NFO_DOCUMENT);
        interpretation_parents.set (Zeitgeist.NFO_HTML_DOCUMENT, Zeitgeist.NFO_DOCUMENT);
        interpretation_parents.set (Zeitgeist.NFO_TEXT_DOCUMENT, Zeitgeist.NFO_DOCUMENT);
        interpretation_parents.set (Zeitgeist.NFO_SPREADSHEET, Zeitgeist.NFO_DOCUMENT);
        interpretation_parents.set (Zeitgeist.NFO_PRESENTATION, Zeitgeist.NFO_DOCUMENT);
        /****PROGRAMMING****/
        interpretation_parents.set (Zeitgeist.NFO_SOURCE_CODE, Zeitgeist.NFO_SOURCE_CODE);
        /****IMAGES****/
        interpretation_parents.set (Zeitgeist.NFO_IMAGE, Zeitgeist.NFO_IMAGE);
        interpretation_parents.set (Zeitgeist.NFO_VECTOR_IMAGE, Zeitgeist.NFO_IMAGE);
        interpretation_parents.set (Zeitgeist.NFO_RASTER_IMAGE, Zeitgeist.NFO_IMAGE);
        /****AUDIO****/
        interpretation_parents.set (Zeitgeist.NFO_AUDIO, Zeitgeist.NFO_AUDIO);
        interpretation_parents.set (Zeitgeist.NMM_MUSIC_ALBUM, Zeitgeist.NFO_AUDIO);
        interpretation_parents.set (Zeitgeist.NMM_MUSIC_PIECE, Zeitgeist.NFO_AUDIO);
        /****VIDEOS****/
        interpretation_parents.set (Zeitgeist.NFO_VIDEO, Zeitgeist.NFO_VIDEO);
        interpretation_parents.set (Zeitgeist.NMM_MOVIE, Zeitgeist.NFO_VIDEO);
        interpretation_parents.set (Zeitgeist.NMM_MUSIC_ALBUM, Zeitgeist.NFO_VIDEO);
        interpretation_parents.set (Zeitgeist.NMM_TVSERIES, Zeitgeist.NFO_VIDEO);
        interpretation_parents.set (Zeitgeist.NMM_TVSHOW , Zeitgeist.NFO_VIDEO);
        /****APPLICATIONS****/
        interpretation_parents.set (Zeitgeist.NFO_APPLICATION, Zeitgeist.NFO_APPLICATION);
        interpretation_parents.set (Zeitgeist.NFO_SOFTWARE, Zeitgeist.NFO_APPLICATION);
        /****WEBSITE*******/
        interpretation_parents.set (Zeitgeist.NFO_WEBSITE, Zeitgeist.NFO_WEBSITE);
        /****TODOs*******/
        interpretation_parents.set (Zeitgeist.NCAL_TODO ,Zeitgeist.NCAL_TODO);
    }
    
    /****PUBLIC METHODS****/
    
    public static SingleActivity get_activity_for_event (Zeitgeist.Event event) {
        if (interpretation_types == null)
            init ();

        string intpr = event.get_subject (0).get_interpretation ();
        if (intpr == null) 
            //Better way for handling this?
            intpr = Zeitgeist.NFO_DOCUMENT;

        string parent_intpr = get_parent_interpretation (intpr);
        if (interpretation_types.has_key (parent_intpr)){
            Type activity_class = interpretation_types.get (parent_intpr);
            SingleActivity activity = (SingleActivity) 
                                        Object.new (activity_class, event:event);
            return activity;
        }
        return new SingleActivity (event);
    }
    
    public static CompositeActivity get_composite_activity_for_interpretation (
                                     string intpr,
                                     Gee.List<SingleActivity> activities) {
        if (interpretation_types_comp == null)
            init ();
            
        if (intpr == null) 
            //Better way for handling this?
            intpr = Zeitgeist.NFO_DOCUMENT;

        string parent_intpr = get_parent_interpretation (intpr);
        if (interpretation_types_comp.has_key (parent_intpr)){
            Type activity_class = interpretation_types_comp.get (parent_intpr);
            CompositeActivity activity = (CompositeActivity) 
                                        Object.new (activity_class, activities:activities);
            return activity;
        }
        return new CompositeActivity (activities);
    }
    
    public static string? get_parent_interpretation (string intpr) {
        if (interpretation_parents == null)
            init ();
        if (interpretation_parents.has_key (intpr))
            return interpretation_parents.get (intpr);
        else
            return intpr;
    }
}

private class Journal.DayActivityModel : Object {
    public Gee.List<GenericActivity> activities {
        get; private set;
    }
    
    public string day {
        get; private set;
    }
    
    public signal void launch_composite_activity (CompositeActivity activity);

    public DayActivityModel (string day) {
        this.day = day;
        activities = new Gee.ArrayList<GenericActivity> ();
    }
    
    private void add_activity (SingleActivity activity, 
                               Gee.Map<string, Gee.List<SingleActivity>> map) {
        string interpretation = activity.interpretation;
        if (!map.has_key (interpretation))
            map.set (activity.interpretation, 
                            new Gee.ArrayList<SingleActivity> ((a, b) => {
                                SingleActivity first = (SingleActivity) a;
                                SingleActivity second = (SingleActivity) b;
                                return (first.uri == second.uri);
                            }));
                            
        var list = map.get (interpretation);
        if (!list.contains (activity))
            list.add (activity);
    }
    
    private void create_composite_activities (Gee.Map<string, Gee.List<SingleActivity>> _in,
                                              out Gee.List<GenericActivity> _out,
                                              string part_of_the_day) {
        _out = new Gee.ArrayList<GenericActivity> ();
        foreach (string intr in _in.keys) {
            var list = _in.get (intr);
            if (list.size > 1) {
                CompositeActivity c_activity = 
                ActivityFactory.get_composite_activity_for_interpretation (intr, 
                                                    _in.get (intr));
                c_activity.part_of_the_day = part_of_the_day;
                c_activity.launch_activity.connect ((activity) => {
                    this.launch_composite_activity (activity as CompositeActivity);
                });
                _out.add (c_activity);
            }
            else
                _out.add (list.get (0));
        }
    }
    
    public void add_activities (Gee.List<Zeitgeist.Event> event_list) {
        var morning_map = new Gee.HashMap<string, Gee.List<SingleActivity>> ();
        var afternoon_map = new Gee.HashMap<string, Gee.List<SingleActivity>> ();
        var evening_map = new Gee.HashMap<string, Gee.List<SingleActivity>> ();
        foreach (Zeitgeist.Event e in event_list) {
            SingleActivity activity = ActivityFactory.get_activity_for_event (e);
            int64 time = e.get_timestamp () / 1000;
            var dt = new DateTime.from_unix_local (time);
            var hour = dt.get_hour (); 
            if (hour < 12) {
                activity.part_of_the_day = _("Morning");
                add_activity (activity, morning_map);
            }
            else if (hour < 18) {
                activity.part_of_the_day = _("Afternoon");
                add_activity (activity, afternoon_map);
            }
            else {
                activity.part_of_the_day = _("Evening");
                add_activity (activity, evening_map);
            }
        }
        
        Gee.List<GenericActivity> morning_activities;
        Gee.List<GenericActivity> afternoon_activities;
        Gee.List<GenericActivity> evening_activities;
        create_composite_activities (morning_map, out morning_activities, _("Morning"));
        create_composite_activities (afternoon_map, out afternoon_activities, _("Afternoon"));
        create_composite_activities (evening_map, out evening_activities, _("Evening"));
        
        activities.add_all (morning_activities);
        activities.add_all (afternoon_activities);
        activities.add_all (evening_activities);
        
                
        activities.sort ((a,b) =>{
                GenericActivity first = (GenericActivity)a;
                GenericActivity second = (GenericActivity)b;
                if (first.time_start > second.time_start)
                    return -1;
                else if (first.time_start == second.time_start)
                    return 0;
                else
                    return 1;
        });
    }
}

private class Journal.ActivityModel : Object {
    private ZeitgeistBackend backend;
    private SearchManager search_manager;
    
    //Key: Date formatted YYYY-MM-DD
    public Gee.Map<string, DayActivityModel> activities {
        get; private set;
    }
    
    public signal void activities_loaded (string day);
    public signal void launch_composite_activity (CompositeActivity activity);
    public signal void search_finished (Gee.List<uint> searched_events);

    public ActivityModel () {
        activities = new Gee.HashMap<string, DayActivityModel> ();
        backend = new ZeitgeistBackend ();
        search_manager = new SearchManager ();
        
        backend.load_events_on_start ();
        backend.events_loaded.connect ((day) => {
            on_events_loaded (day);
        });
        
        search_manager.search_finished.connect (() => {
            search_finished (search_manager.searched_events);
        });
    }
    
    private void on_events_loaded (string? day) {
        if (day == null) {
            load_other_days (1);
            return;
        }
        if (activities.has_key (day))
            return;
        var model = new DayActivityModel (day);
        Gee.List<Zeitgeist.Event> event_list = backend.get_events_for_date (day);
        model.add_activities (event_list);
        activities.set (day, model);
        model.launch_composite_activity.connect ((activity) => {
                    this.launch_composite_activity (activity);
        });
        activities_loaded (day);
    }

    public void load_activities (DateTime start) {
        TimeVal tv;
        TimeVal tv2;
        //add some days to the jump date, permitting the user to navigate more.
        // FIXME always 3? Something better?
        DateTime larger_date = start.add_days (-3);
        larger_date.to_timeval (out tv);

        //FIXME how many days we should load? Same as above
        var tmp_date = start.add_days (3);
        tmp_date.to_timeval (out tv2);
        backend.load_events_for_date_range (tv, tv2);
    }
    
    public void load_other_days (int num_days) {
        TimeVal tv;
        TimeVal tv2;
        DateTime larger_date = backend.last_loaded_date.add_days (-num_days);
        larger_date.to_timeval (out tv);
        backend.last_loaded_date.to_timeval (out tv2);
        backend.load_events_for_date_range (tv, tv2);
    }
    
    public async void search (string query) {
        yield this.search_manager.search_simple (query);
    }
}
