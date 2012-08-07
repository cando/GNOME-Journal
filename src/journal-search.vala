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

private class Journal.SearchManager : Object {
    private const int MAX_NUM_RESULTS = 25;
    private Zeitgeist.Index search_proxy;
    
    private Gee.List<Zeitgeist.Event> searched_events;
    public Gee.Map<string, Gee.ArrayList<Zeitgeist.Event>> days_map{
        get; private set;
    }
    
    public signal void search_finished ();
    
    public SearchManager () {
        Object ();
        searched_events = new Gee.ArrayList <Zeitgeist.Event> ();
        days_map = new Gee.HashMap<string, Gee.ArrayList<Zeitgeist.Event>> ();
        search_proxy = new Zeitgeist.Index ();
    }
    
    public async int search_simple (string text, int offset) {
        days_map.clear ();
        var tr = new Zeitgeist.TimeRange.anytime ();
        var ptr_arr = new PtrArray ();
        
        Zeitgeist.ResultSet rs;
        try {
           rs = yield search_proxy.search (text,
                                           tr, 
                                           (owned) ptr_arr,
                                           offset,
                                           MAX_NUM_RESULTS,
                                           Zeitgeist.ResultType.MOST_RECENT_SUBJECTS,
                                           null);
            
           foreach (Zeitgeist.Event e in rs)
           {
               if (e.num_subjects () <= 0) continue;
               searched_events.add (e);
           }
        
       } catch (Error e) {
           warning ("%s", e.message);
       }

       fill_days_map ();
       return offset + MAX_NUM_RESULTS;
   }
    
    public async int search_with_relevancies (string text, 
                                              out double[] relevancies,
                                              int offset) {
        days_map.clear ();
        var tr = new Zeitgeist.TimeRange.anytime ();
        var event = new Zeitgeist.Event ();
        var ptr_arr = new PtrArray ();
        ptr_arr.add (event);
        
        Zeitgeist.ResultSet rs;
        try {
            rs = yield search_proxy.search_with_relevancies (text,
                                                             tr,
                                                             (owned) ptr_arr, 
                                                             Zeitgeist.StorageState.ANY,
                                                             offset,
                                                             MAX_NUM_RESULTS,
                                                             Zeitgeist.ResultType.MOST_RECENT_SUBJECTS,
                                                             null,
                                                             out relevancies);
            foreach (Zeitgeist.Event e in rs)
            {
                if (e.num_subjects () <= 0) continue;
                searched_events.add (e);
            }
         } catch (Error e) {
             warning ("%s", e.message);
         }

         fill_days_map ();
         return offset + MAX_NUM_RESULTS;
    }
    
    private void fill_days_map () {
        string key = null;
        foreach (Zeitgeist.Event e1 in searched_events)
        {
          if (e1.num_subjects () <= 0) continue;
          DateTime date = Utils.get_date_for_event (e1);
          key = date.format("%Y-%m-%d");
          if (days_map.has_key (key) == false)
            days_map[key] = new Gee.ArrayList<Zeitgeist.Event> ();

          days_map[key].add (e1);
        }
        //OK, we have mapped the new events. Let's clear the list.
        searched_events.clear ();
        search_finished ();
    }
    
    public Gee.List<Zeitgeist.Event>? get_events_for_date (string ymd) {
        if (days_map.has_key (ymd))
            return days_map[ymd];
        return null;
    }
}

private class Journal.SearchWidget : Toolbar {
    private const int TIMEOUT_SEARCH = 500;
    
    public Gd.TaggedEntry entry {
        get; private set;
    }
    
    private uint search_timeout;
    
    public signal void search (string text);
    
    public SearchWidget (){
        this.search_timeout = 0;
        this.get_style_context().add_class (STYLE_CLASS_PRIMARY_TOOLBAR);
        entry = new Gd.TaggedEntry ();
        entry.secondary_icon_name = "edit-find-symbolic";
        entry.width_request = 260;
        entry.secondary_icon_sensitive = false;
        entry.secondary_icon_activatable = false;
        
        this.entry.changed.connect(() => {
            var text = this.entry.get_text();
            if (text != null && text != "") {
                this.entry.secondary_icon_name = "edit-clear-symbolic";
                this.entry.secondary_icon_sensitive = true;
                this.entry.secondary_icon_activatable = true;
            } else {
                this.entry.secondary_icon_name = "edit-find-symbolic";
                this.entry.secondary_icon_sensitive = false;
                this.entry.secondary_icon_activatable = false;
            }
            
            if (this.search_timeout != 0) {
                Source.remove (search_timeout);
                this.search_timeout = 0;
            }
            this.search_timeout = Timeout.add (TIMEOUT_SEARCH, () => {
                this.search_timeout = 0;
                var text_l = this.entry.get_text ().down ();
                if (text != null && text != "")
                    search (text_l);
                return false;
            });
        });
        
        this.entry.activate.connect(() => {
            var text_l = this.entry.get_text ().down ();
            if (text_l != null && text_l != "")
                search (text_l);
        });
        
        this.entry.icon_release.connect (() => {
            this.entry.set_text ("");
        });
        
        var item = new ToolItem();
        item.set_expand (true);
        item.add (entry);
        
        this.insert (item, 0);
    }
}
