AC_PREREQ([2.67])

AC_INIT([gnome-activity-journal],
        [0.1],
        [https://bugzilla.gnome.org/enter_bug.cgi?product=gnome-activity-journal],
        [gnome-activity-journal],
        [http://live.gnome.org/GnomeActivityJournal])

AC_CONFIG_MACRO_DIR([m4])
AC_CONFIG_HEADERS([config.h])
AC_CONFIG_AUX_DIR([build-aux])
AC_CONFIG_SRCDIR([src/main.vala])

AM_INIT_AUTOMAKE
AM_MAINTAINER_MODE([enable])

AM_SILENT_RULES([yes])

# Check for programs
AC_PROG_CC
AM_PROG_VALAC([0.14.0])
AC_PROG_INSTALL

# Initialize libtool
LT_PREREQ([2.2])
LT_INIT([disable-static])

# Pkg-config
PKG_PROG_PKG_CONFIG([0.22])

# i18 support
IT_PROG_INTLTOOL(0.40.0)

GETTEXT_PACKAGE=gnome-activity-journal
AC_SUBST(GETTEXT_PACKAGE)
AC_DEFINE_UNQUOTED(GETTEXT_PACKAGE,"$GETTEXT_PACKAGE",[The name of the gettext domain])

ALL_LINGUAS=""
AM_GLIB_GNU_GETTEXT

# GObject-introspection support
GOBJECT_INTROSPECTION_REQUIRE([0.9.6])

# GSettings support
GLIB_GSETTINGS

pkg_modules="gtk+-3.0
	     glib-2.0
	     clutter-gtk-1.0
	     gee-0.8
	     zeitgeist-1.0
	     gnome-desktop-3.0
	     gio-2.0
	     "
PKG_CHECK_MODULES(JOURNAL, [$pkg_modules])

JOURNAL_PACKAGES="--pkg gtk+-3.0 --pkg clutter-gtk-1.0 --pkg gdk-pixbuf-2.0 --pkg glib-2.0 --pkg gee-0.8 --pkg zeitgeist-1.0 --pkg gio-2.0"
AC_SUBST(JOURNAL_PACKAGES)

AC_CONFIG_FILES([
  Makefile
  src/Makefile
  vapi/Makefile
  po/Makefile.in
  data/Makefile
  data/icons/Makefile
  data/gnome-activity-journal.desktop.in
])

AC_OUTPUT

dnl ==========================================================================
AC_MSG_NOTICE([

        GNOME Journal $VERSION
        =================

        prefix:                   ${prefix}
        c compiler:               ${CC} ${CFLAGS}
])
