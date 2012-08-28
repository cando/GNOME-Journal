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
 
[DBus (name = "org.gnome.zeitgeist.Histogram")]
interface Histogram : Object {
    [DBus (signature = "a(xu)")]
    public abstract Variant get_histogram_data () throws IOError;
}

private class Journal.ZeitgeistHistogram : GLib.Object 
{
    private Histogram histogram_proxy;
    
    public ZeitgeistHistogram () {
        Object ();
        try {
            histogram_proxy = Bus.get_proxy_sync (
                                    BusType.SESSION, 
                                    "org.gnome.zeitgeist.Engine",
                                    "/org/gnome/zeitgeist/journal/activity");
        } catch (Error e) {
            warning ("%s", e.message);
        }
    }
    
    public Gee.List<DateTime?> load_histogram_data () {
        var days_list = new Gee.ArrayList<DateTime?> ((a,b) => {
            DateTime first = (DateTime) a;
            DateTime second = (DateTime) b;
            return first.compare (second) == 0;
        });
       
        try {
            Variant data = histogram_proxy.get_histogram_data ();
            size_t n = data. n_children ();
            int64 time = 0;
            uint count = 0;
            
            for (size_t j =0; j <n; j++) {
                data.get_child (j, "(xu)", &time, &count);
                DateTime date = new DateTime.from_unix_local (time);
                days_list.add (date);
            }
        } catch (Error e) {
            warning ("%s", e.message);
        }
        
        return days_list;
    }
}

//Taken from lp:synapse-project
public class Journal.ZeitgeistBackend: GLib.Object
{
    private Zeitgeist.Log zg_log;
    private Zeitgeist.Monitor zg_monitor;
    private ZeitgeistHistogram histogram;
    
    //Events that need to be classified (divided day by day)
    private Gee.ArrayList<Zeitgeist.Event> new_events;
    //The Map of the events divided day by day
    private Gee.Map<string, Gee.ArrayList<Zeitgeist.Event>> days_map;
    //The list of the days with at least 1 Zeitgeist event
    public Gee.List<DateTime?> days_list {
        get; private set;
    }
    
    public DateTime last_loaded_date {
        get; private set;
    }

    //Day is the day containing the events loaded
    public signal void events_loaded (string day);

    construct
    {
      zg_log = new Zeitgeist.Log ();
      histogram = new ZeitgeistHistogram ();
      
      new_events = new Gee.ArrayList<Zeitgeist.Event> ();
      days_map = new Gee.HashMap<string, Gee.ArrayList<Zeitgeist.Event>> ();
      
      days_list = histogram.load_histogram_data ();
      
      //Initialize Monitor
      var tr = new Zeitgeist.TimeRange.from_now ();
      var event = new Zeitgeist.Event ();
      event.set_interpretation ("!" + Zeitgeist.ZG_LEAVE_EVENT);
      var subject = new Zeitgeist.Subject ();
      //TODO add a configuration value?
      subject.set_interpretation ("!" + Zeitgeist.NFO_SOFTWARE);
      event.add_subject (subject);
      var ptr_arr = new PtrArray ();
      ptr_arr.add (event);
      zg_monitor = new Zeitgeist.Monitor (tr, (owned)ptr_arr);
      zg_monitor.events_inserted.connect ((tr, rs) => {
          foreach (Zeitgeist.Event e1 in rs)
          {
              if (e1.num_subjects () <= 0) continue;
              new_events.add(e1);
          }
          fill_days_map ();
      });
      
      zg_log.install_monitor (zg_monitor);
    }

    private async void load_gtg_events (Zeitgeist.TimeRange tr, 
                                     bool show_applications=false)
    {
      var event = new Zeitgeist.Event ();
      event.set_interpretation ("!" + Zeitgeist.ZG_DELETE_EVENT);
      var subject = new Zeitgeist.Subject ();
      subject.set_interpretation (Zeitgeist.NCAL_TODO);
      event.add_subject (subject);
      var ptr_arr = new PtrArray ();
      ptr_arr.add (event);

      Zeitgeist.ResultSet rs;
      
      try
      {
        /* Get popularity for file uris */
        rs = yield zg_log.find_events (tr, (owned) ptr_arr,
                                       Zeitgeist.StorageState.ANY,
                                       0,
                                       Zeitgeist.ResultType.MOST_POPULAR_SUBJECTS,
                                       null);

        foreach (Zeitgeist.Event e1 in rs)
        {
          if (e1.num_subjects () <= 0) continue;
          new_events.add(e1);
        }
      }
      catch (Error err)
      {
        warning ("%s", err.message);
      }
    }
    
    private async void load_events (Zeitgeist.TimeRange tr, 
                                     bool show_applications=false)
    {
      var event = new Zeitgeist.Event ();
      event.set_interpretation ("!" + Zeitgeist.ZG_LEAVE_EVENT);
      var subject = new Zeitgeist.Subject ();
      if (!show_applications)
        subject.set_interpretation ("!" + Zeitgeist.NFO_SOFTWARE);
//      if (!show_websites)
//        subject.set_interpretation ("!" + Zeitgeist.NFO_WEBSITE);
      event.add_subject (subject);
      var ptr_arr = new PtrArray ();
      ptr_arr.add (event);

      Zeitgeist.ResultSet rs;
      
      try
      {
        /* Get popularity for file uris */
        rs = yield zg_log.find_events (tr, (owned) ptr_arr,
                                       Zeitgeist.StorageState.ANY,
                                       0,
                                       Zeitgeist.ResultType.MOST_POPULAR_SUBJECTS,
                                       null);

        foreach (Zeitgeist.Event e1 in rs)
        {
          if (e1.num_subjects () <= 0) continue;
          new_events.add(e1);
        }
      }
      catch (Error err)
      {
        warning ("%s", err.message);
      }
      
      fill_days_map ();
    }
    
    private void fill_days_map () {
        string key = null;
        foreach (Zeitgeist.Event e1 in new_events)
        {
          if (e1.num_subjects () <= 0) continue;
          DateTime date = Utils.get_date_for_event (e1);
          key = date.format("%Y-%m-%d");
          if (days_map.has_key (key) == false)
            days_map[key] = new Gee.ArrayList<Zeitgeist.Event> ();

          days_map[key].add (e1);
        }
        //OK, we have mapped the new events. Let's clear the list.
        new_events.clear ();
        events_loaded (key);
    }
    
    private void load_events_for_timerange (Zeitgeist.TimeRange tr) {
        load_gtg_events.begin(tr);
        load_events.begin (tr);
        
        last_loaded_date = Utils.get_start_of_the_day (tr.get_end ());
    }
    
    /*PUBLIC METHODS*/
    public void load_events_on_start ()
    {
        int max_days = int.min (3, days_list.size);
        load_days_list (days_list.slice (0, max_days));
    }
    
    public void load_days_list (Gee.List<DateTime?> list) {
        if (list.size == 0)
            return;
        int64 start;
        int64 end;
        for (int i = 0 ; i < list.size; i++) {
            end = Zeitgeist.Timestamp.next_midnight (list.get (i).to_unix () * 1000);
            start = end - Zeitgeist.Timestamp.DAY;
            var tr = new Zeitgeist.TimeRange (start, end);
            load_events_for_timerange (tr);
        }
    }
    
    public int load_other_days (int num_days) {
        int index = days_list.index_of (last_loaded_date);
        if (index == -1) {
            critical ("[Load_other_days] Problem in loading new activities. Please file a bug.");
            return -1;
        }
        if (index + 1 == days_list.size) {
            warning ("[Load_other_days] End of your activities. Load nothing");
            return -1;
        }
        var stop = int.min (index + 1 + num_days, days_list.size);
        var to_load_list = days_list.slice (index + 1, stop);
        
        load_days_list (to_load_list);
        
        return to_load_list.size;
    }
    
    public Gee.ArrayList<Zeitgeist.Event>? get_events_for_date (string ymd) {
        if (days_map.has_key (ymd))
            return days_map[ymd];
        return null;
    }
}

