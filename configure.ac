AC_PREREQ([2.67])

AC_INIT([gnome-journal],
        [0.1],
        [https://bugzilla.gnome.org/enter_bug.cgi?product=gnome-activity-journal],
        [gnome-journal],
        [https://live.gnome.org/SummerOfCode2012/Projects/Stefano_Candori_GNOME_Journal])

AC_CONFIG_MACRO_DIR([m4])
AC_CONFIG_HEADERS([config.h])
AC_CONFIG_AUX_DIR([build-aux])
AC_CONFIG_SRCDIR([src/main.vala])

AM_INIT_AUTOMAKE
AM_MAINTAINER_MODE([enable])

AM_SILENT_RULES([yes])

# Check for programs
AC_PROG_CC
AM_PROG_VALAC([0.16.0])
AC_PROG_INSTALL

# Initialize libtool
LT_PREREQ([2.2])
LT_INIT([disable-static])

# Pkg-config
PKG_PROG_PKG_CONFIG([0.22])

# i18 support
IT_PROG_INTLTOOL(0.40.0)

GETTEXT_PACKAGE=gnome-journal
AC_SUBST(GETTEXT_PACKAGE)
AC_DEFINE_UNQUOTED(GETTEXT_PACKAGE,"$GETTEXT_PACKAGE",[The name of the gettext domain])

ALL_LINGUAS=""
AM_GLIB_GNU_GETTEXT

# GObject-introspection support
GOBJECT_INTROSPECTION_REQUIRE([0.9.6])

# GSettings support
GLIB_GSETTINGS

pkg_modules="gtk+-3.0 >= 3.4.0
	     glib-2.0
	     clutter-1.0 >= 1.10
	     clutter-gtk-1.0 >= 1.0.1
	     gee-1.0
	     zeitgeist-1.0
	     gnome-desktop-3.0
	     gio-2.0
	     gio-unix-2.0
	     gstreamer-0.10 
	     gstreamer-interfaces-0.10
	     gdk-x11-3.0
	     "
PKG_CHECK_MODULES(JOURNAL, [$pkg_modules])

JOURNAL_PACKAGES="--pkg gtk+-3.0 --pkg clutter-gtk-1.0 --pkg gdk-pixbuf-2.0 --pkg glib-2.0 --pkg gee-1.0 --pkg zeitgeist-1.0 --pkg gio-2.0 --pkg gio-unix-2.0 --pkg gstreamer-0.10 --pkg gstreamer-interfaces-0.10 --pkg gdk-x11-3.0"
AC_SUBST(JOURNAL_PACKAGES)

AC_CONFIG_FILES([
  Makefile
  src/Makefile
  vapi/Makefile
  po/Makefile.in
  data/Makefile
  data/icons/Makefile
  data/gnome-journal.desktop.in
])

AC_OUTPUT


dnl ==========================================================================
AC_MSG_NOTICE([

        GNOME Journal $VERSION
        =================

        prefix:                   ${prefix}
        c compiler:               ${CC} ${CFLAGS}
])
