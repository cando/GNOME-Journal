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
 
//Taken from lp:synapse-project
public class Journal.ZeitgeistBackend: GLib.Object
{
    private Zeitgeist.Log zg_log;
    private Zeitgeist.Monitor zg_monitor;
    //Events that need to be classified (divided day by day)
    private Gee.ArrayList<Zeitgeist.Event> new_events;
    private Gee.ArrayList<Zeitgeist.Event> all_app_events;
    private Gee.Map<string, Gee.ArrayList<Zeitgeist.Event>> days_map;
    
    public DateTime last_loaded_date {
        get; private set;
    }

    //Day is the day containing the events loaded
    public signal void events_loaded (string? day);

    construct
    {
      zg_log = new Zeitgeist.Log ();
      
      new_events = new Gee.ArrayList<Zeitgeist.Event> ();
      all_app_events = new Gee.ArrayList<Zeitgeist.Event> ();
      days_map = new Gee.HashMap<string, Gee.ArrayList<Zeitgeist.Event>> ();
      
      //Initialize Monitor
      var tr = new Zeitgeist.TimeRange.from_now ();
      var event = new Zeitgeist.Event ();
      event.set_interpretation ("!" + Zeitgeist.ZG_LEAVE_EVENT);
      var subject = new Zeitgeist.Subject ();
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
    
    public void load_events_on_start ()
    {
      int64 end = Zeitgeist.Timestamp.next_midnight (Zeitgeist.Timestamp.now ());
      int64 start = end - Zeitgeist.Timestamp.DAY;
      for (int i = 0 ; i < 3; i++) {
        var tr = new Zeitgeist.TimeRange (start, end);
        load_events_for_timerange (tr);
        end = start;
        start = end - Zeitgeist.Timestamp.DAY;
      }
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
        
        last_loaded_date = Utils.get_start_of_the_day (tr.get_start ());
    }
    
    /*PUBLIC METHODS*/
    public void load_events_for_date_range (TimeVal? start_date, TimeVal? end_date) {
        int64 start = 0;
        int64 end = 0;
        Zeitgeist.TimeRange tr;
        if (start_date == null && end_date == null)
            tr = new Zeitgeist.TimeRange.anytime ();
        else if (start_date != null && end_date == null) {
            start = Zeitgeist.Timestamp.from_timeval (start_date);
            tr = new Zeitgeist.TimeRange (start, int64.MAX);
        }
        else if (start_date == null && end_date != null) {
            end = Zeitgeist.Timestamp.from_timeval (end_date);
            tr = new Zeitgeist.TimeRange (0, end);
        }
        else {
            start = Zeitgeist.Timestamp.from_timeval (start_date);
            end = Zeitgeist.Timestamp.from_timeval (end_date);
            tr = new Zeitgeist.TimeRange (start, end);
        }
        
        //Since we query the database asking for MostRecentSubjects and not Most
        //RecentEvents we need do load every day singularly, otherwise we'll show
        //false results.
        int64 real_start = tr.get_start ();
        int64 real_end = tr.get_end ();
        int64 tmp_end = real_end;
        int64 tmp_start = tmp_end - Zeitgeist.Timestamp.DAY;
        while (real_start != tmp_start) {
            var new_tr = new Zeitgeist.TimeRange (tmp_start, tmp_end);
            load_events_for_timerange (new_tr);
            tmp_end = tmp_start;
            tmp_start = tmp_end - Zeitgeist.Timestamp.DAY;
        }
    }
    
    public Gee.ArrayList<Zeitgeist.Event>? get_events_for_date (string ymd) {
        if (days_map.has_key (ymd))
            return days_map[ymd];
        return null;
    }
}

