
//Taken from lp:synapse-project
public class Journal.ZeitgeistBackend: GLib.Object
{
    private Zeitgeist.Log zg_log;
    private Gee.ArrayList<Zeitgeist.Event> all_events;
    private Gee.ArrayList<Zeitgeist.Event> all_app_events;
    private Gee.Map<string, Gee.ArrayList<Zeitgeist.Event>> days_map;

    public signal void events_loaded ();

    construct
    {
      zg_log = new Zeitgeist.Log ();
      all_events = new Gee.ArrayList<Zeitgeist.Event> ();
      all_app_events = new Gee.ArrayList<Zeitgeist.Event> ();
      
      days_map = new Gee.HashMap<string, Gee.ArrayList<Zeitgeist.Event>> ();

      load_events ();
      
      //TODO Add a monitor for new events here
      //Timeout.add_seconds (60*30, refresh_popularity);
    }

    private bool load_events ()
    {
      //TODO data for histogram? we need only the events count?
      int64 end = Zeitgeist.Timestamp.now ();
      //FIXME only 6 days atm
      int64 start = end - Zeitgeist.Timestamp.DAY * 50;
      load_uri_events.begin (start, end);
      load_application_events.begin (start, end);
      return true;
    }

    private async void load_application_events (int64 start, int64 end)
    {
      Idle.add (load_application_events.callback, Priority.LOW);
      yield;

      Zeitgeist.TimeRange tr = new Zeitgeist.TimeRange (start, end);

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
                                       256,
                                       Zeitgeist.ResultType.MOST_POPULAR_SUBJECTS,
                                       null);

        foreach (Zeitgeist.Event e in rs)
        {
          if (e.num_subjects () <= 0) continue;
          all_app_events.add(e);
        }
      }
      catch (Error err)
      {
        warning ("%s", err.message);
        return;
      }
    }

    private async void load_uri_events (int64 start, int64 end)
    {
      Idle.add (load_uri_events.callback);
      yield;

      Zeitgeist.TimeRange tr = new Zeitgeist.TimeRange (start, end);

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
                                       256,
                                       Zeitgeist.ResultType.MOST_RECENT_EVENTS,
                                       null);

        foreach (Zeitgeist.Event e1 in rs)
        {
          if (e1.num_subjects () <= 0) continue;
          all_events.add(e1);
        }
        
        /* Get popularity for web uris */
        subject.set_interpretation (Zeitgeist.NFO_WEBSITE);
        subject.set_uri ("");
        ptr_arr = new PtrArray ();
        ptr_arr.add (event);

        rs = yield zg_log.find_events (tr, (owned) ptr_arr,
                                       Zeitgeist.StorageState.ANY,
                                       128,
                                       Zeitgeist.ResultType.MOST_RECENT_EVENTS,
                                       null);

        foreach (Zeitgeist.Event e2 in rs)
        {
          if (e2.num_subjects () <= 0) continue;
          all_events.add(e2);
        }
      }
      catch (Error err)
      {
        warning ("%s", err.message);
      }
      
      yield fill_days_map ();
    }
    
    private async void fill_days_map () {
        Idle.add (fill_days_map.callback);
        yield;
        
        foreach (Zeitgeist.Event e1 in all_events)
        {
          if (e1.num_subjects () <= 0) continue;
          //Zeitgeist.Subject s1 = e1.get_subject (0);
          int64 timestamp = e1.get_timestamp () / 1000;
          //TODO To localtime here? Zeitgeist uses UTC timestamp, right?
          DateTime date = new DateTime.from_unix_utc (timestamp).to_local ();
          //TODO efficiency here? Use String? Int? Quark?
          string key = date.format("%Y-%m-%d");
          if (days_map.has_key(key) == false)
            days_map[key] = new Gee.ArrayList<Zeitgeist.Event> ();
          days_map[key].add (e1);
        }
        
        events_loaded ();
    }
    
    /*PUBLIC METHODS*/
    
    public Gee.ArrayList<Zeitgeist.Event>? get_events_for_day (string ymd) {
        if (days_map.has_key (ymd))
            return days_map[ymd];
        return null;
    }
    
    public Gee.ArrayList<Zeitgeist.Event> all_activities {
        get { return all_events; }
    }
}

