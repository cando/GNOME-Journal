using Gtk;

private class Journal.ActivityInfoPage : Box {
    
    private Gd.MainView view;
    private ListStore model;
    private ScrolledWindow scrolled_window;
    
    public ActivityInfoPage () {
        Object (orientation: Orientation.VERTICAL, spacing : 5);
        this.model = new ListStore (6, 
                                   typeof (string), // URI
                                   typeof (string), // TITLE
                                   typeof (Gdk.Pixbuf), // THUMB_ICON
                                   typeof (string), // DISPLAY_URI
                                   typeof (int64),  // TIME
                                   typeof (bool)); // SELECTED
        this.model.set_sort_column_id (Gd.MainColumns.TIME, 
                                       SortType.DESCENDING);
                                       
        view = new Gd.MainView (Gd.MainViewType.LIST);
        
        scrolled_window = new ScrolledWindow (null, null);
        scrolled_window.set_policy (PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
        scrolled_window.add_with_viewport(view);

        this.pack_start (scrolled_window, true, true, 0);
    }
    
    public void set_activity (CompositeActivity activity) {
        model.clear ();
        TreeIter iter;
        foreach (GenericActivity act in activity.activities) {
            this.model.append (out iter);
            this.model.set (iter,
                            0, act.uri,
                            1, act.title,
                            2, act.thumb_icon,
                            3, act.display_uri,
                            4, act.time,
                            5, act.selected);
           
           act.thumb_loaded.connect (() => {
                this.update_icon_for_activity (act);
            });
        }
        view.set_model (model);
        view.item_activated.connect ((o, path) => {
            this.launch_item (path);
        });
        
        this.show_all ();
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
    
    private void launch_item (TreePath path_in) {
        this.model.foreach ((model, path, iter) => {
            Value uri;
            this.model.get_value (iter, 0, out uri);
            if (path.compare (path_in) == 0) {
                try {
                    AppInfo.launch_default_for_uri (uri.get_string (), null);
                } catch (Error e) {
                    warning ("Error in launching: "+ uri.get_string ());
                }
                return true;
            }
            return false;
        });
    }
}

