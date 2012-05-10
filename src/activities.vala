/*
 * Copyright (c) 2012 Stefano Candori <scandori@gnome.org>
 *
 * Gnome Activity Journal is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by the
 * Free Software Foundation; either version 2 of the License, or (at your
 * option) any later version.
 *
 * Gnome Documents is distributed in the hope that it will be useful, but
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
    
    public signal void thumb_loaded (GenericActivity activity);
    
    private Zeitgeist.Subject subject;
    private string thumb_path;

    public GenericActivity (Zeitgeist.Event event) {
        this.subject = event.get_subject (0);
        this.uri = subject.get_uri ();
        this.title = subject.get_text ();
        this.type_icon = null;
        this.thumb_icon = null;
        this.display_uri = create_display_uri ();
        this.time = event.get_timestamp ();
        this.selected = false;
        this.mimetype = subject.get_mimetype ();
        
        updateActivityIcon ();
    }
    
    private string create_display_uri () {
        string home = Environment.get_home_dir ();
        string uri = this.subject.get_origin ().split ("://")[1];
        return uri.replace (home, "~");
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
                                            IconLookupFlags.FORCE_SVG);
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

    private async void get_thumb () {
        var file = File.new_for_path (this.thumb_path);
        try {
            FileInputStream stream = yield file.read_async (Priority.DEFAULT, null);
            this.thumb_icon = yield Pixbuf.new_from_stream_at_scale_async (
                                                       stream, 
                                                       Utils.getIconSize(),
                                                       Utils.getIconSize(),
                                                       true, null);
            thumb_loaded (this);
        } catch (Error e) {
            warning ("Unable to load pixbuf of"+ this.uri+" : " + e.message);
       }
    }
}

//private class Journal.DocumentActivity : GenericActivity {

//}


private class Journal.ActivityModel : Object {

    private ListStore model;
    private Gee.ArrayList<GenericActivity> _activities;
    
    public Gee.ArrayList<GenericActivity> activities {
        get { return this._activities; }
    }

    public ActivityModel () {
        this._activities = new Gee.ArrayList<GenericActivity> ();
        this.model = new ListStore (6, 
                                   typeof (string), // URI
                                   typeof (string), // TITLE
                                   typeof (Pixbuf), // THUMB_ICON
                                   typeof (string), // DISPLAY_URI
                                   typeof (int64),  // TIME
                                   typeof (bool)); // SELECTED
        this.model.set_sort_column_id (Gd.MainColumns.TIME, 
                                       SortType.DESCENDING);
    }
    
    public void clear () {
        this.model.clear ();
    }
    
    public void add_activity (GenericActivity activity) {
        TreeIter iter;
        this.model.append (out iter);
        this.model.set (iter,
                        0, activity.uri,
                        1, activity.title,
                        2, activity.thumb_icon,
                        3, activity.display_uri,
                        4, activity.time,
                        5, activity.selected);
                        
        activity.thumb_loaded.connect ((activity) => {
                this.update_icon_for_activity (activity);
        });
        
        activities.add (activity);
    }
    
    public void remove_activity (GenericActivity activity) {
        this.model.foreach ((model, path, iter) => {
            Value uri;
            this.model.get_value (iter, 0, out uri);
            if (uri.get_string () == activity.uri) {
                    this.model.remove (iter);
                    return true;
            }
            
            return false;
        });
    }
    
    private void update_icon_for_activity (GenericActivity activity) {
        //TODO Animated transition for the new icon?
        this.model.foreach ((model, path, iter) => {
            Value uri;
            this.model.get_value (iter, 0, out uri);
            if (uri.get_string () == activity.uri) {
                    this.model.set_value (iter, 2, activity.thumb_icon);
                    return true;
            }
            
            return false;
        });
    }
    
    public ListStore get_model () {
        return this.model;
    }
}
