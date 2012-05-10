NULL =

SUBDIRS = data src po vapi


INTLTOOL_FILES =				\
	intltool-extract.in			\
	intltool-merge.in			\
	intltool-update.in			\
	$(NULL)

DISTCLEANFILES =				\
	gnome-doc-utils.make			\
	intltool-extract			\
	intltool-merge				\
	intltool-update				\
	po/.intltool-merge-cache		\
	version.h				\
	$(NULL)

ChangeLog:
	$(AM_V_GEN) if test -d "$(srcdir)/.git"; then \
	  (GIT_DIR=$(top_srcdir)/.git ./missing --run git log --stat) | fmt --split-only > $@.tmp \
	  && mv -f $@.tmp $@ \
	  || ($(RM) $@.tmp; \
	      echo Failed to generate ChangeLog, your ChangeLog may be outdated >&2; \
	      (test -f $@ || echo git-log is required to generate this file >> $@)); \
	else \
	  test -f $@ || \
	  (echo A git checkout and git-log is required to generate ChangeLog >&2 && \
	  echo A git checkout and git-log is required to generate this file >> $@); \
	fi

