/*
 * Copyright (c) 2012 Stefano Candori <scandori@gnome.org>
 *
 * GNOME Journal is free software; you can redistribute it and/or modify
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
 
//Taken from lp:synapse-project
public class Journal.ZeitgeistBackend: GLib.Object
{
    private Zeitgeist.Log zg_log;
    private Gee.ArrayList<Zeitgeist.Event> all_events;
    //Events that need to be classified (divided day by day)
    private Gee.ArrayList<Zeitgeist.Event> new_events;
    private Gee.ArrayList<Zeitgeist.Event> all_app_events;
    private Gee.Map<string, Gee.ArrayList<Zeitgeist.Event>> days_map;
    
    public DateTime last_loaded_date {
        get; private set;
    }

    //Tr is the timerange containing the events loaded
    public signal void events_loaded (Zeitgeist.TimeRange tr);

    construct
    {
      zg_log = new Zeitgeist.Log ();
      
      new_events = new Gee.ArrayList<Zeitgeist.Event> ();
      all_events = new Gee.ArrayList<Zeitgeist.Event> ();
      all_app_events = new Gee.ArrayList<Zeitgeist.Event> ();
      
      days_map = new Gee.HashMap<string, Gee.ArrayList<Zeitgeist.Event>> ();
      
      //TODO Add a monitor for new events here
      //Timeout.add_seconds (60*30, refresh_popularity);
    }
    
    public void load_events_on_start ()
    {
      int64 end = Zeitgeist.Timestamp.now ();
      //FIXME only 3 days atm
      int64 start = end - Zeitgeist.Timestamp.DAY * 3;
      load_events_for_timestamp_range (start, end);
    }

    private async void load_application_events (Zeitgeist.TimeRange tr)
    {
      Idle.add (load_application_events.callback, Priority.LOW);
      yield;

      var event = new Zeitgeist.Event ();
      event.set_interpretation ("!" + Zeitgeist.ZG_LEAVE_EVENT);
      var subject = new Zeitgeist.Subject ();
      subject.set_interpretation (Zeitgeist.NFO_SOFTWARE);
      subject.set_uri ("application://*");
      event.add_subject (subject);

      var ptr_arr = new PtrArray ();
      ptr_arr.add (event);

      Zeitgeist.ResultSet rs;

      try
      {
        rs = yield zg_log.find_events (tr, (owned) ptr_arr,
                                       Zeitgeist.StorageState.ANY,
                                       -1,
                                       Zeitgeist.ResultType.MOST_RECENT_EVENTS,
                                       null);

        foreach (Zeitgeist.Event e in rs)
        {
          if (e.num_subjects () <= 0) continue;
          all_app_events.add(e);
          all_events.add(e);
          new_events.add(e);
        }
      }
      catch (Error err)
      {
        warning ("%s", err.message);
        return;
      }
      
      yield fill_days_map ();
      events_loaded (tr);
    }

    private async void load_uri_events (Zeitgeist.TimeRange tr)
    {
      Idle.add (load_uri_events.callback);
      yield;

      var event = new Zeitgeist.Event ();
      event.set_interpretation ("!" + Zeitgeist.ZG_LEAVE_EVENT);
      var subject = new Zeitgeist.Subject ();
      subject.set_interpretation ("!" + Zeitgeist.NFO_SOFTWARE);
      subject.set_uri ("file://*");
      event.add_subject (subject);

      var ptr_arr = new PtrArray ();
      ptr_arr.add (event);

      Zeitgeist.ResultSet rs;

      try
      {
        /* Get popularity for file uris */
        rs = yield zg_log.find_events (tr, (owned) ptr_arr,
                                       Zeitgeist.StorageState.ANY,
                                       -1,
                                       Zeitgeist.ResultType.MOST_RECENT_SUBJECTS,
                                       null);

        foreach (Zeitgeist.Event e1 in rs)
        {
          if (e1.num_subjects () <= 0) continue;
          all_events.add(e1);
          new_events.add(e1);
        }
        
        /* Get popularity for web uris */
        subject.set_interpretation (Zeitgeist.NFO_WEBSITE);
        subject.set_uri ("");
        ptr_arr = new PtrArray ();
        ptr_arr.add (event);

        rs = yield zg_log.find_events (tr, (owned) ptr_arr,
                                       Zeitgeist.StorageState.ANY,
                                       -1,
                                       Zeitgeist.ResultType.MOST_RECENT_SUBJECTS,
                                       null);

        foreach (Zeitgeist.Event e2 in rs)
        {
          if (e2.num_subjects () <= 0) continue;
          all_events.add(e2);
          new_events.add(e2);
        }
      }
      catch (Error err)
      {
        warning ("%s", err.message);
      }
    }
    
    private async void fill_days_map () {
        Idle.add (fill_days_map.callback);
        yield;
        
        foreach (Zeitgeist.Event e1 in new_events)
        {
          if (e1.num_subjects () <= 0) continue;
          DateTime date = Utils.get_date_for_event (e1);
          string key = date.format("%Y-%m-%d");
          if (days_map.has_key (key) == false)
          {
            days_map[key] = new Gee.ArrayList<Zeitgeist.Event> ();
            last_loaded_date = date;
          }
          days_map[key].add (e1);
        }
        
        //OK, we have mapped the new events. Let's clear the list.
        new_events.clear ();
    }
    
    /*PUBLIC METHODS*/
    
    public void load_events_for_timerange (Zeitgeist.TimeRange tr) {
        load_uri_events.begin (tr);
        load_application_events.begin (tr);
    }
    
    public void load_events_for_timestamp_range (int64 start, int64 end) {
        Zeitgeist.TimeRange tr = new Zeitgeist.TimeRange (start, end);
        load_events_for_timerange (tr);
    }
    
    public void load_events_for_date_range (Date? start_date, Date? end_date) {
        int64 start;
        int64 end;
        Zeitgeist.TimeRange tr;
        if (start_date == null && end_date == null)
            tr = new Zeitgeist.TimeRange.anytime ();
        else if (start_date != null && end_date == null) {
            start = Zeitgeist.Timestamp.from_date (start_date);
            tr = new Zeitgeist.TimeRange (start, int64.MAX);
        }
        else if (start_date == null && end_date != null) {
            end = Zeitgeist.Timestamp.from_date (end_date);
            tr = new Zeitgeist.TimeRange (0, end);
        }
        else {
            start = Zeitgeist.Timestamp.from_date (start_date);
            end = Zeitgeist.Timestamp.from_date (end_date);
            tr = new Zeitgeist.TimeRange (start, end);
        }
        
        load_events_for_timerange (tr);
    }
    
    public Gee.ArrayList<Zeitgeist.Event>? get_events_for_date (string ymd) {
        if (days_map.has_key (ymd))
            return days_map[ymd];
        return null;
    }
    
    //TODO remove this and all_events array list when all the views use the right
    //way for retrieving events (see VTL)
    public Gee.ArrayList<Zeitgeist.Event> all_activities {
        get { return all_events; }
    }
}

