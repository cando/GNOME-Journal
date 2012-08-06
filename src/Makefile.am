NULL =

AM_CPPFLAGS = \
	-include config.h 				\
	-I$(top_builddir)/config 		\
	-I$(top_srcdir)					\
	-I$(srcdir)/lib					\
	$(JOURNAL_CFLAGS)				\
	-DLOCALEDIR=\""$(localedir)"\" \
	-DPKGDATADIR=\""$(pkgdatadir)"\" \
	-DPKGLIBDIR=\""$(pkglibdir)"\" \
	-DGNOME_DESKTOP_USE_UNSTABLE_API \
	$(NULL)

pkglib_LTLIBRARIES =

include lib/Makefile.am

AM_VALAFLAGS =						\
	--vapidir=$(top_srcdir)/vapi	\
	--pkg config					\
	--pkg Gd-1.0					\
	--pkg custom					\
	@JOURNAL_PACKAGES@				\
	-g\
	$(NULL)

bin_PROGRAMS = gnome-journal

gnome_journal_SOURCES =\
	journal-activities.vala			\
	app.vala						\
	journal-activity-info-page.vala	\
	journal-timeline-navigator.vala \
	journal-media-actors.vala		\
	journal-search.vala				\
	main.vala						\
	journal-timelineview.vala		\
	utils.vala						\
	zg-backend.vala					\
	$(NULL)

gnome_journal_LDADD = $(JOURNAL_LIBS) libgdprivate-1.0.la -lm

MAINTAINERCLEANFILES =				\
	$(gnome_journal_SOURCES:.vala=.c)		\
	*.stamp					\
	$(NULL)

