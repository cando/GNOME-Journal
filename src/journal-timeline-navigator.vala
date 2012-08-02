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

[DBus (name = "org.gnome.zeitgeist.Histogram")]
interface Histogram : Object {
    [DBus (signature = "a(xu)")]
    public abstract Variant get_histogram_data () throws IOError;
}

private class Journal.TimelineNavigator : ButtonBox {

    public static string[] time_labels = {
      _("Today"),
      _("Yesterday"),
      _("This Week"),
      _("This Month"),
      _("This year")
    };
    
    private Histogram histogram_proxy;
    private Gee.Map<DateTime?, uint> count_map;
    
    public static Gee.Map<string, DateTime?> jump_date;
    public string current_highlighted;
    public int current_highlighted_index;
    
    private Pango.AttrList attr_list_selected;
    private Pango.AttrList attr_list_normal;
    
    public signal void go_to_date (DateTime date);

    public TimelineNavigator (Orientation orientation){
        Object (orientation: orientation);
        this.set_layout (ButtonBoxStyle.START);
        
        this.jump_date = new Gee.HashMap<string, DateTime> ();
        var today = Utils.get_start_of_today ();

        jump_date.set (time_labels[0], today);
        jump_date.set (time_labels[1], today.add_days (-1));
        jump_date.set (time_labels[2], today.add_days (-7));
        
        /**********HISTOGRAM DBUS STUFF****************************/
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

        setup_ui ();
        if (orientation == Orientation.VERTICAL)
            this.get_style_context ().add_class ("vtimenav");
        else
            this.get_style_context ().add_class ("htimenav");
    }
    
    private void load_attributes () {
        attr_list_selected = new Pango.AttrList ();
        attr_list_selected.insert (Pango.attr_scale_new (Pango.Scale.SMALL));
        attr_list_selected.insert (Pango.attr_weight_new (Pango.Weight.BOLD));
        
        attr_list_normal = new Pango.AttrList ();
        attr_list_normal.insert (Pango.attr_scale_new (Pango.Scale.SMALL));
    }
    
    private Gee.List<string> select_time_labels () {
        Gee.List<string> result = new Gee.ArrayList<string> ();
        var today = Utils.get_start_of_today ();
        foreach (DateTime key in count_map.keys) {
            int diff_days = (int)Math.round(((double)(today.difference (key)) / 
                                             (double)TimeSpan.DAY));
            //Give more importance to "near" days
            if (diff_days < 15) {
                switch (diff_days){
                    case 0: 
                        if (result.index_of (time_labels[0]) == -1)
                            result.add (time_labels[0]); 
                        break;
                    case 1:
                        if (result.index_of (time_labels[1]) == -1)
                            result.add (time_labels[1]); 
                        break;
                    case 2:
                        var bef_yesterday = today.add_days (-2);
                        var text = bef_yesterday.format("%A");
                        if (result.index_of (text) == -1) {
                            result.add (text);
                            jump_date.set (text, bef_yesterday); 
                        }
                        break;
                    case 3: case 4: case 5: case 6: case 7:
                        if (result.index_of (time_labels[2]) == -1)
                            result.add (time_labels[2]); 
                        break;
                    default: break;
                }
            }
            else if (diff_days < 31 && today.get_day_of_month() > 15) {//This month
                var this_month = today.add_days (-today.get_day_of_month() + 1);
                if (result.index_of (time_labels[3]) == -1) {
                    result.add (time_labels[3]);
                    jump_date.set (time_labels[3], this_month);
                }
            }
            else if (diff_days < 62 && today.get_month() != 1) {//Last month
                var last_month = today.add_months (-1);
                var text = last_month.format("%B");
                if (result.index_of (text) == -1) {
                    result.add (text);
                    jump_date.set (text, last_month);
                }
            }
            else if (key.get_year () == today.get_year ()) {//This year
                var text = _("This year");
                jump_date.set (text, today.add_days(-diff_days));
                if (result.index_of (text) == -1 )
                    result.add (text);
            }
            else { //Other years
                var text = key.get_year ().to_string ();
                jump_date.set (text, today.add_days(-diff_days));
                if (result.index_of (text) == -1)
                    result.add (text);
            }
        }
        
        result.sort ( (a,b) => {
            string first_s = (string) a;
            string second_s = (string) b;
            DateTime first = jump_date.get (first_s);
            DateTime second = jump_date.get (second_s);
            return - (first.compare (second));
        });
        return result;
    }
    
    private void setup_ui () {
        load_attributes ();
        int i = 0;
        foreach(string s in select_time_labels ()) {
            var l = new Label (s);
            l.attributes = attr_list_normal;
            Button b = new Button();
            b.add(l);
            b.set_alignment (0, 0);
            //Let's highlight Today.
            if (i == 0) {
                Label label = (Label) b.get_child ();
                label.attributes = attr_list_selected;
                current_highlighted = jump_date.get(time_labels[0]).format ("%Y-%m-%d");
                current_highlighted_index = 0;
           }
            b.clicked.connect (() => {
                foreach (Widget w in this.get_children ()) {
                    Label other_label = (Label)((Button)w).get_child ();
                    other_label.attributes = attr_list_normal;
                 }
                Label label = (Label) b.get_child ();
                label.attributes = attr_list_selected;
                DateTime date = jump_date.get (label.label);
                this.go_to_date (date);
            });
            this.pack_start (b, false, false, 0);
            i++;
        }
        this.show_all();
    }
    
    public void highlight_next () {
        var index = current_highlighted_index + 1;
        int i = 0;
        foreach (Widget w in this.get_children ()) {
            Label label = (Label)((Button)w).get_child ();
            if (i == index)
                label.attributes = attr_list_selected;
            else
                label.attributes = attr_list_normal;
            i++;
        }
    }
    
    public void highlight_previous () {
        var index = current_highlighted_index - 1;
        int i = 0;
        foreach (Widget w in this.get_children ()) {
            Label label = (Label)((Button)w).get_child ();
            if (i == index)
                label.attributes = attr_list_selected;
            else
                label.attributes = attr_list_normal;
            i++;
        }
    }
    
    public void highlight_date (string date) {
        foreach (Gee.Map.Entry<string,DateTime> entry in jump_date.entries) {
            if (entry.value.format ("%Y-%m-%d") == date) {
                string key = entry.key;
                foreach (Widget w in this.get_children ()) {
                    Label label = (Label)((Button)w).get_child ();
                    if (label.label == key)
                        label.attributes = attr_list_selected;
                    else
                        label.attributes = attr_list_normal;
                }
            }
        }
    }
}

