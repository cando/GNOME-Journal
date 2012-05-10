/* -*- Mode: vala; indent-tabs-mode: t; c-basic-offset: 2; tab-width: 8 -*- */
/*
 * Copyright (C) 2011 Alexander Larsson <alexl@redhat.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

using Gtk;

public class Journal.Revealer : Viewport {
  protected Gdk.Window bin_window;
  protected Gdk.Window view_window;
  protected Adjustment vadjustment;
  protected double amount_visible;
  protected double target_amount;
  const int animation_time = 200;
  const int animation_n_steps = 8;
  private uint timeout;

  public Revealer () {
    add_events (Gdk.EventMask.ENTER_NOTIFY_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK);
    this.set_shadow_type (ShadowType.NONE);
    target_amount = amount_visible = 0.0;
    vadjustment = get_vadjustment ();
  }
  
  public override bool enter_notify_event (Gdk.EventCrossing event) {
        stdout.printf("entro");
        return false;
  }
  
  public override bool leave_notify_event (Gdk.EventCrossing event) {
        stdout.printf("esco");
        return false;
  }

  private void ensure_timer () {
    if (timeout == 0) {
      if (amount_visible == target_amount)
	return;
      
      timeout = Gdk.threads_add_timeout (animation_time /  animation_n_steps,
					 animate_cb);
    }
  }

  public override void show () {
    base.show ();
    if (target_amount != 1.0)
      reveal ();
  }

  public override void hide () {
    base.hide ();
    target_amount = 0;
    amount_visible = 0;
    if (timeout != 0) {
      Source.remove (timeout);
      timeout = 0;
    }
  }
  
  
  public void reveal () {
    target_amount = 1.0;
    this.show ();
    ensure_timer ();
  }

  public void unreveal () {
    target_amount = 0.0;
    ensure_timer ();
  }

  private  bool animate_cb () {
    double delta = 1.0 /  animation_n_steps;
    if (amount_visible < target_amount) {
      amount_visible = double.min (target_amount, amount_visible + delta);
    } else {
      amount_visible = double.max (target_amount, amount_visible - delta);
    }

    queue_resize ();

    if (amount_visible == target_amount) {
      timeout = 0;

      if (amount_visible == 0)
	this.hide ();
      
      return false;
    }
    
    return true;
  }

  public override void get_preferred_width (out int minimum_width, out int natural_width) {
    base.get_preferred_height (out minimum_width, out natural_width);
    minimum_width = (int) (minimum_width * amount_visible);
    natural_width = (int) (natural_width * amount_visible);
  }

  public override void get_preferred_width_for_height (int height, out int minimum_width, out int natural_width) {
    base.get_preferred_width_for_height (height, out minimum_width, out natural_width);
    minimum_width = (int) (minimum_width * amount_visible);
    natural_width = (int) (natural_width * amount_visible);
  }

  public override void size_allocate (Gtk.Allocation allocation) {
    base.size_allocate (allocation);
    var upper = hadjustment.get_upper ();
    hadjustment.set_value (upper - allocation.width);
  }
}
