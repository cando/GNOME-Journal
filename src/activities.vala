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

private class Journal.GenericActivity : Object {

    public Clutter.Actor actor {
        get; protected set;
    }

    public Zeitgeist.Event event {
        get; construct set;
    }
    
    public string uri {
        get; private set;
    }
    
    public string title {
        get; private set;
    }
    
    public Pixbuf? type_icon {
        get; private set;
    }
    
    public Pixbuf? thumb_icon {
        get; private set;
    }
    
    public string display_uri {
        get; private set;
    }
    
    public int64 time {
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

    public GenericActivity (Zeitgeist.Event event) {
        Object (event: event);
    }
    
    construct {
        this.subject = event.get_subject (0);
        this.uri = subject.get_uri ();
        this.type_icon = null;
        this.thumb_icon = null;
        this.display_uri = create_display_uri ();
        this.title = subject.get_text () == null ? 
                     this.display_uri () : subject.get_text ();
        this.time = event.get_timestamp ();
        this.selected = false;
        this.mimetype = subject.get_mimetype ();
        string intpr = subject.get_interpretation ();
        if (intpr == null) 
            //Better way for handling this?
            intpr = Zeitgeist.NFO_DOCUMENT;
        this.interpretation = intpr;

        updateActivityIcon ();
        
        create_actor ();
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
    private async void updateActivityIcon () {
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
            warning ("Unable to query info for file at " + this.uri + ": " + e.message);
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
            warning ("Unable to query info for file at " + this.uri + ": " + e.message);
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
                this.type_icon = icon_info.load_icon();
                //Let's use this for the moment.
                this.thumb_icon = this.type_icon;
            } catch (Error e) {
                warning ("Unable to load pixbuf: " + e.message);
            }
        }
        
        //If the icon is still null let's use a default text/plain mime icon.
        if (type_icon == null) {
            _icon = ContentType.get_icon ("text/plain");

            if (_icon != null)
                icon_info = 
                    Gtk.IconTheme.get_default().lookup_by_gicon (_icon, Utils.getIconSize (),
                                            IconLookupFlags.FORCE_SVG | 
                                            IconLookupFlags.GENERIC_FALLBACK);
            if (icon_info != null) {
                try {
                    this.type_icon = icon_info.load_icon();
                    //Let's use this for the moment.
                    this.thumb_icon = this.type_icon;
                } catch (Error e) {
                    warning ("Unable to load pixbuf: " + e.message);
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
        } catch (Error e) {
            warning ("Unable to load pixbuf of"+ this.uri+" : " + e.message);
       }
    }
    
    public virtual Clutter.Actor create_actor () {
        DateTime d = new DateTime.from_unix_utc (this.time / 1000).to_local ();
        string date = d.format ("%H:%M");
        actor = new DocumentActor (this.title, this.type_icon, date);
        return actor;
    }
    
    public virtual void update_icon () {
        ((DocumentActor)actor).update_image (this.thumb_icon);
    }
}

/**Single Activity**/
private class Journal.DocumentActivity : GenericActivity {
    public DocumentActivity (Zeitgeist.Event event) {
        Object (event:event);
    }
}

private class Journal.DevelopmentActivity : GenericActivity {
    public DevelopmentActivity (Zeitgeist.Event event) {
        Object (event:event);
    }
}

private class Journal.AudioActivity : GenericActivity {
    public AudioActivity (Zeitgeist.Event event) {
        Object (event:event);
    }
}

private class Journal.ImageActivity : GenericActivity {
    public ImageActivity (Zeitgeist.Event event) {
        Object (event:event);
    }
    
    public override Clutter.Actor create_actor () {
        actor = new ImageActor.from_uri (this.uri);
        return actor;
    }
    
    public override void update_icon () {
        ((ImageActor)actor).set_pixbuf (this.thumb_icon);
    }
}

private class Journal.VideoActivity : GenericActivity {
    public VideoActivity (Zeitgeist.Event event) {
        Object (event:event);
    }
    
    public override Clutter.Actor create_actor () {
        actor = new VideoActor (this.uri);
        return actor;
    }
    
    public override void update_icon () {
        //do none
    }
}

/**Collection of Activity**/
//TODO


private class Journal.ActivityFactory : Object {
    
    private static Gee.Map<string, Type> interpretation_types;
    
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
        interpretation_types.set (Zeitgeist.NFO_PRESENTATION, typeof (DocumentActivity));
        /****PROGRAMMING****/
        interpretation_types.set (Zeitgeist.NFO_SOURCE_CODE, typeof (DevelopmentActivity));
        /****IMAGES****/
        interpretation_types.set (Zeitgeist.NFO_IMAGE, typeof (ImageActivity));
        interpretation_types.set (Zeitgeist.NFO_VECTOR_IMAGE, typeof (ImageActivity));
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
    }
    
    /****PUBLIC METHODS****/
    
    public static GenericActivity get_activity_for_event (Zeitgeist.Event event) {
        if (interpretation_types == null)
            init ();
            
        string intpr = event.get_subject (0).get_interpretation ();
        if (intpr == null) 
            //Better way for handling this?
            intpr = Zeitgeist.NFO_DOCUMENT;
        
        if (interpretation_types.has_key (intpr)){
            Type activity_class = interpretation_types.get (intpr);
            GenericActivity activity = (GenericActivity) 
                                        Object.new (activity_class, event:event);
            return activity;
        }
        return new GenericActivity (event);
    }
}

private class Journal.DayActivityModel : Object {

    //Key: Zeitgeist.Interpretation
    public Gee.Map<string, Gee.List<GenericActivity>> activities {
        get; private set;
    }

    public DayActivityModel () {
        activities = new Gee.HashMap<string, Gee.List<GenericActivity>> ();
    }
    
    public void add_activity (GenericActivity activity) {
        string interpretation = activity.interpretation;
        if (!activities.has_key (interpretation))
            activities.set (activity.interpretation, 
                            new Gee.ArrayList<GenericActivity> ((a, b) => {
                                GenericActivity first = (GenericActivity) a;
                                GenericActivity second = (GenericActivity) b;
                                return (first.uri == second.uri);
                            }));
                            
        var list = activities.get (interpretation);
        if (!list.contains (activity))
            list.add (activity);
    }
    
/****One day will be useful...but not now!*********/
//    public void remove_activity (GenericActivity activity) {
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
        DateTime start_date = new DateTime.from_unix_utc (start).to_local ();
        DateTime end_date = new DateTime.from_unix_utc (end).to_local ();
        
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
        }
        
        //Sort for timestamp order
        foreach (DayActivityModel day_model in activities.values) 
            foreach (Gee.List<GenericActivity> list in day_model.activities.values)
                list.sort ( (a,b) =>{
                    GenericActivity first = (GenericActivity)a;
                    GenericActivity second = (GenericActivity)b;
                    if (first.time > second.time)
                        return -1;
                    else if (first.time == second.time)
                        return 0;
                    else
                        return 1;
                });
        
        activities_loaded (dates_loaded);
    }
    
    private bool add_day (string day) {
        var model = new DayActivityModel ();
        Gee.List<Zeitgeist.Event> event_list = backend.get_events_for_date (day);
        if (event_list == null)
                return false;
        foreach (Zeitgeist.Event e in event_list) {
            GenericActivity activity = ActivityFactory.get_activity_for_event (e);
            model.add_activity (activity);
        }
        activities.set (day, model);
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
        backend.last_loaded_date.to_timeval (out tv);
        Date end_date = {};
        end_date.set_time_val (tv);
        backend.load_events_for_date_range (start_date, end_date);
    }
}
