NULL=
SUBDIRS = icons

desktopdir       = $(datadir)/applications
desktop_in_files = gnome-activity-journal.desktop.in
desktop_DATA     = $(desktop_in_files:.desktop.in=.desktop)
@INTLTOOL_DESKTOP_RULE@

gsettings_SCHEMAS = org.gnome.activity-journal.gschema.xml
@INTLTOOL_XML_NOMERGE_RULE@
@GSETTINGS_RULES@

styledir         = $(datadir)/gnome-activity-journal/style
style_DATA       = gtk-style.css

iconsdir = $(pkgdatadir)/icons


EXTRA_DIST =					\
	gnome-activity-journal.desktop.in			\
	org.gnome.activity-journal.gschema.xml.in		\
	$(desktop_in_files)			\
	$(style_DATA)				\
	$(NULL)

CLEANFILES =					\
	$(desktop_DATA)				\
	$(NULL)

DISTCLEANFILES =				\
	org.gnome.activity-journal.gschema.xml		\
	$(desktop_DATA)				\
	$(NULL)

