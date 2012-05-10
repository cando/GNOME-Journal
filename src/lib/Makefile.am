gdprivate_cflags = \
    -I$(top_srcdir)/src \
    -DPREFIX=\"$(prefix)\" \
    -DLIBDIR=\"$(libdir)\" \
    -DG_LOG_DOMAIN=\"Gdprivate\" \
    -DG_DISABLE_DEPRECATED \
    $(JOURNAL_CFLAGS)

gdprivate_source_h = \
    lib/gd-utils.h \
    lib/gd-fullscreen-filter.h \
    lib/gd-main-toolbar.h \
    lib/gd-main-view-generic.h \
    lib/gd-main-icon-view.h \
    lib/gd-main-list-view.h \
    lib/gd-main-view.h \
    lib/gd-margin-container.h \
    lib/gd-notification.h \
    lib/gd-styled-text-renderer.h \
    lib/gd-tagged-entry.h \
    lib/gd-toggle-pixbuf-renderer.h \
    lib/gd-two-lines-renderer.h \
    $(NULL)

gdprivate_source_c = \
    lib/gd-utils.c \
    lib/gd-fullscreen-filter.c \
    lib/gd-main-toolbar.c \
    lib/gd-main-view-generic.c \
    lib/gd-main-icon-view.c \
    lib/gd-main-list-view.c \
    lib/gd-main-view.c \
    lib/gd-margin-container.c \
    lib/gd-notification.c \
    lib/gd-styled-text-renderer.c \
    lib/gd-tagged-entry.c \
    lib/gd-toggle-pixbuf-renderer.c \
    lib/gd-two-lines-renderer.c \
    $(NULL)

pkglib_LTLIBRARIES += libgdprivate-1.0.la

libgdprivate_1_0_la_LIBADD = \
    $(JOURNAL_LIBS) \
    $(LIBM)

libgdprivate_1_0_la_LDFLAGS = \
    -avoid-version

libgdprivate_1_0_la_CPPFLAGS = \
    $(gdprivate_cflags)

libgdprivate_1_0_la_SOURCES = \
    $(gdprivate_source_h) \
    $(gdprivate_source_c)



