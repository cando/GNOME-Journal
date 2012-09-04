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
 
[DBus (name = "org.gnome.NautilusPreviewer")]
interface NautilusPreviewer : Object {
    public abstract void show_file (string uri, int xid, bool close) throws IOError;
}

private class Journal.Previewer : GLib.Object 
{
    private NautilusPreviewer previewer_proxy;
    
    public async void show_file (string uri) {
        try {
            previewer_proxy = yield Bus.get_proxy (
                                    BusType.SESSION, 
                                    "org.gnome.NautilusPreviewer",
                                    "/org/gnome/NautilusPreviewer");
            int xid = (int)Gdk.X11Window.get_xid (Utils.window.get_window ());
            previewer_proxy.show_file (uri, xid, true);
        } catch (Error e) {
            warning ("%s", e.message);
        }
    }
}
