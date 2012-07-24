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

//TODO Add maximum number of time labels??
[DBus (name = "org.gnome.zeitgeist.Histogram")]
interface Histogram : Object {
    [DBus (signature = "a(xu)")]
    public abstract Variant get_histogram_data () throws IOError;
}

private class Journal.TimelineNavigator : ButtonBox {

    public static string[] time_labels = {
      _("Today"),
      _("Yesterday"),
      _("2 Days Ago"),
      _("3 Days Ago"),
      _("A Week Ago"),
      _("Two Weeks Ago"),
      _("Three Weeks Ago"),
      _("A Month Ago"),
      _("2 Month Ago"),
      _("3 Month Ago"),
      _("4 Month Ago"),
      _("5 Month Ago"),
      _("6 Month Ago"),
      _("7 Month Ago"),
      _("8 Month Ago"),
      _("9 Month Ago"),
      _("10 Month Ago"),
      _("11 Month Ago"),
      _("Last year")
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
        jump_date.set (time_labels[2], today.add_days (-2));
        jump_date.set (time_labels[3], today.add_days (-3));
        jump_date.set (time_labels[4], today.add_days (-7));
        jump_date.set (time_labels[5], today.add_days (-7*2));
        jump_date.set (time_labels[6], today.add_days (-7*3));
        jump_date.set (time_labels[7], today.add_days (-30));
        jump_date.set (time_labels[8], today.add_days (-30*2));
        jump_date.set (time_labels[9], today.add_days (-30*3));
        jump_date.set (time_labels[10], today.add_days (-30*4));
        jump_date.set (time_labels[11], today.add_days (-30*5));
        jump_date.set (time_labels[12], today.add_days (-30*6));
        jump_date.set (time_labels[13], today.add_days (-30*7));
        jump_date.set (time_labels[14], today.add_days (-30*8));
        jump_date.set (time_labels[15], today.add_days (-30*9));
        jump_date.set (time_labels[16], today.add_days (-30*10));
        jump_date.set (time_labels[17], today.add_days (-30*11));
        jump_date.set (time_labels[18], today.add_days (-365));
        
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
                DateTime date = new DateTime.from_unix_utc (time).to_local ();
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
            //TODO use count for a better selection of label basing on importance
            //of days-->number of events.
            //uint count = count_map.get (key);
            //Difference (in days) with today.
            int diff_days = (int)Math.round(((double)(today.difference (key)) / 
                                             (double)TimeSpan.DAY));
            //Give more importance to "near" days
            if (diff_days <= 3)
                result.add (time_labels[diff_days]);
            else {
                //Start from "This week" label
                int choosen_label = 0;
                for(int i = 4 ; i < time_labels.length; i++) {
                    DateTime possible_date = jump_date.get (time_labels[i]);
                    int diff = (int)Math.round(((double)
                                    (possible_date.difference (key)) / 
                                     (double)TimeSpan.DAY));
                    int abs_diff = diff.abs ();
                    //Stupid algorithm that try to find the nearest time_label
                    //in respect to a certain DateTime.
                    if (i >= 4 && i <= 6) {
                        //We are in the week's labels
                        if (abs_diff < 4) { //4 = half week
                            choosen_label = i;
                            break;
                         }
                    }
                    else if (i > 6 && i < 18) {
                        //We are in the month's labels
                        if (abs_diff < 15) { //15 = half month
                            choosen_label = i;
                            break;
                         }
                    }
                    else if (i == 18){
                        if (abs_diff > 30) {
                            //Last Year label
                            choosen_label = i;
                            break;
                         }
                    }
                    //else continue with next possible date
                }
                
                string label = time_labels[choosen_label];
                if (!result.contains (label))
                    result.add (label);
                    continue;
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

