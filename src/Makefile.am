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
	$(NULL)

bin_PROGRAMS = gnome-activity-journal

gnome_activity_journal_SOURCES =\
	activities.vala					\
	app.vala						\
	dayview.vala					\
	loading.vala					\
	journal-timeline-navigator.vala \
	main.vala						\
	reminderview.vala				\
	revealer.vala					\
	selectionbar.vala				\
	timelineview.vala				\
	utils.vala						\
	zg-backend.vala					\
	$(NULL)

gnome_activity_journal_LDADD = $(JOURNAL_LIBS) libgdprivate-1.0.la -lm
