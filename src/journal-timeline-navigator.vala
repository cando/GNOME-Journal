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

enum RangeType {
    YEAR,
    MONTH,
    WEEK,
    LAST_WEEK,
    DAY
}

[DBus (name = "org.gnome.zeitgeist.Histogram")]
interface Histogram : Object {
    [DBus (signature = "a(xu)")]
    public abstract Variant get_histogram_data () throws IOError;
}

private class Journal.TimelineNavigator : Frame {
    
    private Histogram histogram_proxy;
    private Gee.Map<DateTime?, uint> count_map;
    
    private TreeStore model;
    private TreeView view;
    private TreePath? expanded_row;
    
    private ScrolledWindow scrolled_window;
    
    public signal void go_to_date (DateTime date, RangeType type);

    public TimelineNavigator (Orientation orientation){
        Object ();
        this.get_style_context ().add_class (STYLE_CLASS_SIDEBAR);
        scrolled_window = new ScrolledWindow (null, null);
        scrolled_window.set_policy (PolicyType.NEVER, PolicyType.AUTOMATIC);
        
        /**********HISTOGRAM DBUS STUFF**********/
        try {
            histogram_proxy = Bus.get_proxy_sync (
                                    BusType.SESSION, 
                                    "org.gnome.zeitgeist.Engine",
                                    "/org/gnome/zeitgeist/journal/activity");
            Variant data = histogram_proxy.get_histogram_data ();
            size_t n = data. n_children ();
            int64 time = 0;
            uint count = 0;
            this.count_map = new Gee.HashMap<DateTime?, uint> ();
            
            for (size_t j =0; j <n; j++) {
                data.get_child (j, "(xu)", &time, &count);
                DateTime date = new DateTime.from_unix_local (time);
                count_map.set (date, count);
            }
        } catch (Error e) {
            warning ("%s", e.message);
        }
        
        model = new TreeStore (3, typeof (DateTime), // Date
                                  typeof (string),   // String repr. of the Date
                                  typeof (RangeType));  // RangeType type (used for padding)
        view = new TreeView ();
        model.set_sort_func (0, (model, a,b) => {
            Value f;
            Value s;
            model.get_value (a, 0, out f);
            model.get_value (b, 0, out s);
            DateTime first = f as DateTime;
            DateTime second = s as DateTime;
            return first.compare (second);
        });
        model.set_sort_column_id (0, SortType.DESCENDING);
        
        view.cursor_changed.connect (on_cursor_change);
        view.motion_notify_event.connect (on_motion_notify);
        
        expanded_row = null;
        
        setup_ui ();
    }

    private void on_cursor_change () {
        var selection = view.get_selection();
        TreeModel model_f;
        TreeIter iter;
        DateTime date;
        RangeType type;
        if (selection == null)
            return;
        if(selection.get_selected (out model_f, out iter))
        {
            model_f.get(iter, 0, out date, 2, out type);
            if (type != RangeType.DAY) {
                view.collapse_all ();
                var path = model.get_path (iter);
                if (path != null)
                    view.expand_row (path, false);
            }
            else
                this.go_to_date (date, type);
        }
    }
    
    private bool on_motion_notify (Gdk.EventMotion event) {
        //Expand weeks on mouse-hover
        TreePath path;
        TreeIter iter;
        DateTime date;
        RangeType type;
        view.get_path_at_pos ((int)event.x, (int)event.y, out path, null, null, null);
        if (path == null)
            return false;
        model.get_iter_from_string (out iter, path.to_string ());
        model.get(iter, 0, out date, 2, out type);
        if (type == RangeType.WEEK || type == RangeType.LAST_WEEK) {
            view.expand_row (path, false);
            //Collapse the previous expanded week row
            if (expanded_row != null && expanded_row.compare (path) != 0)
                view.collapse_row (expanded_row);
            expanded_row = path;
        }
        else if ((type != RangeType.DAY) || 
                (type == RangeType.DAY && Utils.is_today_or_yesterday (date))){
            if (expanded_row != null)
                view.collapse_row (expanded_row);
        }
        return false;
    }

    private void setup_ui () {
        view.set_model (model);
        view.show_expanders = false;
        view.level_indentation = 10;
        view.set_headers_visible (false);
        
        var text = new CellRendererText ();
        text.set_alignment (0, 0.5f);
        text.set ("weight", Pango.Weight.BOLD,
                  "height", 30);
        
        var column = new TreeViewColumn ();
        column.pack_start (text, false);
        
        column.set_cell_data_func (text, (layout, cell, model, iter) => {
            RangeType type;
            string name;
            model.get (iter, 1, out name, 2, out type);
            cell.set ("text", name);
            if (type == RangeType.WEEK || type == RangeType.LAST_WEEK) {
                cell.set ("foreground", "grey", "foreground-set", true);
            }
            else {
                cell.set ("foreground-set", false);
            }
        });
        
        view.append_column (column);
        
        setup_timebar ();
        scrolled_window.add_with_viewport (view);
        this.add (scrolled_window);
        
//        model.foreach ((model_, path, year_iter) => {
//            string name;
//            model.get (year_iter, 1, out name);
//            warning(name);
//            return false;
//        });

        //Select the first day---> Today!
        TreeIter iter;
        var selection = view.get_selection ();
        model.get_iter_first (out iter);
        selection.select_iter (iter);
    }
    
    //WTF!!!!!!!!!!!!!!!
    private void setup_timebar () {
        var today = Utils.get_start_of_today ();
        var this_year_added = false;
        var last_month_added = false;
        var this_month_added = false;
        var last_week_added = false;
        var this_week_added = false;
        foreach (DateTime key in count_map.keys) {
            int diff_days = (int)Math.round(((double)(today.difference (key)) / 
                                             (double)TimeSpan.DAY));
            TreeIter root;
            if (diff_days < 7) {
                switch (diff_days){
                    case 0: 
                        model.append (out root, null);
                        model.set (root, 0, key, 1, _("Today"), 2, RangeType.DAY);
                        break;
                    case 1:
                        model.append (out root, null);
                        model.set (root, 0, key, 1, _("Yesterday"), 2, RangeType.DAY); 
                        break;
                    case 2: case 3: case 4: case 5: case 6:
                        if (!this_week_added) {
                            model.append (out root, null);
                            model.set (root, 0, key, 1, _("This week"), 2, RangeType.WEEK);
                            this_week_added = true;
                        }
                        var next = model.iter_children (out root, null);
                        while (next) {
                            RangeType type;
                            model.get (root, 2, out type);
                            if (type == RangeType.WEEK) {
                                TreeIter this_week_iter;
                                model.append (out this_week_iter, root);
                                var text = get_day_representation (key);
                                model.set (this_week_iter, 
                                           0, key, 
                                           1, text, 
                                           2, RangeType.DAY);
                                break;
                            }
                            next = model.iter_next (ref root);
                        }
                        break;
                    default: break;
                }
            } else if (diff_days > 6 && diff_days < 14) {
                if (!last_week_added) {
                    model.append (out root, null);
                    model.set (root, 0, key, 1, _("Last week"), 2, RangeType.LAST_WEEK);
                    last_week_added = true;
                }
                var next = model.iter_children (out root, null);
                while (next) {
                    RangeType type;
                    model.get (root, 2, out type);
                    if (type == RangeType.LAST_WEEK) {
                        TreeIter last_week_iter;
                        model.append (out last_week_iter, root);
                        var text = get_day_representation (key);
                        model.set (last_week_iter, 
                                   0, key, 
                                   1, text, 
                                   2, RangeType.DAY);
                        break;
                    }
                    next = model.iter_next (ref root);
                }
            } else if (diff_days < 31) { //This month
                if (!this_month_added) {
                    var this_month = new DateTime.local (today.get_year (), 
                                                         today.get_month (),
                                                         1, 0, 0, 0);
                    model.append (out root, null);
                    var text = this_month.format (_("%B"));
                    model.set (root, 0, this_month, 1, text, 2, RangeType.MONTH);
                    this_month_added = true;
                }
            } else if (diff_days < 60) { //Last month
                if (!last_month_added) {
                    var new_date = today.add_months (-1);
                    var last_month = new DateTime.local (new_date.get_year (), 
                                                         new_date.get_month (),
                                                         1, 0, 0, 0);
                    model.append (out root, null);
                    var text = last_month.format (_("%B"));
                    model.set (root, 0, last_month, 1, text, 2, RangeType.MONTH);
                    last_month_added = true;
                }
            } else if (diff_days < 365) { //Other Months of the year
                if (!this_year_added) {
                    model.append (out root, null);
                    var this_year_date = new DateTime.local (today.get_year (), 1, 1, 0, 0, 0);
                    model.set (root, 0, this_year_date, 1, _("..."), 2, RangeType.YEAR);
                    this_year_added = true;
                }
            }
        }
        foreach (DateTime key in count_map.keys) {
                var year = key.get_year ();
                var month = key.get_month ();
                var day = key.get_day_of_month ();
                var week = (day / 7) + 1;
               
                RangeType type;
                DateTime date;
                var found_year = false;
                var found_month = false;
                var found_near_months = false;
                var found_week = false;
                TreeIter year_iter;
                var next = model.iter_children (out year_iter, null);
                while (next) {
                    model.get (year_iter, 0, out date, 2, out type);
                    if (type == RangeType.MONTH) {
                        //Populate the two nearer month from today!
                        if (date.get_month () == month) {
                            found_near_months = true;
                            TreeIter week_iter;
                            next = model.iter_children (out week_iter, year_iter);
                            while (next) {
                                DateTime w_date;
                                model.get (week_iter, 0, out w_date);
                                var day_ = w_date.get_day_of_month ();
                                var week_ = (day_ / 7) + 1;
                                if (week_ == week) {
                                    found_week = true;
                                    break;
                                }
                                next = model.iter_next (ref week_iter);
                            }
                            //Add week if not found
                            if (!found_week) {
                                model.append (out week_iter, year_iter);
                                int new_day;
                                if (week == 1)
                                    new_day = 1;
                                else
                                    new_day = (week - 1) * 7;
                                var new_date = new DateTime.local (
                                                                   year,
                                                                   month, 
                                                                   new_day, 
                                                                   0, 0, 0);
                               var text = _("Week ") + 
                               new_date.get_week_of_year ().to_string ();
                               model.set (week_iter, 
                                                   0, new_date, 
                                                   1, text,
                                                   2, RangeType.WEEK);
                           }
                           //Add day always
                           TreeIter day_iter;
                           model.append (out day_iter, week_iter);
                           var text = get_day_representation (key);
                           model.set (day_iter, 
                                      0, key, 
                                      1, text,
                                      2, RangeType.DAY);
                           break;
                        }
                    }
                    if (found_near_months)
                        break;
                        
                    if (type == RangeType.YEAR) {
                        if (date.get_year () == year) {
                            found_year = true;
                            TreeIter month_iter;
                            next = model.iter_children (out month_iter, year_iter);
                            while (next) {
                                model.get (month_iter, 0, out date, 2, out type);
                                if (date.get_month () == month) {
                                    found_month = true;
                                    TreeIter week_iter;
                                    next = model.iter_children (out week_iter, month_iter);
                                    while (next) {
                                        DateTime w_date;
                                        model.get (week_iter, 0, out w_date);
                                        var day_ = w_date.get_day_of_month ();
                                        var week_ = (day_ / 7) + 1;
                                        if (week_ == week) {
                                            found_week = true;
                                            break;
                                        }
                                        next = model.iter_next (ref week_iter);
                                     }
                                     //Add week if not found
                                     if (!found_week) {
                                        model.append (out week_iter, month_iter);
                                        int new_day;
                                        if (week == 1)
                                            new_day = 1;
                                        else
                                            new_day = (week - 1) * 7;
                                        var new_date = new DateTime.local (
                                                                       year,
                                                                       month, 
                                                                       new_day, 
                                                                       0, 0, 0);
                                        var text = _("Week ") + 
                                        new_date.get_week_of_year ().to_string ();
                                        model.set (week_iter, 
                                                   0, new_date, 
                                                   1, text,
                                                   2, RangeType.WEEK);
                                     }
                                     //Add day always
                                     TreeIter day_iter;
                                     model.append (out day_iter, week_iter);
                                     var text = get_day_representation (key);
                                     model.set (day_iter, 
                                                0, key, 
                                                1, text,
                                                2, RangeType.DAY);
                                     break;
                                }
                                next = model.iter_next (ref month_iter);
                            }
                            //Add month if not found
                            if (!found_month) {
                                model.append (out month_iter, year_iter);
                                var new_date = new DateTime.local (year, month, 1, 0, 0, 0);
                                model.set (month_iter, 
                                           0, new_date, 
                                           1, new_date.format(_("%B")),
                                           2, RangeType.MONTH);
                            }
                            break;
                        }
                    }
                    next = model.iter_next (ref year_iter);
                }
                //Add year if not found
                if (!found_year && !found_near_months) {
                    model.append (out year_iter, null);
                    DateTime new_date = new DateTime.local (year, 1, 1, 0, 0, 0);
                    model.set (year_iter, 
                               0, new_date, 
                               1, year.to_string (),
                               2, RangeType.YEAR);
                }
        }
    }
    
    //UTILS
    private string get_day_representation (DateTime date) {
        var text = date.format(_("%a,%e"));
        if (date.get_day_of_month () == 1)
            text += _("st");
        else if (date.get_day_of_month () == 2)
            text += _("nd");
        else if (date.get_day_of_month () == 3)
            text += _("rd");
        else
            text += _("th");
            
        return text;
    }
}

