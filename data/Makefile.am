NULL=
SUBDIRS = icons

desktopdir       = $(datadir)/applications
desktop_in_files = gnome-journal.desktop.in
desktop_DATA     = $(desktop_in_files:.desktop.in=.desktop)
@INTLTOOL_DESKTOP_RULE@

gsettings_SCHEMAS = org.gnome.journal.gschema.xml
@INTLTOOL_XML_NOMERGE_RULE@
@GSETTINGS_RULES@

styledir         = $(datadir)/gnome-journal/style
style_DATA       = gtk-style.css

iconsdir = $(pkgdatadir)/icons


EXTRA_DIST =					\
	gnome-journal.desktop.in			\
	org.gnome.journal.gschema.xml.in		\
	$(desktop_in_files)			\
	$(style_DATA)				\
	$(NULL)

CLEANFILES =					\
	$(desktop_DATA)				\
	$(NULL)

DISTCLEANFILES =				\
	org.gnome.journal.gschema.xml		\
	$(desktop_DATA)				\
	$(NULL)

