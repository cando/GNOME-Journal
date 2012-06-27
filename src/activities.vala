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
 
using Gdk;
using Gtk;

private abstract class Journal.GenericActivity : Object {
    public Clutter.Actor actor {
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
    
    public Pixbuf? icon {
        get; protected set;
    }
    
    public abstract void launch ();
    
    public abstract void create_actor ();
    
}

private class Journal.SingleActivity : GenericActivity {

    public Zeitgeist.Event event {
        get; construct set;
    }
    
    public Clutter.Actor content {
        get; protected set;
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
        this.time_start = this.time_end = event.get_timestamp ();
        this.selected = false;
        this.mimetype = subject.get_mimetype ();
        string intpr = subject.get_interpretation ();
        if (intpr == null) 
            //Better way for handling this?
            intpr = Zeitgeist.NFO_DOCUMENT;
        this.interpretation = intpr;

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
        if (this.thumb_path != null) {
            this.get_thumb ();
            return;
        }

        updateTypeIcon ();

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
    
    public virtual void create_content () {
        content = new ImageContent.from_pixbuf (this.icon);
    }
    
    public override void create_actor () {
        DateTime d = new DateTime.from_unix_utc (this.time_start / 1000).to_local ();
        string date = d.format ("%H:%M");
        actor = new GenericActor (this.title, date);
        ((GenericActor)actor).set_content_actor (content);
    }
    
    public virtual void update_icon () {
        ((ImageContent)content).set_pixbuf (this.thumb_icon);
    }
    
    public override void launch (){
        try {
            AppInfo.launch_default_for_uri (uri, null);
        } catch (Error e) {
            warning ("Impossible to launch " + uri);
        }
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
        content = new VideoContent (uri, this.icon);
    }
    
    public override void update_icon () {
        ((VideoContent)content).set_thumbnail (this.thumb_icon);
    }
}

private class Journal.ApplicationActivity : SingleActivity {
    public ApplicationActivity (Zeitgeist.Event event) {
        Object (event:event);
    }
    
    protected override async void updateActivityIcon () {
        var info = new  DesktopAppInfo (display_uri);
        this.icon = Utils.load_pixbuf_from_name ("application-x-executable",
                                                    Utils.getIconSize ());
        if (info == null) {
            this.thumb_icon = this.icon;
            return;
        }
        this.thumb_icon = Utils.load_pixbuf_from_icon (info.get_icon (), 
                                                       Utils.getIconSize ());
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

/**Collection of Activity TODO documention here!**/
private class Journal.CompositeActivity : GenericActivity {

    private const int MAXIMUM_ITEMS = 5;

    public Gee.List<SingleActivity> activities {
        get; construct set;
    }
    
    public string[] uris {
        get; private set;
    }
    
    public string date {
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
                this.uris[i] = "...";
                break;
            }
            this.uris[i] = activity.title;
            i++;
        }
        this.icon = create_icon ();
        //Subclasses will modify this.
        this.title = create_title ();
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
        return _("Various activities");
    }
    
    public virtual Gdk.Pixbuf? create_icon () {
        //Find icon names in http://developer.gnome.org/icon-naming-spec/
        return Utils.load_fallback_icon ();
    }
    
    public override void create_actor () {
        actor = new CompositeDocumentActor (this.title, 
                                            this.icon, 
                                            this.uris, 
                                            this.date);
    }
    
    public override void launch (){
        this.launch_activity (this);
    }
}

private class Journal.CompositeDocumentActivity : CompositeActivity {
    public CompositeDocumentActivity (Gee.List<SingleActivity> activities) {
        Object (activities:activities);
    }
    
    public override string create_title () {
        return _("Worked with Documents");
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
        return _("Listened to Music");
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
        return _("Hacked on some Code");
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
        return _("Worked with Images");
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
    
    public override void create_actor () {
        int num = int.min (9, activities.size);
        ImageContent[] pixbufs = new ImageContent[num];
        for (int i = 0; i < num; i++){
            var activity = activities.get (i);
            var content = activity.content as ImageContent;
            content.highlight_items = true;
            content.clicked.connect (() => {activity.launch ();});
            if (content.get_parent () != null)
                content.get_parent ().remove_child (content);
            pixbufs[i] = content;
        }
        actor = new CompositeImageActor (this.title, pixbufs, this.date);
    }
}

private class Journal.CompositeVideoActivity : CompositeActivity {
    public CompositeVideoActivity (Gee.List<SingleActivity> activities) {
        Object (activities:activities);
    }
    
    public override string create_title () {
        return _("Videos watched");
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
        return _("Applications Used");
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
    
    public override void create_actor () {
        int num = int.min (9, activities.size);
        ImageContent[] pixbufs = new ImageContent[num];
        for (int i = 0; i < num; i++){
            var activity = activities.get (i);
            var info = new  DesktopAppInfo (activity.display_uri);
            if (info == null)
                continue;
            Gdk.Pixbuf pixbuf = Utils.load_pixbuf_from_icon (info.get_icon ());
            var content = new ImageContent.from_pixbuf (pixbuf);
            content.highlight_items = true;
            content.clicked.connect (() => {activity.launch ();});
            pixbufs[i] = content;
        }
        actor = new CompositeApplicationActor (this.title, pixbufs, this.date);
    }
}

private class Journal.CompositeDownloadActivity : CompositeActivity {
    public CompositeDownloadActivity (Gee.List<SingleActivity> activities) {
        Object (activities:activities);
    }
    
    public override string create_title () {
        return _("Downloads");
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
        return _("Surfed the web");
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

private class Journal.ActivityFactory : Object {
    
    private static Gee.Map<string, Type> interpretation_types;
    private static Gee.Map<string, Type> interpretation_types_comp;
    
    private static void init () {
        interpretation_types = new Gee.HashMap<string, Type> ();
        //Fill in all interpretations
        /****DOCUMENTS****/
        interpretation_types.set (Zeitgeist.NFO_DOCUMENT, typeof (DocumentActivity));
        interpretation_types.set (Zeitgeist.NFO_PAGINATED_TEXT_DOCUMENT, typeof (DocumentActivity));
        interpretation_types.set (Zeitgeist.NFO_PLAIN_TEXT_DOCUMENT, typeof (DocumentActivity));
        interpretation_types.set (Zeitgeist.NFO_HTML_DOCUMENT, typeof (DocumentActivity));
        interpretation_types.set (Zeitgeist.NFO_TEXT_DOCUMENT, typeof (DocumentActivity));
        interpretation_types.set (Zeitgeist.NFO_SPREADSHEET, typeof (DocumentActivity));
        interpretation_types.set (Zeitgeist.NFO_PRESENTATION, typeof (DocumentActivity));
        /****PROGRAMMING****/
        interpretation_types.set (Zeitgeist.NFO_SOURCE_CODE, typeof (DevelopmentActivity));
        /****IMAGES****/
        interpretation_types.set (Zeitgeist.NFO_IMAGE, typeof (ImageActivity));
        interpretation_types.set (Zeitgeist.NFO_VECTOR_IMAGE, typeof (ImageActivity));
        interpretation_types.set (Zeitgeist.NFO_RASTER_IMAGE, typeof (ImageActivity));
        /****AUDIO****/
        interpretation_types.set (Zeitgeist.NFO_AUDIO, typeof (AudioActivity));
        interpretation_types.set (Zeitgeist.NMM_MUSIC_ALBUM, typeof (AudioActivity));
        interpretation_types.set (Zeitgeist.NMM_MUSIC_PIECE, typeof (AudioActivity));
        /****VIDEOS****/
        interpretation_types.set (Zeitgeist.NFO_VIDEO, typeof (VideoActivity));
        interpretation_types.set (Zeitgeist.NMM_MOVIE, typeof (VideoActivity));
        interpretation_types.set (Zeitgeist.NMM_MUSIC_ALBUM, typeof (VideoActivity));
        interpretation_types.set (Zeitgeist.NMM_TVSERIES, typeof (VideoActivity));
        interpretation_types.set (Zeitgeist.NMM_TVSHOW ,typeof (VideoActivity));
        /****APPLICATIONS****/
        interpretation_types.set (Zeitgeist.NFO_APPLICATION ,typeof (ApplicationActivity));
        interpretation_types.set (Zeitgeist.NFO_SOFTWARE ,typeof (ApplicationActivity));
        /****WEBSITE*******/
        interpretation_types.set (Zeitgeist.NFO_WEBSITE ,typeof (WebActivity));
        
        /**************COMPOSITE ACTIVITIES*********/
        interpretation_types_comp = new Gee.HashMap<string, Type> ();
        //Fill in all interpretations
        /****DOCUMENTS****/
        interpretation_types_comp.set (Zeitgeist.NFO_DOCUMENT, typeof (CompositeDocumentActivity));
        interpretation_types_comp.set (Zeitgeist.NFO_PAGINATED_TEXT_DOCUMENT, typeof (CompositeDocumentActivity));
        interpretation_types_comp.set (Zeitgeist.NFO_PLAIN_TEXT_DOCUMENT, typeof (CompositeDocumentActivity));
        interpretation_types_comp.set (Zeitgeist.NFO_HTML_DOCUMENT, typeof (CompositeDocumentActivity));
        interpretation_types_comp.set (Zeitgeist.NFO_TEXT_DOCUMENT, typeof (CompositeDocumentActivity));
        interpretation_types_comp.set (Zeitgeist.NFO_SPREADSHEET, typeof (CompositeDocumentActivity));
        interpretation_types_comp.set (Zeitgeist.NFO_PRESENTATION, typeof (CompositeDocumentActivity));
        /****PROGRAMMING****/
        interpretation_types_comp.set (Zeitgeist.NFO_SOURCE_CODE, typeof (CompositeDevelopmentActivity));
        /****IMAGES****/
        interpretation_types_comp.set (Zeitgeist.NFO_IMAGE, typeof (CompositeImageActivity));
        interpretation_types_comp.set (Zeitgeist.NFO_VECTOR_IMAGE, typeof (CompositeImageActivity));
        interpretation_types_comp.set (Zeitgeist.NFO_RASTER_IMAGE, typeof (CompositeImageActivity));
        /****AUDIO****/
        interpretation_types_comp.set (Zeitgeist.NFO_AUDIO, typeof (CompositeAudioActivity));
        interpretation_types_comp.set (Zeitgeist.NMM_MUSIC_ALBUM, typeof (CompositeAudioActivity));
        interpretation_types_comp.set (Zeitgeist.NMM_MUSIC_PIECE, typeof (CompositeAudioActivity));
        /****VIDEOS****/
        interpretation_types_comp.set (Zeitgeist.NFO_VIDEO, typeof (CompositeVideoActivity));
        interpretation_types_comp.set (Zeitgeist.NMM_MOVIE, typeof (CompositeVideoActivity));
        interpretation_types_comp.set (Zeitgeist.NMM_MUSIC_ALBUM, typeof (CompositeVideoActivity));
        interpretation_types_comp.set (Zeitgeist.NMM_TVSERIES, typeof (CompositeVideoActivity));
        interpretation_types_comp.set (Zeitgeist.NMM_TVSHOW ,typeof (CompositeVideoActivity));
        /****APPLICATIONS****/
        interpretation_types_comp.set (Zeitgeist.NFO_APPLICATION ,typeof (CompositeApplicationActivity));
        interpretation_types_comp.set (Zeitgeist.NFO_SOFTWARE ,typeof (CompositeApplicationActivity));
        /****WEBSITE*******/
        interpretation_types_comp.set (Zeitgeist.NFO_WEBSITE ,typeof (CompositeWebActivity));
    }
    
    /****PUBLIC METHODS****/
    
    public static SingleActivity get_activity_for_event (Zeitgeist.Event event) {
        if (interpretation_types == null)
            init ();
            
        string intpr = event.get_subject (0).get_interpretation ();
        if (intpr == null) 
            //Better way for handling this?
            intpr = Zeitgeist.NFO_DOCUMENT;
        
        if (interpretation_types.has_key (intpr)){
            Type activity_class = interpretation_types.get (intpr);
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
        
        if (interpretation_types_comp.has_key (intpr)){
            Type activity_class = interpretation_types_comp.get (intpr);
            CompositeActivity activity = (CompositeActivity) 
                                        Object.new (activity_class, activities:activities);
            return activity;
        }
        return new CompositeActivity (activities);
    }
}

private class Journal.DayActivityModel : Object {

    //Key: Zeitgeist.Interpretation
    public Gee.Map<string, Gee.List<SingleActivity>> activities {
        get; private set;
    }
    
    public Gee.List<GenericActivity> composite_activities {
        get; private set;
    }
    
    public string day {
        get; private set;
    }
    
    public signal void launch_composite_activity (CompositeActivity activity);

    public DayActivityModel (string day) {
        activities = new Gee.HashMap<string, Gee.List<SingleActivity>> ();
        composite_activities = new Gee.ArrayList<GenericActivity> ();
        this.day = day;
    }
    
    public void add_activity (SingleActivity activity) {
        string interpretation = activity.interpretation;
        if (!activities.has_key (interpretation))
            activities.set (activity.interpretation, 
                            new Gee.ArrayList<SingleActivity> ((a, b) => {
                                SingleActivity first = (SingleActivity) a;
                                SingleActivity second = (SingleActivity) b;
                                return (first.uri == second.uri);
                            }));
                            
        var list = activities.get (interpretation);
        if (!list.contains (activity))
            list.add (activity);
    }
    
    public void create_composite_activities () {
            foreach (string intr in this.activities.keys) {
                var list = this.activities.get (intr);
                if (list.size > 1) {
                    CompositeActivity c_activity = 
                    ActivityFactory.get_composite_activity_for_interpretation (intr, 
                                                        this.activities.get (intr));
                    c_activity.launch_activity.connect ((activity) => {
                        this.launch_composite_activity (activity as CompositeActivity);
                    });
                    composite_activities.add (c_activity);
                }
                else 
                    composite_activities.add (list.get (0));
            }
            
            composite_activities.sort ( (a,b) =>{
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
    
/****One day will be useful...but not now!*********/
//    public void remove_activity (SingleActivity activity) {
//        string interpretation = activity.interpretation;
//        if (!activities.has_key (interpretation))
//            return;

//        var list = activities.get (interpretation);
//        list.remove (activity);
//        if (list.size == 0)
//            activities.unset (interpretation);
//    }
}

private class Journal.ActivityModel : Object {

    private ZeitgeistBackend backend;
    
    //Key: Date format YYYY-MM-DD
    public Gee.Map<string, DayActivityModel> activities {
        get; private set;
    }
    
    public signal void activities_loaded (Gee.ArrayList<string> dates_loaded);
    public signal void launch_composite_activity (CompositeActivity activity);

    public ActivityModel () {
        activities = new Gee.HashMap<string, DayActivityModel> ();
        backend = new ZeitgeistBackend ();
        
        backend.load_events_on_start ();
        backend.events_loaded.connect ((tr) => {
            on_events_loaded (tr);
        });
    }
    
    private void on_events_loaded (Zeitgeist.TimeRange tr) {
        int64 start = tr.get_start () / 1000;
        int64 end = tr.get_end () / 1000;
        DateTime start_date = new DateTime.from_unix_local (start);
        DateTime end_date = new DateTime.from_unix_local (end);
        
        var dates_loaded = new Gee.ArrayList<string> ();
        DateTime next_date = end_date;
        string day = next_date.format("%Y-%m-%d");
        if (add_day (day))
            dates_loaded.add (day);
        while (next_date.compare (start_date) != 0) {
            next_date = next_date.add_days (-1);
            day = next_date.format("%Y-%m-%d");
            if (add_day (day))
                dates_loaded.add (day);
            else 
                dates_loaded.add ("*"+day); //means day with 0 events.FIXME hack!
        }
        
        //Sort for timestamp order
        foreach (DayActivityModel day_model in activities.values) 
            foreach (Gee.List<SingleActivity> list in day_model.activities.values)
                list.sort ( (a,b) =>{
                    SingleActivity first = (SingleActivity)a;
                    SingleActivity second = (SingleActivity)b;
                    if (first.time_start > second.time_start)
                        return -1;
                    else if (first.time_start == second.time_start)
                        return 0;
                    else
                        return 1;
                });
        
        var empty = true;
        foreach (string d in dates_loaded) {
            if (!d.has_prefix ("*")) {
                empty = false;
                break;
            }
        }
        
        if (empty) 
            this.load_other_days (3);
        else
            activities_loaded (dates_loaded);
    }
    
    private bool add_day (string day) {
        var model = new DayActivityModel (day);
        Gee.List<Zeitgeist.Event> event_list = backend.get_events_for_date (day);
        if (event_list == null)
                return false;
        foreach (Zeitgeist.Event e in event_list) {
            SingleActivity activity = ActivityFactory.get_activity_for_event (e);
            model.add_activity (activity);
        }
        model.create_composite_activities ();
        activities.set (day, model);
        model.launch_composite_activity.connect ((activity) => {
                    this.launch_composite_activity (activity);
        });
        return true;
    }
    
    public void load_activities (DateTime start) {
        TimeVal tv;
        //add some days to the jump date, permitting the user to navigate more.
        // FIXME always 3? Something better?
        DateTime larger_date = start.add_days (-3);
        larger_date.to_timeval (out tv);
        Date start_date = {};
        start_date.set_time_val (tv);
        //FIXME how many days we should load? Same as above
        Date end_date = {};
        var tmp_date = start.add_days (3);
        tmp_date.to_timeval (out tv);
        end_date.set_time_val (tv);
        
        backend.load_events_for_date_range (start_date, end_date);
    }
    
    public void load_other_days (int num_days) {
        TimeVal tv;
        DateTime larger_date = backend.last_loaded_date.add_days (-num_days);
        larger_date.to_timeval (out tv);
        Date start_date = {};
        start_date.set_time_val (tv);
        
        Date end_date = {};
        backend.last_loaded_date.to_timeval (out tv);
        end_date.set_time_val (tv);

        backend.load_events_for_date_range (start_date, end_date);
    }
}
